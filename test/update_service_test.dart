/// 检查新版本：版本号比较与更新信息解析
///
/// 版本号按字符串比会得出「1.1.9 比 1.1.10 新」这种错结论，
/// 一旦搞错，用户就会一直看到「发现新版本」或者永远看不到。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jm_reader/app_info.dart';
import 'package:jm_reader/services/update_service.dart';

void main() {
  group('compareVersion', () {
    test('按数字段比：1.1.10 比 1.1.9 新', () {
      expect(UpdateService.compareVersion('1.1.10', '1.1.9'), greaterThan(0));
      expect(UpdateService.compareVersion('1.1.9', '1.1.10'), lessThan(0));
    });

    test('段数不一样也能比', () {
      expect(UpdateService.compareVersion('1.2', '1.1.9'), greaterThan(0));
      expect(UpdateService.compareVersion('1.1', '1.1.0'), 0);
    });

    test('前面带 v、后面带后缀都不影响', () {
      expect(UpdateService.compareVersion('v1.1.5', '1.1.4'), greaterThan(0));
      expect(UpdateService.compareVersion('1.1.5-beta', '1.1.5'), 0);
    });

    test('相同版本返回 0', () {
      expect(UpdateService.compareVersion(AppInfo.version, AppInfo.version), 0);
    });
  });

  group('parsePayload', () {
    test('JSON 格式', () {
      final update = UpdateService.parsePayload(
        '{"version":"1.1.6","url":"https://a/b.apk","notes":"修了下载"}',
      );

      expect(update, isNotNull);
      expect(update!.version, '1.1.6');
      expect(update.url, 'https://a/b.apk');
      expect(update.notes, '修了下载');
    });

    test('download / changelog 这两个别名也认', () {
      final update = UpdateService.parsePayload(
        '{"version":"2.0","download":"https://a/b.apk","changelog":"大更新"}',
      );

      expect(update!.url, 'https://a/b.apk');
      expect(update.notes, '大更新');
    });

    test('带 BOM、前后有空行也能解析', () {
      final update = UpdateService.parsePayload(
        '\uFEFF\n\n{"version":"1.1.6"}\n',
      );

      expect(update!.version, '1.1.6');
    });

    test('纯文本：第一行版本号、第二行地址、剩下当说明', () {
      final update = UpdateService.parsePayload(
        '1.1.6\nhttps://a/b.apk\n修了下载\n新增排序',
      );

      expect(update!.version, '1.1.6');
      expect(update.url, 'https://a/b.apk');
      expect(update.notes, contains('新增排序'));
    });

    test('只给了版本号也能用', () {
      expect(UpdateService.parsePayload('1.1.6')!.url, isEmpty);
    });

    test('空内容、坏 JSON、缺版本号都返回 null，而不是抛异常', () {
      expect(UpdateService.parsePayload(''), isNull);
      expect(UpdateService.parsePayload('   '), isNull);
      expect(UpdateService.parsePayload('{坏掉的'), isNull);
      expect(UpdateService.parsePayload('{"url":"https://a"}'), isNull);
    });
  });

  group('candidates / mirrors', () {
    test('填 GitHub 原地址会补上 jsDelivr 的几套入口和公共加速', () {
      final list = UpdateService.candidates(
        'https://raw.githubusercontent.com/EAXMAX123/eam-update/main/update.json',
      );

      expect(
        list.first,
        'https://raw.githubusercontent.com/EAXMAX123/eam-update/main/update.json',
      );
      expect(
        list,
        contains(
          'https://cdn.jsdelivr.net/gh/EAXMAX123/eam-update@main/update.json',
        ),
      );
      expect(
        list,
        contains(
          'https://fastly.jsdelivr.net/gh/EAXMAX123/eam-update@main/update.json',
        ),
      );
      expect(
        list,
        contains(
          'https://ghproxy.net/https://raw.githubusercontent.com/'
          'EAXMAX123/eam-update/main/update.json',
        ),
      );
    });

    test('反过来填 jsDelivr 也会补上原地址和别的 CDN', () {
      final list = UpdateService.candidates(
        'https://cdn.jsdelivr.net/gh/a/b@main/c/d.json',
      );

      expect(list.first, 'https://cdn.jsdelivr.net/gh/a/b@main/c/d.json');
      expect(
        list,
        contains('https://raw.githubusercontent.com/a/b/main/c/d.json'),
      );
      expect(list, contains('https://gcore.jsdelivr.net/gh/a/b@main/c/d.json'));
    });

    test('展开出来的地址不重复', () {
      final list = UpdateService.candidates(AppInfo.updateCheckUrl);

      expect(list.toSet(), hasLength(list.length));
    });

    test('换行、逗号、空格都能分隔，重复的只留一个', () {
      final list = UpdateService.candidates(
        'https://a.example/x.json, https://b.example/y.json\n'
        'https://a.example/x.json',
      );

      expect(list, ['https://a.example/x.json', 'https://b.example/y.json']);
    });

    test('别的地址不会被改写', () {
      expect(UpdateService.mirrors('https://my.site/update.json'), isEmpty);
      expect(UpdateService.candidates('https://my.site/update.json'), [
        'https://my.site/update.json',
      ]);
    });

    test('空内容返回空表', () {
      expect(UpdateService.candidates(''), isEmpty);
      expect(UpdateService.candidates('   '), isEmpty);
    });

    test('内置地址能展开出多个入口，说明它是可用的', () {
      expect(
        UpdateService.candidates(AppInfo.updateCheckUrl).length,
        greaterThan(3),
      );
    });
  });

  group('requestHeaders', () {
    test('请求头全是 ASCII —— 混进中文会让请求非法、服务器直接断连', () {
      final headers = UpdateService.requestHeaders();

      expect(headers, isNotEmpty);
      for (final entry in headers.entries) {
        expect(isAscii(entry.key), isTrue, reason: '头名不能有非 ASCII：${entry.key}');
        expect(
          isAscii(entry.value),
          isTrue,
          reason: '头值不能有非 ASCII：${entry.key} = ${entry.value}',
        );
      }
    });

    test('User-Agent 用纯英文名，不是界面上的中文名', () {
      final ua = UpdateService.requestHeaders()[HttpHeaders.userAgentHeader]!;

      expect(ua, contains(AppInfo.asciiName));
      expect(ua, isNot(contains(AppInfo.name)));
    });

    test('应用名本身是中文，所以不能直接拿来拼请求头', () {
      expect(isAscii(AppInfo.name), isFalse);
      expect(isAscii(AppInfo.asciiName), isTrue);
    });
  });

  group('downloadCandidates', () {
    const apk = 'https://github.com/u/r/releases/download/v1.0.0/a.apk';

    test('GitHub 下载地址展开成「加速站在前、原始地址兜底」', () {
      final list = UpdateService.downloadCandidates(apk);

      expect(list.length, UpdateService.downloadMirrors.length + 1);
      expect(list.first, 'https://gh-proxy.com/$apk');
      expect(list.last, apk);
    });

    test('加速站里带的都是原始地址本身，不是别的路径', () {
      for (final candidate in UpdateService.downloadCandidates(apk).take(3)) {
        expect(candidate, endsWith('/releases/download/v1.0.0/a.apk'));
      }
    });

    test('不是 GitHub 的地址原样返回，不套加速站', () {
      expect(UpdateService.downloadCandidates('https://a.com/b.apk'), [
        'https://a.com/b.apk',
      ]);
    });

    test('空地址返回空表，别拿空串去请求', () {
      expect(UpdateService.downloadCandidates('   '), isEmpty);
    });
  });
}

bool isAscii(String value) => value.codeUnits.every((unit) => unit < 128);
