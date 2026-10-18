import 'package:flutter_test/flutter_test.dart';
import 'package:jm_reader/source/r34/r34_web_parse.dart';

void main() {
  test('列表页能解析出 ID、缩略图和视频标记', () {
    const body = '''
<html><body>
<div class="pagination">
  <span class="thumb" id="s101">
    <a href="index.php?page=post&s=view&id=101">
      <img src="//wimg.rule34.xxx/thumbnails/101/thumbnail_abc.jpg"
           title="1girl smile" alt="1girl smile">
    </a>
  </span>
  <span class="thumb video" id="s102">
    <a href="index.php?page=post&s=view&id=102">
      <img data-src="https://wimg.rule34.xxx/thumbnails/102/thumbnail_def.jpg">
    </a>
  </span>
</div>
</body></html>
''';

    final posts = parseR34WebList(body);
    expect(posts, hasLength(2));
    expect(posts[0]['id'], '101');
    expect(posts[0]['preview_url'], startsWith('https:'));
    expect(posts[0]['tags'], '1girl smile');
    expect(posts[1]['id'], '102');
    expect(posts[1]['file_type'], 'video/mp4');
    expect(posts[1]['_webPartial'], isTrue);
  });

  test('详情页能解析原图、尺寸、标签和评分', () {
    const body = '''
<html><body>
<img id="image" src="//wimg.rule34.xxx/images/201/abc.jpeg">
<div id="stats">
  Posted: 2026-01-01  Score: 12  Size: 1200x1600  Rating: Questionable
</div>
<ul id="tag-sidebar">
  <li class="tag-type-artist"><a href="?tags=artist%3Afoo">artist:foo</a></li>
  <li class="tag-type-general"><a href="?tags=1girl">1girl</a></li>
  <li class="tag-type-general"><a href="?tags=smile">smile</a></li>
</ul>
</body></html>
''';

    final post = parseR34WebDetail(body, '201');
    expect(post['file_url'], 'https://wimg.rule34.xxx/images/201/abc.jpeg');
    expect(post['file_ext'], 'jpeg');
    expect(post['width'], '1200');
    expect(post['height'], '1600');
    expect(post['score'], '12');
    expect(post['rating'], 'questionable');
    expect(post['tags'], ['artist:foo', '1girl', 'smile']);
    expect(post['_webPartial'], isFalse);
  });

  test('视频详情页能识别 mp4', () {
    const body = '''
<html><body>
<video id="gelcomVideoPlayer"><source src="https://wimg.rule34.xxx/images/301/clip.mp4"></video>
<img id="image" src="//wimg.rule34.xxx/images/301/cover.jpg">
</body></html>
''';

    final post = parseR34WebDetail(body, '301');
    expect(post['file_url'], 'https://wimg.rule34.xxx/images/301/clip.mp4');
    expect(post['file_type'], 'video/mp4');
    expect(post['file_ext'], 'mp4');
  });

  test('能认出 Cloudflare 验证页', () {
    expect(isR34ChallengePage('<title>Just a moment...</title>'), isTrue);
    expect(isR34ChallengePage('<html><body>normal</body></html>'), isFalse);
  });
}
