/// 存储路径管理（纯 Dart 层，不依赖 Flutter）
///
/// 下载的漫画默认存到公共目录（文件管理器可见），
/// 例如 /storage/emulated/0/JM/1474516/1/00001.jpg
///
/// 平台相关的兜底目录由上层（Flutter 侧）通过 [setRootOverride] 注入。
library;

import 'dart:io';

import 'package:path/path.dart' as p;

class JmStorage {
  JmStorage._();

  static const String publicFolderName = 'JM';

  /// 各源的下载目录名
  static const Map<String, String> sourceFolders = {
    'jm': 'JM',
    'pica': 'Pica',
    'eh': 'EH',
    'pixiv': 'Pixiv',
  };

  /// 某个源的下载根目录
  ///
  /// JM 保持历史路径不变（传入的 root 本身就是 JM 目录），其它源用同级目录：
  /// JM 在 /storage/emulated/0/JM 时，哔咔是 /storage/emulated/0/Pica。
  /// 这样已经下载好的书不会因为改版而找不到。
  static String sourceRoot(String jmRoot, String source) {
    final custom = _sourceRoots[source]?.trim() ?? '';
    if (custom.isNotEmpty) return custom;

    if (source == 'jm') return jmRoot;
    final folder = sourceFolders[source] ?? source;
    final parent = p.dirname(jmRoot);
    if (parent.isEmpty || parent == '.' || parent == '/') {
      return '$jmRoot/$folder';
    }
    return '$parent/$folder';
  }

  /// 各源自定义的下载目录，由上层从设置里灌进来
  ///
  /// 留空就走上面的默认推导。老书靠数据库里记的落盘目录照样能找回来，
  /// 换目录不会让它们消失。
  static final Map<String, String> _sourceRoots = {};

  static void setSourceRoots(Map<String, String> roots) {
    _sourceRoots
      ..clear()
      ..addAll(roots);
  }

  static String? _rootOverride;

  /// 允许上层覆盖根目录（设置页可改，或平台兜底时注入）
  static void setRootOverride(String? path) => _rootOverride = path;

  static String? get rootOverride => _rootOverride;

  /// 平台兜底目录（拿不到公共目录权限时用），由上层注入
  ///
  /// 单独存一份是为了让「界面显示的目录」和「下载实际写入的目录」永远一致——
  /// 之前两处各自算兜底路径，算出来的不一样，用户就会看到「下载完再进来
  /// 显示没下载」。
  static String? _fallbackRoot;

  static void setFallbackRoot(String? path) => _fallbackRoot = path;

  static String? get fallbackRoot => _fallbackRoot;

  /// 公共漫画目录：/storage/emulated/0/JM
  static String get publicRoot => '/storage/emulated/0/$publicFolderName';

  /// 相册「别收录这个目录」的标记文件名
  ///
  /// 公共目录里的图片会被系统相册自动收录，下载一本就多出几百张图，
  /// 相册会变得没法看。往目录里放一个 `.nomedia`，相册就会跳过整个目录，
  /// 而文件管理器不受影响，文件照样能翻到。
  static const String nomediaFileName = '.nomedia';

  /// 需要放 `.nomedia` 的目录：JM 根目录 + 各源的同级目录
  static List<String> galleryGuardDirs(String jmRoot) {
    final dirs = <String>[];
    void add(String dir) {
      final path = dir.trim();
      if (path.isEmpty || dirs.contains(path)) return;
      dirs.add(path);
    }

    add(jmRoot);
    for (final source in sourceFolders.keys) {
      add(sourceRoot(jmRoot, source));
    }
    return dirs;
  }

  /// 往目录里写 `.nomedia`，返回写成功的目录
  static Future<List<String>> writeNoMedia(Iterable<String> dirs) async {
    final done = <String>[];
    for (final dir in dirs) {
      try {
        await ensureDir(dir);
        final file = File('$dir/$nomediaFileName');
        if (!await file.exists()) await file.writeAsString('');
        done.add(dir);
      } on FileSystemException {
        // 单个目录写不进去不影响其它目录
      }
    }
    return done;
  }

  /// 去掉目录里的 `.nomedia`，返回处理过的目录
  static Future<List<String>> removeNoMedia(Iterable<String> dirs) async {
    final done = <String>[];
    for (final dir in dirs) {
      try {
        final file = File('$dir/$nomediaFileName');
        if (await file.exists()) await file.delete();
        done.add(dir);
      } on FileSystemException {
        // 忽略
      }
    }
    return done;
  }

  /// 判断目录是否可写（会自动创建）
  static Future<bool> canWrite(String path) async {
    try {
      final dir = Directory(path);
      await dir.create(recursive: true);
      final probe = File('${dir.path}/.jm_write_test');
      await probe.writeAsString('ok');
      await probe.delete();
      return true;
    } on FileSystemException {
      return false;
    }
  }

  /// 解析实际使用的下载根目录
  ///
  /// 优先公共目录；不可写时返回 null，由上层提供兜底目录。
  static Future<String?> resolveRoot() async {
    final override = _rootOverride;
    if (override != null && override.trim().isNotEmpty) return override.trim();
    if (await canWrite(publicRoot)) return publicRoot;
    return null;
  }

  /// 当前实际使用的根目录，永远返回一个能用的值
  static Future<String> effectiveRoot() async {
    final resolved = await resolveRoot();
    if (resolved != null) return resolved;
    return _fallbackRoot ?? publicRoot;
  }

  /// 单本漫画目录：`<root>/<本子ID>`
  static String albumDir(String root, String albumId) => '$root/$albumId';

  /// 单章目录：`<本子目录>/<章节序号>`
  static String chapterDir(String albumDir, int chapterIndex) =>
      '$albumDir/$chapterIndex';

  /// 单章目录：`<root>/<本子ID>/<章节序号>`，与插件一致，避免多章节互相覆盖
  static String photoDir(String root, String albumId, int chapterIndex) =>
      chapterDir(albumDir(root, albumId), chapterIndex);

  /// 图片文件名：00001.jpg
  static String imageFileName(int index, String suffix) =>
      '${index.toString().padLeft(5, '0')}$suffix';

  /// 确保目录存在
  static Future<Directory> ensureDir(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// 统计目录内图片数量
  static Future<int> countImages(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) return 0;
    var count = 0;
    await for (final entity in dir.list()) {
      if (entity is File && isImage(entity.path)) count++;
    }
    return count;
  }

  static bool isImage(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.gif');
  }

  /// 目录里有没有至少一张图
  ///
  /// 找到第一张就返回，不用把几百个文件列完。
  static Future<bool> hasImages(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) return false;
    await for (final entity in dir.list()) {
      if (entity is File && isImage(entity.path)) return true;
    }
    return false;
  }

  /// 这本书本地真正能看的章节序号（升序）
  ///
  /// 光看目录在不在不够用：下载失败、中途取消都会留下空目录，
  /// 点进去只会得到「本章还没有下载」。这里只认确实有图的目录。
  static Future<List<int>> localChapters(String albumDir) async {
    final dir = Directory(albumDir);
    if (!await dir.exists()) return const [];
    final indexes = <int>[];
    await for (final entity in dir.list()) {
      if (entity is! Directory) continue;
      final index = int.tryParse(p.basename(entity.path));
      if (index == null || index <= 0) continue;
      if (await hasImages(entity.path)) indexes.add(index);
    }
    indexes.sort();
    return indexes;
  }

  /// 列出目录内的图片，按文件名自然排序
  static Future<List<File>> listImages(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) return const [];
    final files = <File>[];
    await for (final entity in dir.list()) {
      if (entity is File && isImage(entity.path)) files.add(entity);
    }
    files.sort((a, b) => _naturalCompare(a.path, b.path));
    return files;
  }

  /// 目录里的第一张图（按文件名排序），没有就返回 null
  static Future<File?> firstImage(String path) async {
    final files = await listImages(path);
    return files.isEmpty ? null : files.first;
  }

  /// 自然排序：00002 排在 00010 前面
  static int _naturalCompare(String a, String b) {
    final ra = RegExp(r'(\d+|\D+)')
        .allMatches(a)
        .map((m) => m.group(0)!)
        .toList();
    final rb = RegExp(r'(\d+|\D+)')
        .allMatches(b)
        .map((m) => m.group(0)!)
        .toList();
    for (var i = 0; i < ra.length && i < rb.length; i++) {
      final x = ra[i];
      final y = rb[i];
      final nx = int.tryParse(x);
      final ny = int.tryParse(y);
      final cmp = (nx != null && ny != null)
          ? nx.compareTo(ny)
          : x.compareTo(y);
      if (cmp != 0) return cmp;
    }
    return ra.length.compareTo(rb.length);
  }

  /// 删除整本
  static Future<void> deleteAlbum(String root, String albumId) async {
    final dir = Directory(albumDir(root, albumId));
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  /// 计算目录占用空间（字节）
  static Future<int> dirSize(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) return 0;
    var total = 0;
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) total += await entity.length();
    }
    return total;
  }
}
