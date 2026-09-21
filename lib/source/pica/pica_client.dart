/// 哔咔（PicACG）API 客户端
///
/// 协议实现参考 https://github.com/huashuiyue07/astrbot_plugin_pica
/// （该插件 2026-08 实测有效），签名与官方 App 一致。
///
/// 三个已经踩过的坑，这里都处理好了：
/// 1. 签名的 path 不能带前导斜杠，否则服务器返回假的 {"code":200} 空响应
/// 2. 中文参数必须 URL 编码，且签名用的是编码后的 path
/// 3. 图片（含封面）也需要带 authorization 头，不能直接外链
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import '../../net/net_error.dart';
import '../../net/net_transport.dart';
import '../comic_source.dart';

class PicaConst {
  PicaConst._();

  static const String baseUrl = 'https://picaapi.picacomic.com';
  static const String nonce = 'b1ab87b4800d4d4590a11701b8551afa';
  static const String apiKey = 'C69BAF41DA5ABD1FFEDC6D2FEA56B';
  static const String secretKey =
      r'~d}$Q7$eIni=V)9\RK/P.RM4;9[7|@/CA}b~OW!3?EV`:<>M7pddUBL5n|0/*Cn';
  static const String appVersion = '2.2.1.2.3.3';
  static const String appUuid = 'defaultUuid';
  static const String appBuildVersion = '44';
  static const String appChannel = '2';
  static const String userAgent = 'okhttp/3.8.1';
  static const String acceptJson = 'application/vnd.picacomic.com.v1+json';

  /// 排序：API 参数 -> 展示名
  static const Map<String, String> orders = {
    'ua': '默认',
    'dd': '新到旧',
    'da': '旧到新',
    'ld': '最多爱心',
    'vd': '最多指名',
  };

  /// 认证失败的 error 码
  static const Set<String> authErrorCodes = {'401', '1005', '1008'};
}

class PicaClient {
  PicaClient({NetTransport? transport})
    : transport = transport ?? const NetTransport();

  /// 网络配置：代理、绕过 DNS 污染
  NetTransport transport;

  /// 当前代理地址，供上层判断是否需要重建
  String get proxyUrl => transport.proxyUrl;

  /// 登录后拿到的 JWT，有效期约 7 天
  String token = '';

  Dio? _dio;

  Dio get dio => _dio ??= _buildDio();

  /// 代理变更后重建连接
  void updateTransport(NetTransport value) {
    if (value.signature == transport.signature) return;
    transport = value;
    _dio = null;
  }

  Dio _buildDio() {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 20),
        responseType: ResponseType.plain,
        // 401 也要能读到 body，交给下面统一判断
        validateStatus: (_) => true,
      ),
    );
    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: transport.createClient,
    );
    return dio;
  }

  // ==================== 签名 ====================

  static String sign(String method, String path, String ts) {
    final raw =
        '$path$ts${PicaConst.nonce}${method.toUpperCase()}${PicaConst.apiKey}'
            .toLowerCase();
    final hmac = Hmac(sha256, utf8.encode(PicaConst.secretKey));
    return hmac.convert(utf8.encode(raw)).toString();
  }

  Map<String, String> _headers(String method, String path) {
    final ts = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    return {
      'api-key': PicaConst.apiKey,
      'accept': PicaConst.acceptJson,
      'app-channel': PicaConst.appChannel,
      'time': ts,
      'nonce': PicaConst.nonce,
      'signature': sign(method, path, ts),
      'app-version': PicaConst.appVersion,
      'app-uuid': PicaConst.appUuid,
      'app-platform': 'android',
      'app-build-version': PicaConst.appBuildVersion,
      'Content-Type': 'application/json; charset=UTF-8',
      'user-agent': PicaConst.userAgent,
      'image-quality': 'original',
      if (token.isNotEmpty) 'authorization': token,
    };
  }

  /// 图片 / 封面请求头（哔咔的图片也要鉴权）
  Map<String, String> get imageHeaders => {
    'user-agent': PicaConst.userAgent,
    'accept': 'image/*',
    if (token.isNotEmpty) 'authorization': token,
  };

  // ==================== 基础请求 ====================

  /// [path] 不带前导斜杠，可含 query；签名用的就是它本身
  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? data,
  }) async {
    final Response<String> resp;
    try {
      resp = await dio.request<String>(
        '${PicaConst.baseUrl}/$path',
        data: data == null ? null : jsonEncode(data),
        options: Options(method: method, headers: _headers(method, path)),
      );
    } on DioException catch (e) {
      throw SourceException(
        NetError.describe(
          e,
          sourceName: '哔咔',
          proxyConfigured: transport.proxy != null,
          vpnActive: transport.vpnActive,
        ).message,
      );
    }

    final body = resp.data ?? '';
    Map<String, dynamic> json;
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('非对象响应');
      }
      json = decoded;
    } on FormatException {
      throw SourceException('哔咔响应解析失败（HTTP ${resp.statusCode}）');
    }

    final code = json['code'];
    if (code != null && code != 200) {
      final message = (json['message'] ?? '未知错误').toString();
      final error = (json['error'] ?? '').toString().trim();

      if (resp.statusCode == 401 || PicaConst.authErrorCodes.contains(error)) {
        throw const SourceException(
          '哔咔登录已失效，请到「设置 → 账号」重新登录',
          needsLogin: true,
        );
      }
      if (resp.statusCode == 400 && body.toLowerCase().contains('banned')) {
        throw SourceException('内容已被哔咔平台封禁：$message');
      }
      throw SourceException('哔咔请求失败：$message');
    }

    return json;
  }

  // ==================== 接口 ====================

  /// 登录，成功返回 token
  ///
  /// 字段名是 `email`，服务端要的也确实是**注册邮箱**，不是账号名——
  /// 实测填账号名会返回 `{"code":400,"error":"1004",
  /// "message":"invalid email or password"}`。界面上也别把它写成「账号名」，
  /// 之前这么改过一版，结果本来能登录的人全登不上了。
  Future<String> login(String email, String password) async {
    final Map<String, dynamic> json;
    try {
      json = await _request(
        'POST',
        'auth/sign-in',
        data: {'email': email, 'password': password},
      );
    } on SourceException catch (e) {
      // 账号密码不对时服务器给的是 code 400 / error 1004，
      // 原文是 "invalid email or password"，翻译成人话再抛出去
      final text = e.message.toLowerCase();
      if (text.contains('invalid email or password') || text.contains('1004')) {
        throw const SourceException(
          '登录失败：邮箱或密码不对（哔咔要用注册时的邮箱登录，不是账号名）',
          needsLogin: true,
        );
      }
      rethrow;
    }
    final t = (json['data'] as Map?)?['token']?.toString() ?? '';
    if (t.isEmpty) {
      final msg = (json['message'] ?? '').toString();
      throw SourceException(
        msg.isEmpty || msg == 'success' ? '登录失败：账号或密码不对' : '登录失败：$msg',
        needsLogin: true,
      );
    }
    token = t;
    return t;
  }

  /// 高级搜索
  Future<Map<String, dynamic>> search(
    String keyword, {
    int page = 1,
    String sort = 'ua',
  }) async {
    final json = await _request(
      'POST',
      'comics/advanced-search?page=$page',
      data: {'categories': <String>[], 'keyword': keyword, 'sort': sort},
    );
    return _map(json, 'data', 'comics');
  }

  /// 本子详情
  Future<Map<String, dynamic>> comic(String id) async {
    final json = await _request('GET', 'comics/$id');
    return _map(json, 'data', 'comic');
  }

  /// 全部章节（自动翻页）
  Future<List<Map<String, dynamic>>> episodes(String id) async {
    final all = <Map<String, dynamic>>[];
    var page = 1;
    while (true) {
      final json = await _request('GET', 'comics/$id/eps?page=$page');
      final eps = _map(json, 'data', 'eps');
      final docs = _docs(eps);
      all.addAll(docs);
      final pages = int.tryParse('${eps['pages'] ?? 1}') ?? 1;
      if (page >= pages || docs.isEmpty || page >= 20) break;
      page++;
    }
    return all;
  }

  /// 某章节的图片列表（自动翻页）
  Future<List<Map<String, dynamic>>> pages(String id, int order) async {
    final all = <Map<String, dynamic>>[];
    var page = 1;
    while (true) {
      final json = await _request(
        'GET',
        'comics/$id/order/$order/pages?page=$page',
      );
      final data = _map(json, 'data', 'pages');
      final docs = _docs(data);
      all.addAll(docs);
      final pages = int.tryParse('${data['pages'] ?? 1}') ?? 1;
      if (page >= pages || docs.isEmpty || page >= 40) break;
      page++;
    }
    return all;
  }

  /// 收藏 / 取消收藏（toggle），返回操作后是否已收藏
  Future<bool> toggleFavorite(String id) async {
    final json = await _request(
      'POST',
      'comics/$id/favourite',
      data: const <String, dynamic>{},
    );
    final data = json['data'];
    if (data is Map) return data['favourite'] == true;
    return false;
  }

  /// 我的收藏（分页）
  ///
  /// 和别的列表接口一样返回 {docs, total, pages}，所以自动翻页的逻辑通用。
  /// 排序 s 用的是哔咔那套：ua 默认 / dd 新到旧 / da 旧到新 / ld 最多爱心。
  Future<Map<String, dynamic>> myFavourite({
    int page = 1,
    String sort = 'ua',
  }) async {
    final json = await _request('GET', 'users/favourite?s=$sort&page=$page');
    return _map(json, 'data', 'comics');
  }

  /// 排行榜
  ///
  /// [tt] 是时间范围：`H24` / `D7` / `D30`；ct 官方只有 `VC` 这一档。
  /// 这个接口是整份榜单一次给完的，没有分页参数，别拿 page 去换页。
  Future<List<Map<String, dynamic>>> leaderboard(String tt) async {
    final json = await _request('GET', 'comics/leaderboard?ct=VC&tt=$tt');
    return _docs(_map(json, 'data', 'comics'));
  }

  // ==================== 解析辅助 ====================

  static Map<String, dynamic> _map(
    Map<String, dynamic> json,
    String outer,
    String inner,
  ) {
    final first = json[outer];
    if (first is! Map) return <String, dynamic>{};
    final second = first[inner];
    if (second is! Map) return <String, dynamic>{};
    return second.map((k, v) => MapEntry(k.toString(), v));
  }

  static List<Map<String, dynamic>> _docs(Map<String, dynamic> source) {
    final raw = source['docs'];
    if (raw is! List) return const [];
    final out = <Map<String, dynamic>>[];
    for (final e in raw) {
      if (e is Map) out.add(e.map((k, v) => MapEntry(k.toString(), v)));
    }
    return out;
  }

  /// 拼接图片地址：{fileServer}/static/{path}
  static String mediaUrl(Map<String, dynamic> media) {
    final server = (media['fileServer'] ?? '').toString();
    final path = (media['path'] ?? '').toString();
    if (server.isEmpty || path.isEmpty) return '';
    return '$server/static/$path';
  }
}
