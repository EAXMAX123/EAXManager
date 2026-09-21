// 真实接口联调探针：验证域名探测 / 搜索 / 详情 / 图片还原
// 用法: dart run tool/jm_probe.dart [关键词]

import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:image/image.dart' as img;
import 'package:jm_reader/jm/jm_client.dart';
import 'package:jm_reader/jm/jm_scramble.dart';

Future<void> main(List<String> args) async {
  final keyword = args.isNotEmpty ? args.first : '无修正';
  final client = JmClient();

  stdout.writeln('=== 1. 域名探测 ===');
  await client.ensureReady();
  stdout.writeln('API 域名: ${client.apiDomain}');
  stdout.writeln('图片域名: ${client.imageDomain ?? "(未选)"}');

  stdout.writeln('\n=== 2. 搜索 "$keyword" ===');
  final page = await client.search(keyword, page: 1);
  stdout.writeln('总数: ${page.total}, 本页: ${page.items.length}');
  for (final item in page.items.take(5)) {
    stdout.writeln('  [${item.id}] ${item.name} / ${item.author} / ${item.category}');
  }
  if (page.items.isEmpty) {
    stdout.writeln('搜索无结果，终止');
    exit(0);
  }

  final albumId = page.items.first.id;
  stdout.writeln('\n=== 3. 本子详情 $albumId ===');
  final album = await client.albumDetail(albumId);
  stdout.writeln('标题: ${album.name}');
  stdout.writeln('作者: ${album.authorText}');
  stdout.writeln('标签: ${album.tags.join(", ")}');
  stdout.writeln('章节数: ${album.series.length}, 总图片: ${album.totalPhotos}');
  stdout.writeln('观看: ${album.views}, 点赞: ${album.likes}');

  final photoId = album.sortedSeries.isNotEmpty
      ? album.sortedSeries.first.id
      : albumId;
  stdout.writeln('\n=== 4. 章节详情 $photoId ===');
  var photo = await client.photoDetail(photoId);
  stdout.writeln('章节名: ${photo.name}, 图片数: ${photo.pageCount}');
  stdout.writeln('前 3 个文件名: ${photo.images.take(3).join(", ")}');

  stdout.writeln('\n=== 5. scramble_id ===');
  final scrambleId = await client.fetchScrambleId(photoId);
  photo = photo.copyWith(scrambleId: scrambleId);
  stdout.writeln('scramble_id = $scrambleId');

  if (photo.images.isEmpty) {
    stdout.writeln('无图片，终止');
    exit(0);
  }

  final fileName = photo.images.first;
  final bare = fileName.contains('.')
      ? fileName.substring(0, fileName.lastIndexOf('.'))
      : fileName;
  stdout.writeln('\n=== 6. 图片还原 ===');
  stdout.writeln('文件: $fileName');
  stdout.writeln('切割数: ${JmScramble.getNum(scrambleId, photoId, fileName)}');

  final url = client.imageUrl(photoId, fileName);
  stdout.writeln('URL: $url');

  final resp = await client.dio.get<List<int>>(
    url,
    options: Options(
      responseType: ResponseType.bytes,
      headers: client.imageHeaders,
    ),
  );
  final bytes = resp.data ?? const <int>[];
  stdout.writeln('下载字节: ${bytes.length}');

  final decoded = img.decodeImage(Uint8List.fromList(bytes));
  if (decoded == null) {
    stdout.writeln('图片解码失败');
    exit(1);
  }
  stdout.writeln('原图尺寸: ${decoded.width}x${decoded.height}');

  final num = JmScramble.getNum(scrambleId, photoId, fileName);
  final fixed = JmScramble.descramble(decoded, num);

  final outDir = Directory('tool/_probe_out')..createSync(recursive: true);
  File('${outDir.path}/raw_$bare.png').writeAsBytesSync(img.encodePng(decoded));
  File('${outDir.path}/fixed_$bare.png').writeAsBytesSync(img.encodePng(fixed));
  stdout.writeln('已输出: ${outDir.path}/raw_$bare.png 与 fixed_$bare.png');
  stdout.writeln('\n完成');
}
