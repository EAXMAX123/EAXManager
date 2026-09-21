import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jm_reader/net/net_error.dart';
import 'package:jm_reader/net/net_ip_table.dart';
import 'package:jm_reader/net/net_transport.dart';

void main() {
  group('NetIpTable', () {
    test('内置表里 JM 和哔咔的域名都有候选 IP', () {
      expect(NetIpTable.of('www.cdngwc.cc'), isNotEmpty);
      expect(NetIpTable.of('picaapi.picacomic.com'), isNotEmpty);
      expect(NetIpTable.of('cdn-msp.jmapiproxy1.cc'), isNotEmpty);
    });

    test('域名大小写不影响查询', () {
      expect(NetIpTable.of('WWW.CDNGWC.CC'), NetIpTable.of('www.cdngwc.cc'));
    });

    test('没收录的域名返回空表而不是报错', () {
      expect(NetIpTable.of('example.com'), isEmpty);
    });

    test('污染应答被识别出来', () {
      expect(NetIpTable.isPoisoned('221.228.32.13'), isTrue);
      expect(NetIpTable.isPoisoned('104.21.10.153'), isFalse);
    });

    test('parseOverrides 解析多行「域名 = IP」', () {
      final map = NetIpTable.parseOverrides('''
# 这是注释
www.cdngwc.cc = 1.2.3.4
picaapi.picacomic.com = 5.6.7.8, 9.10.11.12
''');
      expect(map['www.cdngwc.cc'], ['1.2.3.4']);
      expect(map['picaapi.picacomic.com'], ['5.6.7.8', '9.10.11.12']);
    });

    test('parseOverrides 忽略空行、注释和格式不对的行', () {
      final map = NetIpTable.parseOverrides('\n\n#x\n没有等号\n= 1.2.3.4\n');
      expect(map, isEmpty);
    });
  });

  group('ProxyConfig.parse', () {
    test('裸 host:port 默认按 http 代理处理', () {
      final config = ProxyConfig.parse('127.0.0.1:7890');
      expect(config?.kind, ProxyKind.http);
      expect(config?.host, '127.0.0.1');
      expect(config?.port, 7890);
    });

    test('socks5:// 会被识别成 socks5，而不是被当成 http', () {
      // 老实现把协议头剥掉就当 http 用，等于用户填了 socks5 却没生效
      final config = ProxyConfig.parse('socks5://127.0.0.1:1080');
      expect(config?.kind, ProxyKind.socks5);
      expect(config?.port, 1080);
    });

    test('socks5h 也按 socks5 处理', () {
      expect(
        ProxyConfig.parse('socks5h://127.0.0.1:1080')?.kind,
        ProxyKind.socks5,
      );
    });

    test('http:// 前缀能正常解析', () {
      expect(ProxyConfig.parse('http://127.0.0.1:7890')?.kind, ProxyKind.http);
    });

    test('空串、缺端口、端口非法都返回 null', () {
      expect(ProxyConfig.parse(''), isNull);
      expect(ProxyConfig.parse('127.0.0.1'), isNull);
      expect(ProxyConfig.parse('127.0.0.1:0'), isNull);
      expect(ProxyConfig.parse('127.0.0.1:70000'), isNull);
    });
  });

  group('NetTransport.bypassActive', () {
    test('默认关闭', () {
      expect(const NetTransport().bypassActive, isFalse);
    });

    test('显式开启时生效', () {
      expect(const NetTransport(bypass: DnsBypassMode.on).bypassActive, isTrue);
    });

    test('自动模式：没挂梯子就开，挂了梯子就关', () {
      const noVpn = NetTransport(bypass: DnsBypassMode.auto);
      const withVpn = NetTransport(bypass: DnsBypassMode.auto, vpnActive: true);
      expect(noVpn.bypassActive, isTrue);
      // 挂梯子时强行指定 IP 会让梯子的分流规则认不出域名，必须让路
      expect(withVpn.bypassActive, isFalse);
    });

    test('配了代理就不再自己解析 IP，交给代理解析域名', () {
      const transport = NetTransport(
        bypass: DnsBypassMode.on,
        proxyUrl: 'socks5://127.0.0.1:1080',
      );
      expect(transport.bypassActive, isFalse);
    });

    test('配置指纹能区分开关和自定义 IP 的变化', () {
      const a = NetTransport();
      const b = NetTransport(bypass: DnsBypassMode.on);
      const c = NetTransport(
        overrides: {
          'www.cdngwc.cc': ['1.2.3.4'],
        },
      );
      expect(a.signature, isNot(b.signature));
      expect(a.signature, isNot(c.signature));
      expect(a.signature, const NetTransport().signature);
    });
  });

  group('NetError.describe', () {
    DioException dio(Object error, DioExceptionType type) => DioException(
      requestOptions: RequestOptions(path: '/x'),
      type: type,
      error: error,
    );

    test('连接被重置时说清楚是线路被掐断，并给出下一步', () {
      final info = NetError.describe(
        dio(
          const SocketException(
            'Connection reset by peer',
            osError: OSError('Connection reset by peer', 104),
          ),
          DioExceptionType.connectionError,
        ),
        sourceName: 'JM',
      );
      expect(info.fault, NetFault.blocked);
      expect(info.message, contains('掐断'));
      expect(info.message, contains('强制使用真实 IP'));
    });

    test('域名解析失败归到 DNS 污染', () {
      final info = NetError.describe(
        dio(
          const SocketException('Failed host lookup: "picaapi.picacomic.com"'),
          DioExceptionType.connectionError,
        ),
        sourceName: '哔咔',
      );
      expect(info.fault, NetFault.dnsPoisoned);
      expect(info.message, contains('哔咔'));
    });

    test('超时会区分有没有挂梯子', () {
      final noVpn = NetError.describe(
        dio(
          const SocketException('timed out'),
          DioExceptionType.connectionError,
        ),
        sourceName: 'JM',
      );
      expect(noVpn.fault, NetFault.timeout);
      expect(noVpn.advice, contains('强制使用真实 IP'));

      final withVpn = NetError.describe(
        dio(
          const SocketException('timed out'),
          DioExceptionType.connectionError,
        ),
        sourceName: 'EH',
        vpnActive: true,
      );
      expect(withVpn.advice, contains('节点'));
    });

    test('证书不对时提示可能是假线路', () {
      final info = NetError.describe(
        dio(
          const HandshakeException('CERTIFICATE_VERIFY_FAILED'),
          DioExceptionType.connectionError,
        ),
        sourceName: 'JM',
      );
      expect(info.fault, NetFault.certificate);
    });

    test('填了代理却连不上代理本身，提示去查代理软件', () {
      final info = NetError.describe(
        dio(
          const SocketException(
            'Connection refused',
            osError: OSError('Connection refused', 111),
          ),
          DioExceptionType.connectionError,
        ),
        sourceName: '哔咔',
        proxyConfigured: true,
      );
      expect(info.fault, NetFault.proxyDown);
      expect(info.advice, contains('代理软件'));
    });

    test('认不出来的错误也会给一句人话，不会把原文糊给用户', () {
      final info = NetError.describe(StateError('莫名其妙'), sourceName: 'JM');
      expect(info.fault, NetFault.unknown);
      expect(info.message, isNot(contains('StateError')));
      // 原文仍然保留在 detail 里，方便排查
      expect(info.detail, contains('莫名其妙'));
    });
  });
}
