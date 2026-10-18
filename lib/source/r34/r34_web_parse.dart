/// Rule34 网页版解析
///
/// 没填 API Key 时走这里：直接抓 `rule34.xxx` 的列表页和详情页。
/// 网页版不需要登录，但部分地区要挂梯子，也可能被 Cloudflare 验证拦住。
/// 解析刻意写得宽松一些，站点改版时只影响个别字段，不会整页失效。
library;

import 'package:html/parser.dart' as html_parser;

/// 网页列表一页的条数（Rule34 网页版固定 42 条）
const int r34WebPageSize = 42;

/// 判断返回的是不是 Cloudflare / 人机验证页
bool isR34ChallengePage(String body) {
  final text = body.toLowerCase();
  if (text.contains('just a moment')) return true;
  if (text.contains('cf-challenge')) return true;
  if (text.contains('enable javascript and cookies')) return true;
  if (text.contains('checking your browser')) return true;
  if (text.contains('attention required! | cloudflare')) return true;
  return false;
}

/// 解析列表页，返回统一的 post 结构
///
/// 网页列表只有缩略图和 ID，没有标签、尺寸、原图地址，所以先标成
/// `_webPartial`；点进详情时再补一次。
List<Map<String, dynamic>> parseR34WebList(String body) {
  final doc = html_parser.parse(body);
  final posts = <Map<String, dynamic>>[];
  final seen = <String>{};

  for (final anchor in doc.querySelectorAll('span.thumb a[href]')) {
    final href = anchor.attributes['href'] ?? '';
    final id = _idFromHref(href);
    if (id.isEmpty || !seen.add(id)) continue;

    final thumb = anchor.parent;
    final img = anchor.querySelector('img') ?? thumb?.querySelector('img');
    final src = _imageSrc(img);
    if (src.isEmpty) continue;

    final classes =
        '${thumb?.classes.join(' ') ?? ''} '
        '${anchor.classes.join(' ')}';
    final inner = thumb?.innerHtml.toLowerCase() ?? '';
    final isVideo =
        classes.toLowerCase().contains('video') ||
        inner.contains('class="video"');

    final rawTags = [
      img?.attributes['title'] ?? '',
      img?.attributes['alt'] ?? '',
    ].firstWhere((e) => _looksLikeTags(e), orElse: () => '');

    posts.add({
      'id': id,
      'preview_url': src,
      'sample_url': src,
      'tags': rawTags,
      'file_type': isVideo ? 'video/mp4' : '',
      '_webPartial': true,
    });
  }

  // 站点改版后的兜底：只要是指向 s=view 的链接且带图，也收
  if (posts.isEmpty) {
    for (final anchor in doc.querySelectorAll('a[href*="s=view"]')) {
      final id = _idFromHref(anchor.attributes['href'] ?? '');
      if (id.isEmpty || !seen.add(id)) continue;
      final img = anchor.querySelector('img');
      final src = _imageSrc(img);
      if (src.isEmpty) continue;
      posts.add({
        'id': id,
        'preview_url': src,
        'sample_url': src,
        'tags': '',
        '_webPartial': true,
      });
    }
  }

  return posts;
}

/// 解析详情页
///
/// 返回的字段和 DAPI 对齐，后面的搜索、书架、下载逻辑不用改。
Map<String, dynamic> parseR34WebDetail(String body, String id) {
  final doc = html_parser.parse(body);
  final post = <String, dynamic>{'id': id};

  final image = doc.querySelector('img#image') ?? doc.querySelector('img#img');
  final imageUrl = _imageSrc(image);
  if (imageUrl.isNotEmpty) {
    post['file_url'] = imageUrl;
    post['sample_url'] = imageUrl;
    post['preview_url'] = imageUrl;
  }

  String videoUrl = '';
  for (final source in doc.querySelectorAll('video source[src]')) {
    videoUrl = _absolute(source.attributes['src'] ?? '');
    if (videoUrl.isNotEmpty) break;
  }
  if (videoUrl.isEmpty) {
    for (final video in doc.querySelectorAll('video[src]')) {
      videoUrl = _absolute(video.attributes['src'] ?? '');
      if (videoUrl.isNotEmpty) break;
    }
  }
  if (videoUrl.isEmpty) {
    for (final anchor in doc.querySelectorAll('a[href]')) {
      final href = anchor.attributes['href'] ?? '';
      if (RegExp(
        r'\.(mp4|webm|mov|mkv|m4v)(\?|$)',
        caseSensitive: false,
      ).hasMatch(href)) {
        videoUrl = _absolute(href);
        break;
      }
    }
  }
  if (videoUrl.isNotEmpty) {
    post['file_url'] = videoUrl;
    post['file_type'] = 'video/mp4';
    if (imageUrl.isEmpty) post['preview_url'] = videoUrl;
  }

  final fileUrl = _text(post['file_url']);
  final ext = _extensionOf(fileUrl);
  if (ext.isNotEmpty) post['file_ext'] = ext;
  if (_text(post['file_type']).isEmpty) {
    post['file_type'] = switch (ext) {
      'gif' => 'image/gif',
      'mp4' || 'webm' || 'mov' || 'mkv' || 'm4v' => 'video/$ext',
      _ => 'image/$ext',
    };
  }

  final tags = <String>[];
  for (final anchor in doc.querySelectorAll('#tag-sidebar a, #tags a')) {
    final text = anchor.text.trim();
    if (text.isEmpty || text == '?' || tags.contains(text)) continue;
    tags.add(text);
  }
  post['tags'] = tags;

  final stats = doc.querySelector('#stats')?.text ?? doc.text ?? '';
  final size = RegExp(
    r'Size:\s*(\d+)\s*x\s*(\d+)',
    caseSensitive: false,
  ).firstMatch(stats);
  if (size != null) {
    post['width'] = size.group(1);
    post['height'] = size.group(2);
  }
  final score = RegExp(
    r'Score:\s*(-?\d+)',
    caseSensitive: false,
  ).firstMatch(stats);
  if (score != null) post['score'] = score.group(1);
  final rating = RegExp(
    r'Rating:\s*([A-Za-z]+)',
    caseSensitive: false,
  ).firstMatch(stats);
  if (rating != null) post['rating'] = rating.group(1)!.toLowerCase();

  post['_webPartial'] = false;
  return post;
}

/// 详情页明显没有内容时用来判断
bool isR34MissingPost(String body) {
  final text = body.toLowerCase();
  return text.contains('this post was deleted') ||
      text.contains('post not found') ||
      text.contains('no image found');
}

String _idFromHref(String href) {
  final match = RegExp(r'[?&]id=(\d+)').firstMatch(href);
  return match?.group(1) ?? '';
}

String _imageSrc(dynamic img) {
  if (img == null) return '';
  final attributes = img.attributes as Map;
  for (final key in const ['src', 'data-src', 'data-original']) {
    final value = _text(attributes[key]);
    if (value.isNotEmpty && !value.startsWith('data:')) {
      return _absolute(value);
    }
  }
  return '';
}

bool _looksLikeTags(String text) {
  final value = text.trim();
  if (value.length < 3) return false;
  final lower = value.toLowerCase();
  if (lower == 'image' || lower == 'thumbnail' || lower == 'preview') {
    return false;
  }
  if (lower.contains('http') ||
      lower.contains('.jpg') ||
      lower.contains('.png')) {
    return false;
  }
  return true;
}

String _extensionOf(String url) {
  final path = Uri.tryParse(url)?.path ?? '';
  final name = path.split('/').last;
  final dot = name.lastIndexOf('.');
  if (dot < 0 || dot == name.length - 1) return '';
  return name.substring(dot + 1).toLowerCase();
}

String _absolute(String url) {
  if (url.startsWith('//')) return 'https:$url';
  if (url.startsWith('/')) return 'https://rule34.xxx$url';
  return url;
}

String _text(dynamic value) {
  final text = '${value ?? ''}'.trim();
  return text == 'null' ? '' : text;
}
