/// 统一漫画源抽象层
///
/// 每个源（JM / 哔咔 / EH）实现 [ComicSource]，上层 UI 与下载器只认这里的模型，
/// 不再直接依赖任何单一源的实体类。
library;

import 'package:dio/dio.dart';

/// 源标识：`source` 是源 key（jm / pica / eh），`id` 是源内本子 ID
class SourceId {
  const SourceId(this.source, this.id);

  final String source;
  final String id;

  /// 形如 `jm:1474516`，用于数据库与页面跳转
  String get key => '$source:$id';

  static SourceId parse(String key) {
    final i = key.indexOf(':');
    if (i <= 0) return SourceId('jm', key);
    return SourceId(key.substring(0, i), key.substring(i + 1));
  }

  @override
  bool operator ==(Object other) =>
      other is SourceId && other.source == source && other.id == id;

  @override
  int get hashCode => Object.hash(source, id);

  @override
  String toString() => key;
}

/// 搜索模式；各源尽力映射，映射不了就退化成关键词搜索
enum SearchMode {
  site('site', '综合'),
  work('work', '作品'),
  author('author', '作者'),
  tag('tag', '标签'),
  actor('actor', '登场角色');

  const SearchMode(this.key, this.label);

  final String key;
  final String label;

  static SearchMode parse(String key) => SearchMode.values.firstWhere(
    (e) => e.key == key,
    orElse: () => SearchMode.site,
  );
}

/// 列表项（搜索结果 / 排行 / 推荐通用）
class ComicItem {
  const ComicItem({
    required this.sid,
    required this.title,
    this.author = '',
    this.coverUrl = '',
    this.coverHeaders = const {},
    this.subtitle = '',
  });

  final SourceId sid;
  final String title;
  final String author;
  final String coverUrl;

  /// 封面需要鉴权时带上（哔咔的封面要 authorization）
  final Map<String, String> coverHeaders;
  final String subtitle;
}

/// 章节
class ComicChapter {
  const ComicChapter({
    required this.id,
    required this.title,
    required this.index,
    this.order = 0,
  });

  final String id;
  final String title;

  /// 从 1 开始的显示序号，同时作为本地目录名
  final int index;

  /// 源内排序号（哔咔的 order）
  final int order;
}

/// 本子详情
class ComicDetail {
  const ComicDetail({
    required this.sid,
    required this.title,
    this.author = '',
    this.description = '',
    this.tags = const [],
    this.coverUrl = '',
    this.coverHeaders = const {},
    this.chapters = const [],
    this.meta = const [],
    this.isFavorite,
  });

  final SourceId sid;
  final String title;
  final String author;
  final String description;
  final List<String> tags;
  final String coverUrl;
  final Map<String, String> coverHeaders;
  final List<ComicChapter> chapters;
  final List<MapEntry<String, String>> meta;

  /// null 表示该源不支持收藏
  final bool? isFavorite;

  int get chapterCount => chapters.isEmpty ? 1 : chapters.length;

  String get authorText => author.trim().isEmpty ? '未知作者' : author;
}

/// 单张图片的下载信息
class ChapterImage {
  const ChapterImage({
    required this.url,
    required this.fileName,
    this.headers = const {},
  });

  final String url;

  /// 源侧文件名（JM 乱序还原要用，含后缀）
  final String fileName;
  final Map<String, String> headers;
}

/// 一章的下载计划
class ChapterPlan {
  ChapterPlan({
    required this.images,
    this.scrambleId = '',
    this.scrambleAid = '',
    this.refresh,
    this.resolve,
  });

  final List<ChapterImage> images;

  /// JM 的乱序分界值；其它源为 ''
  final String scrambleId;

  /// 计算乱序段数用的 ID（JM 用的是章节 ID，不是本子 ID）
  final String scrambleAid;

  /// 重试时重新解析第 index 张图的地址
  /// （JM 的图片 CDN 会被运营商重置，失败后要换节点重拼地址）
  final ChapterImage Function(int index)? refresh;

  /// 取图之前需要先进一次详情页才能拿到真实地址时用这个
  ///
  /// EH 就是这样：图片地址藏在每页的 `/s/...` 页面里。下载器会在取每张图
  /// 之前调用一次，同一个下标只解析一次，解析和下载是重叠进行的。
  final Future<ChapterImage> Function(int index, ChapterImage image)? resolve;
}

/// 搜索分页
class ComicSearchPage {
  const ComicSearchPage({
    required this.items,
    this.total = 0,
    this.page = 1,
    this.error,
  });

  final List<ComicItem> items;
  final int total;
  final int page;

  /// 多源并发搜索时，某个源失败不影响其它源，错误挂在这里
  final String? error;

  bool get hasMore => total > 0 && page * items.length < total;
}

/// 排行榜里的一个档位（时间档 / 分类档通用）
///
/// [key] 是给源自己解释的字符串，界面只负责显示 [label]、把选中的 key 传回去。
class RankOption {
  const RankOption(this.key, this.label);

  final String key;
  final String label;
}

/// 源异常
class SourceException implements Exception {
  const SourceException(this.message, {this.needsLogin = false});

  final String message;

  /// true 表示要登录后才能用（UI 可引导去设置页登录）
  final bool needsLogin;

  @override
  String toString() => message;
}

/// 漫画源统一接口
abstract class ComicSource {
  /// 源 key：jm / pica / eh
  String get key;

  /// 展示名：JM / 哔咔 / EH
  String get name;

  /// 本地目录名
  String get folder;

  /// 搜索前是否需要登录
  bool get needsLogin;

  /// 下载图片用的 HTTP 客户端（各源的代理 / Cookie / 鉴权头都不一样）
  Dio get dio;

  /// 图片 / 封面请求头（哔咔要带 authorization）
  Map<String, String> get imageHeaders;

  /// 单章内图片并发的覆盖值；null 表示用设置里的全局值
  ///
  /// Pixiv 走公共反代，单张原图好几兆，压到 3 才不会把反代惹毛。
  int? get imageConcurrencyOverride => null;

  /// 当前是否可用（已登录 / 无需登录）
  Future<bool> ready();

  Future<ComicSearchPage> search(
    String keyword, {
    SearchMode mode = SearchMode.site,
    int page = 1,
  });

  Future<ComicDetail> detail(String id);

  /// 章节下载计划
  Future<ChapterPlan> chapterPlan(ComicDetail detail, ComicChapter chapter);

  /// 收藏 / 取消收藏，返回操作后是否已收藏；不支持则返回 null
  Future<bool?> setFavorite(String id, {required bool want});

  // ==================== 排行榜 ====================

  /// 排行榜的时间档；空表表示这个源没有排行榜，界面上就不会出现它
  List<RankOption> get rankTimes => const [];

  /// 选了某个时间档之后还能挑哪些分类档
  ///
  /// 空表表示这个源没有这一行（哔咔、EH 就是这样）；返回的内容可以跟着
  /// [time] 变——Pixiv 镜像里不同时间档支持的分类并不一样。
  List<RankOption> rankCategories(String time) => const [];

  /// 取一页排行榜
  ///
  /// [time] / [category] 是上面两行选中的 key；不支持的源直接抛异常。
  Future<ComicSearchPage> rank({
    required String time,
    String category = '',
    int page = 1,
  }) async {
    throw SourceException('$name 暂时没有排行榜');
  }
}
