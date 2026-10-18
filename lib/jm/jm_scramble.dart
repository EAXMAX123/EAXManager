/// 图片乱序还原：jmcomic 的 JmImageTool.get_num / decode_and_save 的 Dart 移植
///
/// 禁漫对 aid >= 220980 的本子做了「按水平条带逆序重排」处理，
/// 需要按同样规则还原后才能正常阅读。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;

import 'jm_constants.dart';

class JmScramble {
  JmScramble._();

  /// 去掉文件后缀，jmcomic 计算切割数时用的是不含后缀的文件名
  static String trimSuffix(String fileName) {
    final dot = fileName.lastIndexOf('.');
    return dot > 0 ? fileName.substring(0, dot) : fileName;
  }

  /// 计算切割条带数，0 表示无需还原
  ///
  /// [fileName] 可带后缀，内部会自动去掉（与 jmcomic 的 of_file_name(url, True) 一致）
  static int getNum(String scrambleId, String aid, String fileName) {
    final sid = int.tryParse(scrambleId) ?? JmMagic.scramble220980;
    final id = int.tryParse(aid) ?? 0;

    if (id < sid) return 0;
    if (id < JmMagic.scramble268850) return 10;

    final x = id < JmMagic.scramble421926 ? 10 : 8;
    final bare = trimSuffix(fileName);
    final digest = md5.convert(utf8.encode('$id$bare')).toString();
    var num = digest.codeUnitAt(digest.length - 1);
    num %= x;
    return num * 2 + 2;
  }

  /// 按条带逆序还原图片
  static img.Image descramble(img.Image src, int num) {
    if (num <= 0 || num == 1) return src;

    final w = src.width;
    final h = src.height;
    final dst = img.Image(width: w, height: h, numChannels: src.numChannels);
    final over = h % num;
    final base = h ~/ num;

    for (var i = 0; i < num; i++) {
      var move = base;
      final ySrc = h - (base * (i + 1)) - over;
      var yDst = base * i;

      if (i == 0) {
        move += over;
      } else {
        yDst += over;
      }

      final strip = img.copyCrop(src, x: 0, y: ySrc, width: w, height: move);
      img.compositeImage(dst, strip, dstX: 0, dstY: yDst);
    }

    return dst;
  }

  /// 解码字节流并还原，返回还原后的图片；[scrambleId] 为 0 时不做处理
  static img.Image? decodeAndDescramble(
    List<int> bytes,
    String scrambleId,
    String aid,
    String fileName,
  ) {
    final decoded = img.decodeImage(
      bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
    );
    if (decoded == null) return null;

    final num = getNum(scrambleId, aid, fileName);
    if (num == 0) return decoded;

    return descramble(decoded, num);
  }
}
