// 主题与背景的回归测试
//
// 之前页面 Scaffold 被写死成透明，导致背景透出 Android 窗口底色，
// 浅色/深色都显示黑色。这里锁住主题底色必须是实色。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jm_reader/ui/theme.dart';

void main() {
  group('AppTheme.build', () {
    test('浅色主题的底色是浅色', () {
      final theme = AppTheme.build(
        brightness: Brightness.light,
        seed: 0xFFE91E63,
      );
      final color = theme.scaffoldBackgroundColor;

      expect(color.a, 1.0, reason: '底色必须不透明，否则会透出窗口背景');
      expect(color.computeLuminance(), greaterThan(0.5));
    });

    test('深色主题的底色是深色', () {
      final theme = AppTheme.build(
        brightness: Brightness.dark,
        seed: 0xFFE91E63,
      );
      final color = theme.scaffoldBackgroundColor;

      expect(color.a, 1.0);
      expect(color.computeLuminance(), lessThan(0.2));
    });

    test('浅色与深色底色不同', () {
      final light = AppTheme.build(
        brightness: Brightness.light,
        seed: 0xFFE91E63,
      );
      final dark = AppTheme.build(
        brightness: Brightness.dark,
        seed: 0xFFE91E63,
      );

      expect(
        light.scaffoldBackgroundColor,
        isNot(dark.scaffoldBackgroundColor),
      );
    });
  });

  group('hasBackgroundImage', () {
    test('未设置或文件不存在时返回 false', () {
      expect(AppTheme.hasBackgroundImage(''), isFalse);
      expect(AppTheme.hasBackgroundImage('   '), isFalse);
      expect(AppTheme.hasBackgroundImage('/not/exist/bg.png'), isFalse);
    });
  });

  testWidgets('没有背景图时 backgroundDecor 不包一层透明 Stack', (tester) async {
    const child = Text('内容');
    final decorated = AppTheme.backgroundDecor(imagePath: '', child: child);

    expect(decorated, same(child));
  });
}
