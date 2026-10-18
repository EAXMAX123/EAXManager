/// 网络传输层：统一构造 HttpClient，负责代理与「绕过 DNS 污染」
///
/// ⚠️ 关键机制（已核对 Dart SDK `_http/http_impl.dart` 的 `_ConnectionTarget.connect`）：
/// 只要设置了 `connectionFactory`，SDK 就**不会**再做 TLS 握手，而是直接拿它返回的
/// socket 去建连接（`SecureSocket.secure` 只出现在 HTTP 代理隧道那条分支里）。
/// 所以 https 必须由本文件自己握手——否则明文 HTTP 会被发到 443，
/// 服务器回 `400 The plain HTTP request was sent to HTTPS port`。
///
/// 自己握手还有个好处：SNI 和证书校验用的仍然是真实域名，
/// 连到被污染的 IP 会因为证书不匹配直接失败，不会静默走错路。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'doh_resolver.dart';
import 'net_ip_table.dart';
import 'net_error.dart';

/// 「绕过 DNS 污染」模式
enum DnsBypassMode {
  off('off', '关闭'),
  auto('auto', '自动'),
  on('on', '开启');

  const DnsBypassMode(this.key, this.label);

  final String key;
  final String label;

  static DnsBypassMode parse(String key) => DnsBypassMode.values.firstWhere(
    (e) => e.key == key,
    orElse: () => DnsBypassMode.off,
  );
}

enum ProxyKind { http, socks5 }

/// 代理地址解析结果
class ProxyConfig {
  const ProxyConfig({
    required this.kind,
    required this.host,
    required this.port,
  });

  final ProxyKind kind;
  final String host;
  final int port;

  /// 支持 `127.0.0.1:7890`、`http://…`、`socks5://…`、`socks5h://…`
  static ProxyConfig? parse(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return null;

    var kind = ProxyKind.http;
    final lower = text.toLowerCase();
    if (lower.startsWith('socks5h://')) {
      kind = ProxyKind.socks5;
      text = text.substring(10);
    } else if (lower.startsWith('socks5://')) {
      kind = ProxyKind.socks5;
      text = text.substring(9);
    } else if (lower.startsWith('socks://')) {
      kind = ProxyKind.socks5;
      text = text.substring(8);
    } else if (lower.startsWith('http://')) {
      text = text.substring(7);
    } else if (lower.startsWith('https://')) {
      text = text.substring(8);
    }

    text = text.split('/').first;
    final colon = text.lastIndexOf(':');
    if (colon <= 0) return null;
    final host = text.substring(0, colon).trim();
    final port = int.tryParse(text.substring(colon + 1).trim());
    if (host.isEmpty || port == null || port <= 0 || port > 65535) return null;
    return ProxyConfig(kind: kind, host: host, port: port);
  }
}

/// 一次请求要用的网络配置
class NetTransport {
  const NetTransport({
    this.bypass = DnsBypassMode.off,
    this.overrides = const {},
    this.proxyUrl = '',
    this.vpnActive = false,
  });

  final DnsBypassMode bypass;

  /// 用户手填的「域名 → IP」覆盖，优先级最高
  final Map<String, List<String>> overrides;

  final String proxyUrl;

  /// 系统当前是否挂着 VPN；自动模式下用它决定要不要接管 DNS
  final bool vpnActive;

  ProxyConfig? get proxy => ProxyConfig.parse(proxyUrl);

  /// 配置指纹：变了就必须重建 HttpClient，没变就别白重建
  String get signature =>
      '$proxyUrl|${bypass.key}|$vpnActive|${overrides.length}|'
      '${overrides.entries.map((e) => '${e.key}=${e.value.join(",")}').join(";")}';

  /// 记录「常规这条路走不通」的域名
  ///
  /// 试过一次发现走不通，这个域名之后就优先走真实 IP，省掉每次的等待。
  /// 换网络或用户点「重新探测线路」时会清空。
  static final Set<String> _systemDnsFailed = <String>{};

  /// 忘掉之前的判断：网络环境可能已经变了
  static void forgetFailedHosts() => _systemDnsFailed.clear();

  /// 本次是否真的启用 IP 直连
  ///
  /// 配了代理就交给代理解析域名（SOCKS5 传域名给代理解析，本来就不怕污染），
  /// 挂了 VPN 则由 VPN 接管流量，此时强行指定 IP 反而会让分流规则认不出域名。
  bool get bypassActive {
    if (proxy != null) return false;
    return switch (bypass) {
      DnsBypassMode.on => true,
      DnsBypassMode.off => false,
      DnsBypassMode.auto => !vpnActive,
    };
  }

  /// 构造一个配置好的 HttpClient
  HttpClient createClient() {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..idleTimeout = const Duration(seconds: 30);

    final config = proxy;
    if (config != null) {
      if (config.kind == ProxyKind.http) {
        // Dart 原生支持 http 代理（https 会自动发 CONNECT）
        client.findProxy = (_) => 'PROXY ${config.host}:${config.port}';
      } else {
        client.connectionFactory = (uri, _, _) async {
          final tunnel = await _socks5Tunnel(config, uri.host, uri.port);
          final socket = await _secureIfNeeded(uri, tunnel);
          return ConnectionTask.fromSocket(Future.value(socket), () {});
        };
      }
      return client;
    }

    // 没配代理时一律接管连接，但策略分两种：
    //   强制模式（设置里打开）→ 直接用真实 IP
    //   其它情况（默认）      → 先按常规走系统 DNS，连不上再自动改用真实 IP
    //
    // 「先走常规」这一步很关键：DNS 干净的网络里行为和以前完全一样，
    // 只有真的连不上时才多花一次尝试，用户不需要去动任何设置。
    final directFirst = bypassActive;
    client.connectionFactory = (uri, _, _) async {
      final socket = await _open(uri, directFirst: directFirst);
      return ConnectionTask.fromSocket(Future.value(socket), () {});
    };
    return client;
  }

  /// 打开一条到 [uri] 的连接，两条路自己挑
  Future<Socket> _open(Uri uri, {required bool directFirst}) async {
    // 之前试过常规路走不通的域名，这次别再白等一遍
    if (directFirst || _systemDnsFailed.contains(uri.host)) {
      return _directSocket(uri);
    }

    Object? systemError;
    try {
      return await _viaSystemDns(uri);
    } on Object catch (error) {
      systemError = error;
      _systemDnsFailed.add(uri.host);
    }

    try {
      return await _directSocket(uri);
    } on Object {
      // 两条路都不通，抛第一条：它更贴近用户网络的实际状况，报错也更好懂
      throw systemError;
    }
  }

  /// 常规这条路的预算
  ///
  /// 必须限时：DNS 被污染时那个假地址常常是「连得上但没反应」，
  /// 不限时就会一直干等下去（系统默认能等两分钟以上），
  /// 兜底那条路永远轮不到，用户看到的就是一直转圈然后失败。
  static const Duration _systemDnsBudget = Duration(seconds: 4);

  /// 常规做法：交给系统 DNS 解析（和没有这个功能之前一模一样）
  Future<Socket> _viaSystemDns(Uri uri) async {
    Socket? socket;
    try {
      final task = await Socket.startConnect(
        uri.host,
        uri.port,
      ).timeout(_systemDnsBudget);
      socket = await task.socket.timeout(_systemDnsBudget);
      return await _secureIfNeeded(uri, socket).timeout(_systemDnsBudget);
    } on Object {
      socket?.destroy();
      rethrow;
    }
  }

  // ==================== IP 直连 ====================

  Future<Socket> _directSocket(Uri uri) async {
    final host = uri.host;

    // 先用手上现成的候选（用户手填 + 内置表）：本地数据，不用等网络
    final known = <String>[];
    void add(Iterable<String> ips) {
      for (final ip in ips) {
        if (ip.isEmpty || NetIpTable.isPoisoned(ip)) continue;
        if (known.contains(ip)) continue;
        known.add(ip);
      }
    }

    add(overrides[host] ?? const []);
    add(NetIpTable.of(host));

    if (known.isNotEmpty) {
      try {
        return await _raceConnect(known, uri);
      } on Exception {
        // 内置表里的地址可能过期了，再问一次加密 DNS
      }
    }

    final resolved = await DohResolver.instance.resolve(host);
    if (resolved.isEmpty) {
      // 连候选都拿不到，交回系统 DNS，至少不会比原来更差
      return _viaSystemDns(uri);
    }
    return _raceConnect(resolved, uri);
  }

  /// 并发尝试所有候选 IP，取第一个「连上且 TLS 握手成功」的
  ///
  /// 被污染的 IP 往往能完成 TCP 连接（对方是真实存在的主机），
  /// 但用真实域名做 TLS 握手会失败。所以这里比的是整条链路，
  /// 只比 TCP 的话反而会挑中污染 IP。
  Future<Socket> _raceConnect(List<String> ips, Uri uri) async {
    final completer = Completer<Socket>();
    var remaining = ips.length;

    for (final ip in ips) {
      unawaited(() async {
        try {
          final raw = await Socket.connect(
            ip,
            uri.port,
            timeout: const Duration(seconds: 4),
          );
          final socket = await _secureIfNeeded(uri, raw);
          if (completer.isCompleted) {
            socket.destroy();
            return;
          }
          completer.complete(socket);
        } on Object {
          remaining--;
          if (remaining == 0 && !completer.isCompleted) {
            completer.completeError(
              NetUnreachableException(uri.host, attempts: ips.length),
              StackTrace.current,
            );
          }
          // 单个 IP 失败是常态，不打断其它候选
        }
      }());
    }
    return completer.future;
  }

  /// https 时自己做 TLS 握手
  ///
  /// 证书校验保持默认（真实域名 + 系统根证书），所以连错 IP 会直接失败，
  /// 不会静默连到一个假服务器上。
  static Future<Socket> _secureIfNeeded(Uri uri, Socket socket) async {
    if (uri.scheme != 'https') return socket;
    try {
      return await SecureSocket.secure(
        socket,
        host: uri.host,
      ).timeout(const Duration(seconds: 6));
    } on Object {
      socket.destroy();
      rethrow;
    }
  }

  // ==================== SOCKS5 ====================

  Future<Socket> _socks5Tunnel(
    ProxyConfig config,
    String host,
    int port,
  ) async {
    final socket = await Socket.connect(
      config.host,
      config.port,
      timeout: const Duration(seconds: 10),
    );
    try {
      await _Socks5Handshake(socket, host, port).run();
      return socket;
    } on Object {
      socket.destroy();
      rethrow;
    }
  }
}

/// SOCKS5 握手（只支持无认证方式，即绝大多数本地代理的默认配置）
///
/// 这里必须自己 `listen` 而不能用 `StreamIterator`：后者会在两次读取之间
/// 暂停订阅，导致 socket 内部把后续字节缓冲起来，等 HttpClient 接手时
/// 那些字节就丢了。
class _Socks5Handshake {
  _Socks5Handshake(this._socket, this._host, this._port);

  final Socket _socket;
  final String _host;
  final int _port;

  final List<int> _inbox = [];
  final List<Completer<void>> _waiters = [];
  Object? _error;
  bool _closed = false;

  Future<void> run() async {
    _socket.listen(
      (data) {
        _inbox.addAll(data);
        _wake();
      },
      onError: (Object error) {
        _error = error;
        _wake();
      },
      onDone: () {
        _closed = true;
        _wake();
      },
    );

    // 1. 问候：VER=5, NMETHODS=1, 无认证
    _socket.add(const [0x05, 0x01, 0x00]);
    await _socket.flush();
    final greeting = await _take(2);
    if (greeting[0] != 0x05) {
      throw const SocketException('对方不是 SOCKS5 代理');
    }
    if (greeting[1] != 0x00) {
      throw const SocketException('该 SOCKS5 代理要求密码认证，本应用暂不支持');
    }

    // 2. 请求：CONNECT + 域名寻址（域名交给代理解析，天然不怕污染）
    final hostBytes = utf8.encode(_host);
    if (hostBytes.length > 255) {
      throw const SocketException('域名过长，无法通过 SOCKS5 转发');
    }
    _socket.add([
      0x05,
      0x01,
      0x00,
      0x03,
      hostBytes.length,
      ...hostBytes,
      (_port >> 8) & 0xFF,
      _port & 0xFF,
    ]);
    await _socket.flush();

    // 3. 应答
    final head = await _take(4);
    if (head[0] != 0x05) throw const SocketException('SOCKS5 响应格式不正确');
    if (head[1] != 0x00) {
      throw SocketException('SOCKS5 代理拒绝了连接（错误码 ${head[1]}）');
    }
    switch (head[3]) {
      case 0x01:
        await _take(6);
      case 0x04:
        await _take(18);
      case 0x03:
        final length = (await _take(1)).first;
        await _take(length + 2);
      default:
        throw const SocketException('SOCKS5 返回了未知的地址类型');
    }
  }

  void _wake() {
    final pending = List<Completer<void>>.from(_waiters);
    _waiters.clear();
    for (final waiter in pending) {
      if (!waiter.isCompleted) waiter.complete();
    }
  }

  Future<void> _need(int count) async {
    while (_inbox.length < count) {
      final error = _error;
      if (error != null) throw error;
      if (_closed) throw const SocketException('SOCKS5 代理提前断开了连接');
      final waiter = Completer<void>();
      _waiters.add(waiter);
      await waiter.future;
    }
  }

  Future<List<int>> _take(int count) async {
    await _need(count);
    final out = _inbox.sublist(0, count);
    _inbox.removeRange(0, count);
    return out;
  }
}
