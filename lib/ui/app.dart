import 'package:flutter/material.dart';

import '../app_info.dart';
import '../data/settings_store.dart';
import '../state/app_services.dart';
import '../services/platform_service.dart';
import 'pages/about_page.dart';
import 'pages/downloads_page.dart';
import 'pages/home_page.dart';
import 'pages/library_page.dart';
import 'pages/settings_page.dart';
import 'theme.dart';

class JmReaderApp extends StatelessWidget {
  const JmReaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppSettings>(
      valueListenable: AppServices.I.settings,
      builder: (context, settings, _) {
        return MaterialApp(
          title: AppInfo.name,
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
          home: AppTheme.backgroundDecor(
            imagePath: settings.backgroundColor,
            child: const RootShell(),
          ),
        );
      },
    );
  }
}

class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;

  static const _titles = ['发现', '书架', '下载', '设置', '关于'];

  /// 防止「自动检查」和「手动检查」同时把弹窗弹两遍
  bool _updateDialogOpen = false;

  @override
  void initState() {
    super.initState();
    AppServices.I.pendingUpdate.addListener(_onUpdateFound);
  }

  @override
  void dispose() {
    AppServices.I.pendingUpdate.removeListener(_onUpdateFound);
    super.dispose();
  }

  /// 检查到新版本：弹一次窗，之后到浏览器里下载
  Future<void> _onUpdateFound() async {
    final update = AppServices.I.pendingUpdate.value;
    if (update == null || _updateDialogOpen || !mounted) return;
    _updateDialogOpen = true;
    // 记下来，下次启动不再自动弹同一个版本
    await AppServices.I.markUpdateNotified(update.version);
    if (!mounted) {
      _updateDialogOpen = false;
      return;
    }

    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('发现新版本 v${update.version}'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('当前版本 ${AppInfo.fullVersionText}'),
              if (update.notes.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(update.notes),
              ],
              if (update.url.isEmpty) ...[
                const SizedBox(height: 12),
                const Text('这次没给下载地址，到交流群里问一下最新安装包。'),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('稍后'),
          ),
          if (update.url.isNotEmpty)
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('前往下载'),
            ),
        ],
      ),
    );

    _updateDialogOpen = false;
    AppServices.I.pendingUpdate.value = null;
    if (go == true && update.url.isNotEmpty) {
      // 先挑一条真能下到的线路（GitHub 直连在国内基本不通）
      final target = await AppServices.I.resolveDownloadUrl(update.url);
      await PlatformService.openUrl(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 只有设置了背景图才把页面背景透明化去透出图片；
    // 否则保持主题底色，避免露出 Android 窗口背景（深色模式下是纯黑）
    final hasImage = AppTheme.hasBackgroundImage(
      AppServices.I.settings.value.backgroundColor,
    );

    return Scaffold(
      backgroundColor: hasImage ? Colors.transparent : null,
      appBar: AppBar(
        title: Text(_titles[_index]),
        backgroundColor: hasImage ? Colors.transparent : null,
        // 标题压小、贴左上角，给下方的 TabBar / 内容让出空间
        toolbarHeight: 48,
        titleSpacing: 12,
        centerTitle: false,
        titleTextStyle: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
      body: IndexedStack(
        index: _index,
        children: const [
          HomePage(),
          LibraryPage(),
          DownloadsPage(),
          SettingsPage(),
          AboutPage(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore),
            label: '发现',
          ),
          NavigationDestination(
            icon: Icon(Icons.collections_bookmark_outlined),
            selectedIcon: Icon(Icons.collections_bookmark),
            label: '书架',
          ),
          NavigationDestination(
            icon: Icon(Icons.download_outlined),
            selectedIcon: Icon(Icons.download),
            label: '下载',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '设置',
          ),
          NavigationDestination(
            icon: Icon(Icons.info_outline),
            selectedIcon: Icon(Icons.info),
            label: '关于',
          ),
        ],
      ),
    );
  }
}
