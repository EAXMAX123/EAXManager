/// SankakuBlack 源
///
/// 公开接口不需要账号，列表、详情和原图都能直接取。视频只展示和外链，
/// 不下载、不进书架，也不参与内置阅读。
library;

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import '../../net/net_transport.dart';
import '../comic_source.dart';

class SankakuSource implements ComicSource {
  SankakuSource({NetTransport? transport})
    : _transport = transport ?? const NetTransport();

  static const String apiBase = 'https://sankakuapi.com';
  static const String webBase = 'https://sankaku.app';
  static const int pageSize = 30;

  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

  static const Map<String, String> _apiHeaders = {
    'Accept': 'application/vnd.sankaku.api+json;v=2',
    'Client-Type': 'non-premium',
    'Platform': 'web-app',
    'Api-Version': '2',
    'Obfuscate-Type': 'tag,wiki,comment',
    'Enable-New-Tag-Type': 'true',
    'Expiration-Policy': 'reduced',
    'Origin': 'https://sankaku.app',
    'Referer': 'https://sankaku.app/',
    'User-Agent': _userAgent,
  };

  static const Map<String, String> _imageHeaders = {
    'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
    'Referer': 'https://sankaku.app/',
    'User-Agent': _userAgent,
  };

  NetTransport _transport;
  Dio? _dio;

  /// 搜索列表已经带回了详情，打开详情时先查这里，少发一次请求
  final Map<String, Map<String, dynamic>> _cache = {};

  @override
  String get key => 'sankaku';

  @override
  String get name => 'SankakuBlack';

  @override
  String get folder => 'SankakuBlack';

  @override
  bool get needsLogin => false;

  @override
  int? get imageConcurrencyOverride => null;

  @override
  Dio get dio => _dio ??= _buildDio();

  @override
  Map<String, String> get imageHeaders => _imageHeaders;

  final Map<String, String> _resolvedFiles = {};

  @override
  Future<bool> ready() async => true;

  void updateTransport(NetTransport transport) {
    if (transport.signature == _transport.signature) return;
    _transport = transport;
    _dio = null;
    _resolvedFiles.clear();
  }

  Dio _buildDio() {
    final dio = Dio(
      BaseOptions(
        headers: _apiHeaders,
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 30),
        responseType: ResponseType.json,
        validateStatus: (_) => true,
      ),
    );
    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: _transport.createClient,
    );
    return dio;
  }

  // ==================== 搜索 / 详情 ====================

  @override
  Future<ComicSearchPage> search(
    String keyword, {
    SearchMode mode = SearchMode.site,
    int page = 1,
  }) async {
    final posts = await _posts(tags: _tagsOf(keyword), page: page);
    final items = <ComicItem>[];
    for (final post in posts) {
      _remember(post);
      items.add(_toItem(post));
    }
    return ComicSearchPage(
      items: items,
      total: items.isEmpty ? 0 : page * items.length + 1,
      page: page,
    );
  }

  @override
  Future<ComicDetail> detail(String id) async {
    final post = await _postOf(id);
    final tags = _tagsList(post);
    final media = _mediaOf(post);

    final meta = <MapEntry<String, String>>[];
    final width = _intOf(post['width']);
    final height = _intOf(post['height']);
    if (width > 0 && height > 0) {
      meta.add(MapEntry('尺寸', '$width×$height'));
    }
    final score = _intOf(post['total_score']);
    if (score != 0) meta.add(MapEntry('评分', '$score'));
    final favorites = _intOf(post['fav_count']);
    if (favorites > 0) meta.add(MapEntry('收藏', '$favorites'));
    final size = _intOf(post['file_size']);
    if (size > 0) {
      meta.add(MapEntry('大小', '${(size / 1024 / 1024).toStringAsFixed(1)} MB'));
    }
    final rating = _textOf(post['rating']).toUpperCase();
    if (rating.isNotEmpty) meta.add(MapEntry('分级', rating));
    meta.add(MapEntry('类型', _mediaLabel(media)));
    meta.add(MapEntry('作品 ID', id));

    return ComicDetail(
      sid: SourceId(key, id),
      title: _titleOf(post, id),
      author: _artistOf(post),
      description: tags.isEmpty ? '' : tags.join(' · '),
      tags: tags.take(24).toList(),
      coverUrl: _coverOf(post),
      coverHeaders: _imageHeaders,
      chapters: [
        ComicChapter(
          id: id,
          title: media.isVideo ? '视频（原站观看）' : '全一话',
          index: 1,
          order: 1,
        ),
      ],
      meta: meta,
      isFavorite: null,
      mediaKind: media,
      webUrl: '$webBase/posts/$id',
    );
  }

  @override
  Future<ChapterPlan> chapterPlan(
    ComicDetail detail,
    ComicChapter chapter,
  ) async {
    final id = detail.sid.id;
    final post = await _postOf(id);
    final media = _mediaOf(post);
    if (media.isVideo) {
      throw const SourceException('视频内容暂不支持下载，请在详情页打开原站观看');
    }

    final url = await _resolveFile(id, post);
    if (url.isEmpty) {
      throw const SourceException('没有取到 SankakuBlack 的原图地址，可能作品已删除');
    }

    return ChapterPlan(
      mediaKind: media,
      images: [
        ChapterImage(
          url: url,
          fileName: _fileNameOf(url, id, post),
          headers: _imageHeaders,
        ),
      ],
    );
  }

  @override
  Future<bool?> setFavorite(String id, {required bool want}) async => null;

  @override
  List<RankOption> get rankTimes => const [];

  @override
  List<RankOption> rankCategories(String time) => const [];

  @override
  Future<ComicSearchPage> rank({
    required String time,
    String category = '',
    int page = 1,
  }) async {
    throw SourceException('$name 暂时没有排行榜');
  }

  // ==================== 接口 ====================

  Future<List<Map<String, dynamic>>> _posts({
    required String tags,
    required int page,
  }) async {
    final response = await dio.get<dynamic>(
      '$apiBase/v2/posts',
      queryParameters: {'tags': tags, 'limit': '$pageSize', 'page': '$page'},
    );

    final data = response.data;
    if (data is List) {
      return [
        for (final item in data)
          if (item is Map) Map<String, dynamic>.from(item),
      ];
    }
    if (data is Map) {
      final nested = data['data'];
      if (nested is List) {
        return [
          for (final item in nested)
            if (item is Map) Map<String, dynamic>.from(item),
        ];
      }
      final message = _textOf(data['message'] ?? data['error']);
      if (message.isNotEmpty) {
        throw SourceException('SankakuBlack 返回错误：$message');
      }
    }

    _throwForStatus(response.statusCode);
    if (data is String && data.trim().isNotEmpty) {
      throw SourceException('SankakuBlack 返回了意外内容：${_short(data)}');
    }
    return const [];
  }

  Future<Map<String, dynamic>> _postOf(String id) async {
    final cached = _cache[id];
    if (cached != null) return cached;

    final posts = await _posts(tags: 'id:$id', page: 1);
    if (posts.isEmpty) {
      throw const SourceException('SankakuBlack 没取到这条作品，可能已删除或网络不通');
    }
    _remember(posts.first);
    return posts.first;
  }

  /// `/fu` 返回的是带时效签名的原图地址，列表接口里通常没有
  Future<String> _resolveFile(String id, Map<String, dynamic> post) async {
    final cached = _resolvedFiles[id];
    if (cached != null && cached.isNotEmpty) return cached;

    final response = await dio.get<dynamic>(
      '$apiBase/posts/$id/fu',
      options: Options(headers: _apiHeaders),
    );
    final data = response.data;
    if (data is Map) {
      final nested = data['data'];
      if (nested is Map) {
        for (final key in const ['file_url', 'fallback_url', 'sample_url']) {
          final url = _absoluteUrl(_textOf(nested[key]));
          if (url.isNotEmpty) {
            _resolvedFiles[id] = url;
            return url;
          }
        }
      }
    }

    for (final key in const ['file_url', 'sample_url', 'preview_url']) {
      final url = _absoluteUrl(_textOf(post[key]));
      if (url.isNotEmpty) {
        _resolvedFiles[id] = url;
        return url;
      }
    }
    _throwForStatus(response.statusCode);
    return '';
  }

  void _throwForStatus(int? status) {
    final code = status ?? 0;
    if (code == 401 || code == 403) {
      throw const SourceException('SankakuBlack 拒绝了请求，可能需要挂梯子后重试');
    }
    if (code == 429) {
      throw const SourceException('SankakuBlack 请求太频繁，等一会儿再搜');
    }
    if (code >= 400) {
      throw SourceException('SankakuBlack 连不上（HTTP $code），可以挂梯子再试');
    }
  }

  // ==================== 解析 ====================

  void _remember(Map<String, dynamic> post) {
    final id = _textOf(post['id']);
    if (id.isEmpty) return;
    if (_cache.length >= 40) _cache.remove(_cache.keys.first);
    _cache[id] = post;
  }

  ComicItem _toItem(Map<String, dynamic> post) {
    final id = _textOf(post['id']);
    final media = _mediaOf(post);
    final author = _artistOf(post);
    final ext = _textOf(post['file_ext']).toUpperCase();

    return ComicItem(
      sid: SourceId(key, id),
      title: _titleOf(post, id),
      author: author,
      coverUrl: _coverOf(post),
      coverHeaders: _imageHeaders,
      subtitle: [
        if (author.isNotEmpty) author,
        if (ext.isNotEmpty) ext,
        if (media.isVideo) '视频',
      ].join(' · '),
      mediaKind: media,
    );
  }

  ComicMediaKind _mediaOf(Map<String, dynamic> post) {
    final type = _textOf(post['file_type']).toLowerCase();
    final ext = _textOf(post['file_ext']).toLowerCase();
    final duration = _textOf(post['video_duration']);
    if (type.startsWith('video/') ||
        duration.isNotEmpty ||
        const {'mp4', 'webm', 'mov', 'mkv', 'm4v'}.contains(ext)) {
      return ComicMediaKind.video;
    }
    if (type == 'image/gif' || ext == 'gif') return ComicMediaKind.gif;
    return ComicMediaKind.image;
  }

  String _mediaLabel(ComicMediaKind kind) => switch (kind) {
    ComicMediaKind.video => '视频',
    ComicMediaKind.gif => '动图',
    ComicMediaKind.image => '图片',
  };

  String _coverOf(Map<String, dynamic> post) {
    for (final key in const ['preview_url', 'sample_url', 'file_url']) {
      final url = _absoluteUrl(_textOf(post[key]));
      if (url.isNotEmpty) return url;
    }
    return '';
  }

  List<String> _tagsList(Map<String, dynamic> post) {
    final out = <String>[];

    void add(String tag) {
      final value = tag.trim();
      if (value.isEmpty || out.contains(value)) return;
      out.add(value);
    }

    final names = post['tag_names'];
    if (names is List) {
      for (final name in names) {
        add(_textOf(name));
      }
    }

    if (out.isEmpty) {
      final tags = post['tags'];
      if (tags is List) {
        for (final tag in tags) {
          if (tag is! Map) continue;
          add(
            _textOf(
              tag['name_en'] ?? tag['name'] ?? tag['tagName'] ?? tag['name_ja'],
            ),
          );
        }
      }
    }
    return out;
  }

  static const Set<String> _metaTags = {
    '1girl',
    '1boy',
    '2girls',
    '3girls',
    'solo',
    'female',
    'male',
    'multiple_girls',
    'multiple_boys',
    'highres',
    'lowres',
    'absurdres',
    'commentary',
    'english_commentary',
    'translated',
    'uncensored',
    'censored',
    'animated',
    'video',
    'sound',
    'webm',
    'mp4',
    'gif',
    'ai_generated',
    'bad_source',
    'multiple_views',
    'paid_reward',
    'patreon_reward',
    'high_resolution',
    'large_filesize',
    'very_high_resolution',
  };

  String _titleOf(Map<String, dynamic> post, String id) {
    final tags = _tagsList(post);
    final picked = <String>[];
    for (final tag in tags) {
      final bare = tag.split(':').last.toLowerCase();
      if (_metaTags.contains(bare)) continue;
      final text = tag.replaceAll('_', ' ').trim();
      if (text.isEmpty || picked.contains(text)) continue;
      picked.add(text);
      if (picked.length >= 4) break;
    }
    if (picked.isEmpty) return 'SankakuBlack #$id';
    return picked.join(' / ');
  }

  String _artistOf(Map<String, dynamic> post) {
    final author = post['author'];
    if (author is! Map) return '';
    final display = _textOf(author['display_name']);
    return display.isNotEmpty ? display : _textOf(author['name']);
  }

  String _fileNameOf(String url, String id, Map<String, dynamic> post) {
    final path = Uri.tryParse(url)?.path ?? '';
    final name = path.split('/').last.trim();
    if (name.isNotEmpty && name.contains('.')) return name;
    final ext = _textOf(post['file_ext']);
    return ext.isEmpty ? '$id.jpg' : '$id.$ext';
  }

  static String _tagsOf(String keyword) {
    final raw = keyword.trim().replaceAll('，', ',').replaceAll('、', ',');
    if (raw.isEmpty) return '';
    if (raw.contains(',')) {
      return raw
          .split(',')
          .map((e) => e.trim().replaceAll(RegExp(r'\s+'), '_'))
          .where((e) => e.isNotEmpty)
          .join(' ');
    }
    return raw.replaceAll(RegExp(r'\s+'), '_');
  }

  static String _absoluteUrl(String url) {
    if (url.startsWith('//')) return 'https:$url';
    return url;
  }

  static int _intOf(dynamic value) => int.tryParse('$value') ?? 0;

  static String _textOf(dynamic value) {
    final text = '${value ?? ''}'.trim();
    return text == 'null' ? '' : text;
  }

  static String _short(String text) =>
      text.length <= 120 ? text : '${text.substring(0, 120)}…';
}
