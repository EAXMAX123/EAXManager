/// 常驻 isolate 工作池：把图片还原（解码 → 重排 → 重编码）搬离主线程
///
/// 之前每张图都用一次 `Isolate.run`，而它每次都会**新建并销毁**一个 isolate。
/// 一章 40 张图就是 40 次起停，8 章并发时几百个 isolate 反复创建销毁，
/// 手机又烫又卡。这里改成常驻几个 worker，用完不销毁。
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../jm/jm_scramble.dart';

class ImageWorkerPool {
  ImageWorkerPool._(this._size);

  static ImageWorkerPool? _instance;

  /// 全局共用一个池
  static ImageWorkerPool get instance =>
      _instance ??= ImageWorkerPool._(_defaultSize());

  /// 重活是解码和重编码，留出余量给 UI 线程和网络线程
  static int _defaultSize() {
    final cores = Platform.numberOfProcessors;
    return (cores ~/ 2).clamp(2, 4);
  }

  final int _size;
  final List<_WorkerHandle> _workers = [];
  final ReceivePort _replies = ReceivePort();
  final Map<int, (Completer<Uint8List>, _WorkerHandle)> _pending = {};

  int _jobId = 0;
  Future<void>? _starting;

  Future<void> _ensureStarted() => _starting ??= _start();

  Future<void> _start() async {
    _replies.listen(_onReply);
    for (var i = 0; i < _size; i++) {
      _workers.add(await _WorkerHandle.spawn());
    }
  }

  /// 还原一张图；[num] 为 0 表示这张图没有被乱序，调用方应直接返回原图
  Future<Uint8List> descramble({
    required Uint8List bytes,
    required int num,
    required String suffix,
    required int quality,
  }) async {
    await _ensureStarted();

    // 挑手上活最少的 worker，避免某张图特别大时其它 worker 空转
    var target = _workers.first;
    for (final worker in _workers) {
      if (worker.inflight < target.inflight) target = worker;
    }

    final id = _jobId++;
    final completer = Completer<Uint8List>();
    target.inflight++;
    _pending[id] = (completer, target);
    target.sendPort.send([id, _replies.sendPort, bytes, num, suffix, quality]);
    return completer.future;
  }

  void _onReply(dynamic message) {
    if (message is! List || message.length < 2) return;
    final id = message[0];
    if (id is! int) return;

    final entry = _pending.remove(id);
    if (entry == null) return;
    final (completer, worker) = entry;
    worker.inflight--;
    if (completer.isCompleted) return;

    if (message.length >= 3 && message[1] == null) {
      completer.completeError(FormatException(message[2].toString()));
      return;
    }
    completer.complete(message[1] as Uint8List);
  }

  /// 关掉所有 worker（测试用；正常运行时随进程结束即可）
  Future<void> dispose() async {
    for (final worker in _workers) {
      worker.isolate.kill(priority: Isolate.immediate);
    }
    _workers.clear();
    _pending.clear();
    _replies.close();
    _instance = null;
  }
}

class _WorkerHandle {
  _WorkerHandle(this.isolate, this.sendPort);

  final Isolate isolate;
  final SendPort sendPort;

  /// 该 worker 手上还没做完的活
  int inflight = 0;

  static Future<_WorkerHandle> spawn() async {
    final ready = ReceivePort();
    final isolate = await Isolate.spawn(_workerMain, ready.sendPort);
    final sendPort = await ready.first as SendPort;
    ready.close();
    return _WorkerHandle(isolate, sendPort);
  }
}

/// worker 主循环：收到一张图就处理一张，永不退出
void _workerMain(SendPort ready) {
  final port = ReceivePort();
  ready.send(port.sendPort);
  port.listen((dynamic message) {
    if (message is! List || message.length < 6) return;
    final id = message[0] as int;
    final reply = message[1] as SendPort;
    final bytes = message[2] as Uint8List;
    final num = message[3] as int;
    final suffix = message[4] as String;
    final quality = message[5] as int;
    try {
      reply.send([id, _process(bytes, num, suffix, quality)]);
    } on Object catch (error) {
      reply.send([id, null, error.toString()]);
    }
  });
}

Uint8List _process(Uint8List bytes, int num, String suffix, int quality) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) throw const FormatException('图片解码失败');
  final fixed = JmScramble.descramble(decoded, num);
  final encoded = suffix == '.png'
      ? img.encodePng(fixed)
      : img.encodeJpg(fixed, quality: quality);
  return Uint8List.fromList(encoded);
}
