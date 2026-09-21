import 'dart:io';
import 'package:dio/dio.dart';
import 'package:jm_reader/jm/jm_client.dart';

Future<void> main(List<String> args) async {
  final client = JmClient();
  await client.ensureReady();
  final url = client.coverUrl('1474516');
  stdout.writeln('封面地址: $url');
  final r = await client.dio.get<List<int>>(
    url,
    options: Options(responseType: ResponseType.bytes, headers: client.imageHeaders),
  );
  final out = File('tool/_probe_out/cover.jpg');
  out.writeAsBytesSync(r.data!);
  stdout.writeln('已保存 ${r.data!.length} 字节 -> ${out.path}');
}
