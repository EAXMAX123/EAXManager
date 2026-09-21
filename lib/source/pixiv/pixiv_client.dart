/// Pixiv 客户端
///
/// Pixiv 官方接口和图片站（i.pximg.net）在国内都连不上，所以这里全部走第三方：
/// 数据接口用 HibiAPI 协议的公共镜像，图片把 i.pximg.net 换成公共反代域名。
///
/// 这两样都不是官方服务，随时可能挂，所以各自配了一串备用地址，
/// 一个不通就自动换下一个；用户也能在设置里自己填。
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import '../../net/net_error.dart';
import '../../net/net_transport.dart';
import '../comic_source.dart';

class PixivConst {
  PixivConst._();

  /// 数据接口镜像（实测国内直连可用）
  static const List<String> defaultApiBases = [
    'https://api.cocomi.eu.org',
    'https://hibiapi.cocomi.eu.org',
  ];

  /// 图片反代：把 i.pximg.net 换成这些域名就能直连（全部实测可用）
  static const List<String> defaultImageProxies = [
    'i.pixiv.re',
    'i.pixiv.nl',
    'i.loli.best',
    'img.rika.club',
    'piv.cosine.ren',
    'pximg.perennialte.ch',
    'p.nsso.eu.org',
    'pixiv-img.0068023.xyz',
    'web.pximg.cc',
    'now.pixivs.cn',
  ];

  /// 镜像和反代都要求带一个像浏览器的 UA，不带会被当成机器人直接挡掉
  static const String userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

  static const String referer = 'https://www.pixiv.net/';

  /// 界面的搜索模式 -> 接口的 search_target
  ///
  /// 作者模式实际走的是「先搜画师再列作品」（见 PixivSource），
  /// 这里也给它留一条，是为了这张表始终是全的——少一条的话，
  /// 以后谁改了分支逻辑就会静默退回综合，很难查。
  static const Map<String, String> searchTargets = {
    'site': 'partial_match_for_tags',
    'work': 'title_and_caption',
    'author': 'partial_match_for_tags',
    'tag': 'exact_match_for_tags',
    'actor': 'partial_match_for_tags',
  };

  /// 把设置里填的一串地址拆成列表，空格 / 逗号 / 分号 / 换行都能当分隔符
  static List<String> parseList(String raw) {
    final out = <String>[];
    for (final part in raw.split(RegExp(r'[\s,;]+'))) {
      final item = part.trim();
      if (item.isEmpty || out.contains(item)) continue;
      out.add(item);
    }
    return out;
  }
}

class PixivClient {
  PixivClient({
    NetTransport? transport,
    List<String>? apiBases,
    List<String>? imageProxies,
  }) : transport = transport ?? const NetTransport(),
       apiBases = _orDefault(apiBases, PixivConst.defaultApiBases),
       imageProxies = _orDefault(imageProxies, PixivConst.defaultImageProxies);

  /// 网络配置：代理、绕过 DNS 污染
  NetTransport transport;

  /// 数据接口镜像，按实测速度排序
  List<String> apiBases;

  /// 图片反代域名
  List<String> imageProxies;

  int _baseIndex = 0;
  int _proxyIndex = 0;

  Dio? _dio;

  Dio get dio => _dio ??= _buildDio();

  /// 去掉空项和重复项；一个都没有就用内置的
  static List<String> _orDefault(List<String>? value, List<String> fallback) {
    final cleaned = <String>[];
    for (final raw in value ?? const <String>[]) {
      final item = raw.trim();
      if (item.isEmpty || cleaned.contains(item)) continue;
      cleaned.add(item);
    }
    return cleaned.isEmpty ? fallback : cleaned;
  }

  /// 镜像地址做点清理：补上 https://，去掉结尾斜杠
  static List<String> cleanBases(List<String> value) {
    final out = <String>[];
    for (var raw in value) {
      var item = raw.trim();
      if (item.isEmpty) continue;
      if (!item.startsWith('http')) item = 'https://$item';
      while (item.endsWith('/')) {
        item = item.substring(0, item.length - 1);
      }
      if (!out.contains(item)) out.add(item);
    }
    return out;
  }

  /// 反代地址做点清理：去掉协议头，只留域名
  static List<String> cleanProxies(List<String> value) {
    final out = <String>[];
    for (var raw in value) {
      var item = raw.trim().replaceFirst(RegExp(r'^https?://'), '');
      while (item.endsWith('/')) {
        item = item.substring(0, item.length - 1);
      }
      if (item.isEmpty || out.contains(item)) continue;
      out.add(item);
    }
    return out;
  }

  /// 设置里改过镜像 / 反代之后重新配置
  ///
  /// 传空列表就是「恢复默认」，会退回内置的那一串。
  void reconfigure({List<String>? apiBases, List<String>? imageProxies}) {
    if (apiBases != null) {
      this.apiBases = _orDefault(
        cleanBases(apiBases),
        PixivConst.defaultApiBases,
      );
      _baseIndex = 0;
    }
    if (imageProxies != null) {
      this.imageProxies = _orDefault(
        cleanProxies(imageProxies),
        PixivConst.defaultImageProxies,
      );
      _proxyIndex = 0;
    }
  }

  void updateTransport(NetTransport value) {
    if (value.signature == transport.signature) return;
    transport = value;
    _dio = null;
  }

  Dio _buildDio() {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 40),
        sendTimeout: const Duration(seconds: 20),
        responseType: ResponseType.plain,
        // 非 200 也要能读到 body，才能把镜像的报错原样带出来
        validateStatus: (_) => true,
      ),
    );
    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: transport.createClient,
    );
    return dio;
  }

  // ==================== 请求头 ====================

  /// 数据接口请求头
  static Map<String, String> get apiHeaders => {
    'user-agent': PixivConst.userAgent,
    'accept': 'application/json, text/plain, */*',
    'referer': 'https://pixiv.pictures/',
    'origin': 'https://pixiv.pictures',
  };

  /// 图片请求头：反代认 Referer，不带容易被挡
  static Map<String, String> get imageHeaders => {
    'user-agent': PixivConst.userAgent,
    'accept': 'image/avif,image/webp,image/*,*/*;q=0.8',
    'referer': PixivConst.referer,
  };

  // ==================== 图片地址 ====================

  /// 这次要用的图片反代域名
  String get imageProxyHost => imageProxies[_proxyIndex % imageProxies.length];

  /// 把 pixiv 的图片地址换成本次要用的反代域名
  ///
  /// 不是 i.pximg.net 的地址原样返回（镜像有时直接给相对路径）。
  String imageUrl(String raw) {
    final url = raw.trim();
    if (url.isEmpty || !url.contains('i.pximg.net')) return url;
    return url.replaceFirst(
      RegExp(r'^https?://i\.pximg\.net'),
      'https://$imageProxyHost',
    );
  }

  /// 这个反代不行了，换下一个
  void rotateImageProxy() {
    if (imageProxies.length < 2) return;
    _proxyIndex = (_proxyIndex + 1) % imageProxies.length;
  }

  // ==================== 基础请求 ====================

  /// GET 一个接口，镜像挨个试，谁通用谁
  Future<Map<String, dynamic>> _get(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    Object? lastError;

    for (var i = 0; i < apiBases.length; i++) {
      final index = (_baseIndex + i) % apiBases.length;
      final base = apiBases[index];
      try {
        final resp = await dio.get<String>(
          '$base/api/pixiv/$path',
          queryParameters: query,
          options: Options(headers: apiHeaders),
        );
        final code = resp.statusCode ?? 0;
        final body = resp.data ?? '';
        if (code != 200 || body.trim().isEmpty) {
          lastError = SourceException(_httpMessage(code));
          continue;
        }

        final decoded = jsonDecode(body);
        if (decoded is! Map) {
          lastError = const SourceException('Pixiv 镜像返回了看不懂的内容');
          continue;
        }

        // 记住这次能用的镜像，下次直接从它开始，不用每次都从头试
        _baseIndex = index;
        return decoded.map((k, v) => MapEntry(k.toString(), v));
      } on Exception catch (e) {
        lastError = e;
      }
    }

    throw SourceException(_describe(lastError));
  }

  /// 把底层异常翻译成人话
  String _describe(Object? error) {
    if (error is SourceException) {
      return 'Pixiv 镜像全部连不上（${apiBases.length} 个都试过了）：${error.message}';
    }
    if (error is DioException) {
      final info = NetError.describe(
        error,
        sourceName: 'Pixiv',
        proxyConfigured: transport.proxy != null,
        vpnActive: transport.vpnActive,
      );
      return info.message;
    }
    return 'Pixiv 镜像全部连不上（${apiBases.length} 个都试过了）';
  }

  static String _httpMessage(int code) {
    if (code == 403) return '镜像拒绝了请求（HTTP 403）';
    if (code == 404) return '镜像没有这个接口（HTTP 404）';
    if (code == 429) return '请求太频繁，被镜像限流了（HTTP 429）';
    return 'HTTP $code';
  }

  // ==================== 接口 ====================

  /// 搜索插画 / 漫画
  Future<List<Map<String, dynamic>>> search(
    String word, {
    String target = 'partial_match_for_tags',
    int page = 1,
  }) async {
    final data = await _get(
      'search',
      query: {
        'word': word,
        'page': page,
        'size': 30,
        'mode': target,
        'order': 'date_desc',
      },
    );
    return _maps(data['illusts']);
  }

  /// 搜索画师
  Future<List<Map<String, dynamic>>> searchUser(
    String word, {
    int page = 1,
  }) async {
    final data = await _get(
      'search_user',
      query: {'word': word, 'page': page, 'size': 30},
    );
    return _maps(data['user_previews']);
  }

  /// 某个画师的作品
  Future<List<Map<String, dynamic>>> memberIllust(
    String userId, {
    int page = 1,
  }) async {
    final data = await _get(
      'member_illust',
      query: {'id': userId, 'page': page, 'size': 30},
    );
    return _maps(data['illusts']);
  }

  /// 作品详情
  Future<Map<String, dynamic>> illust(String id) async {
    final data = await _get('illust', query: {'id': id});
    final value = data['illust'];
    if (value is! Map) {
      throw const SourceException('这个作品不存在或已被删除');
    }
    return value.map((k, v) => MapEntry(k.toString(), v));
  }

  /// 排行榜
  ///
  /// [mode] 是镜像那套档位串：`day` / `week` / `day_male` / `week_r18` …
  /// 一页 30 条，翻页靠 offset（镜像也认 page，但 offset 更直白）。
  Future<List<Map<String, dynamic>>> rank(String mode, {int page = 1}) async {
    final data = await _get(
      'rank',
      query: {'mode': mode, 'offset': (page - 1) * 30},
    );
    return _maps(data['illusts']);
  }

  // ==================== 解析辅助 ====================

  static List<Map<String, dynamic>> _maps(dynamic value) {
    if (value is! List) return const [];
    final out = <Map<String, dynamic>>[];
    for (final e in value) {
      if (e is Map) out.add(e.map((k, v) => MapEntry(k.toString(), v)));
    }
    return out;
  }
}
