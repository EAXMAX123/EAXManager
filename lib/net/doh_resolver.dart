/// DNS over HTTPS 解析：绕过运营商 DNS 污染
///
/// 实测腾讯 doh.pub 对这些域名的应答是干净的，阿里 dns.alidns.com 有时也会返回
/// 被污染的 221.228.32.13，所以这里**同时问多家并合并结果**，再由调用方用
/// TLS 握手来裁决哪个 IP 是真的——解析结果只是候选，不是结论。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

class DohResolver {
  DohResolver._();

  static final DohResolver instance = DohResolver._();

  /// 依次尝试的 DoH 服务，前两个在国内直连可用
  static const List<String> providers = [
    'https://doh.pub/dns-query',
    'https://dns.alidns.com/resolve',
  ];

  static const Duration _ttl = Duration(hours: 6);

  final Map<String, List<String>> _cache = {};
  final Map<String, DateTime> _cachedAt = {};

  /// 解析域名，返回候选 IP（失败返回空表，绝不抛异常）
  Future<List<String>> resolve(String host) async {
    // 已经是 IP 字面量就没什么可解析的，也免得为它白打一次 DoH
    if (InternetAddress.tryParse(host) != null) return const [];

    final key = host.toLowerCase();
    final cached = _cache[key];
    final at = _cachedAt[key];
    if (cached != null && at != null && DateTime.now().difference(at) < _ttl) {
      return cached;
    }

    final merged = <String>{};
    for (final provider in providers) {
      try {
        // A 和 AAAA 一起问：纯 IPv6 的网络（部分运营商流量就是这样）只拿
        // IPv4 地址是连不上的，两条一起返回才不至于全灭
        final answers = await Future.wait([
          _query(provider, key, 'A'),
          _query(provider, key, 'AAAA'),
        ]);
        for (final list in answers) {
          merged.addAll(list);
        }
      } on Exception {
        // 单个 DoH 服务不可用不影响其它，继续问下一家
      }
    }

    final list = merged.toList();
    if (list.isNotEmpty) {
      _cache[key] = list;
      _cachedAt[key] = DateTime.now();
    }
    return list;
  }

  /// 清空缓存（用户手动「重新探测线路」时调用）
  void clear() {
    _cache.clear();
    _cachedAt.clear();
  }

  Future<List<String>> _query(String provider, String host, String type) async {
    final recordType = type == 'AAAA' ? 28 : 1;
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 5)
      ..idleTimeout = const Duration(seconds: 5);
    try {
      final request = await client.getUrl(
        Uri.parse('$provider?name=$host&type=$type'),
      );
      request.headers.set(HttpHeaders.acceptHeader, 'application/dns-json');
      final response = await request.close().timeout(
        const Duration(seconds: 6),
      );
      if (response.statusCode != 200) return const [];
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 6));
      final json = jsonDecode(body);
      if (json is! Map) return const [];
      final answers = json['Answer'];
      if (answers is! List) return const [];
      final out = <String>[];
      for (final answer in answers) {
        if (answer is! Map || answer['type'] != recordType) continue;
        final ip = answer['data']?.toString() ?? '';
        if (InternetAddress.tryParse(ip) != null) out.add(ip);
      }
      return out;
    } finally {
      client.close(force: true);
    }
  }
}
