// 调试：直接打印 /chapter_view_template 的原始响应
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:jm_reader/jm/jm_client.dart';
import 'package:jm_reader/jm/jm_constants.dart';
import 'package:jm_reader/jm/jm_crypto.dart';

Future<void> main(List<String> args) async {
  final photoId = args.isNotEmpty ? args.first : '1474516';
  final client = JmClient();
  await client.ensureReady();

  final ts = JmCrypto.timeStamp();
  final (token, tokenparam) =
      JmCrypto.tokenAndTokenParam(ts, secret: JmMagic.appTokenSecret2);

  final resp = await client.dio.get<String>(
    'https://${client.apiDomain}/chapter_view_template',
    queryParameters: {
      'id': photoId,
      'mode': 'vertical',
      'page': '0',
      'app_img_shunt': '1',
      'express': 'off',
      'v': ts,
    },
    options: Options(
      responseType: ResponseType.plain,
      headers: {
        ...JmHeaders.appTemplate,
        'token': token,
        'tokenparam': tokenparam,
      },
    ),
  );

  final text = resp.data ?? '';
  stdout.writeln('HTTP ${resp.statusCode}, 长度 ${text.length}');
  stdout.writeln('--- 前 3000 字符 ---');
  stdout.writeln(text.length > 3000 ? text.substring(0, 3000) : text);
  final m = RegExp(r'scramble_id\s*=\s*(\d+)').firstMatch(text);
  stdout.writeln('--- 匹配 scramble_id: ${m?.group(1)} ---');
}
