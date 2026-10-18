/// 电脑版的窗口外壳：自绘标题栏 + 顶边拖拽改大小
///
/// 为什么不用系统自带那条标题栏：那三个按钮是系统画的，
/// 有的机器上渲染出来只有关闭键看得见（最小化/最大化是空白），
/// 干脆自己画一条，顺便把颜色和软件主题统一，看起来才像个软件。
///
/// 关窗流程没变：仍然走 [windowManager.close]，由 main.dart 里的
/// `_DesktopWindowKeeper` 记住窗口大小和位置再真的退出。
library;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

class DesktopWindowFrame extends StatefulWidget {
  const DesktopWindowFrame({
    super.key,
    required this.child,
    this.title = 'EAX管理器',
    this.background,
    this.pinPrefsKey,
  });

  final Widget child;

  /// 标题栏左边写什么；阅读窗口写「阅读」
  final String title;

  /// 窗口最外圈那几像素窄边涂什么颜色；不给就跟着主题底色走
  final Color? background;

  /// 给了就在标题栏上多一个「钉住」按钮，把窗口固定在别的窗口上面
  ///
  /// 值就是这个偏好的存储键名；两个窗口共用一份设置文件，
  /// 各用各的键，谁也别覆盖谁。手机上没有这回事。
  final String? pinPrefsKey;

  /// 自绘标题栏高度
  static const double titleBarHeight = 36;

  @override
  State<DesktopWindowFrame> createState() => _DesktopWindowFrameState();
}

class _DesktopWindowFrameState extends State<DesktopWindowFrame>
    with WindowListener {
  bool _maximized = false;
  bool _focused = true;
  bool _pinned = false;

  /// 上一次同步给系统的窗口底色，避免每帧都发一次通道调用
  Color? _syncedBackground;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    // 软件可能是从「上次最大化」的状态开起来的，先把真实状态问回来
    _syncMaximized();
    _syncPinned();
  }

  /// 上次是不是钉着的，这次开机照着来
  Future<void> _syncPinned() async {
    final key = widget.pinPrefsKey;
    if (key == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getBool(key) ?? false;
      if (!mounted) return;
      setState(() => _pinned = value);
    } catch (_) {
      // 问不到就当没钉
    }
  }

  Future<void> _syncMaximized() async {
    try {
      final value = await windowManager.isMaximized();
      if (mounted && value != _maximized) {
        setState(() => _maximized = value);
      }
    } catch (_) {
      // 问不到就按「没最大化」显示，点一下按钮也能自己纠正过来
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 窗口最外圈有一圈不属于 Flutter 画布的窄边（系统留着用来拖大小），
    // 给它涂成当前主题的底色，不然那里会露出一条别的颜色。
    final background =
        widget.background ?? Theme.of(context).scaffoldBackgroundColor;
    if (_syncedBackground == background) return;
    _syncedBackground = background;
    windowManager.setBackgroundColor(background).catchError((Object _) {});
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() {
    if (mounted) setState(() => _maximized = true);
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) setState(() => _maximized = false);
  }

  @override
  void onWindowFocus() {
    if (mounted) setState(() => _focused = true);
  }

  @override
  void onWindowBlur() {
    if (mounted) setState(() => _focused = false);
  }

  /// 最大化 / 还原
  Future<void> _toggleMaximize() async {
    final maximized = await windowManager.isMaximized();
    if (maximized) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  /// 钉住 / 松开：钉住之后这个窗口一直浮在别的窗口上面
  Future<void> _togglePin() async {
    final key = widget.pinPrefsKey;
    final next = !_pinned;
    try {
      await windowManager.setAlwaysOnTop(next);
    } catch (_) {
      return;
    }
    if (!mounted) return;
    setState(() => _pinned = next);
    if (key == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, next);
    } catch (_) {
      // 记不住也没关系，这次照样钉着
    }
  }

  @override
  Widget build(BuildContext context) {
    return DragToResizeArea(
      resizeEdgeSize: 6,
      // 左右和下边系统自己会给，只有上边需要软件补一条
      enableResizeEdges: const [
        ResizeEdge.topLeft,
        ResizeEdge.top,
        ResizeEdge.topRight,
      ],
      child: Column(
        children: [
          _titleBar(context),
          Expanded(child: widget.child),
        ],
      ),
    );
  }

  Widget _titleBar(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      height: DesktopWindowFrame.titleBarHeight,
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.35)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: DragToMoveArea(
              child: Padding(
                padding: const EdgeInsets.only(left: 10),
                child: Row(
                  children: [
                    Image.asset(
                      'assets/app_icon.png',
                      width: 20,
                      height: 20,
                      filterQuality: FilterQuality.medium,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface.withValues(
                            alpha: _focused ? 0.9 : 0.55,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          WindowCaptionButton.minimize(
            brightness: theme.brightness,
            onPressed: () => windowManager.minimize(),
          ),
          if (widget.pinPrefsKey != null)
            IconButton(
              iconSize: 16,
              visualDensity: VisualDensity.compact,
              splashRadius: 18,
              icon: Icon(
                _pinned ? Icons.push_pin : Icons.push_pin_outlined,
                color: _pinned
                    ? scheme.primary
                    : scheme.onSurface.withValues(alpha: 0.75),
              ),
              onPressed: _togglePin,
            ),
          if (_maximized)
            WindowCaptionButton.unmaximize(
              brightness: theme.brightness,
              onPressed: _toggleMaximize,
            )
          else
            WindowCaptionButton.maximize(
              brightness: theme.brightness,
              onPressed: _toggleMaximize,
            ),
          WindowCaptionButton.close(
            brightness: theme.brightness,
            onPressed: () => windowManager.close(),
          ),
        ],
      ),
    );
  }
}
