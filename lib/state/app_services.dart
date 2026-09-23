/// 全局服务容器：设置、数据库、各漫画源、下载管理器的统一入口
library;

import 'dart:io';

import 'dart:async';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/app_database.dart';
import '../app_info.dart';
import '../data/settings_store.dart';
import '../jm/jm_client.dart';
import '../jm/jm_storage.dart';
import '../net/net_ip_table.dart';
import '../net/net_transport.dart';
import '../net/doh_resolver.dart';
import '../services/local_library.dart';
import '../services/notification_service.dart';
import '../services/platform_service.dart';
import '../services/subscription_service.dart';
import '../services/update_service.dart';
import '../source/jm_source.dart';
import '../source/comic_source.dart';
import '../source/eh/eh_source.dart';
import '../source/pica/pica_source.dart';
import '../source/pixiv/pixiv_client.dart';
import '../source/image_search/image_search_service.dart';
import '../source/pixiv/pixiv_source.dart';
import '../source/source_registry.dart';
import 'download_manager.dart';

/// 「重新扫描本地文件」的结果
class RescanResult {
  const RescanResult({required this.found, required this.cleared});

  /// 这次从磁盘上认回来的本子数量
  final int found;

  /// 这次发现「记录说已下载、文件其实没了」而清掉标记的本子数量
  final int cleared;

  bool get isEmpty => found == 0 && cleared == 0;
}

class AppServices {
  AppServices._();

  static final AppServices I = AppServices._();

  final ValueNotifier<AppSettings> settings = ValueNotifier(
    const AppSettings(),
  );

  final AppDao dao = AppDao(AppDatabase.instance);

  late JmClient client;
  late PicaSource pica;
  late EhSource eh;
  late PixivSource pixiv;
  late SourceRegistry sources;
  late DownloadManager downloads;
  late SubscriptionService subscriptions;
  late ImageSearchService imageSearch;

  /// JM 登录会话（持久化 cookie），重建客户端时复用
  late final CookieJar cookieJar;

  /// JM 登录用户名，未登录为空
  final ValueNotifier<String> account = ValueNotifier('');

  /// 哔咔登录邮箱，未登录为空
  final ValueNotifier<String> picaAccount = ValueNotifier('');

  /// EH 登录账号（数字 ID），未登录为空
  final ValueNotifier<String> ehAccount = ValueNotifier('');

  /// 书架列表
  final ValueNotifier<List<BookshelfItem>> library = ValueNotifier(
    const <BookshelfItem>[],
  );

  /// 下载根目录（JM 根目录，其它源在同级目录）
  final ValueNotifier<String> rootDir = ValueNotifier('');

  /// 检查到的新版本；界面看到有值就弹窗提示
  final ValueNotifier<AppUpdate?> pendingUpdate = ValueNotifier(null);

  /// 系统里是否挂着 VPN；「绕过 DNS 污染」的自动模式靠它决定要不要自己指定 IP
  bool vpnActive = false;

  /// 系统全局 HTTP 代理。Dart 的网络库不读它，检测出来是为了提示用户手填。
  String systemProxy = '';

  bool _initialized = false;

  /// 已经处理过的「下载目录 + 是否隐藏」组合，避免每次改设置都重复扫描
  String _galleryGuardState = '';

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    cookieJar = await _openCookieJar();

    settings.value = await _loadSettings();
    await _detectNetworkEnv();

    client = _buildClient(settings.value);
    pica = PicaSource(transport: _transportOf(settings.value));
    eh = EhSource(transport: _transportOf(settings.value));
    pixiv = PixivSource(
      transport: _transportOf(settings.value),
      apiBases: PixivConst.parseList(settings.value.pixivApiBase),
      imageProxies: PixivConst.parseList(settings.value.pixivImageProxy),
      imageQuality: settings.value.pixivQuality,
    );
    imageSearch = ImageSearchService(
      transport: _transportOf(settings.value),
      sauceNaoKey: settings.value.imageSearchKey,
      enableIqdb: settings.value.imageSearchUseIqdb,
    );
    sources = SourceRegistry()
      ..register(JmSource(client))
      ..register(pica)
      ..register(eh)
      ..register(pixiv);

    final (savedUser, savedAvs, savedPassword) = await AccountStore.load();
    account.value = savedUser;
    if (savedUser.isNotEmpty) {
      client.restoreAccount(savedUser, avs: savedAvs, password: savedPassword);
    }

    // 哔咔：本地有效 token > 保存的账号密码重登
    await pica.restore();
    picaAccount.value = pica.email;

    // EH：只有「粘贴浏览器 Cookie」一种登录方式
    eh.applyUseEx(settings.value.ehUseEx);
    await eh.restore();
    ehAccount.value = eh.accountLabel;

    downloads = DownloadManager(
      dao: dao,
      sources: sources,
      settings: settings.value,
    );
    subscriptions = SubscriptionService(dao: dao, sources: sources);

    PlatformService.init();
    await NotificationService.instance.init();
    await downloads.init();
    await subscriptions.reload();
    subscriptions.schedule(
      enabled: settings.value.autoCheckUpdate,
      intervalSeconds: settings.value.subscribeCheckInterval,
    );
    await reloadLibrary();
    await refreshRoot();

    settings.addListener(_onSettingsChanged);

    if (settings.value.autoCheckAppUpdate) {
      unawaited(checkAppUpdate());
    }
  }

  /// 当前设置结构版本
  ///
  /// 1 -> 2 是 v1.2.0 加了 Pixiv 源。以后再加源就把这个数字 +1，
  /// 老用户升级时会自动把新源勾上，不用自己去设置里找。
  static const int _currentSourcesVersion = 2;

  Future<AppSettings> _loadSettings() async {
    final loaded = await SettingsStore.load();
    if (loaded.sourcesVersion >= _currentSourcesVersion) return loaded;

    final next = [...loaded.enabledSources];
    for (final key in JmStorage.sourceFolders.keys) {
      if (!next.contains(key)) next.add(key);
    }
    final migrated = loaded.copyWith(
      enabledSources: next,
      sourcesVersion: _currentSourcesVersion,
    );
    await SettingsStore.save(migrated);
    return migrated;
  }

  Future<CookieJar> _openCookieJar() async {
    try {
      final support = await getApplicationSupportDirectory();
      final dir = Directory('${support.path}/jm_cookies');
      if (!await dir.exists()) await dir.create(recursive: true);
      return PersistCookieJar(storage: FileStorage(dir.path));
    } on Exception {
      // 拿不到可写目录时退回内存会话，登录仍可用但重启后失效
      return CookieJar();
    }
  }

  /// 读取系统网络环境：VPN 状态与系统代理
  Future<void> _detectNetworkEnv() async {
    vpnActive = await PlatformService.isVpnActive();
    systemProxy = await PlatformService.systemProxy();
  }

  /// 由「设置 + 系统环境」组装出一次请求要用的网络配置
  NetTransport _transportOf(AppSettings s) => NetTransport(
    bypass: DnsBypassMode.parse(s.dnsBypass),
    overrides: NetIpTable.parseOverrides(s.customIpMap),
    proxyUrl: s.proxyUrl.trim(),
    vpnActive: vpnActive,
  );

  JmClient _buildClient(AppSettings s) => JmClient(
    transport: _transportOf(s),
    customApiDomains: s.customDomains,
    cookieJar: cookieJar,
  );

  /// 重新读取系统网络环境并重建客户端（用户挂上或断开梯子后调用）
  Future<void> refreshNetworkEnv() async {
    // 网络环境变了，之前「哪个域名走不通」的判断也要作废
    NetTransport.forgetFailedHosts();
    DohResolver.instance.clear();
    await _detectNetworkEnv();
    await _onSettingsChanged();
  }

  Future<void> _onSettingsChanged() async {
    final s = settings.value;

    // 代理 / 绕过污染 / VPN 状态任一变化都要重建 HTTP 客户端
    final transport = _transportOf(s);
    if (transport.signature != client.transport.signature) {
      final avs = client.avsSecret;
      final password = client.passwordSecret;
      client = _buildClient(s);
      client.restoreAccount(account.value, avs: avs, password: password);
      sources.register(JmSource(client));
    }
    pica.updateTransport(transport);
    eh.updateTransport(transport);
    eh.applyUseEx(s.ehUseEx);
    pixiv.updateTransport(transport);
    pixiv.reconfigure(
      apiBases: PixivConst.parseList(s.pixivApiBase),
      imageProxies: PixivConst.parseList(s.pixivImageProxy),
      imageQuality: s.pixivQuality,
    );

    imageSearch.transport = transport;
    imageSearch.configure(
      sauceNaoKey: s.imageSearchKey,
      enableIqdb: s.imageSearchUseIqdb,
    );

    downloads.updateSettings(s);
    subscriptions.schedule(
      enabled: s.autoCheckUpdate,
      intervalSeconds: s.subscribeCheckInterval,
    );
    await refreshRoot();
  }

  // ==================== JM 账号 ====================

  Future<void> login(String username, String password) async {
    await client.login(username, password);
    account.value = client.username;
    // 密码一起存下来，会话过期后能自己重登
    await AccountStore.save(
      account.value,
      avs: client.avsSecret,
      password: password,
    );
  }

  Future<void> logout() async {
    await client.logout();
    account.value = '';
    await AccountStore.save('');
  }

  // ==================== 哔咔账号 ====================

  Future<void> picaLogin(String email, String password) async {
    await pica.login(email, password);
    picaAccount.value = pica.email;
  }

  Future<void> picaLogout() async {
    await pica.logout();
    picaAccount.value = '';
  }

  // ==================== EH 账号 ====================

  /// 粘贴浏览器 Cookie 登录
  Future<void> ehLogin(String pastedCookie) async {
    await eh.login(pastedCookie);
    ehAccount.value = eh.accountLabel;
  }

  /// 切换 EH 表站 / 里站
  Future<void> setEhUseEx(bool value) async {
    await updateSettings(settings.value.copyWith(ehUseEx: value));
  }

  Future<void> ehLogout() async {
    await eh.logout();
    ehAccount.value = '';
  }

  // ==================== 其它 ====================

  // ==================== 更新检查 ====================

  /// 看一眼有没有新版本
  ///
  /// 返回一句给用户看的结果（手动检查时用）。自动检查时只在确实有新版本
  /// 且没提醒过的情况下，把结果放进 [pendingUpdate] 让界面弹窗。
  Future<String> checkAppUpdate({bool manual = false}) async {
    final url = settings.value.updateCheckUrl.trim();
    // 没填就用内置的默认地址，所以这个功能装上就是能用的
    final target = url.isEmpty ? AppInfo.updateCheckUrl : url;
    if (target.isEmpty) return manual ? '还没填更新检查地址' : '';

    final update = await UpdateService.check(
      target,
      transport: _transportOf(settings.value),
    );

    if (update == null) {
      return manual ? '已经是最新版（${AppInfo.fullVersionText}）' : '';
    }

    if (!manual) {
      // 同一个版本只自动提醒一次，免得每次开软件都弹
      final notified = await UpdateNoticeStore.load();
      if (notified == update.version) return '';
    }

    pendingUpdate.value = update;
    return manual ? '发现新版本 v${update.version}' : '';
  }

  /// 挑一条真能用的安装包下载地址
  ///
  /// GitHub 的下载链接在国内常常直连不通，所以先探一圈加速站，
  /// 把第一个答应的交给浏览器，省得用户点进去看到一片空白。
  Future<String> resolveDownloadUrl(String url) => UpdateService
      .reachableDownloadUrl(url, transport: _transportOf(settings.value));

  /// 记下这个版本已经提醒过，下次启动不再自动弹窗
  Future<void> markUpdateNotified(String version) =>
      UpdateNoticeStore.save(version);

  Future<void> updateSettings(AppSettings next) async {
    settings.value = next;
    await SettingsStore.save(next);
  }

  /// 搜索页勾选的源
  Future<void> setEnabledSources(List<String> keys) async {
    final current = settings.value.enabledSources;
    if (current.length == keys.length &&
        current.every((e) => keys.contains(e))) {
      return;
    }
    await updateSettings(settings.value.copyWith(enabledSources: keys));
  }

  Future<void> reloadLibrary() async {
    library.value = await dao.listBookshelf();
  }

  /// 扫描下载目录，把磁盘上已经有、数据库里却没记录的本子挂回书架
  ///
  /// 用于重装应用、换手机、数据库丢失之后把已下载的书找回来。
  /// 反过来的事也一起做：文件其实已经不在了，就把书架上那个假的
  /// 「已下载」标记清掉，免得点进去才发现是空的。
  Future<RescanResult> rescanLocalLibrary() async {
    var found = 0;

    // 当前目录 + 每本书当初落盘的目录：换过下载目录之后，
    // 老书还在老地方，不一起扫就永远找不回来
    final roots = <String>{await JmStorage.effectiveRoot()};
    for (final item in library.value) {
      final path = item.rootPath.trim();
      if (path.isNotEmpty) roots.add(path);
    }

    for (final root in roots) {
      for (final source in JmStorage.sourceFolders.keys) {
        found += await _scanSourceDir(root, source);
      }
    }

    await downloads.reload();
    await reloadLibrary();

    final cleared = await _dropMissingDownloads();

    await downloads.reload();
    await reloadLibrary();
    return RescanResult(found: found, cleared: cleared);
  }

  /// 把「记录说已下载、磁盘上其实没有」的标记清掉
  ///
  /// 文件被误删、被手机管家清掉、或者用户自己删过之后，书架会一直挂着
  /// 一个假的「已下载」，点进去又说没下载——看着就像软件坏了。
  /// 返回清掉标记的本子数量。
  Future<int> _dropMissingDownloads() async {
    var cleared = 0;

    for (final item in library.value) {
      final local = (await LocalLibrary.chapters(item.sid)).toSet();

      if (local.isEmpty) {
        if (item.downloaded > 0) {
          await dao.updateDownloaded(item.sid, 0);
          cleared++;
        }
      } else if (local.length != item.downloaded) {
        // 数量对不上就按磁盘上的真实情况写回去
        await dao.updateDownloaded(item.sid, local.length);
      }

      // 章节记录也一起对齐：指着已经不在的目录的记录删掉，
      // 详情页才不会继续显示「已下载」
      final doneTasks = <({int id, int chapterIndex})>[];
      for (final task in downloads.tasks) {
        if (task.sid != item.sid) continue;
        if (task.status != DownloadStatus.done) continue;
        doneTasks.add((id: task.id, chapterIndex: task.chapterIndex));
      }
      for (final id in LocalLibrary.staleChapterTaskIds(doneTasks, local)) {
        await dao.deleteTask(id);
      }
    }

    return cleared;
  }

  /// 扫一个源的目录，返回这次新认出来的本子数量
  Future<int> _scanSourceDir(String root, String source) async {
    final sourceDir = Directory(JmStorage.sourceRoot(root, source));
    if (!await sourceDir.exists()) return 0;

    var found = 0;

    await for (final album in sourceDir.list()) {
      if (album is! Directory) continue;
      final albumId = p.basename(album.path);
      if (albumId.isEmpty || albumId.startsWith('.')) continue;

      // 章节目录名就是章节序号
      final chapters = <int, String>{};
      await for (final chapter in album.list()) {
        if (chapter is! Directory) continue;
        final index = int.tryParse(p.basename(chapter.path));
        if (index == null || index <= 0) continue;
        if (await JmStorage.countImages(chapter.path) > 0) {
          chapters[index] = chapter.path;
        }
      }
      if (chapters.isEmpty) continue;

      final sid = SourceId(source, albumId);
      final existing = await dao.getBookshelf(sid);
      final savedTitle = existing?.title.trim() ?? '';
      final title = savedTitle.isNotEmpty ? savedTitle : albumId;

      await dao.upsertBookshelf(
        sid: sid,
        title: title,
        author: existing?.author ?? '',
        coverUrl: existing?.coverUrl ?? '',
        tags: existing?.tags ?? '',
        chapterCount: (existing?.chapterCount ?? 0) > chapters.length
            ? existing!.chapterCount
            : chapters.length,
        downloaded: chapters.length,
        rootPath: root,
      );

      // 同步补出下载记录：详情页每章才会显示「已下载」，
      // 书架进度条也才对得上
      for (final entry in chapters.entries) {
        final images = await JmStorage.countImages(entry.value);
        await dao.upsertTask(
          DownloadTask(
            id: 0,
            source: source,
            albumId: albumId,
            albumTitle: title,
            chapterId: '${entry.key}',
            chapterIndex: entry.key,
            chapterTitle: '第 ${entry.key} 话',
            status: DownloadStatus.done,
            done: images,
            total: images,
            failed: 0,
            error: '',
            dirPath: entry.value,
          ),
        );
      }
      found++;
    }
    return found;
  }

  Future<void> refreshRoot() async {
    await _resolveRoot();
    await applyGalleryVisibility();
  }

  /// 定下这次要用的下载根目录
  Future<void> _resolveRoot() async {
    // 1. 用户手填的目录优先
    final manual = settings.value.downloadDir.trim();
    if (manual.isNotEmpty && await JmStorage.canWrite(manual)) {
      await _useRoot(manual);
      return;
    }

    // 2. 上次成功用过的目录
    final remembered = await RootStore.load();
    if (remembered.isNotEmpty && await JmStorage.canWrite(remembered)) {
      await _useRoot(remembered);
      return;
    }

    // 3. 公共目录
    if (await JmStorage.canWrite(JmStorage.publicRoot)) {
      await _useRoot(JmStorage.publicRoot);
      return;
    }

    // 4. 没有「所有文件访问」权限：退回应用外部私有目录，保证下载仍可用。
    //    这里刻意不写进 RootStore —— 用户之后授了权，下次启动会自动回到公共目录。
    final base =
        await getExternalStorageDirectory() ??
        await getApplicationDocumentsDirectory();
    await _useRoot(
      '${base.path}/${JmStorage.publicFolderName}',
      persist: false,
    );
  }

  /// 固定下载根目录：界面显示的、下载写入的、下次启动用的，三处必须是同一个值
  Future<void> _useRoot(String path, {bool persist = true}) async {
    JmStorage.setRootOverride(path);
    JmStorage.setFallbackRoot(path);
    rootDir.value = path;
    await _applySourceRoots();
    if (persist) {
      await RootStore.save(path);
    } else {
      await RootStore.clear();
    }
  }

  /// 给每个源定下载目录
  ///
  /// 用户在设置里单独填过的就用它——写不进去就退回默认，免得下载直接失败；
  /// 没填的按默认来：JM 用根目录，哔咔、EH 用根目录旁边的同名文件夹。
  /// 换过目录也不影响老书，阅读时以数据库里记的落盘位置为准。
  Future<void> _applySourceRoots() async {
    final s = settings.value;
    final configured = {
      'jm': s.downloadDir,
      'pica': s.picaDir,
      'eh': s.ehDir,
      'pixiv': s.pixivDir,
    };

    final roots = <String, String>{};
    for (final entry in configured.entries) {
      final dir = entry.value.trim();
      if (dir.isEmpty) continue;
      if (await JmStorage.canWrite(dir)) roots[entry.key] = dir;
    }
    JmStorage.setSourceRoots(roots);
  }

  /// 按设置让下载目录在系统相册里隐藏（或重新显示）
  ///
  /// 公共目录里的图片会被相册自动收录，下一本本子就多出几百张图，
  /// 相册基本没法看了。做法是往目录里放一个 `.nomedia`，再让系统相册
  /// 重新扫一次——光放标记文件不会让已经进去的图消失，必须补扫描那一下。
  ///
  /// [force] 用于设置页的「清理相册」按钮：用户手动点就该重新扫一遍。
  Future<void> applyGalleryVisibility({bool force = false}) async {
    final root = rootDir.value;
    if (root.isEmpty) return;

    final hide = settings.value.hideFromGallery;
    final signature = '$root|$hide';
    if (!force && signature == _galleryGuardState) return;

    final dirs = JmStorage.galleryGuardDirs(root);
    final touched = hide
        ? await JmStorage.writeNoMedia(dirs)
        : await JmStorage.removeNoMedia(dirs);
    await PlatformService.scanMedia(touched);
    _galleryGuardState = signature;
  }
}
