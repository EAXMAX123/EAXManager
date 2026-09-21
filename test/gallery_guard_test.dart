/// 「下载目录不出现在相册」的回归测试
///
/// 下载一本本子是几百张图片，落在公共目录里会被系统相册整本收录，
/// 相册直接被刷屏。挡住它的只有目录里的 `.nomedia` 标记文件——
/// 这个文件一旦没人写，相册马上又会刷屏，所以拿测试钉住。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jm_reader/jm/jm_storage.dart';

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('jm_gallery_');
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  group('galleryGuardDirs', () {
    test('JM 根目录 + 各源的同级目录，且不重复', () {
      final dirs = JmStorage.galleryGuardDirs('/storage/emulated/0/JM');

      expect(dirs.first, '/storage/emulated/0/JM');
      // JM 自己既是根目录又是 jm 源目录，不能出现两次
      expect(dirs.where((e) => e.endsWith('JM')), hasLength(1));
      expect(dirs.where((e) => e.endsWith('Pica')), hasLength(1));
      expect(dirs.where((e) => e.endsWith('EH')), hasLength(1));
      expect(dirs.toSet(), hasLength(dirs.length));
    });

    test('用户自定下载目录时，各源的目录与它同级', () {
      final dirs = JmStorage.galleryGuardDirs(
        '/storage/emulated/0/Download/本子',
      );

      expect(dirs.first, '/storage/emulated/0/Download/本子');
      expect(dirs.where((e) => e.endsWith('Pica')), hasLength(1));
      expect(dirs.where((e) => e.endsWith('EH')), hasLength(1));
    });
  });

  group('writeNoMedia / removeNoMedia', () {
    test('每个目录都写出 .nomedia，重复写不报错', () async {
      final dirs = JmStorage.galleryGuardDirs('${temp.path}/JM');

      final written = await JmStorage.writeNoMedia(dirs);
      expect(written.length, dirs.length);
      for (final dir in dirs) {
        expect(
          File('$dir/${JmStorage.nomediaFileName}').existsSync(),
          isTrue,
          reason: '$dir 里应该有标记文件',
        );
      }

      expect(await JmStorage.writeNoMedia(dirs), hasLength(dirs.length));
    });

    test('关掉开关时能把标记删干净', () async {
      final dirs = JmStorage.galleryGuardDirs('${temp.path}/JM');
      await JmStorage.writeNoMedia(dirs);

      final removed = await JmStorage.removeNoMedia(dirs);

      expect(removed.length, dirs.length);
      for (final dir in dirs) {
        expect(File('$dir/${JmStorage.nomediaFileName}').existsSync(), isFalse);
      }
    });

    test('某个目录建不出来时跳过它，不连累其它目录', () async {
      final root = '${temp.path}/JM';
      await File(root).writeAsString('这里是个文件，不是目录');

      final written = await JmStorage.writeNoMedia(
        JmStorage.galleryGuardDirs(root),
      );

      expect(written, isNot(contains(root)));
      expect(written, isNotEmpty);
    });
  });
}
