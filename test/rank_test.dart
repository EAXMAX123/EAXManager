/// 排行榜：四家源各自对外报什么档位
///
/// 各站点给的档位本来就不一样——年榜只有 EH 有、哔咔官方没有分类、
/// Pixiv 镜像里 `week_male` / `month_r18` 这类组合直接 500。所以这里把
/// 「每个源报哪些档位」锁住：以后改动把档位弄丢、或者报出点不通的组合，
/// 测试会先报出来，而不是等用户点了才发现。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:jm_reader/jm/jm_client.dart';
import 'package:jm_reader/source/comic_source.dart';
import 'package:jm_reader/source/eh/eh_source.dart';
import 'package:jm_reader/source/jm_source.dart';
import 'package:jm_reader/source/pica/pica_source.dart';
import 'package:jm_reader/source/pixiv/pixiv_source.dart';

List<String> keysOf(List<RankOption> options) => [
  for (final option in options) option.key,
];

void main() {
  group('JM', () {
    final source = JmSource(JmClient());

    test('时间档四档，没有年榜', () {
      expect(keysOf(source.rankTimes), ['day', 'week', 'month', 'all']);
    });

    test('分类档九档，单本 / 短篇 / 美漫都在', () {
      final categories = source.rankCategories('week');
      expect(categories.length, 9);
      expect(keysOf(categories), containsAll(['single', 'short', 'meiman']));
    });

    test('分类档不跟着时间变', () {
      expect(
        keysOf(source.rankCategories('day')),
        keysOf(source.rankCategories('all')),
      );
    });
  });

  group('哔咔', () {
    final source = PicaSource();

    test('时间档三档', () {
      expect(keysOf(source.rankTimes), ['day', 'week', 'month']);
    });

    test('官方没有分类这一档，界面上不显示第三行', () {
      expect(source.rankCategories('day'), isEmpty);
      expect(source.rankCategories('month'), isEmpty);
    });
  });

  group('EH', () {
    final source = EhSource();

    test('四家里只有它有「今年」', () {
      expect(keysOf(source.rankTimes), ['yesterday', 'month', 'year', 'all']);
    });

    test('没有分类这一档', () {
      expect(source.rankCategories('year'), isEmpty);
    });
  });

  group('Pixiv', () {
    final source = PixivSource();

    test('时间档三档', () {
      expect(keysOf(source.rankTimes), ['day', 'week', 'month']);
    });

    test('分类档跟着时间变', () {
      expect(keysOf(source.rankCategories('day')), [
        'all',
        'male',
        'female',
        'ai',
        'r18',
        'male_r18',
        'female_r18',
      ]);
      expect(keysOf(source.rankCategories('week')), [
        'all',
        'original',
        'rookie',
        'r18',
      ]);
      expect(keysOf(source.rankCategories('month')), ['all']);
    });

    test('不报镜像上会 500 的组合', () {
      // 实测 week_male / week_female / week_ai / month_* 全是 500
      expect(keysOf(source.rankCategories('week')), isNot(contains('male')));
      expect(keysOf(source.rankCategories('week')), isNot(contains('ai')));
      expect(keysOf(source.rankCategories('month')).length, 1);
    });

    test('每个时间档至少有一个能选的分类', () {
      for (final time in source.rankTimes) {
        expect(source.rankCategories(time.key), isNotEmpty);
      }
    });
  });

  group('档位数据结构', () {
    test('label 都是给用户看的中文，key 都是给接口的英文', () {
      final source = JmSource(JmClient());
      for (final option in [...source.rankTimes, ...source.rankCategories('week')]) {
        expect(option.key, isNotEmpty);
        expect(option.label, isNotEmpty);
        expect(option.key, isNot(contains(' ')));
      }
    });
  });
}
