/// 识图链路体检
///
/// 直接用 App 里的 ImageSearchService 走一遍：预处理 -> 上传 -> 解析结果。
/// 出包之前跑一次，能确认两个识图站都还活着、页面结构没变。
///
/// 用法：dart run tool/image_search_probe.dart <图片路径> [--no-segment]
// ignore_for_file: avoid_print
library;

import 'dart:io';

import 'package:jm_reader/net/net_transport.dart';
import 'package:jm_reader/source/image_search/google_lens_client.dart';
import 'package:jm_reader/source/image_search/image_prep.dart';
import 'package:jm_reader/source/image_search/image_search_service.dart';

Future<void> main(List<String> args) async {
  final path = args.isEmpty ? '' : args.first;
  if (path.isEmpty || !File(path).existsSync()) {
    print('用法：dart run tool/image_search_probe.dart <图片路径> [--no-segment]');
    exitCode = 2;
    return;
  }

  final segment = !args.contains('--no-segment');
  final bytes = File(path).readAsBytesSync();

  final prepared = ImagePrep.prepare(bytes);
  if (prepared == null) {
    print('这张图解不开');
    exitCode = 1;
    return;
  }
  print('原图：${bytes.length} 字节');
  print(
    '预处理后：${prepared.width}×${prepared.height}，'
    '${prepared.bytes.length} 字节，裁掉 ${prepared.inset} 像素',
  );
  final regions = ImagePrep.regions(prepared);
  print('分段：${regions.isEmpty ? '不切' : regions.map((e) => e.label).join(' / ')}');
  print('');

  final proxyArg = args.firstWhere(
    (e) => e.startsWith('--proxy='),
    orElse: () => '',
  );
  final transport = NetTransport(
    proxyUrl: proxyArg.isEmpty ? '' : proxyArg.substring('--proxy='.length),
  );
  print('代理：${proxyArg.isEmpty ? '（无）' : proxyArg}');

  if (args.contains('--lens')) {
    print('');
    print('--- Google Lens 上传 ---');
    try {
      final url = await GoogleLensClient(transport: transport).resultUrl(
        prepared.bytes,
      );
      print('结果页：$url');
    } on Exception catch (e) {
      print('失败：$e');
    }
    return;
  }

  final service = ImageSearchService(transport: transport);
  final started = DateTime.now();
  final report = await service.search(
    bytes,
    segmentRetry: segment,
    onProgress: (stage) => print('  · $stage'),
  );
  final cost = DateTime.now().difference(started);

  print('');
  print('用时：${cost.inMilliseconds} ms');
  print('请求记录：');
  for (final attempt in report.attempts) {
    print(
      attempt.ok
          ? '  ${attempt.engine} · ${attempt.region} -> ${attempt.count} 条'
          : '  ${attempt.engine} · ${attempt.region} -> 失败：${attempt.error}',
    );
  }
  if (report.notice.isNotEmpty) print('提示：${report.notice}');

  print('');
  print('结果 ${report.matches.length} 条：');
  for (final match in report.matches) {
    print(
      '  [${match.similarity.toStringAsFixed(2)}%] ${match.index} '
      '(${match.engine})  ${match.title.isEmpty ? '(无标题)' : match.title}'
      '${match.author.isEmpty ? '' : ' / ${match.author}'}',
    );
    if (match.sourceUrl.isNotEmpty) print('        ${match.sourceUrl}');
  }
}
