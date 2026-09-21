/// 与 Android 原生层的通道：音量键翻页、下载前台服务
library;

import 'package:flutter/services.dart';

class PlatformService {
  PlatformService._();

  static const MethodChannel _channel = MethodChannel('jm_reader/platform');

  /// 音量键回调：+1 为音量上键（往上翻），-1 为音量下键（往下翻）
  static void Function(int delta)? onVolumeKey;

  static bool _initialized = false;

  static void init() {
    if (_initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onVolumeKey') {
        final delta = call.arguments;
        if (delta is int) onVolumeKey?.call(delta);
      }
      return null;
    });
  }

  /// 进入阅读器时开启，退出时关闭，避免影响系统音量
  static Future<void> setVolumeKeyEnabled(bool enabled) async {
    try {
      await _channel.invokeMethod('setVolumeKeyEnabled', enabled);
    } on PlatformException {
      // 桌面/测试环境没有原生实现，忽略
    } on MissingPluginException {
      // 同上
    }
  }

  /// 开始下载时启动前台服务，保证后台不被回收
  static Future<void> startForeground({
    required String title,
    required String text,
  }) async {
    try {
      await _channel.invokeMethod('startForeground', {
        'title': title,
        'text': text,
      });
    } on PlatformException {
      // 忽略
    } on MissingPluginException {
      // 忽略
    }
  }

  static Future<void> stopForeground() async {
    try {
      await _channel.invokeMethod('stopForeground');
    } on PlatformException {
      // 忽略
    } on MissingPluginException {
      // 忽略
    }
  }

  /// 是否已获得「所有文件访问」权限（Android 11+）
  static Future<bool> hasAllFilesAccess() async {
    try {
      final granted = await _channel.invokeMethod<bool>('hasAllFilesAccess');
      return granted ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// 跳到系统设置页申请「所有文件访问」权限
  static Future<void> requestAllFilesAccess() async {
    try {
      await _channel.invokeMethod('requestAllFilesAccess');
    } on PlatformException {
      // 忽略
    } on MissingPluginException {
      // 忽略
    }
  }

  /// 系统里是否挂着 VPN
  ///
  /// 「绕过 DNS 污染」的自动模式用它决定要不要自己指定 IP：
  /// 挂了 VPN 时指定 IP 会让 VPN 的分流规则认不出域名，反而更糟。
  static Future<bool> isVpnActive() async {
    try {
      return await _channel.invokeMethod<bool>('isVpnActive') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// 系统全局 HTTP 代理，形如 `127.0.0.1:7890`；没设置返回空串
  ///
  /// Dart 的网络库不读系统代理，所以这种模式的梯子对 App 是隐形的，
  /// 必须主动检测出来提醒用户手填。
  static Future<String> systemProxy() async {
    try {
      return await _channel.invokeMethod<String>('systemProxy') ?? '';
    } on PlatformException {
      return '';
    } on MissingPluginException {
      return '';
    }
  }

  /// 用系统浏览器打开链接（下载页、新版本安装包）
  static Future<bool> openUrl(String url) async {
    if (url.trim().isEmpty) return false;
    try {
      return await _channel.invokeMethod<bool>('openUrl', {'url': url}) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// 通知系统相册重新扫描这些目录
  ///
  /// 目录里放了 `.nomedia` 之后，这次扫描会把之前已经收录进相册的图片清掉。
  /// 光放标记文件不会让已经进去的图消失，必须补这一下。
  static Future<void> scanMedia(List<String> paths) async {
    if (paths.isEmpty) return;
    try {
      await _channel.invokeMethod('scanMedia', {'paths': paths});
    } on PlatformException {
      // 忽略
    } on MissingPluginException {
      // 忽略
    }
  }
}
