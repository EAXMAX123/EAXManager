import '../data/app_database.dart';

class ShelfFilter {
  static bool matches(BookshelfItem item, String query) {
    final term = query.trim().toLowerCase();
    return term.isEmpty ||
        [
          item.title,
          item.author,
          item.albumId,
          item.sid.key,
        ].any((value) => value.toLowerCase().contains(term));
  }

  static BookshelfItem? latestRead(Iterable<BookshelfItem> items) {
    BookshelfItem? latest;
    for (final item in items) {
      if (item.downloaded > 0 &&
          item.lastReadAt > 0 &&
          (latest == null || item.lastReadAt > latest.lastReadAt)) {
        latest = item;
      }
    }
    return latest;
  }
}
