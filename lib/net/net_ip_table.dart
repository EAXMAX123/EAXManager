/// 内置「域名 → 真实 IP」对照表
///
/// 国内 DNS 对这些域名的应答大量是假的，实测：
///   picacomic.com        → 108.160.165.147（Dropbox 的 IP）
///   e-hentai.org 的子域  → 31.13.x / 64.13.x / 199.59.x（Facebook、Twitter 的 IP）
///   JM 的每个域名        → 都被塞进同一条 221.228.32.13
///
/// 所以不能只信系统 DNS。这里存的是 2026-09 逐条实测、能完成 TLS 握手的 IP。
///
/// 表一定会过期，所以它只是「优先候选」，真正的裁决交给 TLS 证书校验：
/// 连不通的 IP 会被自动跳过，用户也能在设置里手填覆盖。
library;

class NetIpTable {
  NetIpTable._();

  /// 已验证的候选 IP，按优先级排列
  static const Map<String, List<String>> trusted = {
    // ===== JM API 线路 =====
    'www.cdngwc.cc': ['104.21.10.153', '172.67.163.159'],
    'www.cdngwc.net': ['104.21.87.64', '172.67.142.1'],
    'www.cdngwc.club': ['104.21.89.53', '172.67.188.34'],
    'www.cdnutc.me': ['128.241.232.3', '128.241.232.148'],
    'www.cdnhjk.net': ['104.21.44.113', '172.67.199.12'],

    // ===== JM 图片 CDN =====
    'cdn-msp.jmapiproxy1.cc': ['104.21.66.212', '172.67.164.97'],
    'cdn-msp.jmapiproxy2.cc': ['104.21.90.228', '172.67.162.52'],
    'cdn-msp2.jmapiproxy2.cc': ['104.21.90.228', '172.67.162.52'],
    'cdn-msp3.jmapiproxy2.cc': ['104.21.90.228', '172.67.162.52'],
    'cdn-msp.jmapinodeudzn.net': ['104.21.91.168', '172.67.175.205'],
    'cdn-msp3.jmapinodeudzn.net': ['104.21.91.168', '172.67.175.205'],

    // ===== 哔咔（这三个域名共用一个 Cloudflare 入口）=====
    'picaapi.picacomic.com': ['104.21.91.145', '104.20.42.9', '172.66.173.71'],
    'img.picacomic.com': ['104.21.91.145', '104.20.42.9'],
    'storage1.picacomic.com': ['104.21.91.145', '104.20.42.9'],
    'storage-b.picacomic.com': ['104.21.91.145', '104.20.42.9'],

    // ===== EH =====
    // 注意：这几个域名被 SNI 阻断（同样的 IP 换成别的域名就能通），
    // 换 IP 救不了，必须挂梯子。列在这里只是为了在梯子下少一次解析。
    'e-hentai.org': ['172.66.140.62', '172.66.132.196'],
    'exhentai.org': ['178.175.129.254'],
    's.exhentai.org': ['178.175.129.254', '178.175.128.254'],
  };

  /// 某个域名的内置候选 IP
  static List<String> of(String host) =>
      trusted[host.toLowerCase()] ?? const <String>[];

  /// 已知的污染应答，直接丢弃（实测每次查询都会被塞进来）
  static const Set<String> poisoned = {'221.228.32.13'};

  static bool isPoisoned(String ip) => poisoned.contains(ip);

  /// 解析设置页的「域名 = IP」多行文本
  ///
  /// 支持逗号或空格分隔多个 IP，`#` 开头是注释。
  static Map<String, List<String>> parseOverrides(String text) {
    final out = <String, List<String>>{};
    for (final raw in text.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final sep = line.indexOf('=');
      if (sep <= 0) continue;
      final host = line.substring(0, sep).trim().toLowerCase();
      final ips = line
          .substring(sep + 1)
          .split(RegExp(r'[,\s]+'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      if (host.isEmpty || ips.isEmpty) continue;
      out[host] = [...?out[host], ...ips];
    }
    return out;
  }
}
