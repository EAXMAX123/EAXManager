/// 从哪儿都能用的「打开阅读器」：电脑开独立窗口，手机还是页面里看
///
/// 电脑上另起一个进程，那个窗口单独拖动、缩放，主窗口留着继续挑本子；
/// 万一窗口没开起来（免安装版被杀软拦、路径没权限之类），
/// 就退回原来的「盖在应用上」，总之点了就能看。
library;

import 'package:flutter/material.dart';

import '../services/reader_window.dart';
import '../source/comic_source.dart';
import 'pages/reader_page.dart';

Future<void> openReader(
  BuildContext context, {
  required SourceId sid,
  required String albumTitle,
  required int chapterIndex,
  required int chapterCount,
}) async {
  // 先记下来：等窗口开完再读 context 会挨 lint，也不安全
  final navigator = Navigator.of(context);

  // 手机上这句会直接返回 false（不做任何事），电脑上才真的开窗口
  final opened = await ReaderWindowArgs(
    sid: sid,
    albumTitle: albumTitle,
    chapterIndex: chapterIndex,
    chapterCount: chapterCount,
  ).open();
  if (opened) return;

  await navigator.push(
    MaterialPageRoute(
      builder: (_) => ReaderPage(
        sid: sid,
        albumTitle: albumTitle,
        chapterIndex: chapterIndex,
        chapterCount: chapterCount,
      ),
    ),
  );
}
