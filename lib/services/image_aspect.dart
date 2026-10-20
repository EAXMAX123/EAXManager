/// 只读图片头，拿到高宽比，不把整张图解到内存
///
/// 阅读器需要提前知道每张图多高，才能给 Sliver 一个稳定的布局；
/// PDF 分享也要靠它算页面尺寸。这里用 dart:ui 的 ImageDescriptor，
/// 只解析文件头，几百张图也不会把内存吃满。
library;

import 'dart:io';
import 'dart:ui' as ui;

class ImageAspect {
  ImageAspect._();

  /// 读不出尺寸时按常见漫画比例给个兜底
  static const double fallback = 1.4;

  /// 返回 height / width
  static Future<double> heightOverWidth(File file) async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    try {
      buffer = await ui.ImmutableBuffer.fromFilePath(file.path);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final width = descriptor.width;
      final height = descriptor.height;
      if (width <= 0 || height <= 0) return fallback;
      return (height / width).clamp(0.05, 20.0);
    } on Object {
      return fallback;
    } finally {
      descriptor?.dispose();
      buffer?.dispose();
    }
  }

  /// 一批图片的高宽比，最多同时读 4 张
  static Future<List<double>> ratios(Iterable<File> files) async {
    final list = files.toList(growable: false);
    final out = List<double>.filled(list.length, fallback);
    if (list.isEmpty) return out;

    var next = 0;
    Future<void> worker() async {
      while (true) {
        final index = next;
        if (index >= list.length) return;
        next++;
        out[index] = await heightOverWidth(list[index]);
      }
    }

    await Future.wait(
      List.generate(list.length < 4 ? list.length : 4, (_) => worker()),
    );
    return out;
  }
}
