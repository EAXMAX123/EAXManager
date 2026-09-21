/// 检查有没有新版本的安装包
///
/// 软件本身没有服务器，所以「最新版本是多少」这件事得有个地方问。
/// 做法是让用户填一个网址（自己的 GitHub / Gitee 仓库里放一个小文件就行），
/// 里面写清楚最新版本号和安装包地址，软件启动时去看一眼。
library;

import 'dart:convert';
import 'dart:async';
import 'dart:io';

import '../app_info.dart';
import '../net/net_transport.dart';

/// 一次检查的结果
class AppUpdate {
  const AppUpdate({required this.version, this.url = '', this.notes = ''});

  /// 最新版本号，形如 `1.1.5`
  final String version;

  /// 安装包地址，可能为空（只告诉了版本没给地址）
  final String url;

  /// 这一版改了什么
  final String notes;
}

class UpdateService {
  UpdateService._();

  /// 去 [urls] 看一眼有没有比当前更新的版本；没有或失败都返回 null
  ///
  /// [urls] 可以填多个地址（换行、逗号、空格分隔），全部同时问，
  /// 谁先给出可用结果就用谁——国内访问 GitHub 的几条路时通时不通，
  /// 一条一条试会很慢，同时试才快。
  static Future<AppUpdate?> check(
    String urls, {
    NetTransport transport = const NetTransport(),
  }) async {
    final list = candidates(urls);
    if (list.isEmpty) return null;

    final completer = Completer<AppUpdate?>();
    var remaining = list.length;

    for (final url in list) {
      unawaited(() async {
        final text = await _fetch(url, transport);
        final parsed = text == null ? null : parsePayload(text);
        final found =
            parsed != null &&
                compareVersion(parsed.version, AppInfo.version) > 0
            ? parsed
            : null;

        if (found != null) {
          if (!completer.isCompleted) completer.complete(found);
          return;
        }
        remaining--;
        if (remaining == 0 && !completer.isCompleted) completer.complete(null);
      }());
    }

    // 兜底：所有地址都卡住时别让启动流程一直挂着
    return completer.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () => null,
    );
  }

  /// 把用户填的内容展开成一组真正要请求的地址
  ///
  /// 同一个仓库往往有好几个入口（GitHub 原地址、jsDelivr 的几套 CDN、
  /// 公共加速），国内是「这条通那条不通」，而且今天通明天可能就不通，
  /// 所以填一个就把能换的都换出来，一起试。
  static List<String> candidates(String raw) {
    final out = <String>[];
    for (final piece in raw.split(RegExp(r'[\s,，]+'))) {
      final url = piece.trim();
      if (url.isEmpty) continue;
      for (final candidate in [url, ...mirrors(url)]) {
        if (out.contains(candidate)) continue;
        out.add(candidate);
      }
    }
    return out;
  }

  /// jsDelivr 的几套入口
  ///
  /// 背后是同一份文件、不同的 CDN 节点：国内常见 cdn 不通而 fastly 通，
  /// 或者反过来，所以都试一遍。
  static const List<String> jsdelivrHosts = [
    'cdn.jsdelivr.net',
    'fastly.jsdelivr.net',
    'gcore.jsdelivr.net',
    'testingcf.jsdelivr.net',
  ];

  /// 公共加速入口的前缀
  static const String ghProxyPrefix = 'https://ghproxy.net/';

  /// 一个地址还能换成哪些入口；换不了就返回空表
  ///
  /// 只认「GitHub 仓库里的文件」这一类地址，别的地址原样使用。
  static List<String> mirrors(String url) {
    final out = <String>[];

    final viaJsdelivr = RegExp(
      '^https?://(?:${jsdelivrHosts.map(RegExp.escape).join('|')})/gh/(.+)\$',
    ).firstMatch(url);
    if (viaJsdelivr != null) {
      final rest = viaJsdelivr[1]!;
      for (final host in jsdelivrHosts) {
        out.add('https://$host/gh/$rest');
      }
      final raw = _jsdelivrRestToRaw(rest);
      if (raw != null) {
        out.add('https://raw.githubusercontent.com/$raw');
        out.add('${ghProxyPrefix}https://raw.githubusercontent.com/$raw');
      }
      return out;
    }

    final viaRaw = RegExp(r'^https?://raw\.githubusercontent\.com/(.+)$')
        .firstMatch(url);
    if (viaRaw != null) {
      final rest = viaRaw[1]!;
      final jsdelivr = _rawRestToJsdelivr(rest);
      if (jsdelivr != null) {
        for (final host in jsdelivrHosts) {
          out.add('https://$host/gh/$jsdelivr');
        }
      }
      out.add('${ghProxyPrefix}https://raw.githubusercontent.com/$rest');
      return out;
    }

    return out;
  }

  // ==================== 安装包地址的备用入口 ====================

  /// 下载加速站
  ///
  /// GitHub 的 releases 下载（会跳到 objects.githubusercontent.com）在国内
  /// 基本直连不通，这几个公共加速站实测能跑满带宽，按「谁先答应用谁」试。
  static const List<String> downloadMirrors = [
    'https://gh-proxy.com/',
    'https://ghfast.top/',
    'https://ghproxy.net/',
  ];

  /// 把一个安装包地址展开成一组候选：加速站在前，原始地址兜底
  ///
  /// 不是 github.com 的地址原样返回——别的站点（自建服务器之类）不该被
  /// 套上 GitHub 的加速站。
  static List<String> downloadCandidates(String url) {
    final target = url.trim();
    if (target.isEmpty) return const [];

    final uri = Uri.tryParse(target);
    if (uri == null || uri.host != 'github.com') return [target];

    return [for (final prefix in downloadMirrors) '$prefix$target', target];
  }

  /// 挑一个真能下到的地址；全都不行就退回原始地址
  ///
  /// 只探前 1 个字节（Range 请求），够判断通不通又不浪费流量。几条候选
  /// 同时探，谁先成谁赢——一条一条试的话用户要干等好几秒。
  static Future<String> reachableDownloadUrl(
    String url, {
    NetTransport transport = const NetTransport(),
  }) async {
    final list = downloadCandidates(url);
    if (list.length < 2) return url.trim();

    final completer = Completer<String>();
    var remaining = list.length;

    for (final candidate in list) {
      unawaited(() async {
        final ok = await _probeDownload(candidate, transport);
        if (ok) {
          if (!completer.isCompleted) completer.complete(candidate);
          return;
        }
        remaining--;
        if (remaining == 0 && !completer.isCompleted) completer.complete(url.trim());
      }());
    }

    return completer.future.timeout(
      const Duration(seconds: 8),
      onTimeout: () => url.trim(),
    );
  }

  /// 探一下这个地址能不能拿到内容
  static Future<bool> _probeDownload(
    String url,
    NetTransport transport,
  ) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return false;

    final client = transport.createClient();
    try {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-0');
      requestHeaders().forEach((name, value) {
        request.headers.set(name, value);
      });
      final response = await request.close().timeout(
        const Duration(seconds: 6),
      );
      // 200 是服务器不认 Range 直接给全量，206 是老老实实给了 1 字节
      final ok = response.statusCode == 200 || response.statusCode == 206;
      await response.drain<void>().timeout(const Duration(seconds: 4));
      return ok;
    } on Object {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  /// `用户/仓库/分支/路径` -> `用户/仓库@分支/路径`
  static String? _rawRestToJsdelivr(String rest) {
    final m = RegExp(r'^([^/]+)/([^/]+)/([^/]+)/(.+)$').firstMatch(rest);
    if (m == null) return null;
    return '${m[1]}/${m[2]}@${m[3]}/${m[4]}';
  }

  /// `用户/仓库@分支/路径` -> `用户/仓库/分支/路径`
  static String? _jsdelivrRestToRaw(String rest) {
    final m = RegExp(r'^([^/]+)/([^/@]+)@([^/]+)/(.+)$').firstMatch(rest);
    if (m == null) return null;
    return '${m[1]}/${m[2]}/${m[3]}/${m[4]}';
  }

  /// 解析更新信息
  ///
  /// JSON 优先：`{"version":"1.1.5","url":"https://…apk","notes":"…"}`
  /// 也认纯文本，一行版本号、一行下载地址、剩下的当说明——
  /// 随手丢个 txt 上去也能用。
  static AppUpdate? parsePayload(String raw) {
    final text = raw.replaceFirst('\uFEFF', '').trim();
    if (text.isEmpty) return null;

    if (text.startsWith('{')) {
      Object? decoded;
      try {
        decoded = jsonDecode(text);
      } on FormatException {
        return null;
      }
      if (decoded is! Map) return null;
      final version = '${decoded['version'] ?? ''}'.trim();
      if (version.isEmpty) return null;
      return AppUpdate(
        version: version,
        url: '${decoded['url'] ?? decoded['download'] ?? ''}'.trim(),
        notes: '${decoded['notes'] ?? decoded['changelog'] ?? ''}'.trim(),
      );
    }

    final lines = text
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (lines.isEmpty) return null;
    return AppUpdate(
      version: lines.first,
      url: lines.length > 1 ? lines[1] : '',
      notes: lines.length > 2 ? lines.sublist(2).join('\n') : '',
    );
  }

  /// 版本号比较：左边新返回正数，相等返回 0
  ///
  /// 按数字段比，所以 1.1.10 比 1.1.9 新（按字符串比会反过来）。
  /// 前面可以带 v，后面带别的后缀也不影响。
  static int compareVersion(String a, String b) {
    final left = _parts(a);
    final right = _parts(b);
    final length = left.length > right.length ? left.length : right.length;
    for (var i = 0; i < length; i++) {
      final x = i < left.length ? left[i] : 0;
      final y = i < right.length ? right[i] : 0;
      if (x != y) return x > y ? 1 : -1;
    }
    return 0;
  }

  static List<int> _parts(String raw) => raw
      .trim()
      .replaceFirst(RegExp(r'^[vV]'), '')
      .split(RegExp(r'[^0-9]+'))
      .where((e) => e.isNotEmpty)
      .map((e) => int.tryParse(e) ?? 0)
      .toList();

  static Future<String?> _fetch(String url, NetTransport transport) async {
    return fetchText(url, transport: transport);
  }

  /// 请求头
  ///
  /// 这里必须全是 ASCII：请求头里混进中文，整个请求就非法了，
  /// 服务器会直接断连，表现出来和「连不上」一模一样。
  static Map<String, String> requestHeaders() => {
    HttpHeaders.acceptHeader: 'application/json, text/plain, */*',
    HttpHeaders.userAgentHeader: '${AppInfo.asciiName}/${AppInfo.version}',
  };

  /// 把地址上的原文拉下来；连不上或不是 200 返回 null
  ///
  /// 排查「地址到底通不通」时直接用它，比只看 check 的结论清楚。
  static Future<String?> fetchText(
    String url, {
    NetTransport transport = const NetTransport(),
  }) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;

    final client = transport.createClient();
    try {
      final request = await client.getUrl(uri);
      requestHeaders().forEach((name, value) {
        request.headers.set(name, value);
      });
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      if (response.statusCode != 200) return null;
      return await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 15));
    } on Object {
      // 检查更新失败不该影响用户干别的事
      return null;
    } finally {
      client.close(force: true);
    }
  }
}
