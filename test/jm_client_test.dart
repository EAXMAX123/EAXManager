// 线路列表解析与异常翻译的单元测试
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jm_reader/jm/jm_client.dart';
import 'package:jm_reader/jm/jm_exception.dart';
import 'package:jm_reader/net/net_error.dart';

void main() {
  group('parseDomainServerPayload', () {
    test('解析官方新格式（对象 + jm3_Server 带线路名）', () {
      final names = <String, String>{};
      final domains = JmClient.parseDomainServerPayload(const {
        'Setting': ['www.cdnhjk.net', 'www.cdngwc.cc'],
        'Server': ['www.cdnhjk.net', 'www.cdngwc.cc'],
        'jm3_Server': [
          ['www.cdnhjk.net', '線路1'],
          ['www.cdngwc.cc', '線路2'],
          ['www.cdnutc.me', '線路5'],
        ],
      }, names);

      // jm3_Server 排在前面，且重复项被去掉
      expect(domains, ['www.cdnhjk.net', 'www.cdngwc.cc', 'www.cdnutc.me']);
      expect(names['www.cdnutc.me'], '線路5');
      expect(names.length, 3);
    });

    test('兼容旧的数组格式', () {
      final names = <String, String>{};
      final domains = JmClient.parseDomainServerPayload(const [
        'www.cdnhjk.net',
        'www.cdngwc.cc',
      ], names);

      expect(domains, ['www.cdnhjk.net', 'www.cdngwc.cc']);
      expect(names, isEmpty);
    });

    test('无法识别的结构返回空列表而不是抛异常', () {
      final names = <String, String>{};
      expect(JmClient.parseDomainServerPayload('oops', names), isEmpty);
      expect(
        JmClient.parseDomainServerPayload(const <String, dynamic>{}, names),
        isEmpty,
      );
    });
  });

  group('toJmException', () {
    final client = JmClient();

    test('连接被重置时给出换线路的提示', () {
      final error = DioException(
        requestOptions: RequestOptions(path: '/search'),
        type: DioExceptionType.connectionError,
        error: const SocketException(
          'Connection reset by peer',
          osError: OSError('Connection reset by peer', 104),
        ),
      );

      final converted = client.toJmException(error);
      expect(converted.kind, JmErrorKind.network);
      // 现在的文案会说清楚「被掐断」并给出下一步动作，不再是原来的「屏蔽」
      expect(converted.message, contains('掐断'));
      expect(converted.message, contains('重试'));
    });

    test('超时有单独提示', () {
      final error = DioException(
        requestOptions: RequestOptions(path: '/search'),
        type: DioExceptionType.connectionTimeout,
      );

      expect(client.toJmException(error).message, contains('超时'));
    });

    test('已经是 JmException 时原样返回', () {
      final original = JmException(JmErrorKind.notFound, '本子不存在');
      expect(client.toJmException(original), same(original));
    });
  });

  group('probeFailureMessage', () {
    final client = JmClient();

    test('线路全不通时只说是哪几条不通，不再单点某个域名、也不再甩英文原文', () {
      final error = DioException(
        requestOptions: RequestOptions(path: '/search'),
        type: DioExceptionType.connectionError,
        error: const NetUnreachableException('www.cdnutc.me', attempts: 2),
      );

      final message = client.probeFailureMessage(error, 5);

      expect(message, contains('5 条线路全部连不上'));
      expect(message, contains('代理'));
      // 之前会把最后试的那个域名和 DioException 原文一起抛给用户
      expect(message, isNot(contains('www.cdnutc.me')));
      expect(message, isNot(contains('DioException')));
      expect(message, isNot(contains('candidates')));
    });

    test('全都返回被限制时提示换线路或开代理', () {
      final message = client.probeFailureMessage(
        JmException.restricted('IP 被限制访问，请更换域名或开启代理'),
        5,
      );

      expect(message, contains('被限制'));
      expect(message, contains('代理'));
      expect(message, isNot(contains('JmException')));
    });

    test('一条都没试成时用候选总数，不会写出「0 条」', () {
      expect(client.probeFailureMessage(null, 0), contains('线路全部连不上'));
      expect(client.probeFailureMessage(null, 0), isNot(contains('0 条')));
    });
  });
}
