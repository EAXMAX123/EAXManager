/// 应用信息
///
/// 改版本号时这里和 pubspec.yaml 的 version 要一起改，
/// 并同步 android/app/src/main/AndroidManifest.xml 里的 android:label。
library;

import 'dart:io';

class AppInfo {
  AppInfo._();

  static const String name = 'EAX管理器';

  /// 纯 ASCII 的名字
  ///
  /// 只能用在 HTTP 请求头这类地方——头里塞中文会让整个请求非法，
  /// 服务器直接不收，表现出来就是「连不上」。
  static const String asciiName = 'EAXManager';

  /// 版本号
  ///
  /// 手机版和电脑版是两条发布线：手机版用默认值，电脑版构建时通过
  /// --dart-define=EAX_APP_VERSION=... 传自己的版本号，互不影响。
  static const String version = String.fromEnvironment(
    'EAX_APP_VERSION',
    defaultValue: '1.7.6',
  );
  static const int buildNumber = int.fromEnvironment(
    'EAX_BUILD_NUMBER',
    defaultValue: 44,
  );

  /// 更新信息地址：放「最新版本号是多少」的那个小文件
  ///
  /// 用户没在设置里填别的就用这个。同一个仓库的 jsDelivr 入口会自动
  /// 作为备用一起试，见 UpdateService。
  static const String updateCheckUrl =
      'https://raw.githubusercontent.com/EAXMAX123/eam-update/main/update.json';

  /// 电脑版问的是旁边那份文件
  ///
  /// 手机版要下载的是 apk，电脑版要下载的是 zip，两边不能共用一份：
  /// 共用了电脑版会被指去下安卓包，手机版会被指去下压缩包。分开写，
  /// 各自升级互不打扰。
  static const String updateCheckUrlWindows =
      'https://raw.githubusercontent.com/EAXMAX123/eam-update/main/update_win.json';

  /// 当前这台设备该用哪个更新地址
  static String get defaultUpdateCheckUrl =>
      Platform.isWindows ? updateCheckUrlWindows : updateCheckUrl;

  /// 形如 v1.0.1
  static String get versionText => 'v$version';

  /// 形如 v1.0.1 (2)
  static String get fullVersionText => 'v$version ($buildNumber)';
}
