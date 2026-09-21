/// EH（E-Hentai / ExHentai）漫画源
///
/// 把 [EhClient] 包装成统一的 [ComicSource]。EH 和 JM、哔咔有两处根本区别：
/// 1. 一个画廊就是一话，没有章节概念，所以详情里只放一话「全一话」
/// 2. 图片真实地址藏在每一页的 `/s/...` 页面里，列表阶段拿不到，
///    所以用 [ChapterPlan.resolve] 做「边下边解析」
///
/// 另外 EH 的域名在国内被 SNI 阻断，必须挂梯子，这里不做任何绕过尝试。
library;

import 'package:dio/dio.dart';

import '../../net/net_transport.dart';
import '../comic_source.dart';
import 'eh_account.dart';
import 'eh_client.dart';

class EhSource implements ComicSource {
  EhSource({NetTransport? transport}) : client = EhClient(transport: transport);

  final EhClient client;

  /// 详情缓存：下载时还要用一次页数，避免重复请求详情页
  final Map<String, EhGallery> _galleries = {};

  bool _restored = false;

  /// 是否走 ExHentai，真值来自设置项（表站 / 里站开关）
  bool _useEx = false;

  @override
  String get key => 'eh';

  @override
  String get name => 'EH';

  @override
  String get folder => 'EH';

  /// 只看 e-hentai 不需要登录；勾了 ExHentai 就必须先有 Cookie
  @override
  bool get needsLogin => account.useEx && !account.hasLogin;

  @override
  Dio get dio => client.dio;

  @override
  Map<String, String> get imageHeaders => client.imageHeaders;

  /// 用设置里的全局并发
  @override
  int? get imageConcurrencyOverride => null;

  EhAccount get account => client.account;

  bool get loggedIn => client.loggedIn;

  /// 展示用的账号名（EH 只有数字 ID）
  String get accountLabel => account.memberId;

  /// 当前走的是不是 ExHentai
  bool get usingEx => client.baseUrl.contains('exhentai');

  // ==================== 登录态 ====================

  Future<void> restore() async {
    if (_restored) return;
    _restored = true;
    final saved = await EhAccountStore.load();
    if (saved != null) {
      client.update(account: saved.copyWith(useEx: _useEx));
    }
  }

  /// 设置页的「使用 ExHentai」开关
  void applyUseEx(bool value) {
    if (_useEx == value) return;
    _useEx = value;
    client.update(account: client.account.copyWith(useEx: value));
  }

  /// 用户粘贴浏览器 Cookie 登录
  ///
  /// 存下来之前先真请求一次首页验一下：值不对就直接报错、不落盘，
  /// 免得留下一个「看着已登录、其实用不了」的状态。
  Future<void> login(String pasted) async {
    final parsed = EhAccount.parsePasted(pasted, useEx: _useEx);
    if (!parsed.hasLogin) {
      throw const SourceException(
        '没认出 ipb_member_id 和 ipb_pass_hash，请把浏览器里 EH 的完整 Cookie 复制过来',
        needsLogin: true,
      );
    }
    if (_useEx && !parsed.canUseEx) {
      throw const SourceException(
        '走 ExHentai 还需要 igneous 这个 Cookie，请在 ExHentai 站点上复制',
        needsLogin: true,
      );
    }

    final previous = client.account;
    client.update(account: parsed);
    try {
      await client.verifyLogin();
    } on Exception {
      client.update(account: previous);
      rethrow;
    }

    _restored = true;
    await EhAccountStore.save(parsed);
  }

  Future<void> logout() async {
    client.update(account: EhAccount(useEx: _useEx));
    _restored = true;
    await EhAccountStore.clear();
  }

  /// 代理 / 绕过污染配置变更后重建连接
  void updateTransport(NetTransport transport) {
    client.update(transport: transport);
  }

  @override
  Future<bool> ready() async {
    await restore();
    return true;
  }

  // ==================== 搜索 / 详情 ====================

  @override
  Future<ComicSearchPage> search(
    String keyword, {
    SearchMode mode = SearchMode.site,
    int page = 1,
  }) async {
    await restore();
    // EH 只有关键词搜索，作者 / 标签模式统一退化成关键词
    return client.search(keyword, page: page);
  }

  @override
  Future<ComicDetail> detail(String id) async {
    await restore();
    final gallery = await _galleryOf(id);
    final pages = gallery.pageCount;

    final meta = <MapEntry<String, String>>[];
    if (gallery.uploader.trim().isNotEmpty) {
      meta.add(MapEntry('上传者', gallery.uploader));
    }
    if (pages > 0) meta.add(MapEntry('页数', '$pages'));
    meta.add(MapEntry('画廊 ID', id));

    return ComicDetail(
      sid: SourceId(key, id),
      title: gallery.title,
      author: gallery.uploader,
      tags: gallery.tags,
      coverUrl: gallery.coverUrl,
      coverHeaders: client.imageHeaders,
      chapters: [
        ComicChapter(
          id: id,
          title: pages > 0 ? '全一话（$pages 页）' : '全一话',
          index: 1,
          order: 1,
        ),
      ],
      meta: meta,
      // EH 没有收藏接口，详情页据此隐藏收藏按钮
      isFavorite: null,
    );
  }

  @override
  Future<ChapterPlan> chapterPlan(
    ComicDetail detail,
    ComicChapter chapter,
  ) async {
    await restore();
    final id = detail.sid.id;
    final gallery = await _galleryOf(id);
    final paths = await client.pagePaths(id, gallery.pageCount);
    if (paths.isEmpty) {
      throw const SourceException('这一话没取到图片，可能是画廊已删除或配额用完了');
    }

    final headers = client.imageHeaders;
    return ChapterPlan(
      images: [
        for (var i = 0; i < paths.length; i++)
          ChapterImage(url: '', fileName: _pageName(i, '.jpg')),
      ],
      // 下载器取每一张图之前调一次，同一个下标只解析一次
      resolve: (index, image) async {
        final url = await client.imageUrl(paths[index]);
        return ChapterImage(
          url: url,
          fileName: _pageName(index, _extensionOf(url)),
          headers: headers,
        );
      },
    );
  }

  @override
  Future<bool?> setFavorite(String id, {required bool want}) async => null;

  // ==================== 排行榜 ====================

  static const Map<String, String> _rankTl = {
    'yesterday': '15',
    'month': '13',
    'year': '12',
    'all': '11',
  };

  /// EH 的榜单是按「昨日 / 本月 / 今年 / 全部时间」分的，没有周榜
  static const List<RankOption> _rankTimes = [
    RankOption('yesterday', '昨日'),
    RankOption('month', '本月'),
    RankOption('year', '今年'),
    RankOption('all', '全部时间'),
  ];

  @override
  List<RankOption> get rankTimes => _rankTimes;

  /// EH 榜单没有分类这一档，界面上不会出现第三行
  @override
  List<RankOption> rankCategories(String time) => const [];

  @override
  Future<ComicSearchPage> rank({
    required String time,
    String category = '',
    int page = 1,
  }) async {
    await restore();
    return client.toplist(_rankTl[time] ?? '15', page: page);
  }

  // ==================== 辅助 ====================

  Future<EhGallery> _galleryOf(String id) async {
    final cached = _galleries[id];
    if (cached != null) return cached;

    final gallery = await client.gallery(id);
    // 简单限个量，免得长时间浏览把详情全攒在内存里
    if (_galleries.length >= 16) _galleries.remove(_galleries.keys.first);
    _galleries[id] = gallery;
    return gallery;
  }

  static String _pageName(int index, String extension) =>
      '${(index + 1).toString().padLeft(5, '0')}$extension';

  /// 从图片地址里取后缀，取不到就按 JPEG 存（Flutter 按内容识别格式，不影响阅读）
  static String _extensionOf(String url) {
    final path = Uri.tryParse(url)?.path ?? '';
    final dot = path.lastIndexOf('.');
    if (dot < 0) return '.jpg';
    final ext = path.substring(dot).toLowerCase();
    if (ext.length > 5 || ext.contains('/')) return '.jpg';
    return ext;
  }
}
