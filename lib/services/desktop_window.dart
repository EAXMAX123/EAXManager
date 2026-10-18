/// 电脑版窗口的几个小工具：屏幕尺寸、把窗口夹回看得见的地方
///
/// 高分屏、换过显示器、改过缩放之后，上次记下来的窗口位置有可能整块落到
/// 屏幕外面，下次打开只剩一条边，看着就像软件坏了。统一在这里夹一次。
library;

import 'dart:ui';

class DesktopWindow {
  DesktopWindow._();

  /// 主显示器的尺寸（逻辑像素，和窗口坐标是同一套单位）
  static Size screenSize() {
    final display = PlatformDispatcher.instance.implicitView?.display;
    if (display == null) return const Size(1280, 800);

    final ratio = display.devicePixelRatio;
    if (ratio <= 0) return const Size(1280, 800);
    return Size(display.size.width / ratio, display.size.height / ratio);
  }

  /// 把窗口左上角夹进屏幕，尽量让整个窗口都露出来
  static Offset clampPosition(Offset position, Size window) {
    final screen = screenSize();
    final maxLeft = screen.width - window.width;
    final maxTop = screen.height - window.height;
    return Offset(
      maxLeft <= 0 ? 0 : position.dx.clamp(0.0, maxLeft),
      maxTop <= 0 ? 0 : position.dy.clamp(0.0, maxTop),
    );
  }
}
