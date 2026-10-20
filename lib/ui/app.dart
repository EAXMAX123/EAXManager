import 'dart:async';

import 'package:flutter/material.dart';

import '../app_info.dart';
import '../data/app_docs.dart';
import '../data/settings_store.dart';
import '../state/app_services.dart';
import '../services/platform_service.dart';
import 'pages/about_page.dart';
import 'pages/downloads_page.dart';
import 'pages/home_page.dart';
import 'pages/library_page.dart';
import 'pages/settings_page.dart';
import 'theme.dart';
import 'widgets/changelog_dialog.dart';
import 'widgets/desktop_window_frame.dart';
import 'widgets/mascot_navigation_bar.dart';
import 'widgets/retained_tabs.dart';

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
          themeAnimationDuration: const Duration(milliseconds: 200),
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
            // 电脑上套一层自绘标题栏（最小化/最大化/关闭），手机不需要
            child: PlatformService.isDesktop
                ? const DesktopWindowFrame(child: RootShell())
                : const RootShell(),
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

  /// 版本公告弹窗只开一个
  bool _changelogDialogOpen = false;

  /// 启动时的公告和更新提示按顺序来，避免两个弹窗叠在一起
  bool _startupNoticesDone = false;

  @override
  void initState() {
    super.initState();
    AppServices.I.pendingUpdate.addListener(_onUpdateFound);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_runStartupNotices());
    });
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
    // 先让本次版本的公告弹完，更新提示随后再弹
    if (!_startupNoticesDone || _changelogDialogOpen) return;
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

  Future<void> _runStartupNotices() async {
    try {
      await _maybeShowChangelog();
    } catch (_) {
      // 公告读失败也不能把更新提示一起卡住
    } finally {
      _startupNoticesDone = true;
    }
    if (!mounted) return;
    if (AppServices.I.pendingUpdate.value != null) {
      await _onUpdateFound();
    }
  }

  /// 装好新版本后第一次打开，弹一次这一版改了什么
  Future<void> _maybeShowChangelog() async {
    if (_changelogDialogOpen || !mounted) return;
    final entry = Changelog.entryFor(AppInfo.version);
    if (entry == null) return;

    final seen = await ChangelogNoticeStore.load();
    if (!mounted || seen.trim() == AppInfo.version) return;

    _changelogDialogOpen = true;
    bool? openRecords;
    try {
      openRecords = await ChangelogDialog.show(context, entry);
      await ChangelogNoticeStore.save(AppInfo.version);
    } finally {
      _changelogDialogOpen = false;
    }

    if (!mounted) return;
    if (openRecords == true) {
      setState(() => _index = 4);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 设置了背景图时才把页面背景透明化去透出底图；
    // 否则保持主题底色，避免露出 Android 窗口背景（深色模式下是纯黑）
    final settingsNow = AppServices.I.settings.value;
    final hasImage = AppTheme.hasBackgroundImage(settingsNow.backgroundColor);
    // 电脑上窗口是横着的，导航放左边比压在底下顺手，也能少占一条边
    final wide = MediaQuery.sizeOf(context).width >= 900;

    final content = RetainedTabs(
      index: _index,
      builders: [
        (_) => const HomePage(),
        (_) => const LibraryPage(),
        (_) => const DownloadsPage(),
        (_) => const SettingsPage(),
        (_) => const AboutPage(),
      ],
    );

    void select(int index) {
      if (index == _index) return;
      FocusManager.instance.primaryFocus?.unfocus();
      setState(() => _index = index);
    }

    if (wide) {
      return Scaffold(
        backgroundColor: hasImage ? Colors.transparent : null,
        body: Row(
          children: [
            MascotNavigationRail(
              selectedIndex: _index,
              onDestinationSelected: select,
            ),
            VerticalDivider(
              width: 1,
              thickness: 1,
              color: Theme.of(context).dividerColor.withValues(alpha: 0.4),
            ),
            Expanded(
              child: Column(
                children: [
                  _desktopHeader(context, hasImage),
                  Expanded(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1360),
                        child: content,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: hasImage ? Colors.transparent : null,
      appBar: AppBar(
        title: AnimatedSwitcher(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 160),
          child: Text(_titles[_index], key: ValueKey(_index)),
        ),
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
      body: content,
      bottomNavigationBar: MascotNavigationBar(
        selectedIndex: _index,
        onDestinationSelected: select,
      ),
    );
  }

  /// 电脑端顶栏：左边是当前页标题
  Widget _desktopHeader(BuildContext context, bool hasImage) {
    final theme = Theme.of(context);
    return Container(
      height: 54,
      color: hasImage
          ? theme.colorScheme.surface.withValues(alpha: 0.88)
          : null,
      padding: const EdgeInsets.only(left: 20, right: 14),
      child: Row(
        children: [
          AnimatedSwitcher(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 160),
            child: Text(
              _titles[_index],
              key: ValueKey(_index),
              style: theme.textTheme.titleMedium?.copyWith(
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
