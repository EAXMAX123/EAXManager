/// 哔咔协议测试
///
/// 期望值是用参考实现（astrbot_plugin_pica 的 HMAC-SHA256 签名）算出来的，
/// 签名只要有一个字节不一致，哔咔服务器就会返回 401 或假的空响应。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:jm_reader/jm/jm_storage.dart';
import 'package:jm_reader/source/comic_source.dart';
import 'package:jm_reader/source/pica/pica_client.dart';
import 'package:jm_reader/source/pica/pica_source.dart';

void main() {
  group('PicaClient.sign 与参考实现一致', () {
    test('GET 本子详情', () {
      expect(
        PicaClient.sign('GET', 'comics/123456', '1700000000'),
        '1d32a175d9ee7dc780a2e44d61e2382ccace63fd40f9475ac7ccc0350b9d349c',
      );
    });

    test('POST 高级搜索（签名包含 query）', () {
      expect(
        PicaClient.sign('POST', 'comics/advanced-search?page=1', '1700000000'),
        'ecd1f69f942bfde8a97fde6a64590e8d3bdd677e733f6f7bc4106150348a8778',
      );
    });

    test('POST 登录', () {
      expect(
        PicaClient.sign('POST', 'auth/sign-in', '1700000000'),
        'e0b44e51a9012bd617826c426832e92b69c60043236d209b165e0848ff71e6c5',
      );
    });

    test('方法大小写不影响结果', () {
      expect(
        PicaClient.sign('post', 'auth/sign-in', '1700000000'),
        PicaClient.sign('POST', 'auth/sign-in', '1700000000'),
      );
    });
  });

  group('PicaClient.mediaUrl', () {
    test('拼成 {fileServer}/static/{path}', () {
      expect(
        PicaClient.mediaUrl({
          'fileServer': 'https://storage1.picacomic.com',
          'path': 'abc-123.jpg',
        }),
        'https://storage1.picacomic.com/static/abc-123.jpg',
      );
    });

    test('字段缺失时返回空串', () {
      expect(PicaClient.mediaUrl(const {}), '');
      expect(PicaClient.mediaUrl({'path': 'a.jpg'}), '');
    });
  });

  group('SourceId', () {
    test('key 与 parse 可以往返', () {
      const sid = SourceId('pica', '5f2a1b');
      expect(sid.key, 'pica:5f2a1b');
      expect(SourceId.parse('pica:5f2a1b'), sid);
    });

    test('没有源前缀时按 jm 处理（兼容老数据）', () {
      expect(SourceId.parse('1474516'), const SourceId('jm', '1474516'));
    });

    test('不同源的相同 ID 不相等', () {
      expect(const SourceId('jm', '123'), isNot(const SourceId('eh', '123')));
    });
  });

  group('JmStorage.sourceRoot', () {
    test('jm 保持原目录，已下载的书不会找不到', () {
      expect(
        JmStorage.sourceRoot('/storage/emulated/0/JM', 'jm'),
        '/storage/emulated/0/JM',
      );
    });

    test('其它源用同级目录', () {
      expect(
        JmStorage.sourceRoot('/storage/emulated/0/JM', 'pica'),
        '/storage/emulated/0/Pica',
      );
      expect(
        JmStorage.sourceRoot('/storage/emulated/0/Download/JM', 'eh'),
        '/storage/emulated/0/Download/EH',
      );
    });
  });

  group('PicaSource.parseJwtExpire', () {
    String jwt(Object payload) {
      final body = base64Url
          .encode(utf8.encode(jsonEncode(payload)))
          .replaceAll('=', '');
      return 'header.$body.signature';
    }

    test('解析出 exp', () {
      expect(PicaSource.parseJwtExpire(jwt({'exp': 1700000000})), 1700000000);
    });

    test('没有 exp 或格式不对时返回 0', () {
      expect(PicaSource.parseJwtExpire(jwt({'sub': 'x'})), 0);
      expect(PicaSource.parseJwtExpire('not-a-jwt'), 0);
    });
  });

  group('SearchMode', () {
    test('未知 key 回退到综合', () {
      expect(SearchMode.parse('nope'), SearchMode.site);
      expect(SearchMode.parse('author'), SearchMode.author);
    });
  });
}
