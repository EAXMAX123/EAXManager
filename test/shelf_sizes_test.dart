/// 书架「占用空间」：大小统计与显示格式
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jm_reader/services/shelf_sizes.dart';

void main() {
  group('formatBytes', () {
    test('按 1024 进位', () {
      expect(ShelfSizes.formatBytes(0), '0 B');
      expect(ShelfSizes.formatBytes(512), '512 B');
      expect(ShelfSizes.formatBytes(1024), '1.0 KB');
      expect(ShelfSizes.formatBytes(1024 * 1024), '1.0 MB');
      expect(ShelfSizes.formatBytes(1024 * 1024 * 1024), '1.0 GB');
    });

    test('大数值不带小数，读数不至于太长', () {
      expect(ShelfSizes.formatBytes(300 * 1024 * 1024), '300 MB');
    });
  });

  group('scan', () {
    late Directory temp;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('jm_sizes_');
    });

    tearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    test('把整本的图片加起来，键是「源:本子号」', () async {
      final chapter = Directory('${temp.path}/1474516/1');
      await chapter.create(recursive: true);
      await File('${chapter.path}/00001.jpg').writeAsBytes(List.filled(100, 0));
      await File('${chapter.path}/00002.jpg').writeAsBytes(List.filled(50, 0));

      final sizes = await ShelfSizes.scan([temp.path]);

      expect(sizes['jm:1474516'], 150);
    });

    test('多章节一起算', () async {
      for (final index in [1, 2]) {
        final chapter = Directory('${temp.path}/999/$index');
        await chapter.create(recursive: true);
        await File('${chapter.path}/00001.jpg')
            .writeAsBytes(List.filled(40, 0));
      }

      final sizes = await ShelfSizes.scan([temp.path]);

      expect(sizes['jm:999'], 80);
    });

    test('目录不存在时返回空表，不抛异常', () async {
      expect(await ShelfSizes.scan(['${temp.path}/没有这个目录']), isEmpty);
    });

    test('空路径直接返回空表', () async {
      expect(await ShelfSizes.scan(['  ']), isEmpty);
    });

    test('多个根目录一起算：老书留在老目录里也能统计到', () async {
      final old = await Directory.systemTemp.createTemp('jm_sizes_old_');
      addTearDown(() async {
        if (await old.exists()) await old.delete(recursive: true);
      });

      final chapter = Directory('${old.path}/888/1');
      await chapter.create(recursive: true);
      await File('${chapter.path}/00001.jpg').writeAsBytes(List.filled(70, 0));

      final sizes = await ShelfSizes.scan([temp.path, old.path]);

      expect(sizes['jm:888'], 70);
    });
  });
}
