/// EH 源测试
///
/// EH 是这一版里唯一没法在本机对着真站点验证的源（域名被 SNI 阻断，不挂梯子
/// 拿不到页面），所以这里用贴近真实结构的 HTML 固定样本把解析逻辑锁住：
/// 以后改动把解析改坏了，测试会先报出来。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:jm_reader/source/eh/eh_account.dart';
import 'package:jm_reader/source/eh/eh_client.dart';

/// 搜索结果页样本（缩略图链接文字为空，标题在后面的链接里，和真实结构一致）
const String _searchHtml = '''
<html><body>
<p class="gpc">Showing 1 - 25 of 1,234 galleries</p>
<table class="itg">
  <tr>
    <td class="gl1c glcat"><div class="gt"><a href="https://e-hentai.org/g/1234567/abcdef1234/"><img src="https://s.exhentai.org/t/aa/bb/1.jpg" alt="First Gallery"></a></div></td>
    <td class="gl2c"><div class="glink"><a href="https://e-hentai.org/g/1234567/abcdef1234/">First Gallery</a></div></td>
  </tr>
  <tr>
    <td class="gl1c glcat"><div class="gt"><a href="https://e-hentai.org/g/7654321/deadbeef00/"><img src="https://s.exhentai.org/t/cc/dd/2.jpg" alt="Second Gallery"></a></div></td>
    <td class="gl2c"><div class="glink"><a href="https://e-hentai.org/g/7654321/deadbeef00/">Second Gallery</a></div></td>
  </tr>
  <tr><td class="gl1c glcat"></td><td class="gl2c"></td></tr>
</table>
</body></html>
''';

/// 只有缩略图链接、没有标题链接时，标题要能从 img 的 alt 里取到
const String _searchHtmlNoTextLink = '''
<html><body>
<table class="itg">
  <tr>
    <td class="gl1c glcat"><div class="gt"><a href="https://e-hentai.org/g/1234567/abcdef1234/"><img src="https://s.exhentai.org/t/aa/bb/1.jpg" alt="Alt Title"></a></div></td>
  </tr>
</table>
</body></html>
''';

/// 详情页样本
const String _galleryHtml = '''
<html><body>
<h1 id="gn">Some Gallery Title</h1>
<div id="gd1"><img src="https://s.exhentai.org/t/aa/bb/cover.jpg"></div>
<div id="gdd">
  <table>
    <tr><td class="gdt1">Favorited:</td><td class="gdt2">1,234 times</td></tr>
    <tr><td class="gdt1">Pages:</td><td class="gdt2">42</td></tr>
  </table>
</div>
<div id="gdn">UploaderName</div>
<table id="taglist">
  <tr><td class="tc">language:</td><td><a href="/?f_search=language%3Achinese">chinese</a></td></tr>
  <tr><td class="tc">female:</td><td><a href="#">big breasts</a><a href="#">sole female</a></td></tr>
</table>
</body></html>
''';

/// 页数只写在文字里（旧结构）时的兜底样本
const String _galleryHtmlTextPages = '''
<html><body>
<h1 id="gn">T</h1>
<div id="gdd"><table><tr><td class="gdt2">18 pages</td></tr></table></div>
</body></html>
''';

/// 缩略图页样本
const String _thumbHtml = '''
<html><body>
<div id="gdt">
  <a href="https://e-hentai.org/s/aaa111/1234567-1"><img src="https://s.exhentai.org/t/1.jpg"></a>
  <a href="https://e-hentai.org/s/bbb222/1234567-2"><img src="https://s.exhentai.org/t/2.jpg"></a>
  <a href="https://e-hentai.org/g/1234567/abcdef1234/"><img src="https://s.exhentai.org/t/cover.jpg"></a>
  <a href="/s/ccc333/1234567-3"><img src="https://s.exhentai.org/t/3.jpg"></a>
</div>
</body></html>
''';

/// 单页 /s/ 样本
const String _pageHtml = '''
<html><body>
<div id="i3"><a id="img" href="https://e-hentai.org/fullimg/123"><img src="https://abc.hath.network/h/xyz-1.jpg"></a></div>
</body></html>
''';

/// 榜单页样本：EH 的 Toplist 不是搜索结果那套 table.itg 结构，
/// 缩略图在 .gl1t、标题在 .gl2t，靠退化解析兜底
const String _toplistHtml = '''
<html><body>
<div id="toppane">
  <div class="itg gld">
    <div class="gl1t"><a href="https://e-hentai.org/g/1111111/aaaa1111/"><img src="https://s.exhentai.org/t/11/22/1.jpg"></a></div>
    <div class="gl2t"><a href="https://e-hentai.org/g/1111111/aaaa1111/">Top One</a></div>
  </div>
  <div class="itg gld">
    <div class="gl1t"><a href="https://e-hentai.org/g/2222222/bbbb2222/"><img src="https://s.exhentai.org/t/33/44/2.jpg"></a></div>
    <div class="gl2t"><a href="https://e-hentai.org/g/2222222/bbbb2222/">Top Two</a></div>
  </div>
</div>
</body></html>
''';

void main() {
  group('EhAccount.parsePasted', () {
    test('分号分隔的完整 Cookie', () {
      final account = EhAccount.parsePasted(
        'ipb_member_id=12345; ipb_pass_hash=abcdef; igneous=9876',
      );
      expect(account.memberId, '12345');
      expect(account.passHash, 'abcdef');
      expect(account.igneous, '9876');
      expect(account.hasLogin, isTrue);
      expect(account.canUseEx, isTrue);
    });

    test('& 分隔也能认', () {
      final account = EhAccount.parsePasted(
        'ipb_member_id=1&ipb_pass_hash=2&igneous=3',
      );
      expect(account.memberId, '1');
      expect(account.passHash, '2');
      expect(account.igneous, '3');
    });

    test('混着别的 Cookie 只挑需要的三个', () {
      final account = EhAccount.parsePasted(
        'sk=xx; ipb_member_id=7; u=8; ipb_pass_hash=hash; igneous=ign',
      );
      expect(account.memberId, '7');
      expect(account.passHash, 'hash');
      expect(account.igneous, 'ign');
    });

    test('只有表站凭据时不能走里站', () {
      final account = EhAccount.parsePasted('ipb_member_id=1; ipb_pass_hash=2');
      expect(account.hasLogin, isTrue);
      expect(account.canUseEx, isFalse);
      expect(account.baseUrl, 'https://e-hentai.org');
    });

    test('什么都没有就是未登录', () {
      expect(EhAccount.parsePasted('').hasLogin, isFalse);
      expect(EhAccount.parsePasted('随便一段文字').hasLogin, isFalse);
    });

    test('useEx 且凭据齐全时走 ExHentai', () {
      const account = EhAccount(
        memberId: '1',
        passHash: '2',
        igneous: '3',
        useEx: true,
      );
      expect(account.baseUrl, 'https://exhentai.org');
    });

    test('cookieHeader 只拼非空字段', () {
      const account = EhAccount(memberId: '1', passHash: '2');
      expect(account.cookieHeader, 'ipb_member_id=1; ipb_pass_hash=2');
    });
  });

  group('EhClient URL 工具', () {
    test('从详情页 URL 取出 gid 和 token', () {
      expect(
        EhClient.parseGalleryUrl('https://e-hentai.org/g/1234567/abcdef1234/'),
        ('1234567', 'abcdef1234'),
      );
      expect(EhClient.parseGalleryUrl('https://e-hentai.org/'), isNull);
    });

    test('本子 ID 往返', () {
      expect(EhClient.parseGalleryId('1234567-abcdef1234'), (
        '1234567',
        'abcdef1234',
      ));
      expect(EhClient.parseGalleryId('1234567'), isNull);
      expect(EhClient.parseGalleryId('-abc'), isNull);
    });

    test('sidFromGalleryUrl 生成 eh 前缀的源 ID', () {
      final sid = EhClient.sidFromGalleryUrl(
        'https://e-hentai.org/g/1234567/abcdef1234/',
      );
      expect(sid?.source, 'eh');
      expect(sid?.id, '1234567-abcdef1234');
    });

    test('pathOf 只留路径', () {
      expect(EhClient.pathOf('https://e-hentai.org/s/aaa/1-1'), '/s/aaa/1-1');
      expect(EhClient.pathOf('/s/aaa/1-1'), '/s/aaa/1-1');
      expect(EhClient.pathOf('乱写的'), '');
    });
  });

  group('EhParser 搜索结果', () {
    test('解析出本子、标题、封面和源 ID', () {
      final items = EhParser.parseSearchItems(
        _searchHtml,
        coverHeaders: const {'cookie': 'x'},
      );
      expect(items, hasLength(2));
      expect(items[0].sid.key, 'eh:1234567-abcdef1234');
      expect(items[0].title, 'First Gallery');
      expect(items[0].coverUrl, 'https://s.exhentai.org/t/aa/bb/1.jpg');
      expect(items[0].coverHeaders, const {'cookie': 'x'});
      expect(items[1].sid.key, 'eh:7654321-deadbeef00');
    });

    test('没有标题链接时用图片 alt 兜底', () {
      final items = EhParser.parseSearchItems(
        _searchHtmlNoTextLink,
        coverHeaders: const {},
      );
      expect(items, hasLength(1));
      expect(items[0].title, 'Alt Title');
    });

    test('没有结果时返回空列表', () {
      final items = EhParser.parseSearchItems(
        '<html><body><p>No hits found</p></body></html>',
        coverHeaders: const {},
      );
      expect(items, isEmpty);
    });

    test('总数从 "of 1,234" 里取，逗号要去掉', () {
      expect(EhParser.parseTotal(_searchHtml), 1234);
      expect(EhParser.parseTotal('<html><body>没有总数</body></html>'), 0);
    });
  });

  group('EhParser 详情页', () {
    test('标题、封面、上传者、页数、标签', () {
      final gallery = EhParser.parseGallery(_galleryHtml, '1234567-abcdef1234');
      expect(gallery, isNotNull);
      expect(gallery!.title, 'Some Gallery Title');
      expect(gallery.coverUrl, 'https://s.exhentai.org/t/aa/bb/cover.jpg');
      expect(gallery.uploader, 'UploaderName');
      expect(gallery.pageCount, 42);
      expect(gallery.tags, [
        'language:chinese',
        'female:big breasts',
        'female:sole female',
      ]);
    });

    test('页数只写在文字里时也能解析', () {
      final gallery = EhParser.parseGallery(_galleryHtmlTextPages, '1-abc');
      expect(gallery?.pageCount, 18);
    });

    test('取不到标题时返回 null（已删除或需要登录）', () {
      expect(
        EhParser.parseGallery('<html><body></body></html>', '1-a'),
        isNull,
      );
    });
  });

  group('EhParser 图片地址', () {
    test('只取 /s/ 开头的路径，忽略详情页链接', () {
      expect(EhParser.parsePagePaths(_thumbHtml), [
        '/s/aaa111/1234567-1',
        '/s/bbb222/1234567-2',
        '/s/ccc333/1234567-3',
      ]);
    });

    test('从 /s/ 页面里取出真实图片地址', () {
      expect(
        EhParser.parseImageUrl(_pageHtml),
        'https://abc.hath.network/h/xyz-1.jpg',
      );
      // #img 直接就是 <img> 的写法
      expect(
        EhParser.parseImageUrl(
          '<html><body><div id="i3"><img id="img" src="https://a/b.png"></div></body></html>',
        ),
        'https://a/b.png',
      );
      // 连 #img 都没有时退回正文里的第一张图
      expect(
        EhParser.parseImageUrl(
          '<html><body><div id="i3"><img src="https://c/d.jpg"></div></body></html>',
        ),
        'https://c/d.jpg',
      );
      expect(EhParser.parseImageUrl('<html><body></body></html>'), '');
    });
  });

  group('parseRankItems（榜单页）', () {
    test('不是 table.itg 结构时退化成扫 /g/ 链接', () {
      final items = EhParser.parseRankItems(
        _toplistHtml,
        coverHeaders: const {'referer': 'https://e-hentai.org/'},
      );

      expect(items.length, 2);
      expect(items[0].title, 'Top One');
      expect(items[0].sid.id, '1111111-aaaa1111');
      expect(items[1].title, 'Top Two');
      expect(items[1].sid.id, '2222222-bbbb2222');
    });

    test('封面从链接附近的祖先节点里取到', () {
      final items = EhParser.parseRankItems(
        _toplistHtml,
        coverHeaders: const {},
      );

      expect(items[0].coverUrl, 'https://s.exhentai.org/t/11/22/1.jpg');
      expect(items[1].coverUrl, 'https://s.exhentai.org/t/33/44/2.jpg');
    });

    test('封面请求头原样带上（EH 看 Referer）', () {
      final items = EhParser.parseRankItems(
        _toplistHtml,
        coverHeaders: const {'referer': 'https://e-hentai.org/'},
      );

      expect(items[0].coverHeaders['referer'], 'https://e-hentai.org/');
    });

    test('标准结果行结构优先，不会被退化解析重复计数', () {
      final items = EhParser.parseRankItems(_searchHtml, coverHeaders: const {});
      expect(items.length, 2);
    });

    test('同一本子出现两次只算一条', () {
      const html = '''
<html><body>
<div class="gl2t"><a href="https://e-hentai.org/g/3333333/cccc3333/">Dup</a></div>
<div class="gl2t"><a href="https://e-hentai.org/g/3333333/cccc3333/">Dup</a></div>
</body></html>
''';
      final items = EhParser.parseRankItems(html, coverHeaders: const {});
      expect(items.length, 1);
    });
  });
}
