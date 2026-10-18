/// 电脑版的阅读窗口：一个窗口里只放阅读器
///
/// 外壳和主窗口一样是自绘标题栏，左上角写着「阅读」，右边是最小化 / 最大化 /
/// 关闭；下面整块都是本子，点标题栏上的 ✕ 或者阅读器里的返回都会关掉这个窗口。
library;

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../data/settings_store.dart';
import '../services/reader_window.dart';
import '../state/app_services.dart';
import 'pages/reader_page.dart';
import 'theme.dart';
import 'widgets/desktop_window_frame.dart';

class ReaderWindowApp extends StatelessWidget {
  const ReaderWindowApp({super.key, required this.args});

  final ReaderWindowArgs args;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppSettings>(
      valueListenable: AppServices.I.settings,
      builder: (context, settings, _) {
        return MaterialApp(
          title: '阅读 · ${args.albumTitle}',
          debugShowCheckedModeBanner: false,
          themeMode: switch (settings.themeMode) {
            'light' => ThemeMode.light,
            'dark' => ThemeMode.dark,
            _ => ThemeMode.system,
          },
          theme: AppTheme.build(
            brightness: Brightness.light,
            seed: settings.themeSeed,
          ),
          darkTheme: AppTheme.build(
            brightness: Brightness.dark,
            seed: settings.themeSeed,
          ),
          home: DesktopWindowFrame(
            title: '阅读',
            pinPrefsKey: 'readerAlwaysOnTop',
            // 阅读器本身是纯黑的，窗口最外圈那几像素也跟着黑，
            // 别在四周留一圈浅色的边
            background: Colors.black,
            child: ReaderPage(
              sid: args.sid,
              albumTitle: args.albumTitle,
              chapterIndex: args.chapterIndex,
              chapterCount: args.chapterCount,
              onExit: () => windowManager.close(),
            ),
          ),
        );
      },
    );
  }
}
