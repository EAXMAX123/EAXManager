// 探测登录 / 收藏夹接口：确认请求格式与响应结构与移动端 API 一致
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:jm_reader/jm/jm_client.dart';
import 'package:jm_reader/jm/jm_constants.dart';
import 'package:jm_reader/jm/jm_crypto.dart';

Future<void> main(List<String> args) async {
  final client = JmClient();
  await client.ensureReady();
  stdout.writeln('API 域名: ${client.apiDomain}');

  // 1) 未登录时拉收藏夹，观察返回结构
  try {
    final page = await client.favoriteFolder(page: 1);
    stdout.writeln('[favorite] total=${page.total} items=${page.items.length} '
        'folders=${page.folders.map((f) => '${f.id}:${f.name}').join(',')}');
    for (final it in page.items.take(3)) {
      stdout.writeln('   - ${it.id}  ${it.name}');
    }
  } on Exception catch (e) {
    stdout.writeln('[favorite] 失败: $e');
  }

  // 2) 用错误账号登录，确认服务端确实返回了 s 之外的错误结构
  final ts = JmCrypto.timeStamp();
  final (token, tokenparam) = JmCrypto.tokenAndTokenParam(ts);
  final resp = await client.dio.post<String>(
    'https://${client.apiDomain}/login',
    data: {'username': 'codex_probe_no_such_user', 'password': 'x'},
    options: _options(token, tokenparam),
  );
  stdout.writeln('[login] HTTP ${resp.statusCode}');
  final raw = resp.data ?? '';
  stdout.writeln('[login] raw: ${raw.length > 400 ? raw.substring(0, 400) : raw}');
  stdout.writeln('[login] set-cookie: ${resp.headers['set-cookie']}');
  final start = raw.indexOf('{');
  if (start >= 0) {
    final envelope = jsonDecode(raw.substring(start, raw.lastIndexOf('}') + 1));
    stdout.writeln('[login] envelope.code=${envelope['code']}');
    final encoded = envelope['data'];
    if (encoded is String && encoded.isNotEmpty) {
      try {
        final plain = JmCrypto.decodeRespData(encoded, ts);
        stdout.writeln('[login] data=$plain');
      } on Exception catch (e) {
        stdout.writeln('[login] 解密失败: $e');
      }
    }
  } else {
    stdout.writeln('[login] 原始响应: ${raw.substring(0, raw.length.clamp(0, 300))}');
  }
}

Options _options(String token, String tokenparam) => Options(
  responseType: ResponseType.plain,
  headers: {
    ...JmHeaders.appTemplate,
    'token': token,
    'tokenparam': tokenparam,
  },
  contentType: Headers.formUrlEncodedContentType,
  validateStatus: (c) => c != null && c < 500,
);
