/// 识图模块的单元测试
///
/// 识图站的返回只能靠固定样本锁住 —— 真去请求的话结果会随时间变，
/// 而且 SauceNAO 匿名通道每 30 秒只给 3 次，跑测试会把额度耗光。
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:jm_reader/source/image_search/image_prep.dart';
import 'package:jm_reader/source/image_search/image_search_models.dart';
import 'package:jm_reader/source/image_search/google_lens_client.dart';
import 'package:jm_reader/source/image_search/image_search_service.dart';
import 'package:jm_reader/source/image_search/iqdb_client.dart';
import 'package:jm_reader/source/image_search/saucenao_client.dart';

/// SauceNAO 结果页：一条正常结果 + 一条被隐藏的低相似度结果 + 提示节点
const String _saucenaoHtml = '''
<div class="result"><table class="resulttable"><tr>
<td class="resulttableimage"><div class="resultimage"><a href="https://saucenao.com/x" class="linkify">
<img id="resImage0" title="Index #9: Danbooru - e511f56edbcb169b0670b8b14d5e0da3_0.jpg"
src="https://img3.saucenao.com/booru/e/5/e511.jpg" border="0"/></a></div></td>
<td class="resulttablecontent"><div class="resultmatchinfo">
<div class="resultsimilarityinfo">93.72%</div>
<div class="resultmiscinfo"><a href="https://danbooru.donmai.us/post/show/12213877">
<img src="images/static/siteicons/danbooru.ico"/></a></div></div>
<div class="resultcontent"><div class="resulttitle"><strong>Creator: </strong>torino aqua<br /></div>
<div class="resultcontentcolumn"><strong>Source: </strong>
<a href="https://x.com/TorinoAqua/status/2100902205171937298">x.com</a><br />
<strong>Material: </strong>genshin impact<br /></div></div></td></tr></table></div>
<div class="result" id="result-hidden-notification" onclick="showHidden()">Low similarity hidden</div>
<div class="result hidden"><table class="resulttable"><tr>
<td class="resulttableimage"><div class="resultimage"><img title="Index #0: H-Magazines - 100.jpg"
src="images/static/blocked.gif"/></div></td>
<td class="resulttablecontent"><div class="resultmatchinfo">
<div class="resultsimilarityinfo">43.17%</div></div></div></td></tr></table></div>
<div class="result"><table class="resulttable"><tr>
<td class="resulttableimage"><div class="resultimage"><a href="https://saucenao.com/y" class="linkify">
<img title="Index #5: Pixiv - 12345_p0.jpg" src="/res/pixiv/1/2/3.jpg"/></a></div></td>
<td class="resulttablecontent"><div class="resultmatchinfo">
<div class="resultsimilarityinfo">71.5%</div>
<div class="resultmiscinfo"><a href="https://www.pixiv.net/artworks/12345">
<img src="images/static/siteicons/pixiv.ico"/></a></div></div>
<div class="resultcontent"><div class="resulttitle"><strong>Title: </strong>テスト本<br /></div>
<div class="resultcontentcolumn"><strong>Author: </strong>テスト絵師<br />
<strong>Member: </strong>67890<br /></div></div></td></tr></table></div>
''';

/// IQDB 结果页：Best match + Possible match
const String _iqdbHtml = '''
<div class="pages">
<div><table><tr><th>Best match</th></tr>
<tr><td class='image'><a href="//danbooru.donmai.us/posts/12213877">
<img src='/danbooru/e/5/1/e511.jpg' alt="Rating: s"></a></td></tr>
<tr><td><img alt="icon" src="/icon/danbooru.ico" class="service-icon">Danbooru
<span class="el"><a href="//gelbooru.com/index.php"><img alt="icon" src="/icon/gelbooru.png"
class="service-icon">Gelbooru</a></span></td></tr>
<tr><td>1600×2429 [Safe]</td></tr><tr><td>96% similarity</td></tr></table></div>
<div><table><tr><th>Possible match</th></tr>
<tr><td class='image'><a href="//konachan.com/post/show/1">
<img src='/konachan/aa/bb.jpg' alt="Rating: q"></a></td></tr>
<tr><td><img alt="icon" src="/icon/konachan.ico" class="service-icon">Konachan</td></tr>
<tr><td>800×1200 [Questionable]</td></tr><tr><td>82.5% similarity</td></tr></table></div>
</div>
''';

/// 造一张四周纯色、中间有内容的图
img.Image _framed({
  required int size,
  required int inset,
  int borderRgb = 0xFFFFFF,
  int contentRgb = 0x3366CC,
}) {
  final image = img.Image(width: size, height: size);
  img.fill(image, color: img.ColorRgb8(
    (borderRgb >> 16) & 0xFF,
    (borderRgb >> 8) & 0xFF,
    borderRgb & 0xFF,
  ));
  img.fillRect(
    image,
    x1: inset,
    y1: inset,
    x2: size - 1 - inset,
    y2: size - 1 - inset,
    color: img.ColorRgb8(
      (contentRgb >> 16) & 0xFF,
      (contentRgb >> 8) & 0xFF,
      contentRgb & 0xFF,
    ),
  );
  return image;
}

void main() {
  group('ImagePrep.autocrop', () {
    test('裁掉四周的纯色边框', () {
      final source = _framed(size: 400, inset: 40);
      final cropped = ImagePrep.autocrop(source);

      expect(cropped.width, 320);
      expect(cropped.height, 320);
    });

    test('四周不是纯色时不裁', () {
      // 用噪点铺满，边框色不统一，应该原样返回
      final source = img.Image(width: 400, height: 400);
      for (var y = 0; y < 400; y++) {
        for (var x = 0; x < 400; x++) {
          source.setPixelRgb(x, y, (x * 7) % 256, (y * 11) % 256, (x + y) % 256);
        }
      }
      final cropped = ImagePrep.autocrop(source);

      expect(cropped.width, 400);
      expect(cropped.height, 400);
    });

    test('黑边也能裁', () {
      final source = _framed(size: 400, inset: 30, borderRgb: 0x000000);
      final cropped = ImagePrep.autocrop(source);

      expect(cropped.width, 340);
    });

    test('图太小就原样返回', () {
      final source = _framed(size: 100, inset: 10);
      final cropped = ImagePrep.autocrop(source);

      expect(cropped.width, 100);
    });
  });

  group('ImagePrep.prepare', () {
    test('解不开的字节返回 null', () {
      expect(ImagePrep.prepare(Uint8List.fromList([1, 2, 3, 4])), isNull);
    });

    test('超长边会被缩到上限以内，并编成 JPEG', () {
      final source = _framed(size: 2400, inset: 0);
      final bytes = img.encodeJpg(source);
      final prepared = ImagePrep.prepare(bytes);

      expect(prepared, isNotNull);
      expect(prepared!.width, lessThanOrEqualTo(ImagePrep.maxSide));
      expect(prepared.height, lessThanOrEqualTo(ImagePrep.maxSide));
      // JPEG 的魔数
      expect(prepared.bytes[0], 0xFF);
      expect(prepared.bytes[1], 0xD8);
    });

    test('小图不会被放大', () {
      final source = _framed(size: 300, inset: 0);
      final prepared = ImagePrep.prepare(img.encodeJpg(source));

      expect(prepared!.width, 300);
    });
  });

  group('ImagePrep.regions', () {
    test('竖长图切成三段，留出重叠', () {
      final source = img.Image(width: 600, height: 1800);
      img.fill(source, color: img.ColorRgb8(200, 200, 200));
      final prepared = ImagePrep.prepare(img.encodeJpg(source))!;

      final regions = ImagePrep.regions(prepared);

      expect(regions.length, 3);
      expect(regions.map((e) => e.label).toList(), ['上段', '中段', '下段']);
      for (final region in regions) {
        expect(region.bytes.length, greaterThan(0));
      }
    });

    test('正常封面比例不切', () {
      final source = img.Image(width: 800, height: 1000);
      img.fill(source, color: img.ColorRgb8(200, 200, 200));
      final prepared = ImagePrep.prepare(img.encodeJpg(source))!;

      expect(ImagePrep.regions(prepared), isEmpty);
    });
  });

  group('SauceNAO 结果解析', () {
    test('读出相似度、图库名、字段和来源链接', () {
      final matches = SauceNaoClient.parseResults(_saucenaoHtml);

      expect(matches.length, 2);

      final first = matches.first;
      expect(first.engine, 'SauceNAO');
      expect(first.similarity, closeTo(93.72, 0.01));
      expect(first.index, 'Danbooru');
      expect(first.author, 'torino aqua');
      expect(first.fields['Source'], 'x.com');
      expect(first.fields['Material'], 'genshin impact');
      expect(first.sourceUrl, 'https://danbooru.donmai.us/post/show/12213877');
    });

    test('跳过隐藏结果和纯提示节点', () {
      final matches = SauceNaoClient.parseResults(_saucenaoHtml);

      expect(matches.any((e) => e.similarity == 43.17), isFalse);
      expect(matches.any((e) => e.index == 'H-Magazines'), isFalse);
    });

    test('按相似度降序排列', () {
      final matches = SauceNaoClient.parseResults(_saucenaoHtml);

      expect(matches.map((e) => e.similarity).toList(), [93.72, 71.5]);
    });

    test('pixiv 结果的标题和作者取对', () {
      final pixiv = SauceNaoClient.parseResults(
        _saucenaoHtml,
      ).firstWhere((e) => e.index == 'Pixiv');

      expect(pixiv.title, 'テスト本');
      expect(pixiv.author, 'テスト絵師');
      expect(pixiv.keywords, ['テスト本', 'テスト絵師']);
    });

    test('相对路径的缩略图补成绝对地址', () {
      final pixiv = SauceNaoClient.parseResults(
        _saucenaoHtml,
      ).firstWhere((e) => e.index == 'Pixiv');

      expect(pixiv.thumbnailUrl, 'https://saucenao.com/res/pixiv/1/2/3.jpg');
    });

    test('空页面解析出空列表', () {
      expect(SauceNaoClient.parseResults('<html><body></body></html>'), isEmpty);
    });
  });

  group('IQDB 结果解析', () {
    test('读出两条结果', () {
      final matches = IqdbClient.parseResults(_iqdbHtml);

      expect(matches.length, 2);
      expect(matches.first.engine, 'IQDB');
      expect(matches.first.similarity, 96);
      expect(matches.first.index, 'Danbooru');
      expect(matches.first.sourceUrl, 'https://danbooru.donmai.us/posts/12213877');
      expect(matches.first.thumbnailUrl, 'https://iqdb.org/danbooru/e/5/1/e511.jpg');
    });

    test('第二条按相似度排在后面', () {
      final matches = IqdbClient.parseResults(_iqdbHtml);

      expect(matches[1].index, 'Konachan');
      expect(matches[1].similarity, 82.5);
    });

    test('没有匹配时是空列表', () {
      expect(IqdbClient.parseResults('<div>No relevant matches</div>'), isEmpty);
    });
  });

  group('Google Lens 结果地址', () {
    test('正常的 Location 原样返回', () {
      expect(
        GoogleLensClient.resultUrlFrom(
          'https://www.google.com/search?vsrid=abc&udm=26',
        ),
        'https://www.google.com/search?vsrid=abc&udm=26',
      );
    });

    test('协议相对的地址补上 https', () {
      expect(
        GoogleLensClient.resultUrlFrom('//www.google.com/search?vsrid=abc'),
        'https://www.google.com/search?vsrid=abc',
      );
    });

    test('只有路径的补上域名', () {
      expect(
        GoogleLensClient.resultUrlFrom('/search?vsrid=abc'),
        'https://www.google.com/search?vsrid=abc',
      );
    });

    test('空值返回 null，别把空地址丢给浏览器', () {
      expect(GoogleLensClient.resultUrlFrom(null), isNull);
      expect(GoogleLensClient.resultUrlFrom(''), isNull);
      expect(GoogleLensClient.resultUrlFrom('   '), isNull);
    });

    test('不是 Google 的地址一律拒绝', () {
      expect(
        GoogleLensClient.resultUrlFrom('https://example.com/search?vsrid=abc'),
        isNull,
      );
    });
  });

  group('结果合并', () {
    test('同一个来源页面只留相似度最高的那条', () {
      final merged = ImageSearchService.mergeMatches([
        const ImageMatch(
          engine: 'IQDB',
          index: 'Danbooru',
          similarity: 80,
          sourceUrl: 'https://a/1',
        ),
        const ImageMatch(
          engine: 'SauceNAO',
          index: 'Danbooru',
          similarity: 95,
          sourceUrl: 'https://a/1',
        ),
      ]);

      expect(merged.length, 1);
      expect(merged.first.similarity, 95);
      expect(merged.first.engine, 'SauceNAO');
    });

    test('不同来源分开保留，并按相似度排序', () {
      final merged = ImageSearchService.mergeMatches([
        const ImageMatch(
          engine: 'IQDB',
          index: 'Konachan',
          similarity: 50,
          sourceUrl: 'https://a/2',
        ),
        const ImageMatch(
          engine: 'SauceNAO',
          index: 'Pixiv',
          similarity: 90,
          sourceUrl: 'https://a/1',
        ),
      ]);

      expect(merged.length, 2);
      expect(merged.first.index, 'Pixiv');
    });

    test('两个站给的 danbooru 地址形式不同，也算同一条', () {
      final merged = ImageSearchService.mergeMatches([
        const ImageMatch(
          engine: 'IQDB',
          index: 'Danbooru',
          similarity: 96,
          sourceUrl: 'https://danbooru.donmai.us/posts/12213877',
        ),
        const ImageMatch(
          engine: 'SauceNAO',
          index: 'Danbooru',
          similarity: 93.44,
          sourceUrl: 'https://danbooru.donmai.us/post/show/12213877',
          title: 'genshin impact',
        ),
      ]);

      expect(merged.length, 1);
      expect(merged.first.similarity, 96);
    });

    test('没有来源链接时按站和图库区分，不会全挤成一条', () {
      final merged = ImageSearchService.mergeMatches([
        const ImageMatch(
          engine: 'IQDB',
          index: 'Danbooru',
          similarity: 96,
          title: 'A',
        ),
        const ImageMatch(
          engine: 'IQDB',
          index: 'Danbooru',
          similarity: 80,
          title: 'B',
        ),
      ]);

      expect(merged.length, 2);
    });
  });

  group('ImageMatch', () {
    test('关键词去重且去掉空白项', () {
      const match = ImageMatch(
        engine: 'SauceNAO',
        index: 'Pixiv',
        similarity: 90,
        title: ' 同一本 ',
        author: '同一本',
      );

      expect(match.keywords, ['同一本']);
    });

    test('相似度门槛判断', () {
      const match = ImageMatch(
        engine: 'IQDB',
        index: 'Danbooru',
        similarity: 59.9,
      );

      expect(match.reliable(60), isFalse);
      expect(match.reliable(50), isTrue);
    });
  });
}
