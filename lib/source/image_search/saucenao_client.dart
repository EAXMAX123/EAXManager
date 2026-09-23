/// SauceNAO 客户端
///
/// 这是目前最好用的一个：索引里同时有 pixiv、e-hentai、danbooru、mangadex
/// 这些库，同人本封面命中率明显高于其它站。
///
/// 走的是网页版而不是官方 JSON 接口 —— 官方接口要填 api_key，匿名会直接被
/// 拒（The anonymous account type does not permit API usage）。网页版不用 key。
/// 代价是要解析 HTML，页面结构变了就得跟着改。
///
/// 匿名限速是「每 30 秒 3 次」，超了会返回一段纯文本，这里会抛出可识别的
/// 错误，让上层等一下再重试。
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

import '../../net/net_error.dart';
import '../../net/net_transport.dart';
import '../comic_source.dart';
import 'image_search_models.dart';

/// 被限速了，等一会儿再来
class ImageSearchThrottled implements Exception {
  const ImageSearchThrottled(this.message, {this.wait = const Duration(seconds: 12)});

  final String message;

  /// 建议等多久
  final Duration wait;
}

class SauceNaoClient {
  SauceNaoClient({required this.transport, this.apiKey = ''});

  final NetTransport transport;

  /// 用户自己填的 key，空表示走匿名
  String apiKey;

  static const String _endpoint = 'https://saucenao.com/search.php';

  /// 一次最多要几条，要多了也都是低相似度的噪声
  static const int _maxResults = 8;

  /// 必带的浏览器 UA，不带会被当成机器人
  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

  Dio? _dio;

  Dio get dio => _dio ??= _buildDio();

  Dio _buildDio() {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 60),
        sendTimeout: const Duration(seconds: 60),
        responseType: ResponseType.plain,
        // 非 200 也要能读到 body，才知道到底是被限速还是图片有问题
        validateStatus: (_) => true,
      ),
    );
    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: transport.createClient,
    );
    return dio;
  }

  /// 传一张图去搜，返回命中的条目（已按相似度降序）
  Future<List<ImageMatch>> search(Uint8List jpeg, {String filename = 'image.jpg'}) async {
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        jpeg,
        filename: filename,
        contentType: DioMediaType('image', 'jpeg'),
      ),
      // 999 = 全部索引。匿名下这个参数其实不生效，留着是因为带 key 时有用
      'db': '999',
      'output_type': '0',
      'numres': '$_maxResults',
      if (apiKey.trim().isNotEmpty) 'api_key': apiKey.trim(),
    });

    late final Response<String> resp;
    try {
      resp = await dio.post<String>(
        _endpoint,
        data: form,
        options: Options(
          headers: {
            'user-agent': _userAgent,
            'accept': 'text/html,application/xhtml+xml,*/*',
            'accept-language': 'en-US,en;q=0.9',
            'referer': 'https://saucenao.com/',
          },
        ),
      );
    } on DioException catch (e) {
      throw SourceException(
        NetError.describe(
          e,
          sourceName: 'SauceNAO',
          proxyConfigured: transport.proxy != null,
          vpnActive: transport.vpnActive,
        ).message,
      );
    }

    final body = resp.data ?? '';
    final code = resp.statusCode ?? 0;

    if (body.trim().isEmpty) {
      throw SourceException('SauceNAO 没有返回内容（HTTP $code）');
    }

    // 限速时返回的是一段纯文本，不是页面
    if (!body.contains('class="result')) {
      if (_looksThrottled(body)) throw ImageSearchThrottled(body.trim());
      if (code != 200) throw SourceException('SauceNAO 返回了 HTTP $code');
      if (body.contains('No results found')) return const [];
    }

    return parseResults(body);
  }

  /// 限速文案：`your IP has exceeded the unregistered user's rate limit`
  static bool _looksThrottled(String body) {
    final text = body.toLowerCase();
    return text.contains('rate limit') ||
        text.contains('exceeded') ||
        text.contains('too many');
  }

  /// 解析搜索结果页
  ///
  /// 每个结果是一个 `div.result`，里面有：
  /// - `div.resultsimilarityinfo` 相似度
  /// - `td.resulttableimage img` 它的 title 形如 `Index #9: Danbooru - xxx.jpg`
  /// - `div.resultmiscinfo a` 来源页面
  /// - `div.resulttitle` / `div.resultcontentcolumn` 字段（Title / Author …）
  static List<ImageMatch> parseResults(String htmlText) {
    final doc = html.parse(htmlText);
    final out = <ImageMatch>[];

    for (final node in doc.querySelectorAll('div.result')) {
      // SauceNAO 把低相似度的结果藏在 hidden 里，还有一条纯提示用的节点
      if (node.id == 'result-hidden-notification') continue;
      if (node.classes.contains('hidden')) continue;

      final similarity = _similarity(node);
      if (similarity <= 0) continue;

      final image = node.querySelector('td.resulttableimage img');
      final index = _indexName(image?.attributes['title'] ?? '');
      final thumb = _absolute(image?.attributes['src'] ?? '');

      final fields = <String, String>{};
      for (final box in node.querySelectorAll(
        '.resulttitle, .resultcontentcolumn',
      )) {
        _readFields(box, fields);
      }

      final sourceUrl =
          node.querySelector('div.resultmiscinfo a')?.attributes['href'] ?? '';

      out.add(
        ImageMatch(
          engine: 'SauceNAO',
          index: index.isEmpty ? '未知图库' : index,
          similarity: similarity,
          title: fields['Title'] ?? fields['Material'] ?? '',
          author:
              fields['Author'] ??
              fields['Member'] ??
              fields['Creator'] ??
              '',
          fields: fields,
          sourceUrl: sourceUrl,
          thumbnailUrl: thumb,
        ),
      );
    }

    out.sort((a, b) => b.similarity.compareTo(a.similarity));
    return out;
  }

  static double _similarity(dom.Element node) {
    final text = node.querySelector('.resultsimilarityinfo')?.text ?? '';
    final match = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(text);
    return match == null ? 0 : double.tryParse(match.group(1)!) ?? 0;
  }

  /// `Index #9: Danbooru - e511f5...jpg` -> `Danbooru`
  static String _indexName(String raw) {
    var text = raw.trim();
    final colon = text.indexOf(':');
    if (colon >= 0) text = text.substring(colon + 1);
    final dash = text.lastIndexOf(' - ');
    if (dash > 0) text = text.substring(0, dash);
    return text.trim();
  }

  static String _absolute(String src) {
    final text = src.trim();
    if (text.isEmpty) return '';
    if (text.startsWith('http')) return text;
    if (text.startsWith('//')) return 'https:$text';
    return 'https://saucenao.com/${text.replaceFirst(RegExp(r'^/'), '')}';
  }

  /// 一个容器里可能挤着好几组「标签 + 值」，按 strong 切段读
  static void _readFields(dom.Element box, Map<String, String> out) {
    String? label;
    final buffer = StringBuffer();

    void flush() {
      final name = label;
      if (name == null) return;
      final value = buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
      if (name.isNotEmpty && value.isNotEmpty && !out.containsKey(name)) {
        out[name] = value;
      }
    }

    for (final node in box.nodes) {
      if (node is dom.Element && node.localName == 'strong') {
        flush();
        label = node.text.replaceAll(':', '').trim();
        buffer.clear();
      } else if (node is dom.Text) {
        buffer.write(node.text);
      } else if (node is dom.Element) {
        buffer.write(node.text);
      }
    }
    flush();
  }
}
