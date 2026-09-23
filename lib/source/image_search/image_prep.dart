/// 识图前的图片预处理
///
/// 手机截图和扫描图四周常常带一圈黑边、白边或者状态栏，直接拿去搜会把
/// 相似度拉低。这里先裁掉四周的纯色边框，再等比缩放，最后编码成 JPEG。
library;

import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// 处理好的图片
class PreparedImage {
  const PreparedImage({required this.bytes, required this.image, required this.inset});

  /// JPEG 字节，直接拿去上传
  final Uint8List bytes;

  /// 处理后的图（已裁边、已缩放）；分段重搜时从它上面切，不用重新解码
  final img.Image image;

  /// 四周一共裁掉了多少像素，0 表示没裁
  final int inset;

  int get width => image.width;
  int get height => image.height;
}

/// 切出来的一段
class ImageRegion {
  const ImageRegion({required this.label, required this.bytes});

  /// 上段 / 中段 / 下段
  final String label;

  final Uint8List bytes;
}

class ImagePrep {
  ImagePrep._();

  /// 识图站对超大图没有额外收益，1600 已经够用，还能省流量
  static const int maxSide = 1600;

  /// 比这还小就别折腾了，识图站认不出来
  static const int minSide = 240;

  static const int jpegQuality = 90;

  /// 和参考色差多少以内算「同一个颜色」
  static const int _tolerance = 28;

  /// 一行/一列里至少这么大比例是参考色，才算边框
  static const double _edgeRatio = 0.9;

  /// 单边最多裁掉这么长，防止判断失误把整张图裁没
  static const double _maxInsetRatio = 0.4;

  /// 裁完剩下的面积小于这个比例，就当是判断错了，宁可不裁
  static const double _minKeepRatio = 0.1;

  /// 高宽比超过它才算「长图」，才值得切段
  ///
  /// 正常封面大概 1.3~1.5，切了没意义；手机截图动辄 2.2，才需要切。
  static const double _tallRatio = 1.6;

  /// 裁边框 → 缩放 → 编码
  ///
  /// 返回 null 表示这张图解不开（不是图片，或者格式不支持）。
  static PreparedImage? prepare(Uint8List raw) {
    // 不是图片的字节会让 decodeImage 直接抛异常（image 包对某些格式是这么干的），
    // 所以这里必须包起来，不能只判 null。
    img.Image? decoded;
    try {
      decoded = img.decodeImage(raw);
    } on Object {
      return null;
    }
    if (decoded == null) return null;

    final cropped = autocrop(decoded);
    final inset =
        (decoded.width - cropped.width) + (decoded.height - cropped.height);

    var image = cropped;
    final longest = image.width > image.height ? image.width : image.height;
    if (longest > maxSide) {
      final scale = maxSide / longest;
      image = img.copyResize(
        image,
        width: (image.width * scale).round().clamp(1, maxSide),
        height: (image.height * scale).round().clamp(1, maxSide),
        interpolation: img.Interpolation.linear,
      );
    }

    return PreparedImage(
      bytes: img.encodeJpg(image, quality: jpegQuality),
      image: image,
      inset: inset,
    );
  }

  /// 裁掉四周的纯色边框
  ///
  /// 判断不出来就直接返回原图 —— 宁可多带一圈边，也不能把内容裁掉。
  static img.Image autocrop(img.Image src) {
    final w = src.width;
    final h = src.height;
    if (w < minSide || h < minSide) return src;

    final ref = _borderColor(src);
    if (ref == null) return src;

    final maxX = (w * _maxInsetRatio).round();
    final maxY = (h * _maxInsetRatio).round();

    var left = 0;
    var right = w - 1;
    var top = 0;
    var bottom = h - 1;

    while (left < maxX && _isBorderLine(src, ref, left, false)) {
      left++;
    }
    while ((w - 1 - right) < maxX && _isBorderLine(src, ref, right, false)) {
      right--;
    }
    while (top < maxY && _isBorderLine(src, ref, top, true)) {
      top++;
    }
    while ((h - 1 - bottom) < maxY && _isBorderLine(src, ref, bottom, true)) {
      bottom--;
    }

    final nw = right - left + 1;
    final nh = bottom - top + 1;
    if (nw < minSide || nh < minSide) return src;
    // 裁掉太多说明判断错了，宁可不动
    if (nw * nh < w * h * _minKeepRatio) return src;
    if (left == 0 && top == 0 && right == w - 1 && bottom == h - 1) return src;

    return img.copyCrop(src, x: left, y: top, width: nw, height: nh);
  }

  /// 找出边框颜色
  ///
  /// 取四条最外边上的众数色。如果这些边本身就不均匀（说明根本没有统一
  /// 颜色的边框），返回 null，免得误裁。
  static int? _borderColor(img.Image im) {
    final buckets = <int, int>{};
    var total = 0;

    void sample(int x, int y) {
      final p = im.getPixel(x, y);
      final key =
          ((p.r.toInt() >> 4) << 8) |
          ((p.g.toInt() >> 4) << 4) |
          (p.b.toInt() >> 4);
      buckets[key] = (buckets[key] ?? 0) + 1;
      total++;
    }

    for (var x = 0; x < im.width; x++) {
      sample(x, 0);
      if (im.height > 1) sample(x, im.height - 1);
    }
    for (var y = 0; y < im.height; y++) {
      sample(0, y);
      if (im.width > 1) sample(im.width - 1, y);
    }
    if (total == 0) return null;

    var best = 0;
    var bestCount = 0;
    for (final entry in buckets.entries) {
      if (entry.value > bestCount) {
        bestCount = entry.value;
        best = entry.key;
      }
    }
    if (bestCount / total < _edgeRatio) return null;

    final r = ((best >> 8) & 0xF) * 16 + 8;
    final g = ((best >> 4) & 0xF) * 16 + 8;
    final b = (best & 0xF) * 16 + 8;
    return (r << 16) | (g << 8) | b;
  }

  /// 这一行（row=true）或这一列（row=false）是不是整条都接近参考色
  static bool _isBorderLine(img.Image im, int ref, int index, bool row) {
    final count = row ? im.width : im.height;
    if (count <= 0) return false;

    // 长边不用逐像素看，隔几个取一个就够
    final step = count > 400 ? count ~/ 400 : 1;
    var same = 0;
    var total = 0;
    for (var i = 0; i < count; i += step) {
      final pixel = row ? im.getPixel(i, index) : im.getPixel(index, i);
      total++;
      if (_closeTo(ref, pixel)) same++;
    }
    return total > 0 && same / total >= _edgeRatio;
  }

  static bool _closeTo(int ref, img.Pixel pixel) {
    final dr = ((ref >> 16) & 0xFF) - pixel.r.toInt();
    final dg = ((ref >> 8) & 0xFF) - pixel.g.toInt();
    final db = (ref & 0xFF) - pixel.b.toInt();
    return dr.abs() <= _tolerance &&
        dg.abs() <= _tolerance &&
        db.abs() <= _tolerance;
  }

  /// 整图认不出时用的分段
  ///
  /// 封面常常只占长图的一小块，把整张图切开来单独搜，命中率会高不少。
  /// 只有明显偏长的图才切，正常封面比例切了反而更差。
  static List<ImageRegion> regions(PreparedImage prepared, {int maxCount = 3}) {
    final source = prepared.image;
    if (source.height < source.width * _tallRatio) return const [];

    const labels = ['上段', '中段', '下段'];
    final h = source.height;
    final bandHeight = (h * 0.5).round();
    if (bandHeight < minSide) return const [];

    final starts = <int>[0, ((h - bandHeight) / 2).round(), h - bandHeight];

    final out = <ImageRegion>[];
    final used = <int>{};
    for (var i = 0; i < starts.length && out.length < maxCount; i++) {
      final start = starts[i].clamp(0, h - bandHeight);
      if (!used.add(start)) continue;
      final crop = img.copyCrop(
        source,
        x: 0,
        y: start,
        width: source.width,
        height: bandHeight,
      );
      out.add(
        ImageRegion(
          label: labels[i],
          bytes: img.encodeJpg(crop, quality: jpegQuality),
        ),
      );
    }
    return out;
  }
}
