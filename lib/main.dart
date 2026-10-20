import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'app_info.dart';
import 'services/desktop_window.dart';
import 'services/reader_window.dart';
import 'state/app_services.dart';
import 'ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 这个进程是来当阅读窗口的：只要一页阅读器，别的都不干
  final args = ReaderWindowArgs.fromEnvironment();
  if (args != null) {
    await runReaderWindow(args);
    return;
  }

  await _setupDesktopWindow();
  // 先把启动画面画出来，再在后台初始化数据库、下载和网络。
  // 这样即使某个服务初始化失败，用户也能看到明确的错误页，不会只剩白屏。
  runApp(const _StartupGate());
}

class _StartupGate extends StatefulWidget {
  const _StartupGate();

  @override
  State<_StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<_StartupGate> {
  bool _ready = false;
  Object? _error;
  StackTrace? _stackTrace;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      await AppServices.I.init();
    } on Object catch (error, stackTrace) {
      debugPrint('EAX管理器启动失败: $error\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _error = error;
        _stackTrace = stackTrace;
      });
      return;
    }

    if (!mounted) return;
    setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) return const JmReaderApp();

    final error = _error;
    return MaterialApp(
      title: AppInfo.name,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFE4588F)),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFE4588F),
          brightness: Brightness.dark,
        ),
      ),
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: error == null
                  ? const _StartupLoading()
                  : _StartupError(error: error, stackTrace: _stackTrace),
            ),
          ),
        ),
      ),
    );
  }
}

class _StartupLoading extends StatelessWidget {
  const _StartupLoading();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Image.asset(
            'assets/app_icon.png',
            width: 112,
            height: 112,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) =>
                const Icon(Icons.auto_stories_rounded, size: 96),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          AppInfo.name,
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 20),
        const SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2.6),
        ),
        const SizedBox(height: 14),
        Text('正在准备书架和下载服务…', style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}

class _StartupError extends StatelessWidget {
  const _StartupError({required this.error, required this.stackTrace});

  final Object error;
  final StackTrace? stackTrace;

  @override
  Widget build(BuildContext context) {
    // 只在调试时展开完整堆栈；正式版给用户看简短原因和可执行的下一步。
    final detail = kDebugMode && stackTrace != null
        ? '${error.toString()}\n\n$stackTrace'
        : error.toString();

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: 64,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 18),
          Text(
            '启动失败',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          const Text(
            '请先完全关闭应用再重新打开。如果仍然失败，把这一页截图发到交流群。',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: SelectableText(
              detail,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer,
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 电脑上把窗口摆好：合适的大小、标题，还有下次打开时回到上次的位置
///
/// 手机上这些完全没有，直接跳过。
Future<void> _setupDesktopWindow() async {
  if (Platform.isAndroid || Platform.isIOS) return;

  await windowManager.ensureInitialized();

  const fallback = Size(1360, 880);
  var size = fallback;
  Offset? position;
  try {
    final prefs = await SharedPreferences.getInstance();
    final width = prefs.getDouble('windowWidth');
    final height = prefs.getDouble('windowHeight');
    if (width != null && height != null) {
      size = Size(
        width.clamp(1000, 1900).toDouble(),
        height.clamp(660, 1100).toDouble(),
      );
    }
    final left = prefs.getDouble('windowLeft');
    final top = prefs.getDouble('windowTop');
    if (left != null && top != null) position = Offset(left, top);
  } on Object {
    // 读不到就用默认大小，不影响启动
  }

  final options = WindowOptions(
    size: size,
    minimumSize: const Size(1000, 660),
    // 不让插件自己居中：高分屏上它算出来的位置会把窗口顶到屏幕外，
    // 第一次开就放到左上角一点，之后每次都用用户自己拖到的位置。
    center: false,
    backgroundColor: Colors.transparent,
    title: AppInfo.name,
    // 不用系统那条标题栏：三个按钮交给 DesktopWindowFrame 自己画，
    // 免得某些机器上系统只画出关闭键、最小化和最大化是空白。
    titleBarStyle: TitleBarStyle.hidden,
  );

  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    // 上次可能是在最小化状态下关掉的，坐标会变成 -32000；
    // 统一夹一次，保证窗口一定落在看得见的区域。
    await windowManager.setPosition(
      DesktopWindow.clampPosition(position ?? const Offset(60, 60), size),
    );
    await windowManager.focus();
  });

  await windowManager.setPreventClose(true);
  windowManager.addListener(_DesktopWindowKeeper.instance);
}

/// 关窗前把窗口大小和位置记下来，然后立刻结束进程
///
/// 不用 windowManager.destroy()：它只是往消息队列塞一个退出消息，引擎自己
/// 收尾有时候要十几秒，这十几秒里窗口还白着挂在屏幕上点不动，看着就跟卡死
/// 一样。该存的都存完了，直接把这个进程收掉最干净，窗口立刻消失。
class _DesktopWindowKeeper with WindowListener {
  _DesktopWindowKeeper._();

  static final _DesktopWindowKeeper instance = _DesktopWindowKeeper._();

  /// 关窗流程只走一次：连点几下 ✕ 也只结束一次
  bool _closing = false;

  /// 从阅读窗口切回来时把书架刷一遍
  ///
  /// 阅读窗口是另一个进程，它写的阅读进度只有重新查一遍数据库才看得见，
  /// 不然书架上还停在上次读到的位置。
  @override
  void onWindowFocus() {
    unawaited(_refreshShelf());
  }

  Future<void> _refreshShelf() async {
    try {
      await AppServices.I.reloadLibrary();
    } on Object {
      // 还没初始化完就算了，下次切回来再刷
    }
  }

  @override
  void onWindowClose() async {
    if (_closing) return;
    _closing = true;

    try {
      // 窗口问不到大小位置也不能一直等，一秒多还没回就照旧用默认值
      await _rememberGeometry().timeout(const Duration(milliseconds: 1200));
    } on Object {
      // 记不住就算了，下次用默认大小
    }

    exit(0);
  }

  Future<void> _rememberGeometry() async {
    final prefs = await SharedPreferences.getInstance();
    final size = await windowManager.getSize();
    final position = await windowManager.getPosition();
    // 最小化时窗口会被挪到 -32000，尺寸也只剩任务栏那一小条；
    // 这种值存下来下次打开就看不见窗口了，直接跳过。
    if (size.width >= 400 && size.height >= 300) {
      await prefs.setDouble('windowWidth', size.width);
      await prefs.setDouble('windowHeight', size.height);
    }
    if (position.dx > -10000 && position.dy > -10000) {
      await prefs.setDouble('windowLeft', position.dx);
      await prefs.setDouble('windowTop', position.dy);
    }
  }
}
