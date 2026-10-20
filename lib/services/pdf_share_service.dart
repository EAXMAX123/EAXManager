/// 把本地下载好的本子打成一个 PDF，再交给系统分享面板
///
/// 只在本地拼图，不重新下载：JPG / PNG 直接嵌入原文件，
/// WebP / GIF 转成 JPEG；带密码时由 Android 原生侧的 PDFBox 加密。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../app_info.dart';
import '../data/app_database.dart';
import '../jm/jm_storage.dart';
import '../source/comic_source.dart';
import '../state/app_services.dart';
import 'image_aspect.dart';
import 'local_library.dart';
import 'platform_service.dart';

class PdfShareResult {
  const PdfShareResult({
    required this.path,
    required this.fileName,
    required this.pageCount,
    this.sizeBytes = 0,
    this.reused = false,
  });

  final String path;
  final String fileName;
  final int pageCount;
  final int sizeBytes;

  /// true 表示直接用了之前打包好的文件，没有重新生成
  final bool reused;
}

class PdfShareService {
  PdfShareService._();

  static const double _pageWidth = 595.28;

  static Future<PdfShareResult> buildAlbumPdf({
    required SourceId sid,
    required String title,
    Iterable<int>? chapterIndexes,
    String? fileNameBase,
    String password = '',
    void Function(int done, int total)? onProgress,
  }) async {
    final localChapters = await LocalLibrary.chapters(sid);
    if (localChapters.isEmpty) {
      throw const PdfShareException('本地还没有下载好的章节');
    }

    final wanted = chapterIndexes?.toSet();
    final chapters = wanted == null
        ? localChapters
        : [
            for (final index in localChapters)
              if (wanted.contains(index)) index,
          ];
    if (chapters.isEmpty) {
      throw const PdfShareException('请先选择要分享的章节');
    }

    final chapterFiles = <List<File>>[];
    for (final chapter in chapters) {
      final dir = await LocalLibrary.chapterDir(sid, chapter);
      if (dir == null) continue;
      final files = await JmStorage.listImages(dir);
      if (files.isNotEmpty) chapterFiles.add(files);
    }

    final total = chapterFiles.fold<int>(0, (sum, files) => sum + files.length);
    if (total == 0) {
      throw const PdfShareException('本地还没有可以导出的图片');
    }

    final doc = pw.Document(
      title: title,
      author: AppInfo.name,
      creator: AppInfo.name,
    );

    var done = 0;
    var pageCount = 0;
    for (final files in chapterFiles) {
      for (final file in files) {
        final page = await _buildPage(file);
        if (page != null) {
          doc.addPage(page);
          pageCount++;
        }
        done++;
        onProgress?.call(done, total);
      }
    }

    final rawBytes = await doc.save();
    final dir = await _packageDir(sid);
    final requestedName = fileNameBase?.trim() ?? '';
    final baseName = requestedName.isEmpty
        ? _buildFileStem(
            title: title,
            chapters: chapters,
            allLocal: localChapters,
          )
        : _safeFileName(requestedName);
    final target = File(p.join(dir.path, '$baseName.pdf'));
    final raw = File(p.join(dir.path, '$baseName.raw.pdf'));

    await _deleteIfExists(target);
    await _deleteIfExists(raw);

    final trimmed = password.trim();
    final passwordSig = _passwordSignature(trimmed);
    if (trimmed.isEmpty) {
      await target.writeAsBytes(rawBytes, flush: true);
      return _remember(
        sid: sid,
        title: title,
        chapters: chapters,
        path: target.path,
        pageCount: pageCount,
        passwordSig: passwordSig,
      );
    }

    await raw.writeAsBytes(rawBytes, flush: true);
    final ok = await PlatformService.protectPdf(
      inputPath: raw.path,
      outputPath: target.path,
      password: trimmed,
    );
    await _deleteIfExists(raw);
    if (!ok) {
      await _deleteIfExists(target);
      throw const PdfShareException('PDF 加密失败，请确认手机系统正常后重试');
    }

    return _remember(
      sid: sid,
      title: title,
      chapters: chapters,
      path: target.path,
      pageCount: pageCount,
      passwordSig: passwordSig,
    );
  }

  /// 找一份和这次选择完全一致的本地 PDF；文件被删了就顺手清掉记录
  static Future<PdfShareResult?> findPackage({
    required SourceId sid,
    required Iterable<int> chapterIndexes,
    String password = '',
  }) async {
    final chapters = chapterIndexes.toSet().toList()..sort();
    if (chapters.isEmpty) return null;
    final item = await AppServices.I.dao.findPdfPackage(
      sid,
      chapters,
      passwordSig: _passwordSignature(password.trim()),
    );
    if (item == null) return null;

    final file = File(item.filePath);
    if (!await file.exists() || await file.length() == 0) {
      await AppServices.I.dao.deletePdfPackage(item.id);
      AppServices.I.notifyPdfPackagesChanged();
      return null;
    }

    return PdfShareResult(
      path: item.filePath,
      fileName: p.basename(item.filePath),
      pageCount: item.pageCount,
      sizeBytes: await file.length(),
      reused: true,
    );
  }

  /// 书架「已打包」页用：列出全部记录，并清掉文件已经不在的条目
  static Future<List<PdfPackageItem>> listPackages() async {
    final items = await AppServices.I.dao.listPdfPackages();
    return _validPackages(items, notify: true);
  }

  /// 详情页用：这本书已经打包过哪些章节组合
  static Future<List<PdfPackageItem>> packagesForAlbum(SourceId sid) async {
    final items = await AppServices.I.dao.listPdfPackagesByAlbum(sid);
    return _validPackages(items, notify: true);
  }

  /// 删除一份本地 PDF；只删 PDF，不动下载的图片
  static Future<void> deletePackage(PdfPackageItem item) async {
    await _deleteIfExists(File(item.filePath));
    await AppServices.I.dao.deletePdfPackage(item.id);
    AppServices.I.notifyPdfPackagesChanged();
  }

  /// 「第1-3,5话」这种给人看的章节范围
  static String formatChapters(Iterable<int> chapters) {
    final sorted = chapters.toSet().toList()..sort();
    if (sorted.isEmpty) return '无章节';

    final parts = <String>[];
    var start = sorted.first;
    var previous = start;
    for (final index in sorted.skip(1)) {
      if (index == previous + 1) {
        previous = index;
        continue;
      }
      parts.add(start == previous ? '$start' : '$start-$previous');
      start = index;
      previous = index;
    }
    parts.add(start == previous ? '$start' : '$start-$previous');
    return '第${parts.join(',')}话';
  }

  static Future<List<PdfPackageItem>> _validPackages(
    List<PdfPackageItem> items, {
    required bool notify,
  }) async {
    final valid = <PdfPackageItem>[];
    var removed = false;
    for (final item in items) {
      final path = item.filePath.trim();
      if (path.isEmpty) {
        await AppServices.I.dao.deletePdfPackage(item.id);
        removed = true;
        continue;
      }
      final file = File(path);
      if (!await file.exists() || await file.length() == 0) {
        await AppServices.I.dao.deletePdfPackage(item.id);
        removed = true;
        continue;
      }
      valid.add(item);
    }
    if (removed && notify) AppServices.I.notifyPdfPackagesChanged();
    return valid;
  }

  static Future<PdfShareResult> _remember({
    required SourceId sid,
    required String title,
    required List<int> chapters,
    required String path,
    required int pageCount,
    required String passwordSig,
  }) async {
    final size = await File(path).length();
    await AppServices.I.dao.upsertPdfPackage(
      sid: sid,
      title: title,
      chapters: chapters,
      filePath: path,
      pageCount: pageCount,
      sizeBytes: size,
      passwordSig: passwordSig,
    );
    AppServices.I.notifyPdfPackagesChanged();
    return PdfShareResult(
      path: path,
      fileName: p.basename(path),
      pageCount: pageCount,
      sizeBytes: size,
    );
  }

  static Future<pw.Page?> _buildPage(File file) async {
    try {
      var bytes = await file.readAsBytes();
      var ratio = await ImageAspect.heightOverWidth(file);
      final ext = p.extension(file.path).toLowerCase();

      pw.MemoryImage? image;
      if (ext == '.jpg' || ext == '.jpeg' || ext == '.png') {
        try {
          image = pw.MemoryImage(bytes);
        } on Object {
          // 扩展名不对或者文件截断，交给下面的重编码兜底
          image = null;
        }
      }

      if (image == null) {
        final decoded = img.decodeImage(bytes);
        if (decoded == null) return null;
        final resized = decoded.width > 1600
            ? img.copyResize(decoded, width: 1600)
            : decoded;
        bytes = Uint8List.fromList(img.encodeJpg(resized, quality: 88));
        ratio = resized.height / resized.width;
        image = pw.MemoryImage(bytes);
      }

      final height = (_pageWidth * ratio).clamp(100.0, 5000.0);
      final pageImage = image;

      return pw.Page(
        pageFormat: PdfPageFormat(_pageWidth, height, marginAll: 0),
        build: (_) => pw.FullPage(
          ignoreMargins: true,
          child: pw.Image(pageImage, fit: pw.BoxFit.contain),
        ),
      );
    } on Object {
      // 单张图坏了就跳过，别让整本都导不出来
      return null;
    }
  }

  /// PDF 放下载目录下的「已打包」，文件管理器里也能找到；
  /// 公共目录写不了时退回应用自己的文档目录。
  static Future<Directory> _packageDir(SourceId sid) async {
    final root = AppServices.I.rootDir.value.trim();
    if (root.isNotEmpty && !root.startsWith('(')) {
      final dir = Directory(
        p.join(JmStorage.sourceRoot(root, sid.source), '已打包'),
      );
      try {
        await dir.create(recursive: true);
        return dir;
      } on FileSystemException {
        // 没权限就换私有目录，不能让分享直接失败
      }
    }

    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'EAX打包'));
    await dir.create(recursive: true);
    return dir;
  }

  static String _buildFileStem({
    required String title,
    required List<int> chapters,
    required List<int> allLocal,
  }) {
    if (chapters.length == allLocal.length) return _safeFileName(title);

    final suffix = chapters.length == 1
        ? ' - 第${chapters.first}话'
        : chapters.length <= 8
        ? ' - ${formatChapters(chapters)}'
        : ' - 已选${chapters.length}话-${_shortHash(chapters.join(','))}';
    return '${_safeFileName(title, maxLength: 80 - suffix.length)}$suffix';
  }

  static String _shortHash(String value) {
    var hash = 2166136261;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 16777619) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0').substring(0, 6);
  }

  /// 只用来判断「这次的密码设置和上次打包时是不是一样」，
  /// 不保存明文密码。
  static String _passwordSignature(String password) {
    if (password.isEmpty) return '';
    return sha256.convert(utf8.encode(password)).toString();
  }

  static String _safeFileName(String title, {int maxLength = 80}) {
    var name = title.replaceAll(RegExp(r'[\\/:*?"<>|\r\n\t]'), '_').trim();
    while (name.startsWith('.')) {
      name = name.substring(1).trimLeft();
    }
    if (name.isEmpty) name = 'EAX分享';
    if (maxLength < 1) maxLength = 1;
    if (name.length > maxLength) name = name.substring(0, maxLength);
    return name;
  }

  static Future<void> _deleteIfExists(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // 删不掉就让后面的写覆盖它
    }
  }
}

class PdfShareException implements Exception {
  const PdfShareException(this.message);

  final String message;

  @override
  String toString() => message;
}
