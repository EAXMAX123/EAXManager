/// 检查更新探针：验证「更新信息文件」能不能被正确解析
///
/// 用法：
///   dart run tool/update_probe.dart D:\KAIFA\安装包\update.json
///   dart run tool/update_probe.dart https://cdn.jsdelivr.net/gh/…/update.json
// ignore_for_file: avoid_print
library;

import 'dart:io';

import 'package:jm_reader/app_info.dart';
import 'package:jm_reader/services/update_service.dart';

Future<void> main(List<String> args) async {
  final target = args.isEmpty ? '' : args.first.trim();
  if (target.isEmpty) {
    print('用法：dart run tool/update_probe.dart <文件路径或网址>');
    return;
  }

  print('当前版本：${AppInfo.fullVersionText}');

  if (target.startsWith('http')) {
    for (final url in UpdateService.candidates(target)) {
      final text = await UpdateService.fetchText(url);
      print(
        text == null
            ? '连不上：$url'
            : '通：$url\n${text.trim()}\n---',
      );
    }
    final update = await UpdateService.check(target);
    print(
      update == null
          ? '=> 没有新版本（或者网址连不上、内容不合法）'
          : '=> 发现新版本 v${update.version}',
    );
    return;
  }

  final file = File(target);
  if (!file.existsSync()) {
    print('文件不存在：$target');
    return;
  }

  final update = UpdateService.parsePayload(file.readAsStringSync());
  if (update == null) {
    print('=> 解析失败：内容不是合法的更新信息');
    return;
  }

  print('版本号：${update.version}');
  print('下载地址：${update.url.isEmpty ? '（留空，弹窗会提示去交流群拿安装包）' : update.url}');
  print('说明：\n${update.notes}');
  print(
    UpdateService.compareVersion(update.version, AppInfo.version) > 0
        ? '=> 会被判定为「有新版本」'
        : '=> 会被判定为「已是最新」',
  );
}
