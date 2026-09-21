/// Pixiv 源
///
/// 把 [PixivClient] 包装成统一的 [ComicSource]。和别的源有两处不一样：
/// 1. 一个作品就是一话，没有章节概念，所以详情里只放一话
/// 2. 图片走公共反代，同一个域名可能突然不通，所以下载失败时用
///    [ChapterPlan.refresh] 换一个反代域名重新拼地址
///
/// 免登录就能用：搜索、详情、下载都走公共镜像，代价是收藏 / 关注这类
/// 需要账号的功能做不了（详情页会据此隐藏收藏按钮）。
///
/// 接口返回的 JSON 形状很杂（单页 / 多页 / 动图的字段都不一样），
/// 所以解析全部集中在 [PixivParsing] 里，纯函数、好单独验。
library;

import 'package:dio/dio.dart';

import '../../net/net_transport.dart';
import '../comic_source.dart';
import 'pixiv_client.dart';

class PixivSource implements ComicSource {
  PixivSource({
    NetTransport? transport,
    List<String>? apiBases,
    List<String>? imageProxies,
    this.imageQuality = PixivParsing.qualityOriginal,
  }) : client = PixivClient(
         transport: transport,
         apiBases: apiBases,
         imageProxies: imageProxies,
       );

  final PixivClient client;

  /// 下载哪一档图，取值见 [PixivParsing.qualityOriginal] / [PixivParsing.qualityLarge]
  String imageQuality;

  /// 作者模式下最多同时列几个画师的作品
  static const int authorFanOut = 3;

  @override
  String get key => 'pixiv';

  @override
  String get name => 'Pixiv';

  @override
  String get folder => 'Pixiv';

  @override
  bool get needsLogin => false;

  @override
  Dio get dio => client.dio;

  @override
  Map<String, String> get imageHeaders => PixivClient.imageHeaders;

  /// 反代本来就慢，单张原图好几兆，并发压低一点，免得把手机和反代一起打死
  @override
  int get imageConcurrencyOverride => 3;

  @override
  Future<bool> ready() async => true;

  void updateTransport(NetTransport transport) {
    client.updateTransport(transport);
  }

  /// 设置里改过镜像 / 反代之后重新配置
  void reconfigure({
    List<String>? apiBases,
    List<String>? imageProxies,
    String? imageQuality,
  }) {
    client.reconfigure(apiBases: apiBases, imageProxies: imageProxies);
    if (imageQuality != null) this.imageQuality = imageQuality;
  }

  // ==================== 排行榜 ====================

  /// Pixiv 只有 日 / 周 / 月 三档，没有年榜
  static const List<RankOption> _rankTimes = [
    RankOption('day', '日榜'),
    RankOption('week', '周榜'),
    RankOption('month', '月榜'),
  ];

  /// 每个时间档下镜像**真正支持**的档位
  ///
  /// 镜像实现得并不完整：`week_male`、`month_r18` 这类组合直接 500，
  /// 所以按时间分开列，界面上只给点得通的，免得用户点了报错。
  static const Map<String, List<RankOption>> _rankCategoryTable = {
    'day': [
      RankOption('all', '综合'),
      RankOption('male', '男性向'),
      RankOption('female', '女性向'),
      RankOption('ai', 'AI'),
      RankOption('r18', 'R18'),
      RankOption('male_r18', 'R18 男性向'),
      RankOption('female_r18', 'R18 女性向'),
    ],
    'week': [
      RankOption('all', '综合'),
      RankOption('original', '原创'),
      RankOption('rookie', '新人'),
      RankOption('r18', 'R18'),
    ],
    'month': [RankOption('all', '综合')],
  };

  @override
  List<RankOption> get rankTimes => _rankTimes;

  @override
  List<RankOption> rankCategories(String time) =>
      _rankCategoryTable[time] ?? const [RankOption('all', '综合')];

  /// 镜像的档位串就是 `时间` 或 `时间_分类`（如 day / week_r18）
  @override
  Future<ComicSearchPage> rank({
    required String time,
    String category = '',
    int page = 1,
  }) async {
    final mode = category.isEmpty || category == 'all'
        ? time
        : '${time}_$category';
    final illusts = await client.rank(mode, page: page);

    return ComicSearchPage(
      items: illusts.map(_toItem).toList(),
      // 镜像不给总数，拿到内容就继续允许往下翻
      total: illusts.isEmpty ? 0 : page * illusts.length + 1,
      page: page,
    );
  }

  // ==================== 搜索 / 详情 ====================

  @override
  Future<ComicSearchPage> search(
    String keyword, {
    SearchMode mode = SearchMode.site,
    int page = 1,
  }) async {
    if (mode == SearchMode.author) return _searchByAuthor(keyword, page: page);

    final target = PixivParsing.searchTarget(mode.key);
    final illusts = await client.search(keyword, target: target, page: page);

    return ComicSearchPage(
      items: illusts.map(_toItem).toList(),
      // 镜像不给总数，只要能拿到内容就继续允许往下翻
      total: illusts.isEmpty ? 0 : page * illusts.length + 1,
      page: page,
    );
  }

  /// 作者模式：先搜画师，再把这几个画师的作品合起来
  ///
  /// 接口没有「按作者名搜作品」这一项，只能这么两步走。画师数量固定取前几个，
  /// 这样翻页语义才稳定（第 N 页就是这几个画师的第 N 页作品）。
  Future<ComicSearchPage> _searchByAuthor(
    String keyword, {
    required int page,
  }) async {
    final users = await client.searchUser(keyword, page: 1);
    final picked = <String>[];
    for (final entry in users) {
      final user = entry['user'];
      final id = user is Map ? '${user['id'] ?? ''}'.trim() : '';
      if (id.isEmpty || id == 'null') continue;
      if (!picked.contains(id)) picked.add(id);
      if (picked.length >= authorFanOut) break;
    }

    if (picked.isEmpty) {
      return ComicSearchPage(items: const [], page: page);
    }

    final lists = await Future.wait([
      for (final id in picked)
        client
            .memberIllust(id, page: page)
            .catchError((Object _) => const <Map<String, dynamic>>[]),
    ]);

    final merged = PixivParsing.interleave(lists);
    return ComicSearchPage(
      items: merged.map(_toItem).toList(),
      total: merged.isEmpty ? 0 : page * merged.length + 1,
      page: page,
    );
  }

  @override
  Future<ComicDetail> detail(String id) async {
    final illust = await client.illust(id);

    final type = PixivParsing.typeOf(illust);
    final pages = PixivParsing.pageCount(illust);
    final title = '${illust['title'] ?? ''}'.trim();

    final meta = <MapEntry<String, String>>[];
    void addMeta(String k, String v) {
      if (v.trim().isNotEmpty && v.trim() != 'null') meta.add(MapEntry(k, v));
    }

    final user = illust['user'];
    final author = user is Map ? '${user['name'] ?? ''}'.trim() : '';

    addMeta('作者', author);
    if (user is Map) addMeta('画师 ID', '${user['id'] ?? ''}');
    addMeta('类型', PixivParsing.typeLabel(type));
    addMeta('页数', pages > 0 ? '$pages' : '');
    addMeta('发布', PixivParsing.dateText('${illust['create_date'] ?? ''}'));
    addMeta('尺寸', '${illust['width'] ?? ''}×${illust['height'] ?? ''}');
    addMeta('浏览', '${illust['total_view'] ?? ''}');
    addMeta('收藏', '${illust['total_bookmarks'] ?? ''}');
    if (PixivParsing.intOf(illust['x_restrict']) > 0) addMeta('分级', 'R-18');
    if (PixivParsing.intOf(illust['illust_ai_type']) > 0) addMeta('AI', 'AI 生成');

    return ComicDetail(
      sid: SourceId(key, id),
      title: title.isEmpty ? 'Pixiv $id' : title,
      author: author,
      description: PixivParsing.plainText('${illust['caption'] ?? ''}'),
      tags: PixivParsing.tagsOf(illust),
      coverUrl: _coverUrl(illust),
      coverHeaders: PixivClient.imageHeaders,
      chapters: [
        ComicChapter(
          id: id,
          title: pages > 0 ? '全一话（$pages 页）' : '全一话',
          index: 1,
          order: 1,
        ),
      ],
      meta: meta,
      // 公共镜像只读，收藏 / 关注这类要账号的功能做不了
      isFavorite: null,
    );
  }

  @override
  Future<ChapterPlan> chapterPlan(
    ComicDetail detail,
    ComicChapter chapter,
  ) async {
    final illust = await client.illust(detail.sid.id);
    final urls = PixivParsing.imageUrls(
      illust,
      preferLarge: imageQuality == PixivParsing.qualityLarge,
    );
    if (urls.isEmpty) {
      throw const SourceException('这个作品没取到图片，可能是动图（暂不支持）或已被删除');
    }

    ChapterImage build(int index) => ChapterImage(
      url: client.imageUrl(urls[index]),
      fileName: PixivParsing.pageName(index, urls[index]),
      headers: PixivClient.imageHeaders,
    );

    return ChapterPlan(
      images: [for (var i = 0; i < urls.length; i++) build(i)],
      // 某个反代域名突然不通时换下一个再试
      refresh: (index) {
        client.rotateImageProxy();
        return build(index);
      },
    );
  }

  /// 公共镜像没有写接口，收藏按钮直接不显示
  @override
  Future<bool?> setFavorite(String id, {required bool want}) async => null;

  // ==================== 辅助 ====================

  ComicItem _toItem(Map<String, dynamic> illust) {
    final user = illust['user'];
    final author = user is Map ? '${user['name'] ?? ''}'.trim() : '';
    final pages = PixivParsing.pageCount(illust);

    final subtitle = [
      author,
      PixivParsing.typeLabel(PixivParsing.typeOf(illust)),
      if (pages > 1) '$pages 页',
      if (PixivParsing.intOf(illust['x_restrict']) > 0) 'R-18',
    ].where((e) => e.trim().isNotEmpty).join(' · ');

    return ComicItem(
      sid: SourceId(key, '${illust['id']}'),
      title: '${illust['title'] ?? ''}'.trim(),
      author: author,
      coverUrl: _coverUrl(illust),
      coverHeaders: PixivClient.imageHeaders,
      subtitle: subtitle,
    );
  }

  /// 列表封面用 large（600x1200），详情页大图也用它
  String _coverUrl(Map<String, dynamic> illust) {
    final urls = illust['image_urls'];
    if (urls is! Map) return '';
    for (final key in ['large', 'medium', 'square_medium']) {
      final value = '${urls[key] ?? ''}'.trim();
      if (value.isNotEmpty && value != 'null') return client.imageUrl(value);
    }
    return '';
  }
}

/// 接口 JSON 的解析：全是纯函数，不碰网络，方便单独验
class PixivParsing {
  PixivParsing._();

  /// 界面的搜索模式 -> 接口的 search_target，认不出的退回综合
  static String searchTarget(String modeKey) =>
      PixivConst.searchTargets[modeKey] ?? 'partial_match_for_tags';

  /// 一个作品的全部图片地址
  ///
  /// 多页作品的每一页都在 meta_pages 里；单页作品的原图在 meta_single_page 里。
  /// 动图（ugoira）给的不是图片，返回空列表让上层提示。
  ///
  /// [preferLarge] 为 true 时改用 1200px 那一档：原图动辄两三兆一张，
  /// 一话几十张就是几十兆，手机上换小一档基本看不出差别。
  static List<String> imageUrls(
    Map<String, dynamic> illust, {
    bool preferLarge = false,
  }) {
    if (typeOf(illust) == 'ugoira') return const [];

    final meta = illust['meta_pages'];
    if (meta is List && meta.isNotEmpty) {
      final out = <String>[];
      for (final page in meta) {
        final url = _pick(page is Map ? page['image_urls'] : null, preferLarge);
        if (url.isNotEmpty) out.add(url);
      }
      if (out.isNotEmpty) return out;
    }

    // 单页作品：原图和大图各在一个地方，按档位挑
    final single = illust['meta_single_page'];
    final original = single is Map
        ? _textOf(single['original_image_url'])
        : '';
    final large = _pick(illust['image_urls'], preferLarge);

    if (preferLarge && large.isNotEmpty) return [large];
    if (original.isNotEmpty) return [original];
    if (large.isNotEmpty) return [large];
    return const [];
  }

  /// 从一份 image_urls 里挑一个地址
  static String _pick(dynamic urls, bool preferLarge) {
    if (urls is! Map) return '';
    final keys = preferLarge
        ? const ['large', 'medium', 'original']
        : const ['original', 'large', 'medium'];
    for (final key in keys) {
      final url = _textOf(urls[key]);
      if (url.isNotEmpty) return url;
    }
    return '';
  }

  /// 原图
  static const String qualityOriginal = 'original';

  /// 1200px 那一档
  static const String qualityLarge = 'large';

  static String qualityLabel(String quality) =>
      quality == qualityLarge ? '较大（1200px）' : '原图';

  /// 标签：优先用中文译名，去重，最多留 24 个
  static List<String> tags(Map<String, dynamic> illust) {
    final raw = illust['tags'];
    if (raw is! List) return const [];
    final out = <String>[];
    for (final tag in raw) {
      if (tag is! Map) continue;
      final translated = _textOf(tag['translated_name']);
      final name = _textOf(tag['name']);
      final value = translated.isNotEmpty ? translated : name;
      if (value.isEmpty || out.contains(value)) continue;
      out.add(value);
      if (out.length >= 24) break;
    }
    return out;
  }

  static List<String> tagsOf(Map<String, dynamic> illust) => tags(illust);

  static String typeOf(Map<String, dynamic> illust) {
    final type = _textOf(illust['type']);
    return type.isEmpty ? 'illust' : type;
  }

  static String typeLabel(String type) {
    switch (type) {
      case 'manga':
        return '漫画';
      case 'ugoira':
        return '动图';
      default:
        return '插画';
    }
  }

  static int pageCount(Map<String, dynamic> illust) {
    final count = intOf(illust['page_count']);
    if (count > 0) return count;
    final meta = illust['meta_pages'];
    if (meta is List && meta.isNotEmpty) return meta.length;
    return 0;
  }

  /// 2026-09-21T18:06:57+09:00 -> 2026-09-21
  static String dateText(String raw) {
    final value = raw.trim();
    if (value.length < 10) return value;
    return value.substring(0, 10);
  }

  static int intOf(dynamic value) => int.tryParse('$value') ?? 0;

  /// Pixiv 的简介是 HTML，阅读页显示不了标签，先剥成纯文本
  static String plainText(String html) => html
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&nbsp;', ' ')
      .trim();

  /// 第几页 -> 00001.jpg
  static String pageName(int index, String url) =>
      '${(index + 1).toString().padLeft(5, '0')}${extensionOf(url)}';

  static String extensionOf(String url) {
    final path = Uri.tryParse(url)?.path ?? '';
    final dot = path.lastIndexOf('.');
    if (dot < 0) return '.jpg';
    final ext = path.substring(dot).toLowerCase();
    if (ext.length > 5 || ext.contains('/')) return '.jpg';
    return ext;
  }

  /// 几个画师的结果轮流取一条，避免第一个画师刷屏
  static List<Map<String, dynamic>> interleave(
    List<List<Map<String, dynamic>>> lists,
  ) {
    final out = <Map<String, dynamic>>[];
    final seen = <String>{};
    var index = 0;
    while (true) {
      var added = false;
      for (final list in lists) {
        if (index >= list.length) continue;
        added = true;
        final item = list[index];
        if (seen.add('${item['id']}')) out.add(item);
      }
      if (!added) break;
      index++;
    }
    return out;
  }

  static String _textOf(dynamic value) {
    final text = '${value ?? ''}'.trim();
    return text == 'null' ? '' : text;
  }
}
