// 图片乱序还原算法的单元测试
// 期望值来自 jmcomic 官方 Python 实现，确保 Dart 移植结果一致
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:jm_reader/jm/jm_scramble.dart';

void main() {
  group('getNum', () {
    test('aid 小于 scramble_id 时无需还原', () {
      expect(JmScramble.getNum('220980', '147451', '00001.webp'), 0);
    });

    test('aid 在 220980 与 268850 之间固定切成 10 段', () {
      expect(JmScramble.getNum('220980', '230000', '00001.webp'), 10);
    });

    test('与官方实现一致：1474516 / 00001.webp => 12', () {
      expect(JmScramble.getNum('220980', '1474516', '00001.webp'), 12);
    });

    test('文件名是否带后缀不影响结果', () {
      expect(
        JmScramble.getNum('220980', '1474516', '00001'),
        JmScramble.getNum('220980', '1474516', '00001.webp'),
      );
    });

    test('切割数始终为偶数且不超过 20', () {
      for (var aid = 421926; aid < 422926; aid += 97) {
        final num = JmScramble.getNum('220980', '$aid', '00003.jpg');
        expect(num, greaterThanOrEqualTo(2));
        expect(num, lessThanOrEqualTo(20));
        expect(num.isEven, isTrue);
      }
    });
  });

  group('descramble', () {
    test('还原后条带顺序恢复为原始顺序', () {
      const w = 8;
      const h = 40;
      final source = img.Image(width: w, height: h);
      final colors = [
        img.ColorRgb8(255, 0, 0),
        img.ColorRgb8(0, 255, 0),
        img.ColorRgb8(0, 0, 255),
        img.ColorRgb8(255, 255, 0),
      ];
      for (var y = 0; y < h; y++) {
        final color = colors[(y ~/ 10).clamp(0, 3)];
        for (var x = 0; x < w; x++) {
          source.setPixelRgb(x, y, color.r, color.g, color.b);
        }
      }

      // 人为把 4 段逆序，模拟禁漫的处理
      final scrambled = img.Image(width: w, height: h);
      for (var i = 0; i < 4; i++) {
        final strip = img.copyCrop(
          source,
          x: 0,
          y: (3 - i) * 10,
          width: w,
          height: 10,
        );
        img.compositeImage(scrambled, strip, dstX: 0, dstY: i * 10);
      }

      final restored = JmScramble.descramble(scrambled, 4);

      for (var y = 0; y < h; y++) {
        final expected = colors[(y ~/ 10).clamp(0, 3)];
        final actual = restored.getPixel(0, y);
        expect(actual.r, expected.r, reason: 'y=$y 红色通道不一致');
        expect(actual.g, expected.g, reason: 'y=$y 绿色通道不一致');
        expect(actual.b, expected.b, reason: 'y=$y 蓝色通道不一致');
      }
    });

    test('num 为 0 时原样返回', () {
      final image = img.Image(width: 4, height: 4);
      expect(identical(JmScramble.descramble(image, 0), image), isTrue);
    });
  });
}
