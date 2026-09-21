/// 探测哔咔登录接口到底能不能连通（用假账号，只看服务器怎么回应）
///
/// 用法：dart run tool/pica_login_probe.dart
// ignore_for_file: avoid_print
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:jm_reader/net/net_transport.dart';
import 'package:jm_reader/source/pica/pica_client.dart';

/// 手工重放一次登录请求，把原始状态码和响应体打出来
Future<void> raw(String label, NetTransport transport) async {
  final ts = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
  const path = 'auth/sign-in';
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 30),
      responseType: ResponseType.plain,
      validateStatus: (_) => true,
    ),
  );
  dio.httpClientAdapter = IOHttpClientAdapter(
    createHttpClient: transport.createClient,
  );

  try {
    final resp = await dio.post<String>(
      '${PicaConst.baseUrl}/$path',
      data: jsonEncode({'email': 'probe@example.invalid', 'password': 'x'}),
      options: Options(
        headers: {
          'api-key': PicaConst.apiKey,
          'accept': PicaConst.acceptJson,
          'app-channel': PicaConst.appChannel,
          'time': ts,
          'nonce': PicaConst.nonce,
          'signature': PicaClient.sign('POST', path, ts),
          'app-version': PicaConst.appVersion,
          'app-uuid': PicaConst.appUuid,
          'app-platform': 'android',
          'app-build-version': PicaConst.appBuildVersion,
          'Content-Type': 'application/json; charset=UTF-8',
          'user-agent': PicaConst.userAgent,
          'image-quality': 'original',
        },
      ),
    );
    final body = resp.data ?? '';
    print('[$label] HTTP ${resp.statusCode}');
    print('[$label] headers: ${resp.headers.map}');
    print('[$label] body: ${body.length > 600 ? body.substring(0, 600) : body}');
  } on Object catch (e) {
    print('[$label] 请求异常 $e');
  }
}

Future<void> probe(String label, NetTransport transport) async {
  final client = PicaClient(transport: transport);
  try {
    await client.login('codex-probe@example.invalid', 'not-a-real-password');
    print('[$label] 居然登录成功了');
  } on Object catch (e) {
    print('[$label] ${e.runtimeType}: $e');
  }
}

Future<void> main() async {
  await probe('关闭绕过', const NetTransport());
  await probe(
    '开启绕过',
    const NetTransport(bypass: DnsBypassMode.on),
  );
  await raw('原始请求-开启绕过', const NetTransport(bypass: DnsBypassMode.on));
  await httpsCheck('JM api', 'https://www.cdngwc.cc/');
  await httpsCheck('EH 表站', 'https://e-hentai.org/');
}

/// 通用 https 连通性检查（走「绕过 DNS 污染」这条路）
Future<void> httpsCheck(String label, String url) async {
  final client = const NetTransport(bypass: DnsBypassMode.on).createClient();
  try {
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close().timeout(
      const Duration(seconds: 20),
    );
    print('[$label] HTTP ${response.statusCode}');
    await response.drain<void>();
  } on Object catch (e) {
    print('[$label] 失败 ${e.runtimeType}: $e');
  } finally {
    client.close(force: true);
  }
}
