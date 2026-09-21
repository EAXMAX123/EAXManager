// 打印官方域名服务器返回的域名列表，确认格式（是否带端口 / 协议头）
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:jm_reader/jm/jm_constants.dart';
import 'package:jm_reader/jm/jm_crypto.dart';

Future<void> main(List<String> args) async {
  final dio = Dio();

  for (final url in JmDomains.apiDomainServerList) {
    stdout.writeln('--- $url');
    try {
      final resp = await dio.get<String>(
        url,
        options: Options(
          responseType: ResponseType.plain,
          headers: JmHeaders.appTemplate,
        ),
      );
      var text = resp.data ?? '';
      while (text.isNotEmpty && text.codeUnitAt(0) > 127) {
        text = text.substring(1);
      }
      final trimmed = text.trim();
      stdout.writeln('    HTTP ${resp.statusCode}, 密文长度 ${trimmed.length}');
      final plain = JmCrypto.decodeRespData(
        trimmed,
        '',
        secret: JmMagic.apiDomainServerSecret,
      );
      stdout.writeln('    明文: $plain');
      final data = jsonDecode(plain);
      if (data is List) {
        for (final e in data) {
          stdout.writeln('      > "$e"');
        }
      }
    } on Exception catch (e) {
      stdout.writeln('    失败: $e');
    }
  }
}
