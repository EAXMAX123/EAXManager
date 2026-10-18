/// 本地文件定位：换过下载目录、下载失败留下空目录之后，书还得找得到
///
/// 「界面说已下载、点进去说没下载」这个 bug 的根子就在这里：
/// 光看目录在不在不算数，得看里面到底有没有图。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jm_reader/jm/jm_storage.dart';
import 'package:jm_reader/services/local_library.dart';

void main() {
  group('JmStorage.hasImages', () {
    late Directory temp;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('jm_local_');
    });

    tearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    test('有图的目录返回 true', () async {
      await File('${temp.path}/00001.jpg').writeAsBytes([1]);
      expect(await JmStorage.hasImages(temp.path), isTrue);
    });

    test('空目录返回 false —— 下载失败留下的空目录不算已下载', () async {
      expect(await JmStorage.hasImages(temp.path), isFalse);
    });

    test('目录不存在也返回 false，不抛异常', () async {
      expect(await JmStorage.hasImages('${temp.path}/没有这个目录'), isFalse);
    });

    test('只有非图片文件不算', () async {
      await File('${temp.path}/.nomedia').writeAsString('');
      await File('${temp.path}/readme.txt').writeAsString('x');
      expect(await JmStorage.hasImages(temp.path), isFalse);
    });
  });

  group('JmStorage.localChapters', () {
    late Directory album;

    setUp(() async {
      album = await Directory.systemTemp.createTemp('jm_album_');
    });

    tearDown(() async {
      if (await album.exists()) await album.delete(recursive: true);
    });

    Future<void> addChapter(int index, {bool withImage = true}) async {
      final dir = Directory('${album.path}/$index');
      await dir.create(recursive: true);
      if (withImage) {
        await File('${dir.path}/00001.jpg').writeAsBytes([1]);
      }
    }

    test('只认有图的章节，按序号升序', () async {
      await addChapter(3);
      await addChapter(1);
      await addChapter(2, withImage: false);

      expect(await JmStorage.localChapters(album.path), [1, 3]);
    });

    test('忽略名字不是数字的目录', () async {
      await addChapter(1);
      final other = Directory('${album.path}/cache');
      await other.create();
      await File('${other.path}/00001.jpg').writeAsBytes([1]);

      expect(await JmStorage.localChapters(album.path), [1]);
    });

    test('目录不存在返回空表', () async {
      expect(await JmStorage.localChapters('${album.path}/没有'), isEmpty);
    });
  });

  group('LocalLibrary.candidateDirs', () {
    test('传进来的顺序就是优先级：数据库记的排在拼出来的前面', () {
      expect(LocalLibrary.candidateDirs(['/old/JM/123/1', '/new/JM/123/1']), [
        '/old/JM/123/1',
        '/new/JM/123/1',
      ]);
    });

    test('重复的只留一个', () {
      expect(LocalLibrary.candidateDirs(['/same/1', '/same/1']), ['/same/1']);
    });

    test('空白项直接丢掉', () {
      expect(LocalLibrary.candidateDirs(['  ', '/new/1', '']), ['/new/1']);
    });

    test('什么都没有就是空表', () {
      expect(LocalLibrary.candidateDirs(const []), isEmpty);
    });
  });

  group('LocalLibrary.staleChapterTaskIds', () {
    test('本地没有这一话的记录要清掉，有的留着', () {
      final stale = LocalLibrary.staleChapterTaskIds(
        const [
          (id: 1, chapterIndex: 1),
          (id: 2, chapterIndex: 2),
          (id: 3, chapterIndex: 3),
        ],
        {1, 3},
      );

      expect(stale, [2]);
    });

    test('本地一话都不剩时，记录全清', () {
      final stale = LocalLibrary.staleChapterTaskIds(const [
        (id: 7, chapterIndex: 1),
        (id: 8, chapterIndex: 2),
      ], const {});

      expect(stale, [7, 8]);
    });

    test('本地都在时什么都不清', () {
      expect(
        LocalLibrary.staleChapterTaskIds(const [(id: 1, chapterIndex: 1)], {1}),
        isEmpty,
      );
    });

    test('没有记录时返回空表', () {
      expect(LocalLibrary.staleChapterTaskIds(const [], {1}), isEmpty);
    });
  });

  group('每个源各自的下载目录', () {
    tearDown(() => JmStorage.setSourceRoots(const {}));

    test('没设置时按默认推导：JM 用根目录，其它源用旁边的同名文件夹', () {
      JmStorage.setSourceRoots(const {});

      expect(
        JmStorage.sourceRoot('/storage/emulated/0/JM', 'jm'),
        '/storage/emulated/0/JM',
      );
      expect(
        JmStorage.sourceRoot('/storage/emulated/0/JM', 'pica'),
        '/storage/emulated/0/Pica',
      );
      expect(
        JmStorage.sourceRoot('/storage/emulated/0/JM', 'eh'),
        '/storage/emulated/0/EH',
      );
    });

    test('设置过就用设置里的，三个源互不影响', () {
      JmStorage.setSourceRoots(const {
        'pica': '/sdcard/哔咔',
        'eh': '/sdcard/EH',
      });

      expect(
        JmStorage.sourceRoot('/storage/emulated/0/JM', 'jm'),
        '/storage/emulated/0/JM',
      );
      expect(
        JmStorage.sourceRoot('/storage/emulated/0/JM', 'pica'),
        '/sdcard/哔咔',
      );
      expect(
        JmStorage.sourceRoot('/storage/emulated/0/JM', 'eh'),
        '/sdcard/EH',
      );
    });

    test('单章目录 = 本子目录 / 章节号，photoDir 与它一致', () {
      expect(JmStorage.chapterDir('/JM/123', 4), '/JM/123/4');
      expect(JmStorage.photoDir('/JM', '123', 4), '/JM/123/4');
    });
  });
}
