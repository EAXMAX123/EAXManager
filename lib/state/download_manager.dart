/// 下载管理器：任务队列、并发调度、进度通知、书架联动
///
/// 与具体源解耦：任务只记 source + albumId + chapterId，
/// 真正取图片地址交给对应的 [ComicSource]。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../app_info.dart';
import '../data/app_database.dart';
import '../data/settings_store.dart';
import '../jm/jm_storage.dart';
import '../services/notification_service.dart';
import '../services/platform_service.dart';
import '../source/chapter_downloader.dart';
import '../source/comic_source.dart';
import '../source/source_registry.dart';

class DownloadManager extends ChangeNotifier {
  DownloadManager({
    required this.dao,
    required this.sources,
    required this.settings,
  });

  final AppDao dao;
  final SourceRegistry sources;

  AppSettings settings;

  List<DownloadTask> tasks = const [];
  String? _root;

  final Map<int, DownloadCancelToken> _tokens = {};
  final Set<int> _running = {};

  /// 同一个本子的多个章节共用一份详情，避免每章都重新拉一次
  final Map<String, ComicDetail> _details = {};

  bool _disposed = false;
  Timer? _notifyThrottle;
  bool _notifyPending = false;
  bool _foregroundRunning = false;

  /// 待落库的进度：下载时每张图都写一次 SQLite 会把数据库打满，攒 1 秒批量写
  final Map<int, DownloadTask> _pendingWrites = {};
  Timer? _writeTimer;

  /// 通知栏进度节流：每张图都刷一次通知等于每秒几百次跨进程调用
  DateTime _lastProgressNotify = DateTime.fromMillisecondsSinceEpoch(0);

  /// 最近连续失败的章节数；连续失败就临时降并发，别把网络和手机一起打死
  int _recentFailures = 0;

  bool get isBusy => _running.isNotEmpty;

  int get activeCount => _running.length;

  /// 章节并发：连续失败时自动降档
  int get _chapterConcurrency {
    final base = settings.maxConcurrentChapters.clamp(1, 8);
    if (_recentFailures >= 3) return 1;
    if (_recentFailures >= 1) return (base ~/ 2).clamp(1, base);
    return base;
  }

  /// 单章内图片并发：同上
  int get _imageConcurrency {
    final base = settings.maxConcurrentImages.clamp(1, 16);
    if (_recentFailures >= 3) return 1;
    if (_recentFailures >= 1) return (base ~/ 2).clamp(1, base);
    return base;
  }

  int get pendingCount =>
      tasks.where((t) => t.status == DownloadStatus.pending).length;

  /// 更新设置（并发数等）
  void updateSettings(AppSettings value) {
    settings = value;
    _root = null; // 下载目录可能被改过，下次入队时重新解析
    notifyListeners();
  }

  Future<void> init() async {
    await dao.resetRunningTasks();
    await reload();
  }

  Future<void> reload() async {
    tasks = await dao.listTasks();
    _safeNotify();
  }

  Future<String> _resolveRoot() async {
    // 统一走 JmStorage：界面显示的目录和这里写入的目录必须完全一致
    return _root ??= await JmStorage.effectiveRoot();
  }

  /// 把整本加入下载队列
  Future<int> enqueueAlbum(
    ComicDetail detail, {
    List<ComicChapter>? chapters,
  }) async {
    final list = chapters ?? detail.chapters;
    var added = 0;

    if (list.isEmpty) {
      // 单章本：本子 ID 即章节 ID
      added += await _enqueue(
        detail: detail,
        chapter: ComicChapter(
          id: detail.sid.id,
          title: detail.title,
          index: 1,
          order: 1,
        ),
      );
    } else {
      for (final chapter in list) {
        added += await _enqueue(detail: detail, chapter: chapter);
      }
    }

    await reload();
    _pump();
    return added;
  }

  /// 只下载指定章节
  Future<int> enqueueChapter({
    required ComicDetail detail,
    required ComicChapter chapter,
  }) async {
    final added = await _enqueue(detail: detail, chapter: chapter);
    await reload();
    _pump();
    return added;
  }

  Future<int> _enqueue({
    required ComicDetail detail,
    required ComicChapter chapter,
  }) async {
    final existing = tasks.where(
      (t) =>
          t.source == detail.sid.source &&
          t.albumId == detail.sid.id &&
          t.chapterId == chapter.id,
    );
    if (existing.isNotEmpty && existing.first.status != DownloadStatus.failed) {
      return 0;
    }

    // 同一章只要已经下好了就别再排一次（重新扫描本地时建的任务用的是序号
    // 而不是源侧章节 ID，靠 ID 比对会漏掉）
    final sameChapter = tasks.where(
      (t) =>
          t.source == detail.sid.source &&
          t.albumId == detail.sid.id &&
          t.chapterIndex == chapter.index,
    );
    if (sameChapter.any((t) => t.status == DownloadStatus.done)) return 0;

    await dao.upsertTask(
      DownloadTask(
        id: 0,
        source: detail.sid.source,
        albumId: detail.sid.id,
        albumTitle: detail.title,
        chapterId: chapter.id,
        chapterIndex: chapter.index,
        chapterTitle: chapter.title,
        status: DownloadStatus.pending,
        done: 0,
        total: 0,
        failed: 0,
        error: '',
      ),
    );

    // 建立书架条目，让下载中的本子立刻出现在书架里
    await dao.upsertBookshelf(
      sid: detail.sid,
      title: detail.title,
      author: detail.authorText,
      coverUrl: detail.coverUrl,
      tags: detail.tags.join(' '),
      chapterCount: detail.chapterCount,
      downloaded: 0,
      rootPath: await _resolveRoot(),
    );

    return 1;
  }

  /// 调度队列
  void _pump() {
    final limit = _chapterConcurrency;
    while (_running.length < limit) {
      final next = tasks.firstWhereOrNull(
        (t) => t.status == DownloadStatus.pending && !_running.contains(t.id),
      );
      if (next == null) break;
      _running.add(next.id);
      unawaited(_runTask(next));
    }
    unawaited(_syncForeground());
  }

  /// 有任务在跑就拉起前台服务，空闲时关掉，避免后台被系统冻结
  Future<void> _syncForeground() async {
    final shouldRun = _running.isNotEmpty;
    if (shouldRun == _foregroundRunning) return;
    _foregroundRunning = shouldRun;

    if (shouldRun) {
      final running = tasks.where((t) => _running.contains(t.id));
      final title = running.isEmpty ? AppInfo.name : running.first.albumTitle;
      await PlatformService.startForeground(
        title: title.isEmpty ? AppInfo.name : title,
        text: '正在下载 ${_running.length} 个章节',
      );
    } else {
      await PlatformService.stopForeground();
    }
  }

  Future<ComicDetail> _detailOf(DownloadTask task) async {
    final key = task.sid.key;
    final cached = _details[key];
    if (cached != null) return cached;

    final source = sources.of(task.source);
    if (source == null) {
      throw SourceException('找不到下载源「${task.source}」');
    }
    final detail = await source.detail(task.albumId);
    _details[key] = detail;
    return detail;
  }

  Future<void> _runTask(DownloadTask task) async {
    final token = DownloadCancelToken();
    _tokens[task.id] = token;

    try {
      final source = sources.of(task.source);
      if (source == null) {
        throw SourceException('找不到下载源「${task.source}」');
      }

      final detail = await _detailOf(task);
      final chapter =
          detail.chapters.firstWhereOrNull((c) => c.id == task.chapterId) ??
          ComicChapter(
            id: task.chapterId,
            title: task.chapterTitle,
            index: task.chapterIndex,
            order: task.chapterIndex,
          );

      final plan = await source.chapterPlan(detail, chapter);
      await _updateTask(task.id, total: plan.images.length, done: 0);

      final downloader = ChapterDownloader(
        dio: source.dio,
        // 源可以自己压并发（Pixiv 走公共反代，压到 3 才不会把反代惹毛）
        maxConcurrentImages: source.imageConcurrencyOverride ?? _imageConcurrency,
        jpegQuality: settings.jpegQuality,
        hideFromGallery: settings.hideFromGallery,
      );

      final result = await downloader.download(
        sid: task.sid,
        plan: plan,
        chapterIndex: task.chapterIndex,
        root: await _resolveRoot(),
        cancelToken: token,
        onProgress: (p) {
          _updateTask(task.id, done: p.done, total: p.total, failed: p.failed);
          // 通知栏一秒刷一次就够，用户看不出差别，但系统负担差几十倍
          final now = DateTime.now();
          if (now.difference(_lastProgressNotify) >=
              const Duration(seconds: 1)) {
            _lastProgressNotify = now;
            unawaited(
              NotificationService.instance.showProgress(
                title: task.albumTitle.isEmpty
                    ? task.chapterTitle
                    : task.albumTitle,
                done: p.done,
                total: p.total,
              ),
            );
          }
        },
      );

      // 记下实际落盘目录，「已下载」以后就不再靠猜路径
      await _updateTask(task.id, dirPath: result.dir);

      // 这一章大半成功就恢复正常并发，否则降档
      if (result.done > 0 && (result.done - result.failed) * 2 > result.done) {
        _recentFailures = 0;
      } else {
        _recentFailures = (_recentFailures + 1).clamp(0, 3);
      }

      if (result.failed > 0 && result.done == result.failed) {
        await _updateTask(
          task.id,
          status: DownloadStatus.failed,
          error: '全部图片下载失败，可能是网络或风控问题',
        );
        await NotificationService.instance.showFailed(
          title: task.chapterTitle,
          error: '全部图片下载失败',
        );
      } else {
        await _updateTask(
          task.id,
          status: DownloadStatus.done,
          error: result.failed > 0 ? '${result.failed} 张失败' : '',
        );
        await NotificationService.instance.showDone(
          title: task.albumTitle.isEmpty ? task.chapterTitle : task.albumTitle,
          count: result.done,
        );
      }
    } on DownloadCancelledException {
      await _updateTask(task.id, status: DownloadStatus.paused);
      await NotificationService.instance.cancelProgress();
    } on Exception catch (e) {
      await _updateTask(
        task.id,
        status: DownloadStatus.failed,
        error: e.toString(),
      );
      await NotificationService.instance.showFailed(
        title: task.chapterTitle,
        error: e.toString(),
      );
    } finally {
      _tokens.remove(task.id);
      _running.remove(task.id);
      await _syncBookshelf(task.sid);
      _safeNotify();
      _pump();
    }
  }

  /// 同步书架已下载章节数
  Future<void> _syncBookshelf(SourceId sid) async {
    final done = tasks
        .where((t) => t.sid == sid && t.status == DownloadStatus.done)
        .map((t) => t.chapterIndex)
        .toSet()
        .length;
    await dao.updateDownloaded(sid, done);
  }

  Future<void> _updateTask(
    int id, {
    DownloadStatus? status,
    int? done,
    int? total,
    int? failed,
    String? error,
    String? dirPath,
  }) async {
    final index = tasks.indexWhere((t) => t.id == id);
    if (index < 0) return;
    final updated = tasks[index].copyWith(
      status: status,
      done: done,
      total: total,
      failed: failed,
      error: error,
      dirPath: dirPath,
    );
    tasks = [...tasks]..[index] = updated;
    _safeNotify();

    // 状态变化立刻落库（进程随时可能被系统回收），
    // 而「进度」每秒变几十次，攒起来批量写。
    if (status != null || error != null || dirPath != null) {
      _pendingWrites.remove(id);
      await _flushWrites();
      await dao.upsertTask(updated);
    } else {
      _scheduleWrite(updated);
    }
  }

  /// 攒 1 秒再落库一次
  void _scheduleWrite(DownloadTask task) {
    _pendingWrites[task.id] = task;
    _writeTimer ??= Timer(const Duration(seconds: 1), () {
      _writeTimer = null;
      unawaited(_flushWrites());
    });
  }

  Future<void> _flushWrites() async {
    _writeTimer?.cancel();
    _writeTimer = null;
    if (_pendingWrites.isEmpty) return;
    final batch = _pendingWrites.values.toList();
    _pendingWrites.clear();
    for (final task in batch) {
      await dao.upsertTask(task);
    }
  }

  /// 暂停 / 取消
  void cancelTask(int id) {
    _tokens[id]?.cancel();
    if (!_running.contains(id)) {
      unawaited(_updateTask(id, status: DownloadStatus.paused));
    }
  }

  /// 重新下载
  Future<void> retryTask(int id) async {
    final index = tasks.indexWhere((t) => t.id == id);
    if (index >= 0) _details.remove(tasks[index].sid.key);
    await _updateTask(
      id,
      status: DownloadStatus.pending,
      done: 0,
      failed: 0,
      error: '',
    );
    _pump();
  }

  Future<void> deleteTask(int id) async {
    _tokens[id]?.cancel();
    await dao.deleteTask(id);
    tasks = tasks.where((t) => t.id != id).toList();
    _safeNotify();
    _pump();
  }

  Future<void> clearFinished() async {
    for (final t in tasks.where((t) => t.status == DownloadStatus.done)) {
      await dao.deleteTask(t.id);
    }
    await reload();
    _pump();
  }

  /// 节流通知，避免高频刷新拖慢界面
  void _safeNotify() {
    if (_disposed) return;
    if (_notifyThrottle?.isActive ?? false) {
      _notifyPending = true;
      return;
    }
    notifyListeners();
    _notifyThrottle = Timer(const Duration(milliseconds: 200), () {
      if (_notifyPending && !_disposed) {
        _notifyPending = false;
        notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _notifyThrottle?.cancel();
    unawaited(_flushWrites());
    for (final t in _tokens.values) {
      t.cancel();
    }
    if (_foregroundRunning) {
      _foregroundRunning = false;
      unawaited(PlatformService.stopForeground());
    }
    super.dispose();
  }
}

extension _FirstWhereOrNull<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final e in this) {
      if (test(e)) return e;
    }
    return null;
  }
}
