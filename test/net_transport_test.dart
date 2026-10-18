/// 网络传输层回归测试
///
/// 守住一个真的发出去过的 bug：设置了 `connectionFactory` 之后，Dart 的
/// HttpClient **不会**再做 TLS 握手（`SecureSocket.secure` 只出现在 HTTP 代理
/// 隧道那条分支里）。当时返回的是裸 socket，于是明文 HTTP 被发到了 443，
/// 服务器回 "400 The plain HTTP request was sent to HTTPS port"，
/// 用户看到的就是「一开绕过 DNS，JM 和哔咔全都用不了」。
///
/// 这里用「https 连明文服务器必须失败」来钉住：只要有人再把 TLS 那一步去掉，
/// 明文请求就会打到那个 HTTP 服务器上并拿到 200，测试立刻变红。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jm_reader/net/net_transport.dart';

void main() {
  group('NetTransport 走 connectionFactory 时的 TLS 行为', () {
    late HttpServer server;
    late int port;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      port = server.port;
      server.listen((request) {
        request.response
          ..statusCode = 200
          ..write('ok');
        request.response.close();
      });
    });

    tearDown(() async {
      await server.close(force: true);
    });

    HttpClient clientOf(DnsBypassMode mode) {
      final client = NetTransport(bypass: mode).createClient();
      addTearDown(() => client.close(force: true));
      return client;
    }

    test('http 能正常走通（确认通道本身是好的）', () async {
      final request = await clientOf(DnsBypassMode.on)
          .getUrl(Uri.parse('http://127.0.0.1:$port/'));
      final response = await request.close();
      expect(response.statusCode, 200);
      await response.drain<void>();
    });

    test('开启绕过时 https 会自己做 TLS：连明文服务器必须失败', () async {
      await expectLater(
        clientOf(DnsBypassMode.on)
            .getUrl(Uri.parse('https://127.0.0.1:$port/'))
            .timeout(const Duration(seconds: 15)),
        throwsA(isA<Exception>()),
      );
    });

    test('自动模式（没挂 VPN）同样会自己做 TLS', () async {
      await expectLater(
        clientOf(DnsBypassMode.auto)
            .getUrl(Uri.parse('https://127.0.0.1:$port/'))
            .timeout(const Duration(seconds: 15)),
        throwsA(isA<Exception>()),
      );
    });

    test('默认模式下，常规解析连不上会自动改用真实 IP', () async {
      // dead.invalid 这个域名解析不了，但 overrides 里给了 127.0.0.1。
      // 先走常规 → 失败 → 自动兜底 → 连到本机的测试服务器。
      // 这就是「哔咔连不上」时软件自己想办法的那条路。
      final client = const NetTransport(
        overrides: {
          'dead.invalid': ['127.0.0.1'],
        },
      ).createClient();
      addTearDown(() => client.close(force: true));

      final request = await client.getUrl(
        Uri.parse('http://dead.invalid:$port/'),
      );
      final response = await request.close();
      expect(response.statusCode, 200);
      await response.drain<void>();
    });
  });
}
