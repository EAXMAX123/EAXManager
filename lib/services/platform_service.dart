/// 与系统打交道的杂活集合
///
/// 手机上这些靠原生层（音量键、前台服务、相册扫描），电脑上没有这些概念，
/// 就用 Dart 自己实现一份（打开浏览器、读系统代理、系统播放器放彩蛋）。
library;

import 'dart:io';

import 'package:flutter/services.dart';

class PlatformService {
  PlatformService._();

  static const MethodChannel _channel = MethodChannel('jm_reader/platform');

  /// 是不是电脑（Windows / macOS / Linux）
  ///
  /// 音量键翻页、相册、通知权限这些只有手机才有的东西，
  /// 电脑上要把对应开关藏起来，别摆一堆按了没反应的选项。
  static bool get isDesktop => !Platform.isAndroid && !Platform.isIOS;

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
    if (!Platform.isAndroid) return;
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
    if (!Platform.isAndroid) return;
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
    if (!Platform.isAndroid) return;
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
    // 电脑上的权限是文件系统自己的事，能跑起来就能写
    if (!Platform.isAndroid) return true;
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
    if (!Platform.isAndroid) return;
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
    // 电脑上判断「梯子在不在跑」看的是系统代理：挂着 Clash 这类工具时
    // 设了全局代理，效果跟手机挂 VPN 是一回事。
    if (!Platform.isAndroid) {
      return (await systemProxy()).isNotEmpty;
    }
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
    if (!Platform.isAndroid) return _desktopProxy();
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
    if (!Platform.isAndroid) return _openWithSystem(url);
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
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('scanMedia', {'paths': paths});
    } on PlatformException {
      // 忽略
    } on MissingPluginException {
      // 忽略
    }
  }

  // ==================== 电脑端自己实现的部分 ====================

  static String? _proxyCache;

  /// 电脑上的系统代理
  ///
  /// 先看环境变量（命令行启动、某些工具会写），再看 Windows 注册表里
  /// 「Internet 选项」存的那一份——Clash、v2rayN 这类工具改的就是它。
  static Future<String> _desktopProxy() async {
    final cached = _proxyCache;
    if (cached != null) return cached;

    var value = '';
    const keys = [
      'HTTPS_PROXY',
      'https_proxy',
      'HTTP_PROXY',
      'http_proxy',
      'ALL_PROXY',
      'all_proxy',
    ];
    for (final key in keys) {
      final raw = _normalizeProxy(Platform.environment[key] ?? '');
      if (raw.isNotEmpty) {
        value = raw;
        break;
      }
    }
    if (value.isEmpty && Platform.isWindows) {
      value = await _windowsRegistryProxy();
    }

    _proxyCache = value;
    return value;
  }

  /// 让用户改完代理能立刻生效，不用重启软件
  static void forgetProxyCache() => _proxyCache = null;

  /// 去掉协议头和末尾斜杠，只留 host:port
  static String _normalizeProxy(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return '';
    for (final scheme in const [
      'http://',
      'https://',
      'socks5://',
      'socks://',
    ]) {
      if (text.toLowerCase().startsWith(scheme)) {
        text = text.substring(scheme.length);
        break;
      }
    }
    text = text.split('/').first.trim();
    return text;
  }

  static Future<String> _windowsRegistryProxy() async {
    try {
      final result = await Process.run('reg', [
        'query',
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
        '/v',
        'ProxyServer',
      ]);
      if (result.exitCode != 0) return '';
      final match = RegExp(r'ProxyServer\s+REG_SZ\s+(\S+)')
          .firstMatch(result.stdout.toString());
      final raw = match?.group(1) ?? '';
      // 形如 `http=127.0.0.1:7890;https=127.0.0.1:7890` 时取第一个
      final piece = raw.contains('=')
          ? raw.split(';').first.split('=').last
          : raw;
      return _normalizeProxy(piece);
    } on Object {
      return '';
    }
  }

  /// 交给系统默认程序打开：网址走浏览器，本地文件走关联的播放器
  static Future<bool> _openWithSystem(String target) async {
    try {
      if (Platform.isWindows) {
        // 比 cmd /c start 干净：不会闪一下黑窗口
        await Process.start('rundll32.exe', [
          'url.dll,FileProtocolHandler',
          target,
        ], mode: ProcessStartMode.detached);
        return true;
      }
      if (Platform.isMacOS) {
        await Process.start('open', [target], mode: ProcessStartMode.detached);
        return true;
      }
      await Process.start('xdg-open', [
        target,
      ], mode: ProcessStartMode.detached);
      return true;
    } on Object {
      return false;
    }
  }

}
