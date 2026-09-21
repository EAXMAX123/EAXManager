/// JM 源：把现有的 JmClient 包装成统一的 ComicSource
library;

import '../jm/jm_client.dart';
import '../jm/jm_constants.dart';
import '../jm/jm_models.dart';
import 'comic_source.dart';

import 'package:dio/dio.dart';

class JmSource implements ComicSource {
  JmSource(this.client);

  final JmClient client;

  @override
  String get key => 'jm';

  @override
  String get name => 'JM';

  @override
  String get folder => 'JM';

  @override
  bool get needsLogin => false;

  @override
  Dio get dio => client.dio;

  @override
  Map<String, String> get imageHeaders => client.imageHeaders;

  /// 用设置里的全局并发
  @override
  int? get imageConcurrencyOverride => null;

  @override
  Future<bool> ready() async => true;

  @override
  Future<ComicSearchPage> search(
    String keyword, {
    SearchMode mode = SearchMode.site,
    int page = 1,
  }) async {
    final result = await client.search(keyword, page: page, mode: mode.key);
    return ComicSearchPage(
      items: toItems(result.items),
      total: result.total,
      page: page,
    );
  }

  /// JM 列表项 -> 统一模型（排行 / 推荐页也复用这个）
  ComicItem toItem(JmSearchItem item) => ComicItem(
    sid: SourceId(key, item.id),
    title: item.name,
    author: item.author,
    coverUrl: client.coverUrl(item.id),
    subtitle: [
      item.author,
      item.category,
    ].where((e) => e.trim().isNotEmpty).join(' · '),
  );

  List<ComicItem> toItems(Iterable<JmSearchItem> items) =>
      items.map(toItem).toList();

  @override
  Future<ComicDetail> detail(String id) async {
    final album = await client.albumDetail(id);
    final sorted = album.sortedSeries;

    final chapters = <ComicChapter>[];
    for (var i = 0; i < sorted.length; i++) {
      chapters.add(
        ComicChapter(
          id: sorted[i].id,
          title: sorted[i].name,
          index: i + 1,
          order: sorted[i].sort,
        ),
      );
    }

    final meta = <MapEntry<String, String>>[];
    void addMeta(String k, String v) {
      if (v.trim().isNotEmpty) meta.add(MapEntry(k, v));
    }

    addMeta('观看', '${album.views}');
    addMeta('点赞', '${album.likes}');
    addMeta('页数', '${album.totalPhotos}');
    addMeta('更新', album.pubDate);

    return ComicDetail(
      sid: SourceId(key, id),
      title: album.name,
      author: album.authors.join('、'),
      description: album.description,
      tags: [...album.tags, ...album.works, ...album.actors],
      coverUrl: client.coverUrl(id),
      chapters: chapters,
      meta: meta,
      isFavorite: album.isFavorite,
    );
  }

  @override
  Future<ChapterPlan> chapterPlan(
    ComicDetail detail,
    ComicChapter chapter,
  ) async {
    final photo = await client.photoDetail(chapter.id);
    final scrambleId = await client.fetchScrambleId(photo.id);

    ChapterImage build(int index) {
      final name = photo.images[index];
      return ChapterImage(
        url: client.imageUrl(photo.id, name),
        fileName: name,
        headers: client.imageHeaders,
      );
    }

    if (photo.images.isEmpty) {
      throw const SourceException('这一章没取到图片，可能是本子已下架');
    }

    return ChapterPlan(
      images: [for (var i = 0; i < photo.images.length; i++) build(i)],
      scrambleId: scrambleId,
      scrambleAid: photo.id,
      // 图片 CDN 被重置时换节点重拼地址
      refresh: (index) {
        client.rotateImageDomain();
        return build(index);
      },
    );
  }

  @override
  Future<bool?> setFavorite(String id, {required bool want}) async {
    await client.setFavorite(id, want: want);
    return want;
  }

  // ==================== 排行榜 ====================

  /// JM 只有 今日 / 本周 / 本月 / 全部时间 四档，没有年榜
  static const List<RankOption> _rankTimes = [
    RankOption('day', '今日'),
    RankOption('week', '本周'),
    RankOption('month', '本月'),
    RankOption('all', '全部时间'),
  ];

  /// 分类档：key 和 [jmCategoryMap] 对齐，界面只管显示 label
  static const List<RankOption> _rankCategories = [
    RankOption('all', '全部'),
    RankOption('doujin', '同人'),
    RankOption('single', '单本'),
    RankOption('short', '短篇'),
    RankOption('hanman', '韩漫'),
    RankOption('meiman', '美漫'),
    RankOption('3d', '3D'),
    RankOption('cosplay', 'Cosplay'),
    RankOption('another', '其他'),
  ];

  @override
  List<RankOption> get rankTimes => _rankTimes;

  @override
  List<RankOption> rankCategories(String time) => _rankCategories;

  /// JM 的排行榜 = 按「观看量」排序的分类列表接口
  @override
  Future<ComicSearchPage> rank({
    required String time,
    String category = '',
    int page = 1,
  }) async {
    final result = await client.categoriesFilter(
      page: page,
      category: jmCategoryMap[category] ?? JmMagic.categoryAll,
      orderBy: JmMagic.orderView,
      time: jmTimeMap[time] ?? JmMagic.timeWeek,
    );
    return ComicSearchPage(
      items: toItems(result.items),
      total: result.total,
      page: page,
    );
  }
}
