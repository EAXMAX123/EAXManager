/// Google Lens 客户端
///
/// 这里**只做上传**：把图片传给 Lens，拿到结果页地址，再交给浏览器打开。
///
/// 为什么不把结果解析出来：Lens 的结果页是纯 JS 渲染的，服务端只回一个空壳
/// （实测 91KB 的 HTML 里一条结果都没有，连 `AF_initDataCallback` 都没有），
/// 用 Dart 硬解析只会得到空白。硬要解析就得内嵌一个浏览器内核，代价太大。
///
/// 所以这一步的价值是：省掉用户在 Google 页面上手动选文件的操作 ——
/// 从相册点一下，直接在浏览器里看 Lens 的结果。
///
/// 注意：上传接口本身走代理是通的，但不挂梯子连不上；
/// 而且浏览器打开结果页那一步也要梯子，两个条件缺一不可。
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import '../../net/net_error.dart';
import '../../net/net_transport.dart';
import '../comic_source.dart';

class GoogleLensClient {
  GoogleLensClient({required this.transport});

  final NetTransport transport;

  static const String _endpoint = 'https://lens.google.com/v3/upload';

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

  /// 上传图片，返回 Lens 的结果页地址
  Future<String> resultUrl(Uint8List jpeg, {String filename = 'image.jpg'}) async {
    final form = FormData.fromMap({
      'encoded_image': MultipartFile.fromBytes(
        jpeg,
        filename: filename,
        contentType: DioMediaType('image', 'jpeg'),
      ),
      'image_content': '',
    });

    late final Response<String> resp;
    try {
      resp = await dio.post<String>(
        _endpoint,
        queryParameters: {
          'stcs': '${DateTime.now().millisecondsSinceEpoch}',
        },
        data: form,
        options: Options(
          // 303 的 Location 就是结果页，别让它自己跟过去
          followRedirects: false,
          headers: {
            'user-agent': _userAgent,
            'accept': 'text/html,application/xhtml+xml,*/*',
            'accept-language': 'en-US,en;q=0.9',
          },
        ),
      );
    } on DioException catch (e) {
      final info = NetError.describe(
        e,
        sourceName: 'Google Lens',
        proxyConfigured: transport.proxy != null,
        vpnActive: transport.vpnActive,
      );
      throw SourceException('Google Lens 连不上（这个站必须挂梯子）：${info.message}');
    }

    final url = resultUrlFrom(resp.headers.value('location'));
    if (url == null) {
      throw SourceException(
        'Google Lens 没给出结果地址（HTTP ${resp.statusCode ?? 0}）。'
        '多半是没挂梯子，或者代理没生效',
      );
    }
    return url;
  }

  /// 从 303 的 Location 里挑出结果页地址
  ///
  /// 正常是 `https://www.google.com/search?vsrid=…`，也见过协议相对的形式。
  /// 拿不到就返回 null，让上层给一句人话提示，而不是把一个空地址丢给浏览器。
  static String? resultUrlFrom(String? location) {
    final raw = (location ?? '').trim();
    if (raw.isEmpty) return null;

    final url = raw.startsWith('//')
        ? 'https:$raw'
        : raw.startsWith('/')
        ? 'https://www.google.com$raw'
        : raw;
    if (!url.startsWith('http')) return null;
    if (!url.contains('google.')) return null;
    return url;
  }
}
