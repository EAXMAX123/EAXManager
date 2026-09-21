/// 通用章节下载引擎
///
/// 与具体源无关：拿 [ChapterPlan] 里的图片地址并发下载，
/// 失败按 [ChapterPlan.refresh] 换地址重试，JM 的乱序还原放在独立 isolate 里做。
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../jm/jm_scramble.dart';
import '../jm/jm_storage.dart';
import 'comic_source.dart';
import 'image_worker_pool.dart';

/// 取消令牌
class DownloadCancelToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;

  void throwIfCancelled() {
    if (_cancelled) throw const DownloadCancelledException();
  }
}

class DownloadCancelledException implements Exception {
  const DownloadCancelledException();

  @override
  String toString() => '已取消';
}

/// 单章下载进度
class ChapterProgress {
  const ChapterProgress({
    required this.done,
    required this.total,
    required this.failed,
  });

  final int done;
  final int total;
  final int failed;

  double get ratio => total == 0 ? 0 : done / total;
}

/// 下载结果
class ChapterResult {
  const ChapterResult({
    required this.dir,
    required this.done,
    required this.failed,
    required this.skipped,
  });

  final String dir;
  final int done;
  final int failed;
  final int skipped;
}

class ChapterDownloader {
  ChapterDownloader({
    required this.dio,
    this.maxConcurrentImages = 5,
    this.jpegQuality = 95,
    this.retryPerImage = 2,
    this.hideFromGallery = true,
  });

  final Dio dio;
  final int maxConcurrentImages;
  final int jpegQuality;
  final int retryPerImage;

  /// 下载目录要不要对系统相册隐藏
  final bool hideFromGallery;

  Future<ChapterResult> download({
    required SourceId sid,
    required ChapterPlan plan,
    required int chapterIndex,
    required String root,
    void Function(ChapterProgress progress)? onProgress,
    DownloadCancelToken? cancelToken,
  }) async {
    final dirPath = JmStorage.photoDir(
      JmStorage.sourceRoot(root, sid.source),
      sid.id,
      chapterIndex,
    );
    await JmStorage.ensureDir(dirPath);

    // 先把「别进相册」的标记放好再下图片。
    // 等图片落了盘再补标记就晚了——相册早把它们收进去了，
    // 而事后去媒体库里清记录在部分 ROM 上会连文件一起删掉。
    if (hideFromGallery) {
      await JmStorage.writeNoMedia([JmStorage.sourceRoot(root, sid.source)]);
    }

    final total = plan.images.length;
    var done = 0;
    var failed = 0;
    var skipped = 0;
    final lock = _CounterLock();

    var cursor = 0;

    // 需要先解析页面才能拿到地址的源（EH），每个下标只解析一次
    final resolved = <int, ChapterImage>{};

    Future<void> worker() async {
      while (true) {
        cancelToken?.throwIfCancelled();
        if (cursor >= total) return;
        final index = cursor++;

        var image = plan.images[index];
        final resolver = plan.resolve;
        if (resolver != null) {
          try {
            image = resolved[index] ??= await resolver(index, image);
          } on DownloadCancelledException {
            rethrow;
          } on Exception {
            // 解析地址失败只算这一张失败。EH 的图片地址要先进一次页面才拿得到，
            // 偶尔被限流很正常，不能因此让整话下载整体失败。
            await lock.run(() {
              done++;
              failed++;
            });
            onProgress?.call(
              ChapterProgress(done: done, total: total, failed: failed),
            );
            continue;
          }
        }
        final suffix = _outputSuffix(image.fileName);
        final target = File(
          '$dirPath/${JmStorage.imageFileName(index + 1, suffix)}',
        );

        if (await target.exists() && await target.length() > 0) {
          await lock.run(() {
            done++;
            skipped++;
          });
          onProgress?.call(
            ChapterProgress(done: done, total: total, failed: failed),
          );
          continue;
        }

        try {
          await _fetchOne(
            sid: sid,
            plan: plan,
            index: index,
            image: image,
            target: target,
            suffix: suffix,
            cancelToken: cancelToken,
          );
          await lock.run(() => done++);
        } on DownloadCancelledException {
          rethrow;
        } on Exception {
          await lock.run(() {
            done++;
            failed++;
          });
        }

        onProgress?.call(
          ChapterProgress(done: done, total: total, failed: failed),
        );
      }
    }

    final n = maxConcurrentImages.clamp(1, 16);
    await Future.wait([for (var i = 0; i < n; i++) worker()]);

    return ChapterResult(
      dir: dirPath,
      done: done,
      failed: failed,
      skipped: skipped,
    );
  }

  Future<void> _fetchOne({
    required SourceId sid,
    required ChapterPlan plan,
    required int index,
    required ChapterImage image,
    required File target,
    required String suffix,
    DownloadCancelToken? cancelToken,
  }) async {
    var current = image;

    for (var attempt = 0; attempt <= retryPerImage; attempt++) {
      cancelToken?.throwIfCancelled();
      try {
        final resp = await dio.get<List<int>>(
          current.url,
          options: Options(
            responseType: ResponseType.bytes,
            headers: current.headers,
          ),
        );
        final bytes = resp.data;
        if (bytes == null || bytes.isEmpty) {
          throw const FormatException('图片响应为空');
        }

        final payload = await _prepare(
          Uint8List.fromList(bytes),
          plan: plan,
          fileName: current.fileName,
          suffix: suffix,
        );
        await target.writeAsBytes(payload, flush: true);
        return;
      } on DownloadCancelledException {
        rethrow;
      } on Exception {
        if (attempt >= retryPerImage) rethrow;
        // 换个地址再试（JM 会轮换图片 CDN 节点）
        current = plan.refresh?.call(index) ?? current;
        await Future<void>.delayed(Duration(milliseconds: 300 * (attempt + 1)));
      }
    }
  }

  Future<Uint8List> _prepare(
    Uint8List bytes, {
    required ChapterPlan plan,
    required String fileName,
    required String suffix,
  }) async {
    if (plan.scrambleId.isEmpty) return bytes;

    // 注意：算乱序段数用的是**去掉后缀**的文件名，和上游 jmcomic 一致
    final bare = JmScramble.trimSuffix(fileName);
    final num = JmScramble.getNum(plan.scrambleId, plan.scrambleAid, bare);
    if (num == 0) return bytes;

    // 解码与重排是 CPU 密集操作，交给常驻 isolate 池：
    // 既不阻塞 UI，也不会像 Isolate.run 那样每张图都新建销毁一个 isolate
    return ImageWorkerPool.instance.descramble(
      bytes: bytes,
      num: num,
      suffix: suffix,
      quality: jpegQuality,
    );
  }

  /// 还原后会重新编码，所以除了 PNG 一律按 JPEG 存
  static String _outputSuffix(String sourceFileName) =>
      sourceFileName.toLowerCase().endsWith('.png') ? '.png' : '.jpg';
}

/// 简单的异步计数器，避免并发写竞争
class _CounterLock {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(T Function() action) {
    final completer = Completer<T>();
    _tail = _tail.then((_) {
      try {
        completer.complete(action());
      } on Object catch (e, s) {
        completer.completeError(e, s);
      }
    });
    return completer.future;
  }
}
