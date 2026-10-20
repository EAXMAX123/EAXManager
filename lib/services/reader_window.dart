/// 电脑版的「阅读窗口」
///
/// 在电脑上点开一本书时另起一个进程，那个进程开出来的就是一个独立窗口：
/// 能单独拖动、缩放、最小化，主窗口留着继续挑本子，两边互不遮挡。
///
/// 为什么用新进程而不是多窗口插件：不用动原生工程，Windows 上最不容易出岔子；
/// 而且阅读窗口只读本地文件，不会把主窗口的下载、更新检查再跑一遍。
///
/// 要读什么本子用环境变量传过去（base64 包一层 JSON）。不走命令行参数是因为
/// 本子名里全是中文标点，命令行上容易被拆坏；环境变量则是原样送达。
/// 手机上没有这回事，还是页面里直接看。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import '../source/comic_source.dart';
import '../state/app_services.dart';
import '../ui/reader_window_app.dart';
import 'desktop_window.dart';

/// 阅读窗口要放哪本书的哪一话
class ReaderWindowArgs {
  const ReaderWindowArgs({
    required this.sid,
    required this.albumTitle,
    required this.chapterIndex,
    required this.chapterCount,
  });

  final SourceId sid;
  final String albumTitle;
  final int chapterIndex;
  final int chapterCount;

  /// 传给子进程的环境变量名
  static const String envKey = 'EAX_READER_WINDOW';

  Map<String, Object?> toJson() => {
    'sid': sid.key,
    'title': albumTitle,
    'chapter': chapterIndex,
    'count': chapterCount,
  };

  String encode() => base64Url.encode(utf8.encode(jsonEncode(toJson())));

  /// 从环境变量里认领这次启动要干什么；不是阅读窗口就返回 null
  static ReaderWindowArgs? fromEnvironment() {
    final raw = Platform.environment[envKey];
    if (raw == null || raw.isEmpty) return null;

    try {
      final json = jsonDecode(utf8.decode(base64Url.decode(raw)));
      if (json is! Map) return null;
      return ReaderWindowArgs(
        sid: SourceId.parse(json['sid'] as String? ?? ''),
        albumTitle: json['title'] as String? ?? '',
        chapterIndex: (json['chapter'] as num?)?.toInt() ?? 1,
        chapterCount: (json['count'] as num?)?.toInt() ?? 0,
      );
    } on Object {
      // 内容坏了就当没这回事，照常开主窗口
      return null;
    }
  }

  /// 另起一个进程开阅读窗口
  ///
  /// 返回 false 表示没开起来（免安装版被安全软件拦、路径没权限等），
  /// 调用方就退回原来的「页面里打开」。
  Future<bool> open() async {
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
      return false;
    }

    final exe = Platform.resolvedExecutable;
    try {
      await Process.start(
        exe,
        const [],
        workingDirectory: File(exe).parent.path,
        environment: {envKey: encode()},
        mode: ProcessStartMode.detached,
      );
      return true;
    } on Object {
      return false;
    }
  }
}

/// 阅读窗口这个进程的启动流程
///
/// 和主窗口很像：也是自绘标题栏那条路，只是不给它跑下载和更新检查。
Future<void> runReaderWindow(ReaderWindowArgs args) async {
  await windowManager.ensureInitialized();

  final size = await _windowSize();
  final options = WindowOptions(
    size: size,
    minimumSize: const Size(360, 420),
    center: false,
    backgroundColor: const Color(0x00000000),
    title: '阅读 · ${args.albumTitle}',
    titleBarStyle: TitleBarStyle.hidden,
  );

  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.setPosition(await _windowPosition(size));
    await windowManager.focus();
  });

  await windowManager.setPreventClose(true);
  windowManager.addListener(_ReaderWindowKeeper.instance);

  // 上次钉住的话这次照样钉着
  try {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('readerAlwaysOnTop') ?? false) {
      await windowManager.setAlwaysOnTop(true);
    }
  } on Object {
    // 钉不上就算了，标题栏上那个按钮随时能补
  }

  await AppServices.I.init(readerOnly: true);

  runApp(ReaderWindowApp(args: args));
}

const Size _fallbackSize = Size(880, 1120);

Future<Size> _windowSize() async {
  final screen = DesktopWindow.screenSize();
  final maxWidth = screen.width - 40 < 360 ? 360.0 : screen.width - 40;
  final maxHeight = screen.height - 40 < 420 ? 420.0 : screen.height - 40;

  try {
    final prefs = await SharedPreferences.getInstance();
    final width = prefs.getDouble('readerWindowWidth');
    final height = prefs.getDouble('readerWindowHeight');
    if (width != null && height != null) {
      return Size(width.clamp(360.0, maxWidth), height.clamp(420.0, maxHeight));
    }
  } on Object {
    // 读不到就用默认大小
  }

  return Size(
    _fallbackSize.width.clamp(360.0, maxWidth),
    _fallbackSize.height.clamp(420.0, maxHeight),
  );
}

Future<Offset> _windowPosition(Size size) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final left = prefs.getDouble('readerWindowLeft');
    final top = prefs.getDouble('readerWindowTop');
    if (left != null && top != null) {
      return DesktopWindow.clampPosition(Offset(left, top), size);
    }
  } on Object {
    // 读不到就按默认位置放
  }

  // 头一次打开：靠屏幕右边站，主窗口一般在左边，两边能同时看着
  final screen = DesktopWindow.screenSize();
  return DesktopWindow.clampPosition(
    Offset(screen.width - size.width - 60, 60),
    size,
  );
}

/// 关窗时把阅读窗口自己的大小和位置记下来，然后直接结束这个进程
///
/// 用的键和主窗口不一样，两个进程共用一份设置文件，不能互相覆盖。
///
/// 为什么最后是 [exit] 而不是 windowManager.destroy()：destroy 只是往消息
/// 队列里塞一个退出信号，之后引擎自己收尾要好几秒——这几秒里窗口还挂在
/// 屏幕上，点它也没反应，看着就跟卡死一样。该存的都存完了，直接把这个
/// 进程收掉最干净，窗口立刻消失。
class _ReaderWindowKeeper with WindowListener {
  _ReaderWindowKeeper._();

  static final _ReaderWindowKeeper instance = _ReaderWindowKeeper._();

  /// 关窗流程只走一次：连点几下 ✕ 也只结束一次
  bool _closing = false;

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
    // 最小化时窗口会被挪到 -32000，尺寸也不可信；跳过这种值，
    // 否则下次打开阅读窗口会直接跑到屏幕外。
    if (size.width >= 300 && size.height >= 300) {
      await prefs.setDouble('readerWindowWidth', size.width);
      await prefs.setDouble('readerWindowHeight', size.height);
    }
    if (position.dx > -10000 && position.dy > -10000) {
      await prefs.setDouble('readerWindowLeft', position.dx);
      await prefs.setDouble('readerWindowTop', position.dy);
    }
  }
}
