/// 统计每个本子在磁盘上占了多少空间
///
/// 放在后台 isolate 里做：书架上几十本、每本几百张图，逐张 stat 放在
/// 主线程跑，界面会明显卡一下。
library;

import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import '../jm/jm_storage.dart';

class ShelfSizes {
  ShelfSizes._();

  /// 返回「源 + 本子号」（即 SourceId.key）到字节数的映射
  ///
  /// 可以传多个根目录：下载目录改过之后，老书还留在老目录里，
  /// 只扫当前目录的话它们会显示成 0。
  static Future<Map<String, int>> scan(Iterable<String> roots) async {
    final list = <String>[];
    for (final root in roots) {
      final path = root.trim();
      if (path.isEmpty || path.startsWith('(') || list.contains(path)) continue;
      list.add(path);
    }
    if (list.isEmpty) return const {};

    try {
      return await Isolate.run(() => _scanSync(list));
    } on Object {
      // isolate 起不来（极少见）时退回主线程：慢一点，但总比不显示强
      return _scanSync(list);
    }
  }

  /// 整棵目录树走一遍，比每个本子单独列一次快得多
  static Map<String, int> _scanSync(List<String> roots) {
    final out = <String, int>{};

    for (final root in roots) {
      for (final source in JmStorage.sourceFolders.keys) {
        final sourceDir = Directory(JmStorage.sourceRoot(root, source));
        if (!sourceDir.existsSync()) continue;

        for (final album in sourceDir.listSync(followLinks: false)) {
          if (album is! Directory) continue;
          final albumId = p.basename(album.path);
          if (albumId.isEmpty || albumId.startsWith('.')) continue;

          var bytes = 0;
          for (final entity in album.listSync(
            recursive: true,
            followLinks: false,
          )) {
            if (entity is! File) continue;
            try {
              bytes += entity.lengthSync();
            } on FileSystemException {
              // 单张图读不到就跳过，不为了统计让整件事失败
            }
          }
          final key = '$source:$albumId';
          out[key] = (out[key] ?? 0) + bytes;
        }
      }
    }
    return out;
  }

  /// 字节数转成人看得懂的大小
  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    final text = unit == 0
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(value >= 100 ? 0 : 1);
    return '$text ${units[unit]}';
  }
}
