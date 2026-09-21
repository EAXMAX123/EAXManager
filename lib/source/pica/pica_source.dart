/// 哔咔漫画源
///
/// 搜索 / 详情 / 章节 / 图片地址都要登录 token，所以这里统一用 [_guard] 包一层：
/// token 失效时自动用保存的账号密码重登，重登失败再抛出「需要登录」。
library;

import 'dart:convert';

import 'package:dio/dio.dart';

import '../../data/settings_store.dart';
import '../../net/net_transport.dart';
import '../comic_source.dart';
import 'pica_client.dart';

class PicaSource implements ComicSource {
  PicaSource({NetTransport? transport})
    : client = PicaClient(transport: transport);

  final PicaClient client;

  /// 当前生效的登录邮箱，空表示未登录
  String email = '';

  bool _restored = false;

  @override
  String get key => 'pica';

  @override
  String get name => '哔咔';

  @override
  String get folder => 'Pica';

  @override
  bool get needsLogin => true;

  @override
  Dio get dio => client.dio;

  @override
  Map<String, String> get imageHeaders => client.imageHeaders;

  /// 用设置里的全局并发
  @override
  int? get imageConcurrencyOverride => null;

  bool get loggedIn => client.token.isNotEmpty;

  // ==================== 登录态 ====================

  /// 从本地恢复登录态：有效 token > 用保存的账号密码重登
  ///
  /// 不做任何内置账号兜底：账号是每个人自己的，内置一份既容易被人乱用，
  /// 也容易连带封号。
  Future<void> restore() async {
    if (_restored) return;
    _restored = true;

    final saved = await PicaAccountStore.load();
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    if (saved != null &&
        saved.token.isNotEmpty &&
        (saved.expireAt == 0 || saved.expireAt > now + 60)) {
      client.token = saved.token;
      email = saved.email;
      return;
    }

    if (saved != null && saved.hasCredentials) {
      await _tryLogin(saved.email, saved.password);
    }
  }

  Future<bool> _tryLogin(String mail, String password) async {
    try {
      final token = await client.login(mail, password);
      email = mail;
      await PicaAccountStore.save(
        PicaAccount(
          email: mail,
          password: password,
          token: token,
          expireAt: parseJwtExpire(token),
        ),
      );
      return true;
    } on Exception {
      return false;
    }
  }

  /// 用户主动登录（设置页）
  Future<void> login(String mail, String password) async {
    final token = await client.login(mail, password);
    email = mail;
    _restored = true;
    await PicaAccountStore.save(
      PicaAccount(
        email: mail,
        password: password,
        token: token,
        expireAt: parseJwtExpire(token),
      ),
    );
  }

  Future<void> logout() async {
    client.token = '';
    email = '';
    _restored = true;
    await PicaAccountStore.clear();
  }

  /// 代理变更后重建连接
  void updateTransport(NetTransport transport) {
    client.updateTransport(transport);
  }

  Future<void> _ensure() async {
    await restore();
    if (client.token.isEmpty) {
      throw const SourceException(
        '哔咔需要登录后才能搜索，请到「设置 → 账号」登录哔咔账号',
        needsLogin: true,
      );
    }
  }

  /// 认证失效时自动重登一次
  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on SourceException catch (e) {
      if (!e.needsLogin) rethrow;
      final saved = await PicaAccountStore.load();
      final mail = saved?.email ?? '';
      final pwd = saved?.password ?? '';
      // 没存账号密码就没法自动重登，直接让上层提示去设置页登录
      if (mail.isEmpty || pwd.isEmpty) rethrow;
      if (!await _tryLogin(mail, pwd)) rethrow;
      return await run();
    }
  }

  @override
  Future<bool> ready() async {
    await restore();
    return client.token.isNotEmpty;
  }

  // ==================== 搜索 / 详情 ====================

  @override
  Future<ComicSearchPage> search(
    String keyword, {
    SearchMode mode = SearchMode.site,
    int page = 1,
  }) async {
    await _ensure();
    // 哔咔只支持关键词 + 分区筛选，作者/标签模式统一退化成关键词搜索
    final data = await _guard(() => client.search(keyword, page: page));
    final docs = _docs(data);
    return ComicSearchPage(
      items: docs.map(_toItem).toList(),
      total: int.tryParse('${data['total'] ?? 0}') ?? 0,
      page: page,
    );
  }

  /// 我的收藏（对等 JM 的收藏夹）
  ///
  /// 收藏页的「哔咔」那一栏用它。没登录时 [_ensure] 会抛出「需要登录」，
  /// 由界面引导去设置页。
  Future<ComicSearchPage> favorites({int page = 1}) async {
    await _ensure();
    final data = await _guard(() => client.myFavourite(page: page));
    final docs = _docs(data);
    return ComicSearchPage(
      items: docs.map(_toItem).toList(),
      total: int.tryParse('${data['total'] ?? 0}') ?? 0,
      page: page,
    );
  }

  @override
  Future<ComicDetail> detail(String id) async {
    await _ensure();
    final comic = await _guard(() => client.comic(id));
    final eps = await _guard(() => client.episodes(id));

    // 哔咔返回的章节是 order 倒序，这里排成升序
    final sorted = [...eps]
      ..sort((a, b) => _intOf(a['order']).compareTo(_intOf(b['order'])));
    final chapters = <ComicChapter>[];
    for (var i = 0; i < sorted.length; i++) {
      final order = _intOf(sorted[i]['order'], fallback: i + 1);
      final title = (sorted[i]['title'] ?? '').toString().trim();
      chapters.add(
        ComicChapter(
          id: '$order',
          title: title.isEmpty ? '第 $order 话' : title,
          index: i + 1,
          order: order,
        ),
      );
    }

    final categories = _strList(comic['categories']);
    final tags = _strList(comic['tags']);
    final meta = <MapEntry<String, String>>[];
    void addMeta(String k, String v) {
      if (v.trim().isNotEmpty) meta.add(MapEntry(k, v));
    }

    addMeta('作者', (comic['author'] ?? '').toString());
    addMeta('汉化', (comic['chineseTeam'] ?? '').toString());
    addMeta('观看', (comic['viewsCount'] ?? '').toString());
    addMeta('爱心', (comic['likesCount'] ?? '').toString());
    addMeta('页数', (comic['pagesCount'] ?? '').toString());

    return ComicDetail(
      sid: SourceId(key, id),
      title: (comic['title'] ?? '').toString().trim(),
      author: (comic['author'] ?? '').toString(),
      description: (comic['description'] ?? '').toString(),
      tags: [...categories, ...tags],
      coverUrl: _thumbUrl(comic),
      coverHeaders: client.imageHeaders,
      chapters: chapters,
      meta: meta,
      isFavorite: comic['isFavourite'] == true,
    );
  }

  @override
  Future<ChapterPlan> chapterPlan(
    ComicDetail detail,
    ComicChapter chapter,
  ) async {
    await _ensure();
    // 单章本没有 eps，order 固定为 1
    final order = chapter.order > 0 ? chapter.order : 1;
    final docs = await _guard(() => client.pages(detail.sid.id, order));
    final headers = client.imageHeaders;

    final images = <ChapterImage>[];
    for (var i = 0; i < docs.length; i++) {
      final media = docs[i]['media'];
      if (media is! Map) continue;
      final map = media.map((k, v) => MapEntry(k.toString(), v));
      final url = PicaClient.mediaUrl(map);
      if (url.isEmpty) continue;
      final name = (map['originalName'] ?? '').toString().trim();
      images.add(
        ChapterImage(
          url: url,
          fileName: name.isEmpty
              ? '${(i + 1).toString().padLeft(5, '0')}.jpg'
              : name,
          headers: headers,
        ),
      );
    }

    if (images.isEmpty) {
      throw const SourceException('这一章没取到图片，可能是本子已下架或需要重新登录');
    }
    return ChapterPlan(images: images);
  }

  @override
  Future<bool?> setFavorite(String id, {required bool want}) async {
    await _ensure();
    // 哔咔这个接口是 toggle 语义，返回操作后的真实状态
    return _guard(() => client.toggleFavorite(id));
  }

  // ==================== 排行榜 ====================

  static const Map<String, String> _rankTt = {
    'day': 'H24',
    'week': 'D7',
    'month': 'D30',
  };

  /// 哔咔排行榜只有 24 小时 / 7 天 / 30 天三档，官方没有分类可选
  static const List<RankOption> _rankTimes = [
    RankOption('day', '24小时'),
    RankOption('week', '7天'),
    RankOption('month', '30天'),
  ];

  @override
  List<RankOption> get rankTimes => _rankTimes;

  /// 哔咔榜单没有分类这一档，界面上不会出现第三行
  @override
  List<RankOption> rankCategories(String time) => const [];

  /// 榜单接口不分页，整份一次给完，所以只认第一页
  @override
  Future<ComicSearchPage> rank({
    required String time,
    String category = '',
    int page = 1,
  }) async {
    await _ensure();
    if (page > 1) return const ComicSearchPage(items: <ComicItem>[], page: 2);

    final docs = await _guard(() => client.leaderboard(_rankTt[time] ?? 'H24'));
    return ComicSearchPage(
      items: docs.map(_toItem).toList(),
      total: docs.length,
      page: 1,
    );
  }

  // ==================== 解析辅助 ====================

  ComicItem _toItem(Map<String, dynamic> doc) {
    final categories = _strList(doc['categories']);
    final subtitle = [
      (doc['author'] ?? '').toString(),
      ...categories,
    ].where((e) => e.trim().isNotEmpty).join(' · ');

    return ComicItem(
      sid: SourceId(key, (doc['_id'] ?? '').toString()),
      title: (doc['title'] ?? '').toString().trim(),
      author: (doc['author'] ?? '').toString(),
      coverUrl: _thumbUrl(doc),
      coverHeaders: client.imageHeaders,
      subtitle: subtitle,
    );
  }

  String _thumbUrl(Map<String, dynamic> doc) {
    final thumb = doc['thumb'];
    if (thumb is! Map) return '';
    return PicaClient.mediaUrl(thumb.map((k, v) => MapEntry(k.toString(), v)));
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

  static List<String> _strList(dynamic v) {
    if (v is List) return v.map((e) => e.toString()).toList();
    if (v is String && v.trim().isNotEmpty) return [v.trim()];
    return const [];
  }

  static int _intOf(dynamic v, {int fallback = 0}) =>
      int.tryParse('$v') ?? fallback;

  /// 从 JWT 里解析过期时间（秒级时间戳），失败返回 0
  static int parseJwtExpire(String token) {
    try {
      final parts = token.split('.');
      if (parts.length < 2) return 0;
      var payload = parts[1].replaceAll('-', '+').replaceAll('_', '/');
      while (payload.length % 4 != 0) {
        payload += '=';
      }
      final json = jsonDecode(utf8.decode(base64.decode(payload)));
      if (json is Map) {
        final exp = json['exp'];
        if (exp is int) return exp;
      }
    } on Exception {
      // 解析失败就当没有过期信息，交给服务端判定
    }
    return 0;
  }
}
