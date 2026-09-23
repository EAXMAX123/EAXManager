/// 以图搜图的结果模型
///
/// SauceNAO 和 IQDB 返回的字段不一样，这里统一成一种，界面上就不用管是哪个站给的。
library;

/// 一条匹配结果
class ImageMatch {
  const ImageMatch({
    required this.engine,
    required this.index,
    required this.similarity,
    this.title = '',
    this.author = '',
    this.fields = const {},
    this.sourceUrl = '',
    this.thumbnailUrl = '',
  });

  /// 来自哪个识图站：SauceNAO / IQDB
  final String engine;

  /// 命中的图库名，如 pixiv / e-hentai / Danbooru
  final String index;

  /// 相似度 0-100
  final double similarity;

  /// 作品名，取不到就是空串
  final String title;

  /// 作者，取不到就是空串
  final String author;

  /// 原始字段（Title / Author / Member / Source …），界面上直接铺出来
  final Map<String, String> fields;

  /// 来源页面链接（pixiv 作品页 / danbooru 帖子 / 画廊页）
  final String sourceUrl;

  final String thumbnailUrl;

  /// 拿去搜索的关键词：优先作品名，其次作者
  ///
  /// 命中的作品多半不在 JM 上，但同名同作者的版本往往有，
  /// 所以两个词都留着，让用户自己挑着搜。
  List<String> get keywords {
    final out = <String>[];
    for (final value in [title, author]) {
      final text = value.trim();
      if (text.isNotEmpty && !out.contains(text)) out.add(text);
    }
    return out;
  }

  /// 去重用：同一个来源页面只留一条
  ///
  /// 不能直接比 URL 字符串 —— 两个站给的地址形式常常不一样，
  /// 比如 danbooru 一个是 `/post/show/12213877`、另一个是 `/posts/12213877`，
  /// 指向的其实是同一个帖子。这里只比「域名 + 最后那个长数字」。
  ///
  /// 没有来源链接的结果（比如 IQDB 有时不给）没法这么比，
  /// 就退回按「站 + 图库 + 作品名」区分。
  String get dedupeKey {
    final host = _hostOf(sourceUrl);
    if (host.isEmpty) return '$engine|$index|$title';
    return '$host|${_idOf(sourceUrl)}';
  }

  static String _hostOf(String url) {
    var text = url.trim().toLowerCase();
    text = text.replaceFirst(RegExp(r'^https?://'), '');
    text = text.replaceFirst(RegExp(r'^www\.'), '');
    return text.split('/').first;
  }

  static String _idOf(String url) {
    final numbers = RegExp(
      r'\d{3,}',
    ).allMatches(url).map((e) => e.group(0)!).toList();
    return numbers.isEmpty ? url.trim().toLowerCase() : numbers.last;
  }

  /// 相似度够不够可信
  bool reliable(double threshold) => similarity >= threshold;
}

/// 一次识图请求的记录
///
/// 用来告诉用户「到底搜了几次、哪次失败了」，比一个转圈的进度条有用。
class ImageSearchAttempt {
  const ImageSearchAttempt({
    required this.engine,
    required this.region,
    this.count = 0,
    this.error = '',
  });

  final String engine;

  /// 搜的是哪一块：整图 / 上段 / 中段 / 下段
  final String region;

  /// 这次拿回来几条
  final int count;

  /// 失败原因，空表示成功
  final String error;

  bool get ok => error.isEmpty;
}

/// 一次识图的完整结果
class ImageSearchReport {
  const ImageSearchReport({
    this.matches = const [],
    this.attempts = const [],
    this.notice = '',
  });

  /// 已按相似度降序排好
  final List<ImageMatch> matches;

  final List<ImageSearchAttempt> attempts;

  /// 整体性的提示，比如被限速了、图片太小认不出
  final String notice;

  double get bestSimilarity => matches.isEmpty ? 0 : matches.first.similarity;

  bool get isEmpty => matches.isEmpty;
}
