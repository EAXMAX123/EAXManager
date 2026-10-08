import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:jm_reader/data/app_database.dart';
import 'package:jm_reader/services/reading_progress_writer.dart';
import 'package:jm_reader/services/shelf_filter.dart';
import 'package:jm_reader/state/result_feed.dart';

BookshelfItem book(String id, {int read = 0, int downloaded = 1}) =>
    BookshelfItem.fromRow({
      'album_id': id,
      'title': '春日 ABC',
      'author': 'Alice',
      'last_read_at': read,
      'downloaded': downloaded,
    });

void main() {
  group('ResultFeed', () {
    test('old completion and old failure cannot replace a new request', () {
      final feed = ResultFeed<String>();
      final old = feed.begin(reset: true);
      final current = feed.begin(reset: true);
      expect(feed.complete(old, ['old'], page: 1, total: 1), isFalse);
      expect(feed.fail(old, 'old error'), isFalse);
      expect(feed.loading, isTrue);
      feed.complete(current, ['new'], page: 1, total: 1);
      expect(feed.items, ['new']);
      expect(feed.error, isNull);
    });

    test('search and rank requests are independent', () {
      final search = ResultFeed<String>();
      final rank = ResultFeed<String>();
      final revision = search.begin();
      rank.begin(reset: true);
      search.complete(revision, ['search'], page: 1, total: 5);
      expect(search.items, ['search']);
      expect(rank.items, isEmpty);
      expect(rank.loading, isTrue);
    });

    test('pagination appends and empty page terminates loading', () {
      final feed = ResultFeed<int>();
      feed.complete(feed.begin(), [1], page: 1, total: 100);
      feed.complete(feed.begin(), [2], page: 2, total: 100);
      expect(feed.items, [1, 2]);
      feed.complete(feed.begin(), [], page: 3, total: 100);
      expect(feed.total, 2);
      expect(feed.loading, isFalse);
    });

    test('failed pagination preserves items and last successful page', () {
      final feed = ResultFeed<int>();
      feed.complete(feed.begin(), [1], page: 1, total: 100);
      feed.fail(feed.begin(), 'offline');
      expect(feed.items, [1]);
      expect(feed.page, 1);
      expect(feed.error, 'offline');
      feed.complete(feed.begin(), [2], page: 2, total: 100);
      expect(feed.items, [1, 2]);
      expect(feed.error, isNull);
    });

    test('reset clears previous results and count', () {
      final feed = ResultFeed<int>();
      feed.complete(feed.begin(), [1], page: 2, total: 100);
      feed.begin(reset: true);
      expect(feed.items, isEmpty);
      expect(feed.page, 1);
      expect(feed.total, 0);
    });
  });

  group('ShelfFilter', () {
    test('matches trimmed title, author, ID and source ID without case', () {
      final item = book('1234');
      for (final query in [
        '',
        '  ',
        '春日',
        ' abc ',
        'ALICE',
        '123',
        'JM:1234',
      ]) {
        expect(ShelfFilter.matches(item, query), isTrue, reason: query);
      }
      expect(ShelfFilter.matches(item, 'missing'), isFalse);
    });

    test('continue reading excludes unread and non-downloaded works', () {
      final recent = book('recent', read: 20);
      expect(
        ShelfFilter.latestRead([
          book('old', read: 10),
          recent,
          book('unread'),
          book('not-local', read: 30, downloaded: 0),
        ]),
        same(recent),
      );
      expect(ShelfFilter.latestRead([book('unread')]), isNull);
      expect(ShelfFilter.latestRead([]), isNull);
    });
  });

  group('ReadingProgressWriter', () {
    test(
      'serializes saves and coalesces repeated exit/background saves',
      () async {
        final gate = Completer<void>();
        final pages = <int>[];
        final writer = ReadingProgressWriter((page) async {
          if (page == 1) await gate.future;
          pages.add(page);
        }, onError: (error, stack) => fail('$error'));
        writer.save(1);
        writer.save(7);
        final finished = writer.save(7);
        await Future<void>.delayed(Duration.zero);
        expect(pages, isEmpty);
        gate.complete();
        await finished;
        expect(pages, [1, 7]);
      },
    );

    test('failed write can retry without breaking subsequent saves', () async {
      var attempts = 0;
      final errors = <Object>[];
      final pages = <int>[];
      final writer = ReadingProgressWriter((page) async {
        if (++attempts == 1) throw StateError('storage unavailable');
        pages.add(page);
      }, onError: (error, stack) => errors.add(error));
      await writer.save(3);
      await writer.save(3);
      await writer.save(4);
      await writer.save(0);
      expect(errors, hasLength(1));
      expect(pages, [3, 4]);
    });
  });
}
