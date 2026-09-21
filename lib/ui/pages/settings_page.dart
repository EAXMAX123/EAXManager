/// 设置页
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_info.dart';
import '../../data/settings_store.dart';
import '../../jm/jm_storage.dart';
import '../../services/notification_service.dart';
import '../../services/platform_service.dart';
import '../../source/pixiv/pixiv_client.dart';
import '../../source/pixiv/pixiv_source.dart';
import '../../state/app_services.dart';
import '../widgets/file_browser_sheet.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with WidgetsBindingObserver {
  final TextEditingController _proxy = TextEditingController();
  final TextEditingController _domains = TextEditingController();
  final TextEditingController _ipMap = TextEditingController();
  final TextEditingController _updateUrl = TextEditingController();
  final TextEditingController _pixivApi = TextEditingController();
  final TextEditingController _pixivProxy = TextEditingController();

  bool _storageGranted = false;

  static const _presetColors = <int>[
    0xFFE91E63,
    0xFF7C4DFF,
    0xFF2196F3,
    0xFF009688,
    0xFF4CAF50,
    0xFFFF9800,
    0xFF795548,
    0xFF607D8B,
  ];

  @override
  void initState() {
    super.initState();
    _syncFromSettings();
    WidgetsBinding.instance.addObserver(this);
    _refreshStorageState();
  }

  /// 从系统设置页返回时刷新授权状态
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshStorageState();
  }

  Future<void> _refreshStorageState() async {
    final granted = await PlatformService.hasAllFilesAccess();
    if (!mounted || granted == _storageGranted) return;
    setState(() => _storageGranted = granted);
  }

  void _syncFromSettings() {
    final s = AppServices.I.settings.value;
    _proxy.text = s.proxyUrl;
    _domains.text = s.customDomains.join(', ');
    _ipMap.text = s.customIpMap;
    _updateUrl.text = s.updateCheckUrl;
    _pixivApi.text = s.pixivApiBase;
    _pixivProxy.text = s.pixivImageProxy;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _proxy.dispose();
    _domains.dispose();
    _ipMap.dispose();
    _updateUrl.dispose();
    _pixivApi.dispose();
    _pixivProxy.dispose();
    super.dispose();
  }

  Future<void> _update(AppSettings next) => AppServices.I.updateSettings(next);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppSettings>(
      valueListenable: AppServices.I.settings,
      builder: (context, s, _) {
        return ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            _section('下载'),
            ValueListenableBuilder<String>(
              valueListenable: AppServices.I.rootDir,
              builder: (context, root, _) => Column(
                children: [
                  _dirTile(
                    title: 'JM 下载目录',
                    hint: '留空用默认目录',
                    value: s.downloadDir,
                    effective: root,
                    apply: (dir) => s.copyWith(downloadDir: dir),
                  ),
                  _dirTile(
                    title: '哔咔下载目录',
                    hint: '留空放在 JM 目录旁边的 Pica',
                    value: s.picaDir,
                    effective: JmStorage.sourceRoot(root, 'pica'),
                    apply: (dir) => s.copyWith(picaDir: dir),
                  ),
                  _dirTile(
                    title: 'EH 下载目录',
                    hint: '留空放在 JM 目录旁边的 EH',
                    value: s.ehDir,
                    effective: JmStorage.sourceRoot(root, 'eh'),
                    apply: (dir) => s.copyWith(ehDir: dir),
                  ),
                  _dirTile(
                    title: 'Pixiv 下载目录',
                    hint: '留空放在 JM 目录旁边的 Pixiv',
                    value: s.pixivDir,
                    effective: JmStorage.sourceRoot(root, 'pixiv'),
                    apply: (dir) => s.copyWith(pixivDir: dir),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.manage_search),
              title: const Text('重新扫描本地文件'),
              subtitle: const Text(
                '和磁盘对一遍账：本地有图的挂回书架，'
                '记录说已下载、文件其实已经没了的就把标记清掉',
              ),
              isThreeLine: true,
              onTap: () async {
                final messenger = ScaffoldMessenger.of(context);
                messenger.showSnackBar(const SnackBar(content: Text('正在扫描…')));
                final result = await AppServices.I.rescanLocalLibrary();
                final parts = <String>[
                  if (result.found > 0) '找回 ${result.found} 本',
                  if (result.cleared > 0) '清掉 ${result.cleared} 本的失效标记',
                ];
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      parts.isEmpty
                          ? '扫描完成：本地文件和书架记录对得上'
                          : '扫描完成：${parts.join('，')}',
                    ),
                  ),
                );
              },
            ),
            SwitchListTile(
              secondary: const Icon(Icons.hide_image_outlined),
              title: const Text('下载目录不出现在相册'),
              subtitle: const Text(
                '默认开启。下载的本子是几百张图片，不藏起来相册会被刷屏；'
                '文件管理器里照样能找到，只是相册不显示',
              ),
              isThreeLine: true,
              value: s.hideFromGallery,
              onChanged: (v) async {
                await _update(s.copyWith(hideFromGallery: v));
                await AppServices.I.applyGalleryVisibility();
              },
            ),
            ListTile(
              leading: const Icon(Icons.cleaning_services_outlined),
              title: const Text('清理相册里的已下载图片'),
              subtitle: const Text('已经进了相册的图片不会自己消失，点这里让系统相册重新整理一遍'),
              isThreeLine: true,
              onTap: () async {
                final messenger = ScaffoldMessenger.of(context);
                await AppServices.I.applyGalleryVisibility(force: true);
                messenger.showSnackBar(
                  const SnackBar(content: Text('已通知系统相册重新整理，过几秒刷新相册看看')),
                );
              },
            ),
            _sliderTile(
              icon: Icons.downloading,
              title: '同时下载章节数',
              value: s.maxConcurrentChapters.toDouble(),
              min: 1,
              max: 6,
              divisions: 5,
              label: '${s.maxConcurrentChapters}',
              onChanged: (v) =>
                  _update(s.copyWith(maxConcurrentChapters: v.round())),
            ),
            _sliderTile(
              icon: Icons.photo_library_outlined,
              title: '每章同时下载图片数',
              value: s.maxConcurrentImages.toDouble(),
              min: 1,
              max: 12,
              divisions: 11,
              label: '${s.maxConcurrentImages}',
              onChanged: (v) =>
                  _update(s.copyWith(maxConcurrentImages: v.round())),
            ),
            _sliderTile(
              icon: Icons.high_quality_outlined,
              title: '图片质量',
              value: s.jpegQuality.toDouble(),
              min: 70,
              max: 100,
              divisions: 6,
              label: '${s.jpegQuality}',
              onChanged: (v) => _update(s.copyWith(jpegQuality: v.round())),
            ),

            _section('网络'),
            _tile(
              icon: Icons.vpn_lock_outlined,
              title: '代理地址',
              subtitle: s.proxyUrl.isNotEmpty
                  ? s.proxyUrl
                  : (AppServices.I.systemProxy.isEmpty
                        ? '未设置（http:// 或 socks5:// 都支持）'
                        : '检测到系统代理 ${AppServices.I.systemProxy}，'
                              '点右边填入才能生效'),
              trailing: IconButton(
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => _editText(
                  title: '代理地址',
                  controller: _proxy,
                  hint: 'http://127.0.0.1:7890 或 socks5://127.0.0.1:1080',
                  onSave: (v) => _update(s.copyWith(proxyUrl: v.trim())),
                ),
              ),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.travel_explore_outlined),
              title: const Text('强制使用真实 IP'),
              subtitle: Text(
                s.dnsBypass == 'on'
                    ? '始终直接用内置的真实 IP 连接'
                    : '默认：先按常规方式连接，连不上会自动改用真实 IP，一般不用动这里',
              ),
              value: s.dnsBypass == 'on',
              onChanged: (v) async {
                await _update(s.copyWith(dnsBypass: v ? 'on' : 'off'));
                await AppServices.I.refreshNetworkEnv();
              },
            ),
            _tile(
              icon: Icons.edit_location_alt_outlined,
              title: '自定义解析',
              subtitle: s.customIpMap.trim().isEmpty
                  ? '手动指定「域名 = IP」。内置地址过期时用得上'
                  : '${s.customIpMap.trim().split('\n').where((e) => e.trim().isNotEmpty).length} 条规则',
              trailing: IconButton(
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => _editText(
                  title: '自定义解析',
                  controller: _ipMap,
                  hint: 'www.cdngwc.cc = 104.21.10.153',
                  maxLines: 6,
                  onSave: (v) async {
                    await _update(s.copyWith(customIpMap: v));
                    await AppServices.I.refreshNetworkEnv();
                  },
                ),
              ),
            ),
            _tile(
              icon: Icons.dns_outlined,
              title: '自定义域名',
              subtitle: s.customDomains.isEmpty
                  ? '自动选择（推荐）'
                  : s.customDomains.join(', '),
              trailing: IconButton(
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => _editText(
                  title: '自定义域名',
                  controller: _domains,
                  hint: '多个用逗号分隔，如 www.cdnhjk.net,www.cdngwc.cc',
                  onSave: (v) => _update(
                    s.copyWith(
                      customDomains: v
                          .split(',')
                          .map((e) => e.trim())
                          .where((e) => e.isNotEmpty)
                          .toList(),
                    ),
                  ),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.refresh),
              title: const Text('重新探测线路'),
              subtitle: Text(
                '当前：${AppServices.I.client.lineName}'
                '（共 ${AppServices.I.client.lineCount} 条线路）\n'
                '出现「连接被重置」时点这里换线路',
              ),
              isThreeLine: true,
              onTap: () async {
                final messenger = ScaffoldMessenger.of(context);
                messenger.showSnackBar(const SnackBar(content: Text('正在探测…')));
                try {
                  await AppServices.I.client.reprobe();
                  if (!mounted) return;
                  setState(() {});
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text('已切到 ${AppServices.I.client.lineName}'),
                    ),
                  );
                } on Exception catch (e) {
                  messenger.showSnackBar(SnackBar(content: Text('$e')));
                }
              },
            ),

            _section('Pixiv'),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Pixiv 走的是第三方镜像'),
              subtitle: const Text(
                '官方接口和图片站国内都连不上，所以数据走公共镜像、图片走公共反代。'
                '这些都是别人免费提供的服务，哪天挂了就得换一个——'
                '下面两项留空就用内置的那一串，连不上会挨个自动试。',
              ),
              isThreeLine: true,
            ),
            _tile(
              icon: Icons.cloud_outlined,
              title: '数据镜像地址',
              subtitle: s.pixivApiBase.trim().isEmpty
                  ? '内置 ${PixivConst.defaultApiBases.length} 个（api.cocomi.eu.org 等）'
                  : s.pixivApiBase.trim(),
              trailing: IconButton(
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => _editText(
                  title: '数据镜像地址',
                  controller: _pixivApi,
                  hint: '多个用逗号分隔，如 https://api.cocomi.eu.org',
                  maxLines: 3,
                  onSave: (v) => _update(s.copyWith(pixivApiBase: v.trim())),
                ),
              ),
            ),
            _tile(
              icon: Icons.image_outlined,
              title: '图片反代域名',
              subtitle: s.pixivImageProxy.trim().isEmpty
                  ? '内置 ${PixivConst.defaultImageProxies.length} 个（i.pixiv.re 等）'
                  : s.pixivImageProxy.trim(),
              trailing: IconButton(
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => _editText(
                  title: '图片反代域名',
                  controller: _pixivProxy,
                  hint: '只填域名，多个用逗号分隔，如 i.pixiv.re,i.pixiv.nl',
                  maxLines: 3,
                  onSave: (v) => _update(s.copyWith(pixivImageProxy: v.trim())),
                ),
              ),
            ),
            _tile(
              icon: Icons.high_quality_outlined,
              title: '下载画质',
              subtitle: s.pixivQuality == PixivParsing.qualityLarge
                  ? '1200px 那一档，体积小很多，手机上基本看不出差别'
                  : '原图，一张两三兆，一话几十张会比较占地方',
              trailing: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: PixivParsing.qualityOriginal,
                    label: Text('原图'),
                  ),
                  ButtonSegment(
                    value: PixivParsing.qualityLarge,
                    label: Text('1200px'),
                  ),
                ],
                selected: {s.pixivQuality},
                showSelectedIcon: false,
                onSelectionChanged: (v) =>
                    _update(s.copyWith(pixivQuality: v.first)),
              ),
            ),

            _section('阅读'),
            SwitchListTile(
              secondary: const Icon(Icons.volume_up_outlined),
              title: const Text('音量键翻页'),
              subtitle: const Text('阅读时用音量键上下滚动'),
              value: s.volumeKeyPageTurn,
              onChanged: (v) => _update(s.copyWith(volumeKeyPageTurn: v)),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.image_outlined),
              title: const Text('列表显示封面'),
              value: s.showCoverInList,
              onChanged: (v) => _update(s.copyWith(showCoverInList: v)),
            ),

            _section('追更'),
            SwitchListTile(
              secondary: const Icon(Icons.notifications_active_outlined),
              title: const Text('后台检查更新'),
              subtitle: const Text('定时检查追更的本子有没有新章节'),
              value: s.autoCheckUpdate,
              onChanged: (v) => _update(s.copyWith(autoCheckUpdate: v)),
            ),
            _sliderTile(
              icon: Icons.schedule_outlined,
              title: '检查间隔',
              value: s.subscribeCheckInterval.toDouble(),
              min: 1800,
              max: 43200,
              divisions: 23,
              label: s.subscribeCheckInterval < 3600
                  ? '${(s.subscribeCheckInterval / 60).round()} 分钟'
                  : '${(s.subscribeCheckInterval / 3600).round()} 小时',
              onChanged: (v) =>
                  _update(s.copyWith(subscribeCheckInterval: v.round())),
            ),
            ListTile(
              leading: const Icon(Icons.sync),
              title: const Text('立即检查一次'),
              subtitle: Text(
                AppServices.I.subscriptions.subscriptions.value.isEmpty
                    ? '还没有追更任何本子'
                    : '共 ${AppServices.I.subscriptions.subscriptions.value.length} 本订阅',
              ),
              onTap: () async {
                final messenger = ScaffoldMessenger.of(context);
                final updates = await AppServices.I.subscriptions.checkNow();
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      updates.isEmpty
                          ? '检查完成，暂无新章节'
                          : '发现 ${updates.length} 本有新章节',
                    ),
                  ),
                );
              },
            ),

            _section('外观'),
            _tile(
              icon: Icons.brightness_6_outlined,
              title: '主题模式',
              subtitle: switch (s.themeMode) {
                'light' => '浅色',
                'dark' => '深色',
                _ => '跟随系统',
              },
              trailing: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'system', label: Text('系统')),
                  ButtonSegment(value: 'light', label: Text('浅')),
                  ButtonSegment(value: 'dark', label: Text('深')),
                ],
                selected: {s.themeMode},
                onSelectionChanged: (v) =>
                    _update(s.copyWith(themeMode: v.first)),
                showSelectedIcon: false,
              ),
            ),
            _tile(
              icon: Icons.palette_outlined,
              title: '主题色',
              subtitle: '点击切换',
              trailing: Wrap(
                spacing: 6,
                children: _presetColors
                    .map(
                      (c) => GestureDetector(
                        onTap: () => _update(s.copyWith(themeSeed: c)),
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: Color(c),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: s.themeSeed == c
                                  ? Theme.of(context).colorScheme.onSurface
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
            _tile(
              icon: Icons.wallpaper_outlined,
              title: '背景图',
              subtitle: s.backgroundColor.isEmpty
                  ? '未设置（纯色背景）'
                  : s.backgroundColor,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.image_search_outlined),
                    tooltip: '选择图片',
                    onPressed: () async {
                      final picked = await FileBrowserSheet.show(
                        context,
                        title: '选择背景图',
                        startPath: s.backgroundColor.isEmpty
                            ? null
                            : s.backgroundColor,
                        extensions: const [
                          '.jpg',
                          '.jpeg',
                          '.png',
                          '.webp',
                          '.gif',
                          '.bmp',
                        ],
                      );
                      if (picked != null) {
                        await _update(s.copyWith(backgroundColor: picked));
                      }
                    },
                  ),
                  if (s.backgroundColor.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: '清除背景图',
                      onPressed: () => _update(s.copyWith(backgroundColor: '')),
                    ),
                ],
              ),
            ),

            _section('账号'),
            ValueListenableBuilder<String>(
              valueListenable: AppServices.I.account,
              builder: (context, account, _) => ListTile(
                leading: const Icon(Icons.account_circle_outlined),
                title: Text(account.isEmpty ? 'JM：未登录' : 'JM：$account'),
                subtitle: Text(
                  account.isEmpty
                      ? '登录后可浏览 JM 收藏夹、收藏本子'
                      : '收藏夹见「发现 → 收藏」；登录掉了会自动重登，不用手动再登',
                ),
                trailing: account.isEmpty
                    ? TextButton(onPressed: _loginJm, child: const Text('登录'))
                    : TextButton(
                        onPressed: () async {
                          await AppServices.I.logout();
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('已退出 JM 登录')),
                          );
                        },
                        child: const Text('退出'),
                      ),
              ),
            ),
            ValueListenableBuilder<String>(
              valueListenable: AppServices.I.picaAccount,
              builder: (context, account, _) => ListTile(
                leading: const Icon(Icons.account_circle_outlined),
                title: Text(account.isEmpty ? '哔咔：未登录' : '哔咔：$account'),
                subtitle: Text(
                  account.isEmpty ? '登录后才能搜索和下载哔咔的本子' : '在搜索页勾选「哔咔」即可搜到它的本子',
                ),
                trailing: account.isEmpty
                    ? TextButton(onPressed: _loginPica, child: const Text('登录'))
                    : TextButton(
                        onPressed: () async {
                          await AppServices.I.picaLogout();
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('已退出哔咔登录')),
                          );
                        },
                        child: const Text('退出'),
                      ),
              ),
            ),
            ValueListenableBuilder<String>(
              valueListenable: AppServices.I.ehAccount,
              builder: (context, account, _) => ListTile(
                leading: const Icon(Icons.account_circle_outlined),
                title: Text(account.isEmpty ? 'EH：未登录' : 'EH：已登录（ID $account）'),
                subtitle: Text(
                  account.isEmpty
                      ? '表站免登录也能搜；里站内容需要粘贴浏览器 Cookie'
                      : '在搜索页勾选「EH」即可搜到它的本子',
                ),
                trailing: account.isEmpty
                    ? TextButton(onPressed: _loginEh, child: const Text('登录'))
                    : TextButton(
                        onPressed: () async {
                          await AppServices.I.ehLogout();
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('已退出 EH 登录')),
                          );
                        },
                        child: const Text('退出'),
                      ),
              ),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.lock_outline),
              title: const Text('EH 使用 ExHentai（里站）'),
              subtitle: Text(
                s.ehUseEx
                    ? '走里站：需要 igneous Cookie，且必须一直挂着梯子'
                    : '走 E-Hentai 表站：免登录也能用',
              ),
              value: s.ehUseEx,
              onChanged: AppServices.I.setEhUseEx,
            ),

            _section('权限与通知'),
            ListTile(
              leading: const Icon(Icons.notifications_outlined),
              title: const Text('通知权限'),
              subtitle: const Text('用于显示下载进度与完成提醒'),
              onTap: () async {
                final ok = await NotificationService.instance
                    .requestPermission();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(ok ? '已获得通知权限' : '未获得通知权限')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.storage_outlined),
              title: const Text('存储权限'),
              subtitle: Text(
                _storageGranted
                    ? '已获得「所有文件访问」，可存到手机公共目录'
                    : '未获得，下载会存到应用私有目录（文件管理器不易查看）',
              ),
              onTap: () async {
                if (!_storageGranted) {
                  await PlatformService.requestAllFilesAccess();
                }
                await Future<void>.delayed(const Duration(milliseconds: 400));
                _storageGranted = await PlatformService.hasAllFilesAccess();
                await AppServices.I.refreshRoot();
                if (mounted) setState(() {});
              },
            ),

            _section('更新'),
            SwitchListTile(
              secondary: const Icon(Icons.system_update_alt),
              title: const Text('启动时检查新版本'),
              subtitle: const Text('联网时自动看一眼有没有新的安装包'),
              value: s.autoCheckAppUpdate,
              onChanged: (v) => _update(s.copyWith(autoCheckAppUpdate: v)),
            ),
            _tile(
              icon: Icons.link_outlined,
              title: '更新检查地址',
              subtitle: s.updateCheckUrl.trim().isEmpty
                  ? '默认用 EAXMAX123/eam-update（GitHub），点右边可以换成自己的'
                  : s.updateCheckUrl,
              trailing: IconButton(
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => _editText(
                  title: '更新检查地址',
                  controller: _updateUrl,
                  hint: AppInfo.updateCheckUrl,
                  maxLines: 3,
                  onSave: (v) => _update(s.copyWith(updateCheckUrl: v.trim())),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.refresh),
              title: const Text('立即检查更新'),
              subtitle: Text('当前 ${AppInfo.fullVersionText}'),
              onTap: () async {
                final messenger = ScaffoldMessenger.of(context);
                messenger.showSnackBar(const SnackBar(content: Text('正在检查…')));
                final result = await AppServices.I.checkAppUpdate(manual: true);
                messenger.showSnackBar(SnackBar(content: Text(result)));
              },
            ),

            _section('关于'),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text(AppInfo.name),
              subtitle: Text(
                '${AppInfo.fullVersionText}\n'
                '当前线路：${AppServices.I.client.lineName}\n'
                '仅供个人学习使用',
              ),
              isThreeLine: true,
            ),
            ListTile(
              leading: const Icon(Icons.groups_outlined),
              title: const Text('交流群'),
              subtitle: const Text('1077681089　279654219\n欢迎进来分享交流'),
              isThreeLine: true,
              trailing: const Icon(Icons.copy_outlined, size: 18),
              onTap: () async {
                await Clipboard.setData(
                  const ClipboardData(text: '1077681089、279654219'),
                );
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('群号已复制：1077681089、279654219')),
                );
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _loginJm() async {
    final input = await _askCredentials(
      title: '登录 JM',
      accountLabel: '用户名',
      accountHint: 'JM 账号用户名',
    );
    if (input == null) return;
    try {
      await AppServices.I.login(input.$1, input.$2);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('JM 登录成功')));
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('JM 登录失败：$e')));
    }
  }

  Future<void> _loginPica() async {
    final input = await _askCredentials(
      title: '登录哔咔',
      accountLabel: '邮箱',
      accountHint: '哔咔账号邮箱（注册时填的那个）',
    );
    if (input == null) return;
    try {
      await AppServices.I.picaLogin(input.$1, input.$2);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('哔咔登录成功')));
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('哔咔登录失败：$e')));
    }
  }

  /// EH 登录：粘贴浏览器里的 Cookie
  ///
  /// EH 没有能用的账号密码接口（登录要过论坛表单和验证码），第三方客户端
  /// 一律用复制 Cookie 的方式，这里也一样。
  Future<void> _loginEh() async {
    final cookie = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('登录 EH'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '在浏览器登录 E-Hentai / ExHentai 后，把 Cookie 整段复制过来。'
                '至少要含 ipb_member_id 和 ipb_pass_hash；要走里站还要有 igneous。',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: cookie,
                minLines: 3,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Cookie',
                  hintText: 'ipb_member_id=...; ipb_pass_hash=...; igneous=...',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('登录'),
          ),
        ],
      ),
    );

    final pasted = cookie.text.trim();
    cookie.dispose();
    if (confirmed != true || pasted.isEmpty) return;

    try {
      await AppServices.I.ehLogin(pasted);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('EH 登录成功')));
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('EH 登录失败：$e')));
    }
  }

  /// 弹出账号密码输入框，取消或没填全返回 null
  Future<(String, String)?> _askCredentials({
    required String title,
    required String accountLabel,
    required String accountHint,
  }) async {
    final account = TextEditingController();
    final password = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: account,
              autofocus: true,
              decoration: InputDecoration(
                labelText: accountLabel,
                hintText: accountHint,
              ),
            ),
            TextField(
              controller: password,
              obscureText: true,
              decoration: const InputDecoration(labelText: '密码'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('登录'),
          ),
        ],
      ),
    );

    final name = account.text.trim();
    final secret = password.text;
    account.dispose();
    password.dispose();

    if (confirmed != true || name.isEmpty || secret.isEmpty) return null;
    return (name, secret);
  }

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
    child: Text(
      title,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );

  Widget _tile({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
  }) => ListTile(
    leading: Icon(icon),
    title: Text(title),
    subtitle: subtitle == null ? null : Text(subtitle),
    trailing: trailing,
  );

  /// 一个源的下载目录设置
  ///
  /// 三个源各管各的目录，但书架是合起来显示的——在哪都能翻到，
  /// 不用为了「哔咔的书放哪」去改 JM 的目录。
  Widget _dirTile({
    required String title,
    required String hint,
    required String value,
    required String effective,
    required AppSettings Function(String dir) apply,
  }) => ListTile(
    leading: const Icon(Icons.folder_outlined),
    title: Text(title),
    subtitle: Text(value.isEmpty ? '$hint\n当前：$effective' : effective),
    isThreeLine: value.isEmpty,
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.folder_open_outlined),
          tooltip: '选择目录',
          onPressed: () async {
            final picked = await FileBrowserSheet.show(
              context,
              title: '选择$title',
              startPath: value.isEmpty ? effective : value,
              pickDirectory: true,
            );
            if (picked != null) await _update(apply(picked));
          },
        ),
        IconButton(
          icon: const Icon(Icons.restart_alt),
          tooltip: '恢复默认',
          onPressed: () => _update(apply('')),
        ),
      ],
    ),
  );

  Widget _sliderTile({
    required IconData icon,
    required String title,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String label,
    required ValueChanged<double> onChanged,
  }) => ListTile(
    leading: Icon(icon),
    title: Text(title),
    subtitle: Slider(
      value: value.clamp(min, max),
      min: min,
      max: max,
      divisions: divisions,
      label: label,
      onChanged: onChanged,
    ),
  );

  Future<void> _editText({
    required String title,
    required TextEditingController controller,
    required String hint,
    required ValueChanged<String> onSave,
    int maxLines = 1,
  }) async {
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: maxLines,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result != null) onSave(result);
  }
}
