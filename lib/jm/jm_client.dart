/// JM 移动端 API 客户端
///
/// 对应 jmcomic 的 JmApiClient：携带 token 头请求接口，响应为 AES 加密的 JSON。
library;

import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:cookie_jar/cookie_jar.dart';

import 'jm_constants.dart';
import 'jm_crypto.dart';
import 'jm_exception.dart';
import 'jm_models.dart';
import '../net/net_error.dart';
import '../net/net_transport.dart';

class JmClient {
  JmClient({
    NetTransport? transport,
    List<String>? customApiDomains,
    CookieJar? cookieJar,
    this.retryTimes = 3,
    this.timeout = const Duration(seconds: 20),
  }) : transport = transport ?? const NetTransport(),
       _customDomains = customApiDomains ?? const [],
       _cookieJar = cookieJar ?? CookieJar();

  /// 网络配置：代理、绕过 DNS 污染
  final NetTransport transport;

  /// 当前配置的代理地址，供上层判断是否需要重建客户端
  String get proxyUrl => transport.proxyUrl;

  /// 用户自定义 API 域名（优先于内置列表）
  final List<String> _customDomains;

  final int retryTimes;
  final Duration timeout;

  /// 会话 cookie 存储，注入 PersistCookieJar 后登录状态可跨启动保留
  final CookieJar _cookieJar;
  Dio? _dio;

  /// 当前可用的 API 域名
  String? _apiDomain;

  /// 当前使用的图片 CDN 域名
  String? _imageDomain;

  /// 候选 API 线路（按优先级排序）与当前下标
  List<String> _candidateDomains = const [];
  int _domainIndex = 0;

  /// 线路名（来自官方域名服务器，如「線路5」）
  final Map<String, String> _lineNames = {};

  bool _cookiesReady = false;

  /// 当前登录用户名，未登录为空
  String _username = '';

  /// 登录会话密钥（AVS），换域名时会重新写回 cookie
  String _avs = '';

  /// 登录密码。会话过期后没有任何别的办法重登，只能靠它。
  String _password = '';

  /// 正在重登，避免并发请求各登一次
  Future<bool>? _relogging;

  /// 上次重登失败的时间
  ///
  /// 失败之后冷却一会儿再试：密码改了或者被风控时，每个请求都去登一次
  /// 反而容易把账号搞得更麻烦。
  DateTime? _reloginFailedAt;

  static const Duration _reloginCooldown = Duration(minutes: 5);

  String? get apiDomain => _apiDomain;
  String? get imageDomain => _imageDomain;

  /// 是否已登录（存在用户名即视为登录）
  bool get isLoggedIn => _username.isNotEmpty;

  String get username => _username;

  /// 会话密钥，供上层持久化
  String get avsSecret => _avs;

  /// 留存的密码，供上层在重建客户端时带过去
  String get passwordSecret => _password;

  /// 是否留着密码、能在会话过期后自己重登
  bool get canAutoRelogin => _username.isNotEmpty && _password.isNotEmpty;

  /// 当前线路名，未知时返回域名本身
  String get lineName {
    final domain = _apiDomain;
    if (domain == null) return '未连接';
    return _lineNames[domain] ?? domain;
  }

  /// 候选线路数量
  int get lineCount => _candidateDomains.length;

  Dio _buildDio() {
    final options = BaseOptions(
      connectTimeout: timeout,
      receiveTimeout: timeout,
      sendTimeout: timeout,
      followRedirects: true,
      maxRedirects: 5,
      validateStatus: (code) => code != null && code < 500,
      headers: {...JmHeaders.appTemplate},
    );

    final dio = Dio(options);
    dio.interceptors.add(CookieManager(_cookieJar));
    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: transport.createClient,
    );
    return dio;
  }

  Dio get dio => _dio ??= _buildDio();

  /// 探测可用域名并准备好 cookies
  Future<void> ensureReady() async {
    if (_apiDomain != null && _cookiesReady) return;
    _apiDomain ??= await _probeDomain();
    await _ensureCookies();
    await _applyAvs();
  }

  /// 把登录会话写到当前域名上（换域名后仍保持登录态）
  Future<void> _applyAvs() async {
    if (_avs.isEmpty || _apiDomain == null) return;
    await _cookieJar.saveFromResponse(Uri.parse('https://$_apiDomain/'), [
      Cookie('AVS', _avs)
        ..domain = _apiDomain!
        ..path = '/',
    ]);
  }

  /// 依次尝试候选域名，返回第一个能正常返回加密数据的域名
  Future<String> _probeDomain() async {
    final seen = <String>{};
    final candidates = <String>[];

    void add(Iterable<String> list) {
      for (final raw in list) {
        final host = raw.replaceFirst(RegExp(r'^https?://'), '').trim();
        if (host.isEmpty || !seen.add(host)) continue;
        candidates.add(host);
      }
    }

    add(_customDomains);
    add(await _fetchLatestDomains());
    add(JmDomains.apiList);
    _candidateDomains = candidates;

    Object? lastRaw;
    var tried = 0;
    final deadline = DateTime.now().add(_probeBudget);

    for (var i = 0; i < candidates.length; i++) {
      // 网络整个不通时每条线路都要等好几秒，五条加起来能等到两分钟。
      // 与其让用户对着转圈发呆，不如到点就收手给结论。
      if (tried > 0 && DateTime.now().isAfter(deadline)) break;

      final host = candidates[i];
      tried++;
      try {
        final data = await _rawApi(
          host,
          '/search',
          params: {
            'main_tag': '0',
            'search_query': '',
            'page': '1',
            'o': JmMagic.orderLatest,
            't': JmMagic.timeAll,
          },
          allowFailure: true,
        );
        if (data != null) {
          _domainIndex = i;
          return host;
        }
      } on Exception catch (e) {
        lastRaw = e;
      }
    }

    throw JmException.network(probeFailureMessage(lastRaw, tried));
  }

  /// 线路探测的总时间上限
  static const Duration _probeBudget = Duration(seconds: 25);

  /// 探测全失败时给一句能看懂、也知道下一步该做什么的话
  ///
  /// 以前这里直接把最后一条线路的底层异常拼上去，用户看到的是
  /// 「www.cdnutc.me 不可用：DioException [connection error] …」——
  /// 既像是只有那一个域名有问题，又全是看不懂的英文。
  String probeFailureMessage(Object? lastRaw, int tried) {
    final count = tried > 0 ? tried : JmDomains.apiList.length;
    final prefix = 'JM 的 $count 条线路全部连不上';

    if (lastRaw is JmException) {
      if (lastRaw.kind == JmErrorKind.restricted) {
        return 'JM 能连上，但当前网络的 IP 被限制了。'
            '在设置里点「重新探测线路」换一条，或者开代理 / 加速器再试';
      }
      return '$prefix：${lastRaw.friendlyMessage}';
    }

    if (lastRaw == null) return '$prefix，请检查网络或配置代理';

    final info = NetError.describe(
      lastRaw,
      sourceName: 'JM',
      proxyConfigured: transport.proxy != null,
      vpnActive: transport.vpnActive,
    );
    return '$prefix。${info.advice}';
  }

  /// 换下一条线路
  ///
  /// 连接被重置 / 被风控时调用。成功换到新线路返回 true。
  Future<bool> rotateDomain() async {
    final candidates = _candidateDomains;

    // 还没有候选列表（首次探测就失败）时重新探测一遍
    if (candidates.length < 2) {
      _apiDomain = null;
      _cookiesReady = false;
      try {
        _apiDomain = await _probeDomain();
      } on Exception {
        return false;
      }
      await _ensureCookies();
      await _applyAvs();
      return true;
    }

    _domainIndex = (_domainIndex + 1) % candidates.length;
    final next = candidates[_domainIndex];
    if (next == _apiDomain) return false;

    _apiDomain = next;
    _cookiesReady = false; // 新线路要重新拿 cookies
    _imageDomain = null; // 图片 CDN 一起换，避免继续走被屏蔽的节点
    await _ensureCookies();
    await _applyAvs();
    return true;
  }

  /// 强制重新探测线路（设置页「重新探测线路」用）
  Future<void> reprobe() async {
    _apiDomain = null;
    _cookiesReady = false;
    _imageDomain = null;
    await ensureReady();
  }

  /// 换一个图片 CDN 域名（某个节点被屏蔽时用）
  String rotateImageDomain() {
    final current = _imageDomain;
    final candidates = JmDomains.imageList;
    if (candidates.length <= 1) {
      _imageDomain = candidates.first;
      return _imageDomain!;
    }

    var next = candidates[Random().nextInt(candidates.length)];
    while (next == current) {
      next = candidates[Random().nextInt(candidates.length)];
    }
    _imageDomain = next;
    return next;
  }

  /// 从官方域名服务器拉取最新域名列表（失败返回空）
  Future<List<String>> _fetchLatestDomains() async {
    for (final url in JmDomains.apiDomainServerList) {
      try {
        final resp = await dio.get<String>(
          url,
          options: Options(responseType: ResponseType.plain),
        );
        var text = resp.data ?? '';
        while (text.isNotEmpty && text.codeUnitAt(0) > 127) {
          text = text.substring(1);
        }
        if (text.trim().isEmpty) continue;

        final json = JmCrypto.decodeRespData(
          text.trim(),
          '',
          secret: JmMagic.apiDomainServerSecret,
        );
        final domains = parseDomainServerPayload(jsonDecode(json), _lineNames);
        if (domains.isNotEmpty) return domains;
      } on Exception {
        continue;
      }
    }
    return const [];
  }

  /// 解析官方域名服务器的返回内容
  ///
  /// 兼容两种格式：
  /// - 旧：`["www.cdnhjk.net", ...]`
  /// - 新：`{"Setting":[...], "Server":[...],
  ///        "jm3_Server":[["www.cdnhjk.net","線路1"], ...]}`
  ///
  /// [names] 会填入 `域名 -> 线路名` 的映射。
  static List<String> parseDomainServerPayload(
    dynamic data,
    Map<String, String> names,
  ) {
    final domains = <String>[];
    final seen = <String>{};

    void push(dynamic value) {
      final host = '$value'.trim();
      if (host.isEmpty || !seen.add(host)) return;
      domains.add(host);
    }

    if (data is List) {
      data.forEach(push);
      return domains;
    }

    if (data is Map) {
      final jm3 = data['jm3_Server'];
      if (jm3 is List) {
        for (final e in jm3) {
          if (e is List && e.isNotEmpty) {
            push(e[0]);
            if (e.length > 1) {
              final host = '${e[0]}'.trim();
              final name = '${e[1]}'.trim();
              if (host.isNotEmpty && name.isNotEmpty) names[host] = name;
            }
          } else if (e is String) {
            push(e);
          }
        }
      }
      for (final key in const ['Server', 'Setting']) {
        final list = data[key];
        if (list is List) list.forEach(push);
      }
    }

    return domains;
  }

  /// 把底层异常翻译成带操作建议的 JmException
  JmException toJmException(Object error) {
    if (error is JmException) return error;
    if (error is FormatException) return JmException.api(error.message);
    return JmException.network(
      NetError.describe(
        error,
        sourceName: 'JM',
        proxyConfigured: transport.proxy != null,
        vpnActive: transport.vpnActive,
      ).message,
    );
  }

  /// 移动端要求必须携带 cookies，否则接口会重定向到占位内容
  Future<void> _ensureCookies() async {
    if (_cookiesReady) return;
    try {
      await _rawApi(_apiDomain!, '/setting', allowFailure: true);
      _cookiesReady = true;
    } on Exception {
      _cookiesReady = true; // 拿不到也继续，部分接口不强制
    }
  }

  /// 发起一次 API 请求并解密响应，返回解密后的 JSON
  Future<Map<String, dynamic>?> _rawApi(
    String domain,
    String path, {
    Map<String, String>? params,
    Map<String, dynamic>? form,
    bool allowFailure = false,
    bool useSecret2 = false,
  }) async {
    final ts = JmCrypto.timeStamp();
    final (token, tokenparam) = JmCrypto.tokenAndTokenParam(
      ts,
      secret: useSecret2 ? JmMagic.appTokenSecret2 : JmMagic.appTokenSecret,
    );

    final options = Options(
      responseType: ResponseType.plain,
      headers: {
        ...JmHeaders.appTemplate,
        'token': token,
        'tokenparam': tokenparam,
      },
      // 表单接口（/login、POST /favorite）必须用 form-urlencoded
      contentType: form == null ? null : Headers.formUrlEncodedContentType,
    );
    final url = 'https://$domain$path';

    final resp = form == null
        ? await dio.get<String>(url, queryParameters: params, options: options)
        : await dio.post<String>(
            url,
            queryParameters: params,
            data: form,
            options: options,
          );

    final body = resp.data ?? '';
    final status = resp.statusCode ?? 0;

    if (status == 403) {
      throw JmException.restricted('IP 被限制访问，请更换域名或开启代理');
    }
    if (status == 401) {
      final msg = _errorMessage(body);
      throw JmException.unauthorized(msg.isEmpty ? '登录已失效，请重新登录' : msg);
    }
    if (status >= 400) {
      final msg = _errorMessage(body);
      if (allowFailure) return null;
      throw JmException.network(msg.isEmpty ? '请求失败，HTTP $status' : msg);
    }

    final envelope = _tryParseEnvelope(body);
    if (envelope == null) {
      if (allowFailure) return null;
      throw JmException.network('接口返回非 JSON 数据，可能被风控拦截');
    }

    final code = envelope['code'];
    final encoded = envelope['data'];
    if (code != 200 || encoded is! String || encoded.isEmpty) {
      if (allowFailure) return null;
      final msg = '${envelope['errorMsg'] ?? ''}'.trim();
      if (code == 401) {
        throw JmException.unauthorized(msg.isEmpty ? '登录已失效，请重新登录' : msg);
      }
      throw JmException.api(msg.isEmpty ? '接口返回异常: code=$code' : msg);
    }

    try {
      final plain = JmCrypto.decodeRespData(encoded, ts);
      final decoded = jsonDecode(plain);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is List) return {'content': decoded};
      return null;
    } on Exception catch (e) {
      if (allowFailure) return null;
      throw JmException.api('响应解密失败: $e');
    }
  }

  Map<String, dynamic>? _tryParseEnvelope(String body) {
    final start = body.indexOf('{');
    if (start < 0) return null;
    final end = body.lastIndexOf('}');
    if (end <= start) return null;
    try {
      final obj = jsonDecode(body.substring(start, end + 1));
      return obj is Map<String, dynamic> ? obj : null;
    } on Exception {
      return null;
    }
  }

  /// 带重试的 API 请求
  Future<Map<String, dynamic>> _api(
    String path, {
    Map<String, String>? params,
    Map<String, dynamic>? form,
    bool useSecret2 = false,
  }) async {
    await ensureReady();

    Object? lastError;
    var relogged = false;
    var attempt = 0;
    while (attempt <= retryTimes) {
      try {
        final data = await _rawApi(
          _apiDomain!,
          path,
          params: params,
          form: form,
          useSecret2: useSecret2,
        );
        if (data != null) return data;
        lastError = JmException.api('接口返回空数据');
      } on JmException catch (e) {
        lastError = e;
        if (e.kind == JmErrorKind.unauthorized) {
          // 会话过期是常事（JM 的登录很容易掉），拿留存的密码静默重登一次
          // 再试。这次重试不占重试次数，用户全程无感。
          if (!relogged && await relogin()) {
            relogged = true;
            continue;
          }
          rethrow;
        }
        // 本子不存在重试也没用
        if (e.kind == JmErrorKind.notFound) rethrow;
        // 连接被重置 / 被风控：换一条线路再试
        if (e.kind == JmErrorKind.network || e.kind == JmErrorKind.restricted) {
          await rotateDomain();
        }
      } on Exception catch (e) {
        // DioException 连接错误等，同样换线路
        lastError = toJmException(e);
        await rotateDomain();
      }

      attempt++;
      if (attempt <= retryTimes) {
        await Future<void>.delayed(Duration(milliseconds: 400 * attempt));
      }
    }

    if (lastError is JmException) throw lastError;
    throw toJmException(lastError ?? '未知错误');
  }

  // ==================== 业务接口 ====================

  /// 搜索本子
  ///
  /// [mode] 取值 site / work / author / tag / actor
  Future<JmSearchPage> search(
    String query, {
    int page = 1,
    String mode = 'site',
    String orderBy = JmMagic.orderLatest,
    String time = JmMagic.timeAll,
  }) async {
    final data = await _api(
      '/search',
      params: {
        'main_tag': '${jmSearchMainTag[mode] ?? 0}',
        'search_query': query,
        'page': '$page',
        'o': orderBy,
        't': time,
      },
    );

    // 直接搜索车号时，服务端会返回 redirect_aid
    final redirectAid = data['redirect_aid'];
    if (redirectAid != null && '$redirectAid'.isNotEmpty) {
      final album = await albumDetail('$redirectAid');
      return JmSearchPage(
        items: [
          JmSearchItem(
            id: album.id,
            name: album.name,
            author: album.authors.join('、'),
            description: album.description,
          ),
        ],
        total: 1,
        page: page,
        searchQuery: query,
      );
    }

    return JmSearchPage.fromJson(data, page);
  }

  /// 分类/排行浏览
  ///
  /// [orderBy] 取值 mr/mv/mp/tf，[time] 取值 t/w/m/a
  Future<JmSearchPage> categoriesFilter({
    int page = 1,
    String category = JmMagic.categoryAll,
    String orderBy = JmMagic.orderView,
    String time = JmMagic.timeWeek,
  }) async {
    final o = time == JmMagic.timeAll ? orderBy : '${orderBy}_$time';
    final data = await _api(
      '/categories/filter',
      params: {'page': '$page', 'order': '', 'c': category, 'o': o},
    );
    return JmSearchPage.fromJson(data, page);
  }

  /// 本子详情
  Future<JmAlbum> albumDetail(String albumId) async {
    final id = parseJmId(albumId);
    final data = await _api('/album', params: {'id': id});
    if (data['name'] == null) {
      throw JmException.notFound('本子 $id 不存在或已被删除');
    }
    return JmAlbum.fromJson(data);
  }

  /// 章节详情
  Future<JmPhoto> photoDetail(String photoId) async {
    final id = parseJmId(photoId);
    final data = await _api('/chapter', params: {'id': id});
    if (data['name'] == null) {
      throw JmException.notFound('章节 $id 不存在或已被删除');
    }
    return JmPhoto.fromJson(data);
  }

  /// 获取章节的 scramble_id（决定是否需要图片还原）
  Future<String> fetchScrambleId(String photoId) async {
    final id = parseJmId(photoId);
    final ts = JmCrypto.timeStamp();
    final (token, tokenparam) = JmCrypto.tokenAndTokenParam(
      ts,
      secret: JmMagic.appTokenSecret2,
    );

    await ensureReady();
    try {
      final resp = await dio.get<String>(
        'https://$_apiDomain/chapter_view_template',
        queryParameters: {
          'id': id,
          'mode': 'vertical',
          'page': '0',
          'app_img_shunt': '1',
          'express': 'off',
          'v': ts,
        },
        options: Options(
          responseType: ResponseType.plain,
          headers: {
            ...JmHeaders.appTemplate,
            'token': token,
            'tokenparam': tokenparam,
          },
        ),
      );

      final text = resp.data ?? '';
      final match = RegExp(r'var\s+scramble_id\s*=\s*(\d+);').firstMatch(text);
      return match?.group(1) ?? '${JmMagic.scramble220980}';
    } on Exception {
      return '${JmMagic.scramble220980}';
    }
  }

  /// 封面图地址：https://{API域名}/media/albums/{本子ID}.jpg
  String coverUrl(String albumId) {
    final id = parseJmId(albumId);
    final domain = _apiDomain ?? JmDomains.apiList.first;
    return 'https://$domain/media/albums/$id.jpg';
  }

  /// 生成图片下载地址
  String imageUrl(String photoId, String fileName) {
    final domain = _imageDomain ??= _pickImageDomain();
    final v = JmCrypto.timeStamp();
    return 'https://$domain/media/photos/$photoId/$fileName?v=$v';
  }

  static String _pickImageDomain() =>
      JmDomains.imageList[Random().nextInt(JmDomains.imageList.length)];

  /// 图片请求头（静态版本，供图片组件直接使用）
  static Map<String, String> get imageHeadersStatic => {
    ...JmHeaders.appTemplate,
    ...JmHeaders.appImage(),
  };

  /// 图片请求头
  Map<String, String> get imageHeaders => {
    ...JmHeaders.appTemplate,
    ...JmHeaders.appImage(),
  };

  // ==================== 账号与收藏夹 ====================

  /// 启动时恢复已保存的登录信息（cookie 由 PersistCookieJar 自动恢复）
  ///
  /// 密码留着不是为了「记住我」这个开关，而是会话过期后唯一的自救手段。
  void restoreAccount(String username, {String avs = '', String password = ''}) {
    _username = username.trim();
    _avs = avs.trim();
    _password = password;
  }

  /// 会话过期后，用留存的账号密码静默重登一次
  ///
  /// 同一时刻的多个请求共用同一次登录，免得各登一遍。
  /// 没有密码就直接返回 false，由上层提示用户去设置页手动登录。
  Future<bool> relogin() {
    if (!canAutoRelogin) return Future<bool>.value(false);
    final failedAt = _reloginFailedAt;
    if (failedAt != null &&
        DateTime.now().difference(failedAt) < _reloginCooldown) {
      return Future<bool>.value(false);
    }
    return _relogging ??= _doRelogin().whenComplete(() {
      _relogging = null;
    });
  }

  Future<bool> _doRelogin() async {
    final name = _username;
    final password = _password;
    try {
      await login(name, password);
      _reloginFailedAt = null;
      return true;
    } on Exception {
      _reloginFailedAt = DateTime.now();
      return false;
    }
  }

  /// 从响应体里取出服务端的中文错误提示（errorMsg / msg）
  String _errorMessage(String body) {
    final envelope = _tryParseEnvelope(body);
    if (envelope == null) return '';
    for (final key in ['errorMsg', 'msg']) {
      final value = '${envelope[key] ?? ''}'.trim();
      if (value.isNotEmpty && value != 'null') return value;
    }
    return '';
  }

  /// 登录（移动端 API：POST /login）
  ///
  /// 成功后会写入 AVS cookie，后续接口都以登录态请求。
  Future<void> login(String username, String password) async {
    final name = username.trim();
    if (name.isEmpty || password.isEmpty) {
      throw JmException.unauthorized('请填写用户名和密码');
    }

    await ensureReady();
    final data = await _rawApi(
      _apiDomain!,
      '/login',
      form: {'username': name, 'password': password},
    );
    if (data == null) {
      throw JmException.unauthorized('登录失败：账号或密码错误');
    }

    // 接口把会话密钥放在 s 字段，需要手动写回 cookie
    final secret = '${data['s'] ?? ''}';
    final uid = '${data['uid'] ?? ''}';
    if (secret.isEmpty && uid.isEmpty) {
      throw JmException.unauthorized('登录失败：账号或密码错误');
    }

    _avs = secret;
    await _applyAvs();
    _username = '${data['username'] ?? name}';
    _password = password;
  }

  /// 退出登录，清除本地会话
  Future<void> logout() async {
    _username = '';
    _avs = '';
    _password = '';
    await _cookieJar.deleteAll();
    _cookiesReady = false;
  }

  /// 收藏夹分页
  Future<JmFavoritePage> favoriteFolder({
    int page = 1,
    String folderId = '0',
    String orderBy = JmMagic.orderLatest,
  }) async {
    final data = await _api(
      '/favorite',
      params: {'page': '$page', 'folder_id': folderId, 'o': orderBy},
    );
    return JmFavoritePage.fromJson(data, page);
  }

  /// 查询当前账号是否已收藏该本子（读 /album 的 is_favorite）
  ///
  /// 查询失败返回 null，调用方据此回退到直接切换。
  Future<bool?> isFavorite(String albumId) async {
    try {
      final data = await _api('/album', params: {'id': parseJmId(albumId)});
      return data['is_favorite'] == true;
    } on Exception {
      return null;
    }
  }

  /// 设置收藏状态
  ///
  /// API 端 `/favorite` 是「切换」语义，所以先查当前状态，仅在不一致时才切换，
  /// 避免点「收藏」反而取消收藏。
  Future<void> setFavorite(String albumId, {required bool want}) async {
    final id = parseJmId(albumId);
    final current = await isFavorite(id);
    if (current == want) return;

    final data = await _api('/favorite', form: {'aid': id});
    final status = '${data['status'] ?? ''}';
    if (status != 'ok') {
      final msg = '${data['msg'] ?? ''}'.trim();
      throw JmException.api(
        msg.isEmpty ? '${want ? '收藏' : '取消收藏'}失败（status=$status）' : msg,
      );
    }
  }

  /// 把用户输入解析为 JM ID，支持 "123456" / "JM123456" / 链接
  static String parseJmId(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return trimmed;

    final digits = RegExp(r'(\d{3,})').firstMatch(trimmed);
    return digits?.group(1) ?? trimmed;
  }
}
