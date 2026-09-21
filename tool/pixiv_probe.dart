/// Pixiv 链路体检
///
/// 直接用 App 里的 PixivSource 走一遍：搜索 -> 详情 -> 章节计划 -> 真的下几张图。
/// 出包之前跑一次，能确认镜像和反代都还活着。
///
/// 用法：dart run tool/pixiv_probe.dart [关键词]
// ignore_for_file: avoid_print
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:jm_reader/source/comic_source.dart';
import 'package:jm_reader/source/pixiv/pixiv_source.dart';

Future<void> main(List<String> args) async {
  final keyword = args.isEmpty ? '巨乳' : args.first;
  final source = PixivSource();

  print('关键词：$keyword');
  print('镜像：${source.client.apiBases}');
  print('反代：${source.client.imageProxyHost}（共 ${source.client.imageProxies.length} 个备用）');
  print('');

  await _checkSearch(source, keyword, SearchMode.site, '综合');
  await _checkSearch(source, keyword, SearchMode.work, '作品');
  await _checkSearch(source, keyword, SearchMode.tag, '标签');
  await _checkSearch(source, keyword, SearchMode.author, '作者');
  await _checkPaging(source, keyword);
  await _checkDownload(source, keyword);
  await _checkRotate(source, keyword);
}

Future<void> _checkSearch(
  PixivSource source,
  String keyword,
  SearchMode mode,
  String label,
) async {
  try {
    final page = await source.search(keyword, mode: mode);
    final first = page.items.isEmpty ? '（空）' : page.items.first.title;
    print('[搜索/$label] ${page.items.length} 条，首条：$first');
  } on Exception catch (e) {
    print('[搜索/$label] 失败：$e');
  }
}

Future<void> _checkPaging(PixivSource source, String keyword) async {
  try {
    final p1 = await source.search(keyword, page: 1);
    final p2 = await source.search(keyword, page: 2);
    final same = p1.items.isNotEmpty &&
        p2.items.isNotEmpty &&
        p1.items.first.sid.id == p2.items.first.sid.id;
    print('[翻页] 第1页 ${p1.items.length} 条 / 第2页 ${p2.items.length} 条，'
        '${same ? '两页内容一样（有问题）' : '两页内容不同（正常）'}');
  } on Exception catch (e) {
    print('[翻页] 失败：$e');
  }
}

Future<void> _checkDownload(PixivSource source, String keyword) async {
  try {
    final page = await source.search(keyword);
    if (page.items.isEmpty) {
      print('[下载] 搜索没结果，跳过');
      return;
    }

    // 挑一个多页的，才能真正验证 meta_pages 那条路
    ComicItem? target;
    for (final item in page.items.take(8)) {
      final detail = await source.detail(item.sid.id);
      if (detail.chapterCount > 0 &&
          (detail.meta.firstWhere(
                    (e) => e.key == '页数',
                    orElse: () => const MapEntry('页数', '0'),
                  ).value !=
                  '1')) {
        target = item;
        break;
      }
      target ??= item;
    }
    if (target == null) {
      print('[下载] 没挑到合适的作品');
      return;
    }

    final detail = await source.detail(target.sid.id);
    print('[详情] ${detail.title} / ${detail.authorText} / '
        '${detail.chapters.first.title} / 标签 ${detail.tags.take(5).toList()}');

    final plan = await source.chapterPlan(detail, detail.chapters.first);
    print('[章节计划] ${plan.images.length} 张，第一张 ${plan.images.first.url}');

    final dir = Directory.systemTemp.createTempSync('pixiv_probe_');
    var ok = 0;
    var fail = 0;
    final limit = plan.images.length < 3 ? plan.images.length : 3;
    for (var i = 0; i < limit; i++) {
      final image = plan.images[i];
      try {
        final resp = await source.dio.get<List<int>>(
          image.url,
          options: _bytesOptions(image.headers),
        );
        final bytes = resp.data ?? const <int>[];
        if (bytes.isEmpty) {
          fail++;
          print('  第 ${i + 1} 张：空响应');
        } else {
          ok++;
          print('  第 ${i + 1} 张：${(bytes.length / 1024).round()} KB');
        }
      } on Exception catch (e) {
        fail++;
        print('  第 ${i + 1} 张失败：$e');
      }
    }
    dir.deleteSync(recursive: true);
    print('[下载] 成功 $ok / 失败 $fail');
  } on Exception catch (e) {
    print('[下载] 失败：$e');
  }
}

/// 故意把第一个反代指到一个不存在的域名，验证换域名重试这条线
Future<void> _checkRotate(PixivSource source, String keyword) async {
  final bad = PixivSource(
    imageProxies: ['definitely-not-a-real-proxy.invalid', 'i.pixiv.re'],
  );
  try {
    final page = await bad.search(keyword);
    if (page.items.isEmpty) {
      print('[换反代] 搜索没结果，跳过');
      return;
    }
    final detail = await bad.detail(page.items.first.sid.id);
    final plan = await bad.chapterPlan(detail, detail.chapters.first);

    var refreshed = plan.images.first;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final resp = await bad.dio.get<List<int>>(
          refreshed.url,
          options: _bytesOptions(refreshed.headers),
        );
        final bytes = resp.data ?? const <int>[];
        if (bytes.isNotEmpty) {
          print('[换反代] 第 ${attempt + 1} 次拿到 ${(bytes.length / 1024).round()} KB，'
              '当前域名 ${bad.client.imageProxyHost}');
          return;
        }
      } on Exception {
        // 换个域名再试，和下载器里的做法一致
      }
      final next = plan.refresh?.call(0);
      if (next != null) refreshed = next;
    }
    print('[换反代] 三次都没拿到图');
  } on Exception catch (e) {
    print('[换反代] 失败：$e');
  }
}

Options _bytesOptions(Map<String, String> headers) => Options(
  responseType: ResponseType.bytes,
  headers: headers,
);
