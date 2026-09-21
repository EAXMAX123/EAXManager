/// EH（E-Hentai / ExHentai）客户端
///
/// 和 JM、哔咔不一样，EH 没有干净的 JSON 接口：搜索列表、详情、图片地址
/// 全都要解析 HTML。更麻烦的是图片真实地址藏在每一页的
/// `/s/<ptoken>/<gid>-<n>` 详情页里，所以取一张图要两次请求——这是 EH 的
/// 机制决定的，第三方客户端都这么做。
///
/// 注意：EH 的域名在国内被 **SNI 阻断**（同一个 IP 换成别的域名就能连上），
/// 换线路、换 IP 都没用，必须挂梯子。这个客户端不做任何绕过尝试。
library;

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../../net/net_error.dart';
import '../../net/net_transport.dart';
import '../comic_source.dart';
import 'eh_account.dart';

/// 搜索结果一页多少条（EH 固定 25 条）
const int _ehPageSize = 25;

/// 榜单最多翻到第几页（EH 的榜单本身有上限，翻过头只会拿到空页）
const int _ehMaxRankPage = 200;

class EhClient {
  EhClient({NetTransport? transport, EhAccount? account})
    : transport = transport ?? const NetTransport(),
      account = account ?? const EhAccount();

  NetTransport transport;
  EhAccount account;

  Dio? _dio;

  Dio get dio => _dio ??= _buildDio();

  /// 账号或网络配置变了就重建连接
  void update({NetTransport? transport, EhAccount? account}) {
    var dirty = false;
    if (transport != null && transport.signature != this.transport.signature) {
      this.transport = transport;
      dirty = true;
    }
    if (account != null &&
        (account.cookieHeader != this.account.cookieHeader ||
            account.baseUrl != this.account.baseUrl)) {
      this.account = account;
      dirty = true;
    }
    if (dirty) _dio = null;
  }

  String get baseUrl => account.baseUrl;

  bool get loggedIn => account.hasLogin;

  Dio _buildDio() {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 25),
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 25),
        responseType: ResponseType.plain,
        followRedirects: true,
        maxRedirects: 5,
        validateStatus: (_) => true,
        headers: {
          'user-agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
          'accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'accept-language': 'zh-CN,zh;q=0.9,en;q=0.8',
        },
      ),
    );
    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: transport.createClient,
    );
    return dio;
  }

  /// 图片 / 封面请求头（EH 会看 Referer）
  Map<String, String> get imageHeaders => {
    'referer': '$baseUrl/',
    if (account.cookieHeader.isNotEmpty) 'cookie': account.cookieHeader,
  };

  // ==================== 基础请求 ====================

  Future<String> _getHtml(String url) async {
    final Response<String> response;
    try {
      response = await dio.get<String>(
        url,
        options: Options(
          headers: {
            if (account.cookieHeader.isNotEmpty) 'cookie': account.cookieHeader,
          },
        ),
      );
    } on DioException catch (error) {
      throw SourceException(
        NetError.describe(
          error,
          sourceName: 'EH',
          proxyConfigured: transport.proxy != null,
          vpnActive: transport.vpnActive,
        ).message,
      );
    }

    final body = response.data ?? '';
    final status = response.statusCode ?? 0;

    // ExHentai 没登录时会返回一个空的 "Sad Panda" 页面
    if (body.contains('Sad Panda')) {
      throw const SourceException(
        'EH 说没有登录（Sad Panda）。到「设置 → 账号 → EH」粘贴浏览器 Cookie 再试',
        needsLogin: true,
      );
    }
    if (status == 403) {
      throw const SourceException('EH 拒绝了这次请求（403），可能需要重新登录或换个节点');
    }
    if (status >= 500) {
      throw SourceException('EH 服务器出错（$status），稍后再试');
    }
    if (body.trim().isEmpty) {
      throw const SourceException('EH 返回了空页面，可能是网络被拦截了');
    }
    return body;
  }

  /// 验证当前 Cookie 能不能用
  ///
  /// 拿一次首页，未登录会被判成 Sad Panda 从而抛错；设置页登录时先用它
  /// 校验一遍，避免存下一个用不了的 Cookie。
  Future<void> verifyLogin() async {
    await _getHtml('$baseUrl/');
  }

  // ==================== 搜索 ====================

  Future<ComicSearchPage> search(String keyword, {int page = 1}) async {
    final query = Uri.encodeQueryComponent(keyword.trim());
    final url = '$baseUrl/?f_search=$query&page=${page - 1}';
    final body = await _getHtml(url);

    final items = EhParser.parseSearchItems(body, coverHeaders: imageHeaders);
    if (items.isEmpty && !body.contains('No hits found')) {
      // 页面拿到了却一条都解析不出来，多半是 EH 改版了。
      // 直接说清楚，别让用户以为「就是没这个本子」。
      throw const SourceException('EH 返回的页面没解析出结果，可能是页面改版了，请到交流群反馈');
    }

    final total = EhParser.parseTotal(body);
    return ComicSearchPage(
      items: items,
      page: page,
      // 解析不出总数时，用「这一页满了就还有下一页」来兜底
      total: total > 0
          ? total
          : page * items.length + (items.length >= _ehPageSize ? 1 : 0),
    );
  }

  // ==================== 排行榜 ====================

  /// 榜单（EH 管它叫 Toplist）
  ///
  /// [tl] 是榜单编号：`15` 昨日 / `13` 本月 / `12` 今年 / `11` 全部时间。
  /// 这是公开页面，没登录也能看；但 EH 的域名在国内被 SNI 阻断，
  /// 该挂梯子还是得挂。
  Future<ComicSearchPage> toplist(String tl, {int page = 1}) async {
    final body = await _getHtml('$baseUrl/toplist.php?tl=$tl&p=${page - 1}');

    final items = EhParser.parseRankItems(body, coverHeaders: imageHeaders);
    if (items.isEmpty) {
      throw const SourceException('EH 榜单页没解析出内容，可能是页面改版了，请到交流群反馈');
    }

    // 榜单页不给总数，只能靠「这一页有东西就还有下一页」来兜底
    final total = page >= _ehMaxRankPage
        ? page * items.length
        : page * items.length + 1;
    return ComicSearchPage(items: items, page: page, total: total);
  }

  // ==================== 详情 ====================

  /// [id] 形如 `1234567-abcdef1234`
  Future<EhGallery> gallery(String id) async {
    final parsed = parseGalleryId(id);
    if (parsed == null) throw const SourceException('本子编号不对');
    final body = await _getHtml(galleryUrl(parsed.$1, parsed.$2));

    final gallery = EhParser.parseGallery(body, id);
    if (gallery == null) {
      throw const SourceException('打不开这个本子，可能已删除或需要登录');
    }
    return gallery;
  }

  /// 按顺序取回全部页面的 `/s/...` 路径
  ///
  /// EH 的缩略图是分页的（一页 40 个），所以要翻几页才能拿全。
  Future<List<String>> pagePaths(String id, int pageCount) async {
    final parsed = parseGalleryId(id);
    if (parsed == null) throw const SourceException('本子编号不对');
    final base = galleryUrl(parsed.$1, parsed.$2);

    final paths = <String>[];
    final seen = <String>{};
    var page = 0;
    // 留一点余量：万一解析出的页数偏小，多翻一页就能发现；
    // 页数完全解析不出来时不能只翻两页，否则会悄悄少下图片
    final maxPages = pageCount > 0 ? (pageCount / 40).ceil() + 2 : 60;

    while (page < maxPages && page < 60) {
      final url = page == 0 ? base : '$base?p=$page';
      final found = EhParser.parsePagePaths(await _getHtml(url));

      var added = 0;
      for (final path in found) {
        if (!seen.add(path)) continue;
        paths.add(path);
        added++;
      }
      if (added == 0) break;
      page++;
    }
    return paths;
  }

  /// 打开一页的 `/s/...` 页面，取出真实图片地址
  Future<String> imageUrl(String pagePath) async {
    final source = EhParser.parseImageUrl(await _getHtml('$baseUrl$pagePath'));
    if (source.isEmpty) {
      throw const SourceException('这一页没取到图片地址，可能是配额用完了');
    }
    return source;
  }

  // ==================== URL 工具 ====================

  String galleryUrl(String gid, String token) => '$baseUrl/g/$gid/$token/';

  /// `https://e-hentai.org/g/1234567/abcdef/` -> `1234567-abcdef`
  static SourceId? sidFromGalleryUrl(String url) {
    final parsed = parseGalleryUrl(url);
    if (parsed == null) return null;
    return SourceId('eh', '${parsed.$1}-${parsed.$2}');
  }

  /// 从详情页 URL 里取出 (gid, token)
  static (String, String)? parseGalleryUrl(String url) {
    final match = RegExp(r'/g/(\d+)/([0-9a-fA-F]+)').firstMatch(url);
    if (match == null) return null;
    return (match.group(1)!, match.group(2)!);
  }

  /// 从本子 ID 里取出 (gid, token)
  static (String, String)? parseGalleryId(String id) {
    final index = id.indexOf('-');
    if (index <= 0) return null;
    final gid = id.substring(0, index);
    final token = id.substring(index + 1);
    if (gid.isEmpty || token.isEmpty) return null;
    return (gid, token);
  }

  /// 只保留路径部分
  static String pathOf(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return '';
    if (uri.host.isEmpty) return url.startsWith('/') ? url : '';
    return uri.path;
  }
}

/// 详情页解析结果
class EhGallery {
  const EhGallery({
    required this.id,
    required this.title,
    required this.coverUrl,
    required this.tags,
    required this.pageCount,
    required this.uploader,
  });

  final String id;
  final String title;
  final String coverUrl;
  final List<String> tags;
  final int pageCount;
  final String uploader;
}

/// EH 页面解析
///
/// 全部做成纯函数：EH 的页面结构是这一版里最没把握的东西（本机没法对着真站点
/// 验证），抽出来才能拿固定 HTML 做回归测试。
class EhParser {
  EhParser._();

  /// 解析搜索结果列表
  static List<ComicItem> parseSearchItems(
    String html, {
    required Map<String, String> coverHeaders,
  }) {
    final doc = html_parser.parse(html);
    final items = <ComicItem>[];
    for (final row in doc.querySelectorAll('table.itg tr')) {
      final item = _parseRow(row, coverHeaders);
      if (item != null) items.add(item);
    }
    return items;
  }

  static ComicItem? _parseRow(
    dom.Element row,
    Map<String, String> coverHeaders,
  ) {
    final links = row.querySelectorAll('a[href*="/g/"]');
    if (links.isEmpty) return null;

    // 缩略图那个链接的文字是空的，标题链接才有文字
    dom.Element? titleLink;
    for (final link in links) {
      if (link.text.trim().isNotEmpty) {
        titleLink = link;
        break;
      }
    }
    titleLink ??= links.first;

    final sid = EhClient.sidFromGalleryUrl(titleLink.attributes['href'] ?? '');
    if (sid == null) return null;

    final image = row.querySelector('img');
    final title = titleLink.text.trim().isNotEmpty
        ? titleLink.text.trim()
        : (image?.attributes['alt'] ?? '').trim();
    if (title.isEmpty) return null;

    return ComicItem(
      sid: sid,
      title: title,
      coverUrl: image?.attributes['src'] ?? '',
      coverHeaders: coverHeaders,
    );
  }

  /// 解析排行榜页面（Toplist / Popular）
  ///
  /// 榜单页的排版和搜索结果页不是同一套表格，所以先按标准结果行试一遍，
  /// 一条都拿不到时再退化成「把整页的 /g/ 链接都扫一遍」：后者不挑结构，
  /// 代价是只能拿到标题和封面——榜单列表本来也就只需要这两样。
  static List<ComicItem> parseRankItems(
    String html, {
    required Map<String, String> coverHeaders,
  }) {
    final doc = html_parser.parse(html);

    final rows = <ComicItem>[];
    for (final row in doc.querySelectorAll('table.itg tr')) {
      final item = _parseRow(row, coverHeaders);
      if (item != null) rows.add(item);
    }
    if (rows.isNotEmpty) return rows;

    final items = <ComicItem>[];
    final seen = <String>{};
    for (final link in doc.querySelectorAll('a[href*="/g/"]')) {
      final title = link.text.trim();
      if (title.isEmpty) continue;
      final sid = EhClient.sidFromGalleryUrl(link.attributes['href'] ?? '');
      if (sid == null || !seen.add(sid.key)) continue;

      // 缩略图挂在链接附近的祖先节点里，往上找几层
      var node = link.parent;
      var cover = '';
      for (var i = 0; i < 4 && node != null; i++) {
        final image = node.querySelector('img');
        if (image != null) {
          cover = image.attributes['src'] ?? '';
          break;
        }
        node = node.parent;
      }

      items.add(
        ComicItem(
          sid: sid,
          title: title,
          coverUrl: cover,
          coverHeaders: coverHeaders,
        ),
      );
    }
    return items;
  }

  /// 从整页文字里找 "of 1,234" 这样的总数
  static int parseTotal(String html) {
    final text = html_parser.parse(html).body?.text ?? '';
    final match = RegExp(r'of\s+([\d,]+)').firstMatch(text);
    if (match == null) return 0;
    return int.tryParse(match.group(1)!.replaceAll(',', '')) ?? 0;
  }

  /// 解析详情页；标题都取不到时返回 null（多半是已删除或需要登录）
  static EhGallery? parseGallery(String html, String id) {
    final doc = html_parser.parse(html);
    final title =
        doc.querySelector('#gn')?.text.trim() ??
        doc.querySelector('#gj')?.text.trim() ??
        '';
    if (title.isEmpty) return null;

    final tags = <String>[];
    for (final row in doc.querySelectorAll('#taglist tr')) {
      final cells = row.querySelectorAll('td');
      if (cells.isEmpty) continue;
      // 第一格是命名空间（如 "female:"），后面几格才是标签
      final namespace = cells.first.text.trim().replaceAll(':', '');
      for (final cell in cells.skip(1)) {
        for (final link in cell.querySelectorAll('a')) {
          final name = link.text.trim();
          if (name.isEmpty) continue;
          tags.add(namespace.isEmpty ? name : '$namespace:$name');
        }
      }
    }

    return EhGallery(
      id: id,
      title: title,
      coverUrl: doc.querySelector('#gd1 img')?.attributes['src'] ?? '',
      tags: tags,
      pageCount: _parsePageCount(doc),
      uploader: doc.querySelector('#gdn')?.text.trim() ?? '',
    );
  }

  static int _parsePageCount(dom.Document doc) {
    // 正常是「标签格写 Pages、数值格写 42」；解析不到再退回找 "42 pages"
    for (final row in doc.querySelectorAll('#gdd tr')) {
      final label =
          row.querySelector('td.gdt1')?.text.trim().toLowerCase() ?? '';
      final value = row.querySelector('td.gdt2')?.text ?? '';
      if (!label.startsWith('pages') &&
          !value.toLowerCase().contains('pages')) {
        continue;
      }
      final match = RegExp(r'([\d,]+)').firstMatch(value);
      if (match != null) {
        return int.tryParse(match.group(1)!.replaceAll(',', '')) ?? 0;
      }
    }

    final fallback = RegExp(
      r'([\d,]+)\s*pages',
      caseSensitive: false,
    ).firstMatch(doc.querySelector('#gdd')?.text ?? '');
    if (fallback == null) return 0;
    return int.tryParse(fallback.group(1)!.replaceAll(',', '')) ?? 0;
  }

  /// 解析缩略图页里所有 `/s/...` 路径，按出现顺序
  static List<String> parsePagePaths(String html) {
    final doc = html_parser.parse(html);
    final paths = <String>[];
    for (final link in doc.querySelectorAll('#gdt a')) {
      final href = link.attributes['href'] ?? '';
      if (!href.contains('/s/')) continue;
      final path = EhClient.pathOf(href);
      if (path.isEmpty) continue;
      paths.add(path);
    }
    return paths;
  }

  /// 解析单页 `/s/...` 里的真实图片地址
  static String parseImageUrl(String html) {
    final doc = html_parser.parse(html);
    final node = doc.querySelector('#img');
    if (node != null) {
      // #img 有时是 <img> 本身，有时是包着 <img> 的 <a>，两种都认
      final src = node.attributes['src']?.trim() ?? '';
      if (src.isNotEmpty) return src;
      final inner = node.querySelector('img')?.attributes['src']?.trim() ?? '';
      if (inner.isNotEmpty) return inner;
      final href = node.attributes['href']?.trim() ?? '';
      if (href.isNotEmpty) return href;
    }
    // 兜底：正文区域里的第一张图
    final fallback =
        doc.querySelector('#i3 img') ?? doc.querySelector('#i2 img');
    return fallback?.attributes['src']?.trim() ?? '';
  }
}
