/// Rule34 源
///
/// 两种取数据方式：
/// - 设置里填了 API Key：走官方 DAPI，速度快、字段全；
/// - 没填 Key：走网页版，免登录、免申请，代价是列表只能拿到缩略图，
///   点进详情时再补一次原图和标签。
///
/// 视频内容照常显示在搜索结果里，但只提供原站链接：不下载、不进书架、
/// 不参与内置阅读。
library;

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import '../../net/net_transport.dart';
import '../comic_source.dart';
import 'r34_web_parse.dart';

class R34Source implements ComicSource {
  R34Source({NetTransport? transport, this.apiKey = ''})
    : _transport = transport ?? const NetTransport();

  static const String apiBase = 'https://api.rule34.xxx/index.php';
  static const String webBase = 'https://rule34.xxx/index.php';

  /// 网页版候选域名，第一个连不上就试下一个
  static const List<String> webBases = [
    'https://rule34.xxx/index.php',
    'https://rule34.us/index.php',
  ];

  static const int pageSize = 30;

  static const Map<String, String> _imageHeaders = {
    'Referer': 'https://rule34.xxx/',
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
    'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
  };

  NetTransport _transport;
  String apiKey;
  Dio? _dio;

  /// 详情大多从搜索结果直接带过来，省一次接口请求
  final Map<String, Map<String, dynamic>> _cache = {};

  @override
  String get key => 'r34';

  @override
  String get name => 'Rule34';

  @override
  String get folder => 'Rule34';

  @override
  bool get needsLogin => false;

  @override
  int? get imageConcurrencyOverride => null;

  @override
  Dio get dio => _dio ??= _buildDio();

  @override
  Map<String, String> get imageHeaders => _imageHeaders;

  @override
  Future<bool> ready() async => true;

  void updateTransport(NetTransport transport) {
    if (transport.signature == _transport.signature) return;
    _transport = transport;
    _dio = null;
  }

  void configure({String? apiKey}) {
    if (apiKey != null) this.apiKey = apiKey;
  }

  Dio _buildDio() {
    final dio = Dio(
      BaseOptions(
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
    final posts = await _posts({'tags': _tagsOf(keyword), 'page': '$page'});

    final items = <ComicItem>[];
    for (final post in posts) {
      _remember(post);
      items.add(_toItem(post));
    }
    return ComicSearchPage(
      items: items,
      // 接口和网页都不返回总数，拿到内容就允许继续翻
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
    final score = _intOf(post['score']);
    if (score != 0) meta.add(MapEntry('评分', '$score'));
    final rating = _textOf(post['rating']).toUpperCase();
    if (rating.isNotEmpty) meta.add(MapEntry('分级', rating));
    meta.add(MapEntry('类型', _mediaLabel(media)));
    meta.add(MapEntry('作品 ID', id));

    final author = _artistOf(tags);

    return ComicDetail(
      sid: SourceId(key, id),
      title: _titleOf(tags, id),
      author: author,
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
      webUrl: '$webBase?page=post&s=view&id=$id',
    );
  }

  @override
  Future<ChapterPlan> chapterPlan(
    ComicDetail detail,
    ComicChapter chapter,
  ) async {
    final post = await _postOf(detail.sid.id);
    final media = _mediaOf(post);
    if (media.isVideo) {
      throw const SourceException('视频内容暂不支持下载，请在详情页打开原站观看');
    }

    final url = _fileOf(post);
    if (url.isEmpty) {
      throw const SourceException('没有取到 Rule34 的原图地址，可能作品已删除或网页版改版了');
    }

    return ChapterPlan(
      mediaKind: media,
      images: [
        ChapterImage(
          url: url,
          fileName: _fileNameOf(url, detail.sid.id, post),
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

  Future<Map<String, dynamic>> _postOf(String id) async {
    final cached = _cache[id];
    if (cached != null && cached['_webPartial'] != true) return cached;

    // DAPI 的 id 参数最直接；个别镜像不认就退回 id: 标签
    var posts = await _posts({'id': id, 'limit': '1'});
    if (posts.isEmpty) {
      posts = await _posts({'tags': 'id:$id', 'limit': '1'});
    }
    if (posts.isEmpty) {
      throw const SourceException('Rule34 没取到这条作品：请检查网络或梯子');
    }
    _remember(posts.first);
    return posts.first;
  }

  Future<List<Map<String, dynamic>>> _posts(Map<String, String> params) async {
    final key = apiKey.trim();
    if (key.isEmpty) return _webPosts(params);
    return _dapiPosts(params, key);
  }

  Future<List<Map<String, dynamic>>> _dapiPosts(
    Map<String, String> params,
    String key,
  ) async {
    final page = int.tryParse(params['page'] ?? '1') ?? 1;
    final id = params['id'];
    final tags = params['tags'] ?? '';

    final response = await dio.get<dynamic>(
      apiBase,
      queryParameters: {
        'page': 'dapi',
        's': 'post',
        'q': 'index',
        'json': '1',
        'api_key': key,
        if (id != null && id.isNotEmpty) 'id': id,
        if (id == null || id.isEmpty) 'tags': tags,
        'limit': params['limit'] ?? '$pageSize',
        if (id == null || id.isEmpty) 'pid': '${page - 1}',
      },
    );

    final data = response.data;
    if (data is List) {
      return [
        for (final item in data)
          if (item is Map) Map<String, dynamic>.from(item),
      ];
    }
    if (data is Map) {
      final posts = data['post'];
      if (posts is List) {
        return [
          for (final item in posts)
            if (item is Map) Map<String, dynamic>.from(item),
        ];
      }
    }
    if (data is String) {
      if (data.toLowerCase().contains('authentication')) {
        throw const SourceException(
          'Rule34 API Key 无效：请到 api.rule34.xxx 重新申请，'
          '再填到「设置 → Rule34」',
        );
      }
      throw SourceException('Rule34 返回了意外内容：${_short(data)}');
    }
    if ((response.statusCode ?? 0) >= 400) {
      throw SourceException('Rule34 连不上（HTTP ${response.statusCode}），可能需要挂梯子');
    }
    return const [];
  }

  // ==================== 网页版 ====================

  Future<List<Map<String, dynamic>>> _webPosts(
    Map<String, String> params,
  ) async {
    final id = params['id']?.trim() ?? '';
    if (id.isNotEmpty) {
      return [await _webDetail(id)];
    }

    final page = int.tryParse(params['page'] ?? '1') ?? 1;
    final pid = (page - 1) * r34WebPageSize;
    final body = await _webGet({
      'page': 'post',
      's': 'list',
      'tags': params['tags'] ?? '',
      'pid': '$pid',
    });
    return parseR34WebList(body);
  }

  Future<Map<String, dynamic>> _webDetail(String id) async {
    final body = await _webGet({'page': 'post', 's': 'view', 'id': id});
    if (isR34MissingPost(body)) {
      throw const SourceException('这条 Rule34 作品已经删掉了');
    }
    return parseR34WebDetail(body, id);
  }

  Future<String> _webGet(Map<String, String> query) async {
    Object? lastError;
    for (final base in webBases) {
      final uri = Uri.parse(base).replace(queryParameters: query);
      try {
        final response = await dio.get<String>(
          uri.toString(),
          options: Options(
            responseType: ResponseType.plain,
            headers: const {
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
                  'AppleWebKit/537.36 (KHTML, like Gecko) '
                  'Chrome/124.0.0.0 Safari/537.36',
              'Accept':
                  'text/html,application/xhtml+xml,application/xml;q=0.9,'
                  'image/avif,image/webp,*/*;q=0.8',
              'Accept-Language': 'en-US,en;q=0.9',
              'Referer': 'https://rule34.xxx/',
            },
          ),
        );
        final body = response.data ?? '';
        final status = response.statusCode ?? 0;
        if (status >= 400 || body.trim().isEmpty) {
          lastError = SourceException('Rule34 网页版连不上（HTTP $status）');
          continue;
        }
        if (isR34ChallengePage(body)) {
          lastError = const SourceException(
            'Rule34 网页版被 Cloudflare 验证拦住了：挂梯子再试，'
            '或到「设置 → Rule34」填一个免费 API Key',
          );
          continue;
        }
        return body;
      } on DioException catch (e) {
        lastError = e;
      } catch (e) {
        lastError = e;
      }
    }

    if (lastError is SourceException) throw lastError;
    throw const SourceException(
      'Rule34 连不上：这个站在国内多数网络需要挂梯子；'
      '也可以到「设置 → Rule34」填免费 API Key 换一条路',
    );
  }

  // ==================== 解析 ====================

  void _remember(Map<String, dynamic> post) {
    final id = _textOf(post['id']);
    if (id.isNotEmpty) _cache[id] = post;
  }

  ComicItem _toItem(Map<String, dynamic> post) {
    final id = _textOf(post['id']);
    final tags = _tagsList(post);
    final media = _mediaOf(post);
    final author = _artistOf(tags);
    final ext = _textOf(post['file_ext']).toUpperCase();

    return ComicItem(
      sid: SourceId(key, id),
      title: _titleOf(tags, id),
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
    if (type.startsWith('video/') ||
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

  String _fileOf(Map<String, dynamic> post) {
    for (final key in const ['file_url', 'sample_url', 'preview_url']) {
      final url = _absoluteUrl(_textOf(post[key]));
      if (url.isNotEmpty) return url;
    }
    return '';
  }

  List<String> _tagsList(Map<String, dynamic> post) {
    final raw = post['tags'];
    if (raw is List) {
      return [
        for (final tag in raw)
          if (_textOf(tag).isNotEmpty) _textOf(tag),
      ];
    }
    final text = _textOf(raw);
    if (text.isEmpty) return const [];
    return text.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
  }

  static const Set<String> _metaTags = {
    '1girl',
    '1boy',
    '2girls',
    '3girls',
    'solo',
    'multiple_girls',
    'multiple_boys',
    'absurdres',
    'highres',
    'lowres',
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
  };

  String _titleOf(List<String> tags, String id) {
    final picked = <String>[];
    for (final tag in tags) {
      final bare = tag.split(':').last;
      if (_metaTags.contains(bare.toLowerCase())) continue;
      final text = tag.replaceAll('_', ' ').trim();
      if (text.isEmpty || picked.contains(text)) continue;
      picked.add(text);
      if (picked.length >= 4) break;
    }
    if (picked.isEmpty) return 'Rule34 #$id';
    return picked.join(' / ');
  }

  String _artistOf(List<String> tags) {
    for (final tag in tags) {
      if (tag.toLowerCase().startsWith('artist:')) {
        return tag.substring(tag.indexOf(':') + 1).replaceAll('_', ' ');
      }
    }
    return '';
  }

  String _fileNameOf(String url, String id, Map<String, dynamic> post) {
    final path = Uri.tryParse(url)?.path ?? '';
    final name = path.split('/').last.trim();
    if (name.isNotEmpty && name.contains('.')) return name;
    final ext = _textOf(post['file_ext']);
    return ext.isEmpty ? '$id.jpg' : '$id.$ext';
  }

  static String _tagsOf(String keyword) =>
      keyword.trim().replaceAll(RegExp(r'\s+'), '_').replaceAll('，', ',');

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
