/// 应用主题：颜色、背景、文字样式
library;

import 'dart:io';

import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  static ThemeData build({required Brightness brightness, required int seed}) {
    final scheme = ColorScheme.fromSeed(
      seedColor: Color(seed),
      brightness: brightness,
    );

    final isDark = brightness == Brightness.dark;
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: isDark
          ? const Color(0xFF121212)
          : scheme.surface,
    );

    return base.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? const Color(0xFF1A1A1A) : scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: base.cardTheme.copyWith(
        clipBehavior: Clip.antiAlias,
        elevation: 0,
        color: isDark ? const Color(0xFF1E1E1E) : scheme.surfaceContainerLow,
      ),
      listTileTheme: base.listTileTheme.copyWith(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isDark ? const Color(0xFF1A1A1A) : scheme.surface,
        indicatorColor: scheme.primaryContainer,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark
            ? const Color(0xFF232323)
            : scheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  /// 背景装饰：设置了背景图就用图，否则用纯色
  static Widget backgroundDecor({
    required String imagePath,
    required Widget child,
  }) {
    if (!hasBackgroundImage(imagePath)) return child;

    return Stack(
      fit: StackFit.expand,
      children: [
        Image.file(
          File(imagePath),
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
        Container(color: Colors.black.withValues(alpha: 0.35)),
        child,
      ],
    );
  }

  /// 是否配置了可用的背景图
  ///
  /// 只有这种情况下才需要把页面背景设成透明去透出图片，
  /// 否则透明背景会露出 Android 窗口底色（深色模式下就是黑的）。
  static bool hasBackgroundImage(String imagePath) {
    final path = imagePath.trim();
    if (path.isEmpty) return false;
    return File(path).existsSync();
  }
}
