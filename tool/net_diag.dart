/// 网络诊断：逐层看某个域名卡在哪一步
///
/// 用法：dart run tool/net_diag.dart raw.githubusercontent.com
// ignore_for_file: avoid_print
library;

import 'dart:io';

import 'package:jm_reader/net/doh_resolver.dart';
import 'package:jm_reader/net/net_transport.dart';

Future<void> main(List<String> args) async {
  final url = args.isEmpty
      ? 'https://raw.githubusercontent.com/EAXMAX123/eam-update/main/update.json'
      : args.first.trim();
  final host = Uri.parse(url).host;
  print('目标：$url\n');

  await probe('A 普通 HttpClient（不用本软件的网络层）', url, null);
  await probe(
    'B 本软件网络层（强制真实 IP）',
    url,
    const NetTransport(bypass: DnsBypassMode.on),
  );
  await probe('C 本软件网络层（默认设置）', url, const NetTransport());

  print('');

  print('--- 1. 系统 DNS + TCP + TLS（和没装本软件时一样） ---');
  try {
    final task = await Socket.startConnect(
      host,
      443,
    ).timeout(const Duration(seconds: 8));
    final sock = await task.socket.timeout(const Duration(seconds: 8));
    print('  TCP 通了，对端 ${sock.remoteAddress.address}:${sock.remotePort}');
    try {
      final secure = await SecureSocket.secure(
        sock,
        host: host,
      ).timeout(const Duration(seconds: 8));
      print('  TLS 通了，证书主体：${secure.peerCertificate?.subject}');
      secure.destroy();
    } on Object catch (e) {
      print('  TLS 失败：$e');
      sock.destroy();
    }
  } on Object catch (e) {
    print('  TCP 失败：$e');
  }

  print('\n--- 2. 加密 DNS（DoH）解析出来的地址 ---');
  final ips = await DohResolver.instance.resolve(host);
  print(ips.isEmpty ? '  没解析出来' : '  ${ips.join(', ')}');

  print('\n--- 3. 用软件自己的网络层发一次请求 ---');
  final client = NetTransport().createClient();
  try {
    final request = await client.getUrl(Uri.parse('https://$host/'));
    final response = await request.close().timeout(const Duration(seconds: 15));
    print('  HTTP ${response.statusCode}');
    await response.drain<void>();
  } on Object catch (e) {
    print('  失败：$e');
  } finally {
    client.close(force: true);
  }
}

Future<void> probe(String label, String url, NetTransport? transport) async {
  final watch = Stopwatch()..start();
  final client =
      transport?.createClient() ??
      (HttpClient()..connectionTimeout = const Duration(seconds: 12));
  try {
    final request = await client.getUrl(Uri.parse(url));
    request.headers.set(HttpHeaders.userAgentHeader, 'EAX-probe');
    final response = await request.close().timeout(const Duration(seconds: 20));
    print('$label：HTTP ${response.statusCode}，用时 ${watch.elapsedMilliseconds}ms');
    await response.drain<void>();
  } on Object catch (e) {
    print('$label：失败（${watch.elapsedMilliseconds}ms）：$e');
  } finally {
    client.close(force: true);
  }
}
