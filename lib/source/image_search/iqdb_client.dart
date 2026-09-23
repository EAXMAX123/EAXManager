/// IQDB 客户端
///
/// 不用 key、不用登录，直接 POST 图片就能查。索引以 booru 系为主
/// （danbooru / gelbooru / yande.re / konachan 这些），所以对动画向的图
/// 很准，对同人本封面一般 —— 但胜在免费无限量，用来给 SauceNAO 兜底。
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

class IqdbClient {
  IqdbClient({required this.transport});

  final NetTransport transport;

  static const String _endpoint = 'https://iqdb.org/';

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
        validateStatus: (_) => true,
      ),
    );
    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: transport.createClient,
    );
    return dio;
  }

  Future<List<ImageMatch>> search(Uint8List jpeg, {String filename = 'image.jpg'}) async {
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        jpeg,
        filename: filename,
        contentType: DioMediaType('image', 'jpeg'),
      ),
      // 0 = 不限定某个 booru，让它自己在全部索引里找
      'service': '0',
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
            'referer': 'https://iqdb.org/',
          },
        ),
      );
    } on DioException catch (e) {
      throw SourceException(
        NetError.describe(
          e,
          sourceName: 'IQDB',
          proxyConfigured: transport.proxy != null,
          vpnActive: transport.vpnActive,
        ).message,
      );
    }

    final body = resp.data ?? '';
    if (body.trim().isEmpty) {
      throw SourceException('IQDB 没有返回内容（HTTP ${resp.statusCode ?? 0}）');
    }
    if (body.contains('No relevant matches') ||
        body.contains('could not find') ||
        body.contains('No matches found')) {
      return const [];
    }

    return parseResults(body);
  }

  /// 解析结果页
  ///
  /// 每条结果是一张表，表头写着 Best match / Possible match / Additional match，
  /// 表里依次是缩略图、来源站名、尺寸、相似度。
  static List<ImageMatch> parseResults(String htmlText) {
    final doc = html.parse(htmlText);
    final out = <ImageMatch>[];

    for (final head in doc.querySelectorAll('th')) {
      final label = head.text.trim().toLowerCase();
      if (!label.contains('match')) continue;

      // th 的父节点是 tr，再往上一层才是整张结果表
      final table = _ownerTable(head);
      if (table == null) continue;

      final similarity = _similarity(table);
      if (similarity <= 0) continue;

      final link = table.querySelector('td.image a');
      final img = table.querySelector('td.image img');

      out.add(
        ImageMatch(
          engine: 'IQDB',
          index: _serviceName(table),
          similarity: similarity,
          sourceUrl: _absolute(link?.attributes['href'] ?? ''),
          thumbnailUrl: _absolute(img?.attributes['src'] ?? ''),
        ),
      );
    }

    out.sort((a, b) => b.similarity.compareTo(a.similarity));
    return out;
  }

  /// 往上找到包着这个节点的那张 table
  static dom.Element? _ownerTable(dom.Element node) {
    dom.Element? current = node.parent;
    while (current != null) {
      if (current.localName == 'table') return current;
      current = current.parent;
    }
    return null;
  }
  static double _similarity(dom.Element table) {
    for (final cell in table.querySelectorAll('td')) {
      final match = RegExp(r'(\d+(?:\.\d+)?)\s*%\s*similarity').firstMatch(
        cell.text,
      );
      if (match != null) return double.tryParse(match.group(1)!) ?? 0;
    }
    return 0;
  }

  /// 来源站名：那一格里有 service-icon 图标，文字形如「Danbooru Gelbooru」
  static String _serviceName(dom.Element table) {
    for (final cell in table.querySelectorAll('td')) {
      if (cell.querySelector('img.service-icon') == null) continue;
      final text = cell.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (text.isEmpty) continue;
      final first = text.split(' ').first;
      return first.isEmpty ? 'IQDB' : first;
    }
    return 'IQDB';
  }

  static String _absolute(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return '';
    if (text.startsWith('http')) return text;
    if (text.startsWith('//')) return 'https:$text';
    return 'https://iqdb.org/${text.replaceFirst(RegExp(r'^/'), '')}';
  }
}
