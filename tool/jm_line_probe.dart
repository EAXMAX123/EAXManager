// 验证线路列表解析与切换逻辑
import 'dart:io';

import 'package:jm_reader/jm/jm_client.dart';

Future<void> main(List<String> args) async {
  final client = JmClient();
  await client.ensureReady();

  stdout.writeln('候选线路数: ${client.lineCount}');
  stdout.writeln('当前线路: ${client.lineName} (${client.apiDomain})');

  final search = await client.search('', page: 1);
  stdout.writeln('搜索返回 ${search.items.length} 条，total=${search.total}');

  for (var i = 0; i < client.lineCount + 1; i++) {
    final ok = await client.rotateDomain();
    stdout.writeln('切换 -> $ok  ${client.lineName} (${client.apiDomain})');
    try {
      final page = await client.search('', page: 1);
      stdout.writeln('   该线路搜索 OK：${page.items.length} 条');
    } on Exception catch (e) {
      stdout.writeln('   该线路失败：$e');
    }
  }
}
