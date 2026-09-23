/// 应用设置：持久化到 SharedPreferences
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  const AppSettings({
    this.downloadDir = '',
    this.picaDir = '',
    this.ehDir = '',
    this.pixivDir = '',
    this.pixivApiBase = '',
    this.pixivImageProxy = '',
    this.pixivQuality = 'original',
    this.proxyUrl = '',
    this.customDomains = const [],
    this.maxConcurrentChapters = 3,
    this.maxConcurrentImages = 5,
    this.jpegQuality = 95,
    this.volumeKeyPageTurn = true,
    this.showCoverInList = true,
    this.themeMode = 'system',
    this.themeSeed = 0xFFE91E63,
    this.backgroundColor = '',
    this.subscribeCheckInterval = 3600,
    this.autoCheckUpdate = true,
    this.enabledSources = const ['jm', 'pica', 'eh', 'pixiv'],
    this.sourcesVersion = 0,
    this.dnsBypass = 'off',
    this.customIpMap = '',
    this.ehUseEx = false,
    this.hideFromGallery = true,
    this.shelfSort = 'read',
    this.updateCheckUrl = '',
    this.autoCheckAppUpdate = true,
    this.imageSearchKey = '',
    this.imageSearchThreshold = 60,
    this.imageSearchSegment = true,
    this.imageSearchUseIqdb = true,
  });

  /// JM 下载目录，空表示用默认（公共 JM 目录，不可写时用应用私有目录）
  ///
  /// 它同时是「根目录」：哔咔、EH 没单独设置时放在它旁边。
  final String downloadDir;

  /// 哔咔下载目录，空表示用默认（JM 目录旁边的 Pica）
  final String picaDir;

  /// EH 下载目录，空表示用默认（JM 目录旁边的 EH）
  final String ehDir;

  /// Pixiv 下载目录，空表示用默认（JM 目录旁边的 Pixiv）
  final String pixivDir;

  /// Pixiv 数据接口镜像地址，空表示用内置的那几个
  ///
  /// 填一个自己的镜像，形如 https://api.example.com（不带结尾斜杠）。
  final String pixivApiBase;

  /// Pixiv 图片反代域名，空表示用内置的那一串
  ///
  /// 只填域名，形如 i.pixiv.re，不带 https://。
  final String pixivImageProxy;

  /// Pixiv 下载哪一档图：original 原图 / large 较大（1200px）
  ///
  /// 原图动辄两三兆一张，一话几十张就是几十兆；large 小一大截，
  /// 手机上基本看不出差别。默认还是给原图。
  final String pixivQuality;

  /// 代理，如 http://127.0.0.1:7890
  final String proxyUrl;

  /// 自定义 API 域名
  final List<String> customDomains;

  final int maxConcurrentChapters;
  final int maxConcurrentImages;

  /// 还原后重新编码为 JPEG 的质量
  final int jpegQuality;

  /// 阅读器是否支持音量键翻页
  final bool volumeKeyPageTurn;

  /// 阅读时保持屏幕常亮

  /// 列表是否显示封面
  final bool showCoverInList;

  /// system / light / dark
  final String themeMode;

  /// 主题色
  final int themeSeed;

  /// 自定义背景图路径，空表示纯色
  final String backgroundColor;

  /// 追更检查间隔（秒）
  final int subscribeCheckInterval;

  /// 是否开启后台追更检查
  final bool autoCheckUpdate;

  /// 搜索页勾选的源（jm / pica / eh）
  final List<String> enabledSources;

  /// 设置结构版本，用来在升级时把新加的源补进 [enabledSources]
  final int sourcesVersion;

  /// 绕过 DNS 污染：off / auto / on
  ///
  /// 国内 DNS 对 JM、哔咔的域名大量返回假 IP，打开后会改用加密 DNS 拿真实
  /// 地址再直连。默认关闭，因为它和 VPN 的分流规则可能互相干扰。
  final String dnsBypass;

  /// 用户手填的「域名 = IP」覆盖，一行一条，优先级高于内置表
  final String customIpMap;

  /// EH 是否走 ExHentai（里站）
  ///
  /// 里站必须有 igneous Cookie，而且国内一律要挂梯子；默认走表站，
  /// 表站免登录也能搜。
  final bool ehUseEx;

  /// 下载目录是否对系统相册隐藏（放 .nomedia）
  ///
  /// 默认开：下载的本子是几百张图片，不藏起来相册会被刷屏。
  /// 文件管理器不受影响，文件照样能翻到。
  final bool hideFromGallery;

  /// 书架排序方式：read / addedDesc / addedAsc / sizeDesc / sizeAsc / title
  final String shelfSort;

  /// 新版本信息的地址（JSON 或纯文本），留空表示不检查
  final String updateCheckUrl;

  /// 启动时自动检查有没有新安装包
  final bool autoCheckAppUpdate;

  /// SauceNAO 的 API key，留空走匿名通道
  ///
  /// 匿名每 30 秒只能搜 3 次，填了自己的 key 会宽松很多（免费申请）。
  final String imageSearchKey;

  /// 相似度门槛：低于它算「还没认出来」，会继续切段再搜
  final int imageSearchThreshold;

  /// 整图认不出时，切上中下三段重搜
  final bool imageSearchSegment;

  /// 是否同时查 IQDB（免费不限量，但索引偏动画向）
  final bool imageSearchUseIqdb;

  AppSettings copyWith({
    String? downloadDir,
    String? picaDir,
    String? ehDir,
    String? pixivDir,
    String? pixivApiBase,
    String? pixivImageProxy,
    String? pixivQuality,
    String? proxyUrl,
    List<String>? customDomains,
    int? maxConcurrentChapters,
    int? maxConcurrentImages,
    int? jpegQuality,
    bool? volumeKeyPageTurn,
    bool? showCoverInList,
    String? themeMode,
    int? themeSeed,
    String? backgroundColor,
    int? subscribeCheckInterval,
    bool? autoCheckUpdate,
    List<String>? enabledSources,
    int? sourcesVersion,
    String? dnsBypass,
    String? customIpMap,
    bool? ehUseEx,
    bool? hideFromGallery,
    String? shelfSort,
    String? updateCheckUrl,
    bool? autoCheckAppUpdate,
    String? imageSearchKey,
    int? imageSearchThreshold,
    bool? imageSearchSegment,
    bool? imageSearchUseIqdb,
  }) => AppSettings(
    downloadDir: downloadDir ?? this.downloadDir,
    picaDir: picaDir ?? this.picaDir,
    ehDir: ehDir ?? this.ehDir,
    pixivDir: pixivDir ?? this.pixivDir,
    pixivApiBase: pixivApiBase ?? this.pixivApiBase,
    pixivImageProxy: pixivImageProxy ?? this.pixivImageProxy,
    pixivQuality: pixivQuality ?? this.pixivQuality,
    proxyUrl: proxyUrl ?? this.proxyUrl,
    customDomains: customDomains ?? this.customDomains,
    maxConcurrentChapters: maxConcurrentChapters ?? this.maxConcurrentChapters,
    maxConcurrentImages: maxConcurrentImages ?? this.maxConcurrentImages,
    jpegQuality: jpegQuality ?? this.jpegQuality,
    volumeKeyPageTurn: volumeKeyPageTurn ?? this.volumeKeyPageTurn,
    showCoverInList: showCoverInList ?? this.showCoverInList,
    themeMode: themeMode ?? this.themeMode,
    themeSeed: themeSeed ?? this.themeSeed,
    backgroundColor: backgroundColor ?? this.backgroundColor,
    subscribeCheckInterval:
        subscribeCheckInterval ?? this.subscribeCheckInterval,
    autoCheckUpdate: autoCheckUpdate ?? this.autoCheckUpdate,
    enabledSources: enabledSources ?? this.enabledSources,
    sourcesVersion: sourcesVersion ?? this.sourcesVersion,
    dnsBypass: dnsBypass ?? this.dnsBypass,
    customIpMap: customIpMap ?? this.customIpMap,
    ehUseEx: ehUseEx ?? this.ehUseEx,
    hideFromGallery: hideFromGallery ?? this.hideFromGallery,
    shelfSort: shelfSort ?? this.shelfSort,
    updateCheckUrl: updateCheckUrl ?? this.updateCheckUrl,
    autoCheckAppUpdate: autoCheckAppUpdate ?? this.autoCheckAppUpdate,
    imageSearchKey: imageSearchKey ?? this.imageSearchKey,
    imageSearchThreshold: imageSearchThreshold ?? this.imageSearchThreshold,
    imageSearchSegment: imageSearchSegment ?? this.imageSearchSegment,
    imageSearchUseIqdb: imageSearchUseIqdb ?? this.imageSearchUseIqdb,
  );

  Map<String, Object?> toJson() => {
    'downloadDir': downloadDir,
    'picaDir': picaDir,
    'ehDir': ehDir,
    'pixivDir': pixivDir,
    'pixivApiBase': pixivApiBase,
    'pixivImageProxy': pixivImageProxy,
    'pixivQuality': pixivQuality,
    'proxyUrl': proxyUrl,
    'customDomains': customDomains,
    'maxConcurrentChapters': maxConcurrentChapters,
    'maxConcurrentImages': maxConcurrentImages,
    'jpegQuality': jpegQuality,
    'volumeKeyPageTurn': volumeKeyPageTurn,
    'showCoverInList': showCoverInList,
    'themeMode': themeMode,
    'themeSeed': themeSeed,
    'backgroundColor': backgroundColor,
    'subscribeCheckInterval': subscribeCheckInterval,
    'autoCheckUpdate': autoCheckUpdate,
    'enabledSources': enabledSources,
    'sourcesVersion': sourcesVersion,
    'dnsBypass': dnsBypass,
    'customIpMap': customIpMap,
    'ehUseEx': ehUseEx,
    'hideFromGallery': hideFromGallery,
    'shelfSort': shelfSort,
    'updateCheckUrl': updateCheckUrl,
    'autoCheckAppUpdate': autoCheckAppUpdate,
    'imageSearchKey': imageSearchKey,
    'imageSearchThreshold': imageSearchThreshold,
    'imageSearchSegment': imageSearchSegment,
    'imageSearchUseIqdb': imageSearchUseIqdb,
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
    downloadDir: json['downloadDir'] as String? ?? '',
    picaDir: json['picaDir'] as String? ?? '',
    ehDir: json['ehDir'] as String? ?? '',
    pixivDir: json['pixivDir'] as String? ?? '',
    pixivApiBase: json['pixivApiBase'] as String? ?? '',
    pixivImageProxy: json['pixivImageProxy'] as String? ?? '',
    pixivQuality: json['pixivQuality'] as String? ?? 'original',
    proxyUrl: json['proxyUrl'] as String? ?? '',
    customDomains:
        (json['customDomains'] as List?)?.map((e) => e.toString()).toList() ??
        const [],
    maxConcurrentChapters: json['maxConcurrentChapters'] as int? ?? 3,
    maxConcurrentImages: json['maxConcurrentImages'] as int? ?? 5,
    jpegQuality: json['jpegQuality'] as int? ?? 95,
    volumeKeyPageTurn: json['volumeKeyPageTurn'] as bool? ?? true,
    showCoverInList: json['showCoverInList'] as bool? ?? true,
    themeMode: json['themeMode'] as String? ?? 'system',
    themeSeed: json['themeSeed'] as int? ?? 0xFFE91E63,
    backgroundColor: json['backgroundColor'] as String? ?? '',
    subscribeCheckInterval: json['subscribeCheckInterval'] as int? ?? 3600,
    autoCheckUpdate: json['autoCheckUpdate'] as bool? ?? true,
    enabledSources:
        (json['enabledSources'] as List?)?.map((e) => e.toString()).toList() ??
        const ['jm', 'pica', 'eh', 'pixiv'],
    sourcesVersion: json['sourcesVersion'] as int? ?? 0,
    dnsBypass: json['dnsBypass'] as String? ?? 'off',
    customIpMap: json['customIpMap'] as String? ?? '',
    ehUseEx: json['ehUseEx'] as bool? ?? false,
    hideFromGallery: json['hideFromGallery'] as bool? ?? true,
    shelfSort: json['shelfSort'] as String? ?? 'read',
    updateCheckUrl: json['updateCheckUrl'] as String? ?? '',
    autoCheckAppUpdate: json['autoCheckAppUpdate'] as bool? ?? true,
    imageSearchKey: json['imageSearchKey'] as String? ?? '',
    imageSearchThreshold: json['imageSearchThreshold'] as int? ?? 60,
    imageSearchSegment: json['imageSearchSegment'] as bool? ?? true,
    imageSearchUseIqdb: json['imageSearchUseIqdb'] as bool? ?? true,
  );
}

/// 已经弹过窗提醒过的版本号
///
/// 同一个版本只在自动检查时提醒一次，免得每次开软件都弹一遍；
/// 用户手动点「立即检查更新」时不看这个记录。
class UpdateNoticeStore {
  UpdateNoticeStore._();

  static const String _key = 'update_notified_version';

  static Future<String> load() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key) ?? '';
  }

  static Future<void> save(String version) async {
    final prefs = await SharedPreferences.getInstance();
    if (version.trim().isEmpty) {
      await prefs.remove(_key);
      return;
    }
    await prefs.setString(_key, version.trim());
  }
}

class SettingsStore {
  SettingsStore._();

  static const String _key = 'app_settings';

  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const AppSettings();
    try {
      final json = jsonDecode(raw);
      if (json is Map<String, dynamic>) return AppSettings.fromJson(json);
    } on FormatException {
      // 配置损坏时回退到默认值
    }
    return const AppSettings();
  }

  static Future<void> save(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(settings.toJson()));
  }
}

/// JM 账号状态：用户名 + 会话密钥 + 密码
///
/// 会话 cookie 由 PersistCookieJar 保管，但它会过期，过期之后没有任何
/// 办法重登——除非把密码也留着。所以这里连密码一起存，启动时和收到 401 时
/// 都能静默重登，用户不用每次会话掉了都手动登一遍。
class AccountStore {
  AccountStore._();

  static const String _userKey = 'jm_username';
  static const String _avsKey = 'jm_avs';
  static const String _passKey = 'jm_password';

  /// 返回 (用户名, 会话密钥, 密码)
  static Future<(String, String, String)> load() async {
    final prefs = await SharedPreferences.getInstance();
    return (
      prefs.getString(_userKey) ?? '',
      prefs.getString(_avsKey) ?? '',
      prefs.getString(_passKey) ?? '',
    );
  }

  static Future<void> save(
    String username, {
    String avs = '',
    String password = '',
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (username.trim().isEmpty) {
      await prefs.remove(_userKey);
      await prefs.remove(_avsKey);
      await prefs.remove(_passKey);
      return;
    }
    await prefs.setString(_userKey, username.trim());
    if (avs.trim().isEmpty) {
      await prefs.remove(_avsKey);
    } else {
      await prefs.setString(_avsKey, avs.trim());
    }
    if (password.isEmpty) {
      await prefs.remove(_passKey);
    } else {
      await prefs.setString(_passKey, password);
    }
  }
}

/// 下载目录：记住上次成功用过的那个
///
/// 单独存而不是塞进 [AppSettings]，是为了让「解析目录」这件事不触发设置变更
/// 回调，避免绕成一圈。记住之后每次启动都直接用同一个目录，不再重新探测——
/// 之前每次启动都探测，权限状态稍有波动就悄悄换目录，已下载的书会集体「消失」。
class RootStore {
  RootStore._();

  static const String _key = 'resolved_download_root';

  static Future<String> load() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key) ?? '';
  }

  static Future<void> save(String path) async {
    final prefs = await SharedPreferences.getInstance();
    if (path.trim().isEmpty) {
      await prefs.remove(_key);
      return;
    }
    await prefs.setString(_key, path.trim());
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

/// 哔咔账号：token 是 JWT，有效期约 7 天，过期后用账号密码自动重登
class PicaAccount {
  const PicaAccount({
    this.email = '',
    this.password = '',
    this.token = '',
    this.expireAt = 0,
  });

  final String email;
  final String password;
  final String token;

  /// token 过期时间（秒级时间戳），0 表示解析不出来
  final int expireAt;

  bool get hasCredentials => email.trim().isNotEmpty && password.isNotEmpty;
}

class PicaAccountStore {
  PicaAccountStore._();

  static const String _key = 'pica_account';

  static Future<PicaAccount?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw);
      if (json is Map<String, dynamic>) {
        return PicaAccount(
          email: json['email'] as String? ?? '',
          password: json['password'] as String? ?? '',
          token: json['token'] as String? ?? '',
          expireAt: json['expireAt'] as int? ?? 0,
        );
      }
    } on FormatException {
      // 数据损坏时当作未登录
    }
    return null;
  }

  static Future<void> save(PicaAccount account) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode({
        'email': account.email,
        'password': account.password,
        'token': account.token,
        'expireAt': account.expireAt,
      }),
    );
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
