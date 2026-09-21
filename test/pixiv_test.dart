import 'package:flutter_test/flutter_test.dart';
import 'package:jm_reader/source/comic_source.dart';
import 'package:jm_reader/source/pixiv/pixiv_client.dart';
import 'package:jm_reader/source/pixiv/pixiv_source.dart';

/// 多页作品：原图在 meta_pages 里
Map<String, dynamic> _multiPage() => {
  'id': 149931934,
  'title': '夏から秋に',
  'type': 'illust',
  'page_count': 2,
  'image_urls': {
    'large': 'https://i.pximg.net/c/600x1200_90/img-master/img/1_p0_master1200.jpg',
  },
  'meta_pages': [
    {
      'image_urls': {
        'original': 'https://i.pximg.net/img-original/img/1_p0.jpg',
      },
    },
    {
      'image_urls': {
        'original': 'https://i.pximg.net/img-original/img/1_p1.jpg',
      },
    },
  ],
  'meta_single_page': <String, dynamic>{},
  'user': {'id': 1498166, 'name': '貓臉Nekokao'},
  'tags': [
    {'name': 'オリジナル', 'translated_name': '原创'},
    {'name': '猫', 'translated_name': '猫'},
    {'name': '猫', 'translated_name': '猫'},
    {'name': '無題', 'translated_name': null},
  ],
  'create_date': '2026-09-21T18:06:57+09:00',
  'x_restrict': 0,
  'illust_ai_type': 0,
};

/// 单页作品：原图在 meta_single_page 里
Map<String, dynamic> _singlePage() => {
  'id': 1,
  'title': '深夜',
  'type': 'illust',
  'page_count': 1,
  'image_urls': {
    'large': 'https://i.pximg.net/c/600x1200_90/img-master/img/1_p0_master1200.jpg',
  },
  'meta_pages': <dynamic>[],
  'meta_single_page': {
    'original_image_url': 'https://i.pximg.net/img-original/img/1_p0.jpg',
  },
  'user': {'id': 9, 'name': '画师'},
  'tags': <dynamic>[],
  'create_date': '2026-09-21T18:13:29+09:00',
};

void main() {
  group('PixivConst.parseList', () {
    test('空格 / 逗号 / 分号 / 换行都能当分隔符', () {
      expect(PixivConst.parseList('a b, c;d\ne'), ['a', 'b', 'c', 'd', 'e']);
    });

    test('空白串得到空列表', () {
      expect(PixivConst.parseList('   \n  '), isEmpty);
    });

    test('重复项只留一个', () {
      expect(PixivConst.parseList('a,a, a ,b'), ['a', 'b']);
    });
  });

  group('地址清理', () {
    test('镜像地址补 https://、去掉结尾斜杠', () {
      expect(PixivClient.cleanBases(['api.x.com/', 'https://api.y.com']), [
        'https://api.x.com',
        'https://api.y.com',
      ]);
    });

    test('反代地址只留域名', () {
      expect(PixivClient.cleanProxies(['https://i.pixiv.re/', 'i.pixiv.nl']), [
        'i.pixiv.re',
        'i.pixiv.nl',
      ]);
    });

    test('清理时丢掉空项', () {
      expect(PixivClient.cleanBases(['', '  ']), isEmpty);
      expect(PixivClient.cleanProxies(['', '/']), isEmpty);
    });
  });

  group('图片地址改写', () {
    test('把 i.pximg.net 换成当前反代域名', () {
      final client = PixivClient(imageProxies: ['proxy.test']);
      expect(
        client.imageUrl(
          'https://i.pximg.net/img-original/img/1_p0.jpg',
        ),
        'https://proxy.test/img-original/img/1_p0.jpg',
      );
    });

    test('不是 pximg 的地址原样返回', () {
      final client = PixivClient(imageProxies: ['proxy.test']);
      expect(client.imageUrl('https://example.com/a.jpg'), 'https://example.com/a.jpg');
      expect(client.imageUrl(''), '');
    });

    test('换反代用下一个域名，走到头会绕回第一个', () {
      final client = PixivClient(imageProxies: ['a.test', 'b.test']);
      expect(client.imageProxyHost, 'a.test');
      client.rotateImageProxy();
      expect(client.imageProxyHost, 'b.test');
      client.rotateImageProxy();
      expect(client.imageProxyHost, 'a.test');
    });

    test('只有一个反代时不会越界', () {
      final client = PixivClient(imageProxies: ['only.test']);
      client.rotateImageProxy();
      client.rotateImageProxy();
      expect(client.imageProxyHost, 'only.test');
    });
  });

  group('reconfigure', () {
    test('传空列表退回内置默认', () {
      final client = PixivClient(
        apiBases: ['https://a.test'],
        imageProxies: ['a.test'],
      );
      client.reconfigure(apiBases: const [], imageProxies: const []);
      expect(client.apiBases, PixivConst.defaultApiBases);
      expect(client.imageProxies, PixivConst.defaultImageProxies);
    });

    test('传了就用传的，并且顺手清理', () {
      final client = PixivClient();
      client.reconfigure(
        apiBases: ['api.mine.com/'],
        imageProxies: ['https://img.mine.com/'],
      );
      expect(client.apiBases, ['https://api.mine.com']);
      expect(client.imageProxies, ['img.mine.com']);
    });

    test('只改一项时另一项保持不动', () {
      final client = PixivClient(
        apiBases: ['https://a.test'],
        imageProxies: ['a.test'],
      );
      client.reconfigure(imageProxies: ['b.test']);
      expect(client.apiBases, ['https://a.test']);
      expect(client.imageProxies, ['b.test']);
    });
  });

  group('画质档位', () {
    test('默认原图，改过之后生效', () {
      final source = PixivSource();
      expect(source.imageQuality, PixivParsing.qualityOriginal);
      source.reconfigure(imageQuality: PixivParsing.qualityLarge);
      expect(source.imageQuality, PixivParsing.qualityLarge);
    });

    test('不传画质时保持原样', () {
      final source = PixivSource(imageQuality: PixivParsing.qualityLarge);
      source.reconfigure(imageProxies: ['a.test']);
      expect(source.imageQuality, PixivParsing.qualityLarge);
    });

    test('档位有中文说明', () {
      expect(PixivParsing.qualityLabel(PixivParsing.qualityOriginal), '原图');
      expect(PixivParsing.qualityLabel(PixivParsing.qualityLarge), '较大（1200px）');
    });
  });

  group('原图地址', () {
    test('多页作品从 meta_pages 取，顺序不变', () {
      expect(PixivParsing.imageUrls(_multiPage()), [
        'https://i.pximg.net/img-original/img/1_p0.jpg',
        'https://i.pximg.net/img-original/img/1_p1.jpg',
      ]);
    });

    test('单页作品从 meta_single_page 取', () {
      expect(PixivParsing.imageUrls(_singlePage()), [
        'https://i.pximg.net/img-original/img/1_p0.jpg',
      ]);
    });

    test('动图不给图片地址', () {
      final ugoira = {
        'id': 2,
        'type': 'ugoira',
        'page_count': 1,
        'meta_pages': [
          {
            'image_urls': {'original': 'https://i.pximg.net/zip.zip'},
          },
        ],
      };
      expect(PixivParsing.imageUrls(ugoira), isEmpty);
    });

    test('两个字段都没有时退回 image_urls', () {
      final bare = {
        'id': 3,
        'type': 'illust',
        'page_count': 1,
        'image_urls': {
          'large': 'https://i.pximg.net/img-master/img/3_p0_master1200.jpg',
        },
      };
      expect(PixivParsing.imageUrls(bare), [
        'https://i.pximg.net/img-master/img/3_p0_master1200.jpg',
      ]);
    });

    test('meta_pages 里全是空值时继续往下找', () {
      final partial = {
        'id': 4,
        'type': 'illust',
        'page_count': 1,
        'meta_pages': [
          {'image_urls': <String, dynamic>{}},
        ],
        'meta_single_page': {
          'original_image_url': 'https://i.pximg.net/img-original/img/4_p0.jpg',
        },
      };
      expect(PixivParsing.imageUrls(partial), [
        'https://i.pximg.net/img-original/img/4_p0.jpg',
      ]);
    });

    test('要小图时改用 1200px 那一档', () {
      final illust = {
        'id': 5,
        'type': 'illust',
        'page_count': 1,
        'meta_pages': <dynamic>[],
        'meta_single_page': {
          'original_image_url': 'https://i.pximg.net/img-original/img/5_p0.png',
        },
        'image_urls': {
          'large': 'https://i.pximg.net/c/600x1200_90/img-master/img/5_p0_master1200.jpg',
        },
      };
      expect(PixivParsing.imageUrls(illust, preferLarge: true), [
        'https://i.pximg.net/c/600x1200_90/img-master/img/5_p0_master1200.jpg',
      ]);
    });

    test('要小图但拿不到时退回原图', () {
      expect(PixivParsing.imageUrls(_singlePage(), preferLarge: true), [
        'https://i.pximg.net/c/600x1200_90/img-master/img/1_p0_master1200.jpg',
      ]);
      final onlyOriginal = {
        'id': 6,
        'type': 'illust',
        'page_count': 1,
        'meta_single_page': {
          'original_image_url': 'https://i.pximg.net/img-original/img/6_p0.jpg',
        },
      };
      expect(PixivParsing.imageUrls(onlyOriginal, preferLarge: true), [
        'https://i.pximg.net/img-original/img/6_p0.jpg',
      ]);
    });
  });

  group('其它字段解析', () {
    test('页数优先用 page_count，没有就数 meta_pages', () {
      expect(PixivParsing.pageCount(_multiPage()), 2);
      expect(
        PixivParsing.pageCount({
          'meta_pages': [<String, dynamic>{}, <String, dynamic>{}],
        }),
        2,
      );
      expect(PixivParsing.pageCount(<String, dynamic>{}), 0);
    });

    test('标签优先中文译名，没有译名就用原名，去重', () {
      expect(PixivParsing.tagsOf(_multiPage()), ['原创', '猫', '無題']);
    });

    test('标签最多留 24 个', () {
      final many = {
        'tags': [
          for (var i = 0; i < 40; i++) {'name': 'tag$i'},
        ],
      };
      expect(PixivParsing.tagsOf(many).length, 24);
    });

    test('类型缺省当插画，译名对得上', () {
      expect(PixivParsing.typeOf(<String, dynamic>{}), 'illust');
      expect(PixivParsing.typeOf({'type': 'manga'}), 'manga');
      expect(PixivParsing.typeLabel('manga'), '漫画');
      expect(PixivParsing.typeLabel('ugoira'), '动图');
      expect(PixivParsing.typeLabel('illust'), '插画');
      expect(PixivParsing.typeLabel('unknown'), '插画');
    });

    test('日期只留年月日', () {
      expect(PixivParsing.dateText('2026-09-21T18:06:57+09:00'), '2026-09-21');
      expect(PixivParsing.dateText('2026'), '2026');
      expect(PixivParsing.dateText(''), '');
    });

    test('简介剥成纯文本', () {
      expect(
        PixivParsing.plainText('第一行<br />第二行 &amp; <b>粗体</b>'),
        '第一行\n第二行 & 粗体',
      );
      expect(PixivParsing.plainText('  <p>段落</p>  '), '段落');
    });

    test('页码文件名补零并带上后缀', () {
      expect(PixivParsing.pageName(0, 'https://a/1_p0.jpg'), '00001.jpg');
      expect(PixivParsing.pageName(9, 'https://a/1_p9.png'), '00010.png');
      expect(PixivParsing.pageName(0, 'https://a/noext'), '00001.jpg');
    });

    test('后缀从地址里取，认不出就按 jpg', () {
      expect(PixivParsing.extensionOf('https://a/b.jpg?x=1'), '.jpg');
      expect(PixivParsing.extensionOf('https://a/b.PNG'), '.png');
      expect(PixivParsing.extensionOf('https://a/b'), '.jpg');
    });

    test('多个画师的结果轮流取，重复的丢掉', () {
      final merged = PixivParsing.interleave([
        [
          {'id': 1},
          {'id': 2},
        ],
        [
          {'id': 2},
          {'id': 3},
        ],
      ]);
      expect(merged.map((e) => e['id']), [1, 2, 3]);
    });
  });

  group('搜索模式', () {
    test('每个搜索模式都有对应的 search_target', () {
      for (final mode in SearchMode.values) {
        expect(
          PixivConst.searchTargets.containsKey(mode.key),
          isTrue,
          reason: '模式 ${mode.key} 没有映射',
        );
      }
    });

    test('认不出的模式退回综合', () {
      expect(PixivParsing.searchTarget('nonsense'), 'partial_match_for_tags');
      expect(PixivParsing.searchTarget('work'), 'title_and_caption');
      expect(PixivParsing.searchTarget('tag'), 'exact_match_for_tags');
    });
  });

  group('PixivSource', () {
    test('源标识正确', () {
      final source = PixivSource();
      expect(source.key, 'pixiv');
      expect(source.name, 'Pixiv');
      expect(source.folder, 'Pixiv');
    });

    test('不需要登录就能搜', () {
      expect(PixivSource().needsLogin, isFalse);
    });

    test('图片并发压到 3，免得把公共反代惹毛', () {
      expect(PixivSource().imageConcurrencyOverride, 3);
    });

    test('不支持收藏', () async {
      expect(await PixivSource().setFavorite('1', want: true), isNull);
    });
  });
}
