/// 本地文件定位：一本书、一话，图片到底在哪
///
/// 只按「当前下载目录 + 本子号 + 章节号」拼路径不够用：下载目录会变
/// （用户换过目录、后来才授了存储权限、权限波动退回私有目录），旧书就留在
/// 老目录里，界面说「已下载」，点进去却报「本章还没有下载」。
/// 数据库里记了每一章真正落盘的位置，这里优先信它，拼出来的路径只当兜底。
library;

import '../data/app_database.dart';
import '../jm/jm_storage.dart';
import '../source/comic_source.dart';
import '../state/app_services.dart';

class LocalLibrary {
  LocalLibrary._();

  /// 这一话的图片目录；本地确实有图才给路径，否则 null
  static Future<String?> chapterDir(SourceId sid, int chapterIndex) async {
    for (final dir in await _candidates(sid, chapterIndex)) {
      if (await JmStorage.hasImages(dir)) return dir;
    }
    return null;
  }

  /// 这一话本地有没有图
  static Future<bool> chapterReady(SourceId sid, int chapterIndex) async =>
      await chapterDir(sid, chapterIndex) != null;

  /// 记录说「下完了」、本地却已经没有图的章节，该清掉哪些记录
  ///
  /// [doneTasks] 是已经下完的章节记录。文件被误删、被手机管家清掉、
  /// 或者用户自己删过之后，这些记录就成了假的——书架上挂着「已下载」，
  /// 点进去却是空的。纯函数，方便单测。
  static List<int> staleChapterTaskIds(
    Iterable<({int id, int chapterIndex})> doneTasks,
    Set<int> localChapters,
  ) => [
    for (final task in doneTasks)
      if (!localChapters.contains(task.chapterIndex)) task.id,
  ];

  /// 本地能看的章节序号（升序）
  ///
  /// 数据库记录和当前下载目录两边都看：前者管「换过目录的老书」，
  /// 后者管「数据库丢了但文件还在」。
  static Future<List<int>> chapters(SourceId sid) async {
    final found = <int>{};

    for (final entry in (await _recordedDirs(sid)).entries) {
      if (await JmStorage.hasImages(entry.value)) found.add(entry.key);
    }

    for (final album in await _albumDirs(sid)) {
      found.addAll(await JmStorage.localChapters(album));
    }

    return found.toList()..sort();
  }

  /// 把候选目录按可信度排好：去空、去重
  ///
  /// 数据库记的落盘目录最可信——下载目录改过也照样对；
  /// 按目录拼出来的只当兜底。传进来的顺序就是优先级。
  static List<String> candidateDirs(Iterable<String> dirs) {
    final out = <String>[];
    for (final dir in dirs) {
      final path = dir.trim();
      if (path.isEmpty || out.contains(path)) continue;
      out.add(path);
    }
    return out;
  }

  /// 这一话该去哪几个目录找，按可信度排
  static Future<List<String>> _candidates(
    SourceId sid,
    int chapterIndex,
  ) async {
    final albums = await _albumDirs(sid);
    return candidateDirs([
      (await _recordedDirs(sid))[chapterIndex] ?? '',
      for (final album in albums) JmStorage.chapterDir(album, chapterIndex),
    ]);
  }

  /// 数据库里记过的「章节序号 -> 落盘目录」
  static Future<Map<int, String>> _recordedDirs(SourceId sid) async {
    try {
      return await AppServices.I.dao.recordedChapterDirs(sid);
    } on Object {
      // 数据库没准备好时不该让阅读跟着失败，退回按路径拼
      return const {};
    }
  }

  /// 这本书可能所在的目录，按可信度排
  ///
  /// 先看当前下载目录，再看这本书当初落盘的目录——下载目录改过之后，
  /// 老书还留在老地方。
  static Future<List<String>> _albumDirs(SourceId sid) async {
    final item = await _bookshelf(sid);
    return candidateDirs([
      _albumOf(AppServices.I.rootDir.value, sid),
      _albumOf(item?.rootPath ?? '', sid),
    ]);
  }

  static String _albumOf(String root, SourceId sid) {
    final path = root.trim();
    if (path.isEmpty || path.startsWith('(')) return '';
    return JmStorage.albumDir(JmStorage.sourceRoot(path, sid.source), sid.id);
  }

  static Future<BookshelfItem?> _bookshelf(SourceId sid) async {
    try {
      return await AppServices.I.dao.getBookshelf(sid);
    } on Object {
      return null;
    }
  }
}
