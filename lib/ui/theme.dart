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
          ? const Color(0xFF11151B)
          : scheme.surfaceContainerLowest,
    );

    return base.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: base.scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: base.cardTheme.copyWith(
        clipBehavior: Clip.antiAlias,
        elevation: 0,
        color: isDark ? const Color(0xFF1C222B) : scheme.surfaceContainerLow,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      listTileTheme: base.listTileTheme.copyWith(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        elevation: 0,
        backgroundColor: isDark ? const Color(0xFF181E26) : scheme.surface,
        indicatorColor: scheme.primaryContainer,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark
            ? const Color(0xFF202833)
            : scheme.surfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: const StadiumBorder(),
        side: BorderSide.none,
        backgroundColor: scheme.surfaceContainerLow,
        selectedColor: scheme.secondaryContainer,
        showCheckmark: false,
      ),
      tabBarTheme: base.tabBarTheme.copyWith(
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      snackBarTheme: base.snackBarTheme.copyWith(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      bottomSheetTheme: base.bottomSheetTheme.copyWith(
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
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
        Builder(
          builder: (context) => ColoredBox(
            color: Theme.of(context).colorScheme.surface
                .withValues(alpha: 0.82),
          ),
        ),
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
