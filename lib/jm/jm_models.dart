/// JM 数据模型：与 jmcomic 实体对应，字段命名贴近接口返回值
library;

import 'jm_constants.dart';

/// 搜索结果 / 列表项
class JmSearchItem {
  const JmSearchItem({
    required this.id,
    required this.name,
    this.author = '',
    this.description = '',
    this.category = '',
    this.categorySub = '',
  });

  final String id;
  final String name;
  final String author;
  final String description;
  final String category;
  final String categorySub;

  factory JmSearchItem.fromJson(Map<String, dynamic> json) {
    String titleOf(dynamic v) {
      if (v is Map && v['title'] != null) return v['title'].toString();
      return '';
    }

    return JmSearchItem(
      id: '${json['id'] ?? ''}',
      name: (json['name'] ?? '').toString().trim(),
      author: (json['author'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      category: titleOf(json['category']),
      categorySub: titleOf(json['category_sub']),
    );
  }
}

/// 搜索/分类分页结果
class JmSearchPage {
  const JmSearchPage({
    required this.items,
    required this.total,
    required this.page,
    this.searchQuery = '',
  });

  final List<JmSearchItem> items;
  final int total;
  final int page;
  final String searchQuery;

  bool get hasMore => page * items.length < total;

  factory JmSearchPage.fromJson(Map<String, dynamic> json, int page) {
    final raw = json['content'];
    final items = <JmSearchItem>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map<String, dynamic>) items.add(JmSearchItem.fromJson(e));
      }
    }
    return JmSearchPage(
      items: items,
      total: int.tryParse('${json['total'] ?? 0}') ?? 0,
      page: page,
      searchQuery: (json['search_query'] ?? '').toString(),
    );
  }
}

/// 章节条目
class JmSeriesItem {
  const JmSeriesItem({
    required this.id,
    required this.name,
    required this.sort,
  });

  final String id;
  final String name;
  final int sort;

  factory JmSeriesItem.fromJson(Map<String, dynamic> json) => JmSeriesItem(
    id: '${json['id'] ?? ''}',
    name: (json['name'] ?? '').toString().trim(),
    sort: int.tryParse('${json['sort'] ?? 1}') ?? 1,
  );
}

/// 本子详情（API /album）
class JmAlbum {
  const JmAlbum({
    required this.id,
    required this.name,
    this.authors = const [],
    this.tags = const [],
    this.works = const [],
    this.actors = const [],
    this.description = '',
    this.views = 0,
    this.likes = 0,
    this.commentCount = 0,
    this.totalPhotos = 0,
    this.pubDate = '',
    this.series = const [],
    this.isFavorite = false,
    this.liked = false,
    this.related = const [],
  });

  final String id;
  final String name;
  final List<String> authors;
  final List<String> tags;
  final List<String> works;
  final List<String> actors;
  final String description;
  final int views;
  final int likes;
  final int commentCount;
  final int totalPhotos;
  final String pubDate;
  final List<JmSeriesItem> series;
  final bool isFavorite;
  final bool liked;
  final List<JmSearchItem> related;

  String get authorText => authors.isEmpty ? '未知作者' : authors.join('、');

  /// 章节按 sort 升序排列
  List<JmSeriesItem> get sortedSeries {
    final list = [...series];
    list.sort((a, b) => a.sort.compareTo(b.sort));
    return list;
  }

  factory JmAlbum.fromJson(Map<String, dynamic> json) {
    List<String> strList(dynamic v) {
      if (v is List) return v.map((e) => e.toString()).toList();
      if (v is String && v.trim().isNotEmpty) {
        return v.trim().split(RegExp(r'\s+'));
      }
      return const [];
    }

    final series = <JmSeriesItem>[];
    final rawSeries = json['series'];
    if (rawSeries is List) {
      for (final e in rawSeries) {
        if (e is Map<String, dynamic>) series.add(JmSeriesItem.fromJson(e));
      }
    }

    final related = <JmSearchItem>[];
    final rawRelated = json['related_list'];
    if (rawRelated is List) {
      for (final e in rawRelated) {
        if (e is Map<String, dynamic>) related.add(JmSearchItem.fromJson(e));
      }
    }

    var pubDate = '';
    final addtime = int.tryParse('${json['addtime'] ?? ''}');
    if (addtime != null && addtime > 0) {
      final dt = DateTime.fromMillisecondsSinceEpoch(addtime * 1000);
      pubDate =
          '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    }

    return JmAlbum(
      id: '${json['id'] ?? ''}',
      name: (json['name'] ?? '').toString().trim(),
      authors: strList(json['author']),
      tags: strList(json['tags']),
      works: strList(json['works']),
      actors: strList(json['actors']),
      description: (json['description'] ?? '').toString(),
      views: int.tryParse('${json['total_views'] ?? 0}') ?? 0,
      likes: int.tryParse('${json['likes'] ?? 0}') ?? 0,
      commentCount: int.tryParse('${json['comment_total'] ?? 0}') ?? 0,
      totalPhotos: int.tryParse('${json['total_photos'] ?? 0}') ?? 0,
      pubDate: pubDate,
      series: series,
      isFavorite: json['is_favorite'] == true,
      liked: json['liked'] == true,
      related: related,
    );
  }
}

/// 章节详情（API /chapter）
class JmPhoto {
  const JmPhoto({
    required this.id,
    required this.name,
    this.albumId = '',
    this.sort = 1,
    this.seriesId = '0',
    this.tags = const [],
    this.images = const [],
    this.scrambleId = '${JmMagic.scramble220980}',
    this.isFavorite = false,
  });

  final String id;
  final String name;
  final String albumId;
  final int sort;
  final String seriesId;
  final List<String> tags;

  /// 图片文件名列表，如 ["00001.webp", "00002.webp"]
  final List<String> images;

  /// 图片乱序还原所需的分界值
  final String scrambleId;
  final bool isFavorite;

  int get pageCount => images.length;

  factory JmPhoto.fromJson(Map<String, dynamic> json) {
    final tagsRaw = json['tags'];
    final tags = <String>[];
    if (tagsRaw is List) {
      tags.addAll(tagsRaw.map((e) => e.toString()));
    } else if (tagsRaw is String && tagsRaw.trim().isNotEmpty) {
      tags.addAll(tagsRaw.trim().split(RegExp(r'\s+')));
    }

    final images = <String>[];
    final rawImages = json['images'];
    if (rawImages is List) images.addAll(rawImages.map((e) => e.toString()));

    var sort = 1;
    final rawSeries = json['series'];
    if (rawSeries is List) {
      for (final e in rawSeries) {
        if (e is Map && '${e['id']}' == '${json['id']}') {
          sort = int.tryParse('${e['sort'] ?? 1}') ?? 1;
          break;
        }
      }
    }

    return JmPhoto(
      id: '${json['id'] ?? ''}',
      name: (json['name'] ?? '').toString().trim(),
      albumId: '${json['series_id'] ?? ''}',
      sort: sort,
      seriesId: '${json['series_id'] ?? '0'}',
      tags: tags,
      images: images,
      isFavorite: json['is_favorite'] == true,
    );
  }

  JmPhoto copyWith({String? scrambleId, List<String>? images}) => JmPhoto(
    id: id,
    name: name,
    albumId: albumId,
    sort: sort,
    seriesId: seriesId,
    tags: tags,
    images: images ?? this.images,
    scrambleId: scrambleId ?? this.scrambleId,
    isFavorite: isFavorite,
  );
}

/// 单张图片的下载信息
class JmImageDetail {
  const JmImageDetail({
    required this.aid,
    required this.index,
    required this.fileName,
    required this.suffix,
    required this.url,
    required this.scrambleId,
  });

  final String aid;
  final int index; // 从 1 开始
  final String fileName; // 不含后缀
  final String suffix; // 含点，如 ".webp"
  final String url;
  final String scrambleId;

  String get fullName => '$fileName$suffix';
}

/// 收藏夹
class JmFavoriteFolder {
  const JmFavoriteFolder({required this.id, required this.name});

  final String id;
  final String name;

  factory JmFavoriteFolder.fromJson(Map<String, dynamic> json) =>
      JmFavoriteFolder(
        id: '${json['FID'] ?? json['id'] ?? ''}',
        name: (json['name'] ?? '').toString(),
      );
}

/// 收藏夹分页（API GET /favorite）
///
/// 返回结构：
/// {
///   "list": [{ "id": "363859", "name": "...", "author": "...", ... }],
///   "folder_list": [{ "FID": "0", "name": "全部收藏" }],
///   "total": "87",
///   "count": 20
/// }
class JmFavoritePage {
  const JmFavoritePage({
    required this.items,
    required this.folders,
    required this.total,
    required this.page,
  });

  final List<JmSearchItem> items;
  final List<JmFavoriteFolder> folders;
  final int total;
  final int page;

  factory JmFavoritePage.fromJson(Map<String, dynamic> json, int page) {
    final items = <JmSearchItem>[];
    final rawList = json['list'];
    if (rawList is List) {
      for (final e in rawList) {
        if (e is Map<String, dynamic>) items.add(JmSearchItem.fromJson(e));
      }
    }

    final folders = <JmFavoriteFolder>[];
    final rawFolders = json['folder_list'];
    if (rawFolders is List) {
      for (final e in rawFolders) {
        if (e is Map<String, dynamic>) {
          folders.add(JmFavoriteFolder.fromJson(e));
        }
      }
    }

    return JmFavoritePage(
      items: items,
      folders: folders,
      total: int.tryParse('${json['total'] ?? 0}') ?? 0,
      page: page,
    );
  }
}
