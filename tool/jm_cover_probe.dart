// 探测封面图 URL 规律
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:jm_reader/jm/jm_client.dart';
import 'package:jm_reader/jm/jm_constants.dart';

Future<void> main(List<String> args) async {
  final client = JmClient();
  await client.ensureReady();
  final album = await client.albumDetail('1474516');
  stdout.writeln('本子: ${album.name}, totalPhotos=${album.totalPhotos}');

  final api = client.apiDomain!;
  final img = JmDomains.imageList.first;
  final html = JmDomains.htmlList.first;

  final candidates = <String>[
    'https://$img/media/photos/1474516/00001.webp',
    'https://$html/media/photos/1474516/00001.webp',
    'https://$html/media/albums/1474516.jpg',
    'https://$html/media/albums/1474516_3x4.jpg',
    'https://$html/media/albums/1474516.webp',
    'https://$api/media/albums/1474516.jpg',
    'https://$html/media/album/1474516.jpg',
  ];

  for (final url in candidates) {
    try {
      final r = await client.dio.get<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          headers: client.imageHeaders,
          validateStatus: (c) => c != null && c < 500,
        ),
      );
      final n = r.data?.length ?? 0;
      stdout.writeln('${r.statusCode}  ${n.toString().padLeft(8)} B  $url');
    } on Exception catch (e) {
      stdout.writeln('ERR              $url  ($e)');
    }
  }
}
