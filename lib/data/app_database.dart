/// 本地数据库：书架、下载任务、追更订阅、书架分类
///
/// v2 起支持多源：三张表都加了 `source` 列，主键改成 (source, album_id)，
/// 避免 JM 和 EH 这种纯数字 ID 互相撞车。
///
/// v3 起：下载任务记录实际落盘目录（`dir_path`），并加入书架分类表。
library;

import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../source/comic_source.dart';

class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  Database? _db;

  Future<Database> get database async => _db ??= await _open();

  Future<Database> _open() async {
    final dir = await getDatabasesPath();
    final path = p.join(dir, 'jm_reader.db');
    return openDatabase(
      path,
      version: 3,
      onCreate: (db, version) => _createTables(db),
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) await _migrateV1ToV2(db);
        if (oldVersion < 3) await _migrateV2ToV3(db);
      },
    );
  }

  static Future<void> _createTables(Database db) async {
    await db.execute('''
      CREATE TABLE bookshelf (
        source          TEXT NOT NULL DEFAULT 'jm',
        album_id        TEXT NOT NULL,
        title           TEXT NOT NULL DEFAULT '',
        author          TEXT NOT NULL DEFAULT '',
        cover_url       TEXT NOT NULL DEFAULT '',
        tags            TEXT NOT NULL DEFAULT '',
        chapter_count   INTEGER NOT NULL DEFAULT 0,
        downloaded      INTEGER NOT NULL DEFAULT 0,
        root_path       TEXT NOT NULL DEFAULT '',
        last_chapter    INTEGER NOT NULL DEFAULT 1,
        last_page       INTEGER NOT NULL DEFAULT 1,
        last_read_at    INTEGER NOT NULL DEFAULT 0,
        created_at      INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (source, album_id)
      )
    ''');

    await db.execute('''
      CREATE TABLE download_task (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        source          TEXT NOT NULL DEFAULT 'jm',
        album_id        TEXT NOT NULL,
        album_title     TEXT NOT NULL DEFAULT '',
        chapter_id      TEXT NOT NULL,
        chapter_index   INTEGER NOT NULL DEFAULT 1,
        chapter_title   TEXT NOT NULL DEFAULT '',
        status          TEXT NOT NULL DEFAULT 'pending',
        done            INTEGER NOT NULL DEFAULT 0,
        total           INTEGER NOT NULL DEFAULT 0,
        failed          INTEGER NOT NULL DEFAULT 0,
        error           TEXT NOT NULL DEFAULT '',
        dir_path        TEXT NOT NULL DEFAULT '',
        created_at      INTEGER NOT NULL DEFAULT 0,
        updated_at      INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute(
      'CREATE UNIQUE INDEX idx_task_chapter '
      'ON download_task(source, album_id, chapter_id)',
    );

    await db.execute('''
      CREATE TABLE subscription (
        source          TEXT NOT NULL DEFAULT 'jm',
        album_id        TEXT NOT NULL,
        title           TEXT NOT NULL DEFAULT '',
        author          TEXT NOT NULL DEFAULT '',
        known_chapters  INTEGER NOT NULL DEFAULT 0,
        last_check_at   INTEGER NOT NULL DEFAULT 0,
        created_at      INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (source, album_id)
      )
    ''');

    await _createCategoryTables(db);
  }

  /// 书架分类：分类表 + 本子与分类的关联表
  static Future<void> _createCategoryTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS category (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        name        TEXT NOT NULL UNIQUE,
        sort        INTEGER NOT NULL DEFAULT 0,
        created_at  INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS album_category (
        source      TEXT NOT NULL,
        album_id    TEXT NOT NULL,
        category_id INTEGER NOT NULL,
        PRIMARY KEY (source, album_id, category_id)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_album_category_cat '
      'ON album_category(category_id)',
    );
  }

  /// v2 -> v3：下载任务补上落盘目录，并建分类表。老数据原样保留。
  static Future<void> _migrateV2ToV3(Database db) async {
    final columns = await db.rawQuery('PRAGMA table_info(download_task)');
    final hasDirPath = columns.any((c) => c['name'] == 'dir_path');
    if (!hasDirPath) {
      await db.execute(
        "ALTER TABLE download_task ADD COLUMN dir_path TEXT NOT NULL DEFAULT ''",
      );
    }
    await _createCategoryTables(db);
  }

  /// v1 -> v2：加 source 列、主键改复合。老数据全部归到 jm 源，不丢书。
  static Future<void> _migrateV1ToV2(Database db) async {
    await db.execute('ALTER TABLE bookshelf RENAME TO bookshelf_v1');
    await db.execute('ALTER TABLE download_task RENAME TO download_task_v1');
    await db.execute('ALTER TABLE subscription RENAME TO subscription_v1');
    await db.execute('DROP INDEX IF EXISTS idx_task_chapter');

    await _createTables(db);

    await db.execute('''
      INSERT INTO bookshelf (source, album_id, title, author, cover_url, tags,
                             chapter_count, downloaded, root_path, last_chapter,
                             last_page, last_read_at, created_at)
      SELECT 'jm', album_id, title, author, cover_url, tags, chapter_count,
             downloaded, root_path, last_chapter, last_page, last_read_at,
             created_at
      FROM bookshelf_v1
    ''');
    await db.execute('''
      INSERT INTO download_task (id, source, album_id, album_title, chapter_id,
                                 chapter_index, chapter_title, status, done,
                                 total, failed, error, created_at, updated_at)
      SELECT id, 'jm', album_id, album_title, chapter_id, chapter_index,
             chapter_title, status, done, total, failed, error, created_at,
             updated_at
      FROM download_task_v1
    ''');
    await db.execute('''
      INSERT INTO subscription (source, album_id, title, author, known_chapters,
                                last_check_at, created_at)
      SELECT 'jm', album_id, title, author, known_chapters, last_check_at,
             created_at
      FROM subscription_v1
    ''');

    await db.execute('DROP TABLE bookshelf_v1');
    await db.execute('DROP TABLE download_task_v1');
    await db.execute('DROP TABLE subscription_v1');
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}

/// 书架条目
class BookshelfItem {
  const BookshelfItem({
    required this.source,
    required this.albumId,
    required this.title,
    required this.author,
    required this.coverUrl,
    required this.tags,
    required this.chapterCount,
    required this.downloaded,
    required this.rootPath,
    required this.lastChapter,
    required this.lastPage,
    required this.lastReadAt,
    required this.createdAt,
  });

  final String source;
  final String albumId;
  final String title;
  final String author;
  final String coverUrl;
  final String tags;
  final int chapterCount;
  final int downloaded;
  final String rootPath;
  final int lastChapter;
  final int lastPage;
  final int lastReadAt;
  final int createdAt;

  SourceId get sid => SourceId(source, albumId);

  double get progress =>
      chapterCount == 0 ? 0 : (downloaded / chapterCount).clamp(0, 1);

  factory BookshelfItem.fromRow(Map<String, Object?> row) => BookshelfItem(
    source: row['source'] as String? ?? 'jm',
    albumId: row['album_id'] as String,
    title: row['title'] as String? ?? '',
    author: row['author'] as String? ?? '',
    coverUrl: row['cover_url'] as String? ?? '',
    tags: row['tags'] as String? ?? '',
    chapterCount: row['chapter_count'] as int? ?? 0,
    downloaded: row['downloaded'] as int? ?? 0,
    rootPath: row['root_path'] as String? ?? '',
    lastChapter: row['last_chapter'] as int? ?? 1,
    lastPage: row['last_page'] as int? ?? 1,
    lastReadAt: row['last_read_at'] as int? ?? 0,
    createdAt: row['created_at'] as int? ?? 0,
  );
}

/// 下载任务状态
enum DownloadStatus { pending, running, paused, done, failed }

extension DownloadStatusX on DownloadStatus {
  static DownloadStatus parse(String value) => DownloadStatus.values.firstWhere(
    (e) => e.name == value,
    orElse: () => DownloadStatus.pending,
  );
}

/// 下载任务
class DownloadTask {
  const DownloadTask({
    required this.id,
    this.source = 'jm',
    required this.albumId,
    required this.albumTitle,
    required this.chapterId,
    required this.chapterIndex,
    required this.chapterTitle,
    required this.status,
    required this.done,
    required this.total,
    required this.failed,
    required this.error,
    this.dirPath = '',
  });

  final int id;
  final String source;
  final String albumId;
  final String albumTitle;
  final String chapterId;
  final int chapterIndex;
  final String chapterTitle;
  final DownloadStatus status;
  final int done;
  final int total;
  final int failed;
  final String error;

  /// 这一章实际落盘的目录
  ///
  /// 有了它，「已下载」就不用靠猜路径——重装应用、换下载目录、权限变化之后
  /// 都还能把书认回来。
  final String dirPath;

  SourceId get sid => SourceId(source, albumId);

  double get progress => total == 0 ? 0 : (done / total).clamp(0, 1);

  DownloadTask copyWith({
    DownloadStatus? status,
    int? done,
    int? total,
    int? failed,
    String? error,
    String? dirPath,
  }) => DownloadTask(
    id: id,
    source: source,
    albumId: albumId,
    albumTitle: albumTitle,
    chapterId: chapterId,
    chapterIndex: chapterIndex,
    chapterTitle: chapterTitle,
    status: status ?? this.status,
    done: done ?? this.done,
    total: total ?? this.total,
    failed: failed ?? this.failed,
    error: error ?? this.error,
    dirPath: dirPath ?? this.dirPath,
  );

  factory DownloadTask.fromRow(Map<String, Object?> row) => DownloadTask(
    id: row['id'] as int,
    source: row['source'] as String? ?? 'jm',
    albumId: row['album_id'] as String,
    albumTitle: row['album_title'] as String? ?? '',
    chapterId: row['chapter_id'] as String,
    chapterIndex: row['chapter_index'] as int? ?? 1,
    chapterTitle: row['chapter_title'] as String? ?? '',
    status: DownloadStatusX.parse(row['status'] as String? ?? 'pending'),
    done: row['done'] as int? ?? 0,
    total: row['total'] as int? ?? 0,
    failed: row['failed'] as int? ?? 0,
    error: row['error'] as String? ?? '',
    dirPath: row['dir_path'] as String? ?? '',
  );
}

/// 书架分类
class ShelfCategory {
  const ShelfCategory({
    required this.id,
    required this.name,
    required this.sort,
  });

  final int id;
  final String name;
  final int sort;

  factory ShelfCategory.fromRow(Map<String, Object?> row) => ShelfCategory(
    id: row['id'] as int,
    name: row['name'] as String? ?? '',
    sort: row['sort'] as int? ?? 0,
  );
}

/// 追更订阅
class SubscriptionItem {
  const SubscriptionItem({
    this.source = 'jm',
    required this.albumId,
    required this.title,
    required this.author,
    required this.knownChapters,
    required this.lastCheckAt,
  });

  final String source;
  final String albumId;
  final String title;
  final String author;
  final int knownChapters;
  final int lastCheckAt;

  SourceId get sid => SourceId(source, albumId);

  factory SubscriptionItem.fromRow(Map<String, Object?> row) =>
      SubscriptionItem(
        source: row['source'] as String? ?? 'jm',
        albumId: row['album_id'] as String,
        title: row['title'] as String? ?? '',
        author: row['author'] as String? ?? '',
        knownChapters: row['known_chapters'] as int? ?? 0,
        lastCheckAt: row['last_check_at'] as int? ?? 0,
      );
}

/// 数据访问
class AppDao {
  AppDao(this._db);

  final AppDatabase _db;

  static int _now() => DateTime.now().millisecondsSinceEpoch;

  // ==================== 书架 ====================

  Future<void> upsertBookshelf({
    required SourceId sid,
    required String title,
    required String author,
    required String coverUrl,
    required String tags,
    required int chapterCount,
    required int downloaded,
    required String rootPath,
  }) async {
    final db = await _db.database;
    final existing = await db.query(
      'bookshelf',
      where: 'source = ? AND album_id = ?',
      whereArgs: [sid.source, sid.id],
      limit: 1,
    );

    // 已存在时只更新元信息，避免覆盖阅读进度（last_chapter / last_page）
    if (existing.isNotEmpty) {
      await db.update(
        'bookshelf',
        {
          'title': title,
          'author': author,
          'cover_url': coverUrl,
          'tags': tags,
          'chapter_count': chapterCount,
          'root_path': rootPath,
        },
        where: 'source = ? AND album_id = ?',
        whereArgs: [sid.source, sid.id],
      );
      return;
    }

    await db.insert('bookshelf', {
      'source': sid.source,
      'album_id': sid.id,
      'title': title,
      'author': author,
      'cover_url': coverUrl,
      'tags': tags,
      'chapter_count': chapterCount,
      'downloaded': downloaded,
      'root_path': rootPath,
      'created_at': _now(),
    });
  }

  Future<List<BookshelfItem>> listBookshelf() async {
    final db = await _db.database;
    final rows = await db.query(
      'bookshelf',
      orderBy: 'last_read_at DESC, created_at DESC',
    );
    return rows.map(BookshelfItem.fromRow).toList();
  }

  Future<BookshelfItem?> getBookshelf(SourceId sid) async {
    final db = await _db.database;
    final rows = await db.query(
      'bookshelf',
      where: 'source = ? AND album_id = ?',
      whereArgs: [sid.source, sid.id],
      limit: 1,
    );
    return rows.isEmpty ? null : BookshelfItem.fromRow(rows.first);
  }

  Future<void> updateDownloaded(SourceId sid, int downloaded) async {
    final db = await _db.database;
    await db.update(
      'bookshelf',
      {'downloaded': downloaded},
      where: 'source = ? AND album_id = ?',
      whereArgs: [sid.source, sid.id],
    );
  }

  Future<void> updateReadProgress(
    SourceId sid,
    int chapterIndex,
    int page,
  ) async {
    final db = await _db.database;
    await db.update(
      'bookshelf',
      {'last_chapter': chapterIndex, 'last_page': page, 'last_read_at': _now()},
      where: 'source = ? AND album_id = ?',
      whereArgs: [sid.source, sid.id],
    );
  }

  Future<void> removeBookshelf(SourceId sid) async {
    final db = await _db.database;
    await db.delete(
      'bookshelf',
      where: 'source = ? AND album_id = ?',
      whereArgs: [sid.source, sid.id],
    );
  }

  // ==================== 下载任务 ====================

  Future<int> upsertTask(DownloadTask task) async {
    final db = await _db.database;
    final existing = await db.query(
      'download_task',
      where: 'source = ? AND album_id = ? AND chapter_id = ?',
      whereArgs: [task.source, task.albumId, task.chapterId],
      limit: 1,
    );
    final now = _now();
    if (existing.isNotEmpty) {
      final id = existing.first['id'] as int;
      await db.update(
        'download_task',
        {
          'status': task.status.name,
          'done': task.done,
          'total': task.total,
          'failed': task.failed,
          'error': task.error,
          'dir_path': task.dirPath,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      return id;
    }
    return db.insert('download_task', {
      'source': task.source,
      'album_id': task.albumId,
      'album_title': task.albumTitle,
      'chapter_id': task.chapterId,
      'chapter_index': task.chapterIndex,
      'chapter_title': task.chapterTitle,
      'status': task.status.name,
      'done': task.done,
      'total': task.total,
      'failed': task.failed,
      'error': task.error,
      'dir_path': task.dirPath,
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<List<DownloadTask>> listTasks() async {
    final db = await _db.database;
    final rows = await db.query('download_task', orderBy: 'created_at DESC');
    return rows.map(DownloadTask.fromRow).toList();
  }

  Future<void> deleteTask(int id) async {
    final db = await _db.database;
    await db.delete('download_task', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteTasksByAlbum(SourceId sid) async {
    final db = await _db.database;
    await db.delete(
      'download_task',
      where: 'source = ? AND album_id = ?',
      whereArgs: [sid.source, sid.id],
    );
  }

  /// 记下这一章实际落盘的目录
  Future<void> updateTaskDir(int id, String dirPath) async {
    final db = await _db.database;
    await db.update(
      'download_task',
      {'dir_path': dirPath},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 某本书里所有「已下载」章节的落盘目录（用于界面判断本地有没有内容）
  Future<List<String>> downloadedDirsOf(SourceId sid) async {
    final db = await _db.database;
    final rows = await db.query(
      'download_task',
      columns: ['dir_path'],
      where: 'source = ? AND album_id = ? AND status = ? AND dir_path != ?',
      whereArgs: [sid.source, sid.id, DownloadStatus.done.name, ''],
    );
    return rows.map((e) => e['dir_path'] as String).toList();
  }

  /// 数据库里记过的「章节序号 -> 实际落盘目录」
  ///
  /// 下载目录被改过（换目录、后来才授存储权限）之后，按当前目录拼出来的
  /// 路径会指向空地方，靠这份记录才能把以前下好的书找回来。
  Future<Map<int, String>> recordedChapterDirs(SourceId sid) async {
    final db = await _db.database;
    final rows = await db.query(
      'download_task',
      columns: ['chapter_index', 'dir_path'],
      where: 'source = ? AND album_id = ? AND dir_path != ?',
      whereArgs: [sid.source, sid.id, ''],
    );
    final out = <int, String>{};
    for (final row in rows) {
      final index = row['chapter_index'] as int? ?? 0;
      final dir = (row['dir_path'] as String? ?? '').trim();
      if (index <= 0 || dir.isEmpty) continue;
      out[index] = dir;
    }
    return out;
  }

  /// 应用启动时把残留的 running 状态重置，避免界面卡在「下载中」
  Future<void> resetRunningTasks() async {
    final db = await _db.database;
    await db.update(
      'download_task',
      {'status': DownloadStatus.paused.name},
      where: 'status = ?',
      whereArgs: [DownloadStatus.running.name],
    );
  }

  // ==================== 订阅 ====================

  Future<void> upsertSubscription({
    required SourceId sid,
    required String title,
    required String author,
    required int knownChapters,
  }) async {
    final db = await _db.database;
    final existing = await db.query(
      'subscription',
      where: 'source = ? AND album_id = ?',
      whereArgs: [sid.source, sid.id],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      await db.update(
        'subscription',
        {
          'title': title,
          'author': author,
          'known_chapters': knownChapters,
          'last_check_at': _now(),
        },
        where: 'source = ? AND album_id = ?',
        whereArgs: [sid.source, sid.id],
      );
      return;
    }
    await db.insert('subscription', {
      'source': sid.source,
      'album_id': sid.id,
      'title': title,
      'author': author,
      'known_chapters': knownChapters,
      'last_check_at': _now(),
      'created_at': _now(),
    });
  }

  Future<List<SubscriptionItem>> listSubscriptions() async {
    final db = await _db.database;
    final rows = await db.query('subscription', orderBy: 'created_at DESC');
    return rows.map(SubscriptionItem.fromRow).toList();
  }

  Future<void> updateSubscriptionCheck(SourceId sid, int knownChapters) async {
    final db = await _db.database;
    await db.update(
      'subscription',
      {'known_chapters': knownChapters, 'last_check_at': _now()},
      where: 'source = ? AND album_id = ?',
      whereArgs: [sid.source, sid.id],
    );
  }

  Future<void> removeSubscription(SourceId sid) async {
    final db = await _db.database;
    await db.delete(
      'subscription',
      where: 'source = ? AND album_id = ?',
      whereArgs: [sid.source, sid.id],
    );
  }

  // ==================== 书架分类 ====================

  Future<List<ShelfCategory>> listCategories() async {
    final db = await _db.database;
    final rows = await db.query('category', orderBy: 'sort ASC, id ASC');
    return rows.map(ShelfCategory.fromRow).toList();
  }

  /// 新建分类；重名时直接返回已有分类的 id，不报错
  Future<int> createCategory(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 0;
    final db = await _db.database;
    final existing = await db.query(
      'category',
      columns: ['id'],
      where: 'name = ?',
      whereArgs: [trimmed],
      limit: 1,
    );
    if (existing.isNotEmpty) return existing.first['id'] as int;
    return db.insert('category', {
      'name': trimmed,
      'sort': _now(),
      'created_at': _now(),
    });
  }

  Future<void> renameCategory(int id, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final db = await _db.database;
    await db.update(
      'category',
      {'name': trimmed},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 删分类只删分类本身，书还在书架上，不会跟着没
  Future<void> deleteCategory(int id) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      await txn.delete(
        'album_category',
        where: 'category_id = ?',
        whereArgs: [id],
      );
      await txn.delete('category', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<List<int>> categoryIdsOf(SourceId sid) async {
    final db = await _db.database;
    final rows = await db.query(
      'album_category',
      columns: ['category_id'],
      where: 'source = ? AND album_id = ?',
      whereArgs: [sid.source, sid.id],
    );
    return rows.map((e) => e['category_id'] as int).toList();
  }

  /// 覆盖式设置某个本子的分类
  Future<void> setCategoriesOf(SourceId sid, List<int> categoryIds) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      await txn.delete(
        'album_category',
        where: 'source = ? AND album_id = ?',
        whereArgs: [sid.source, sid.id],
      );
      for (final id in categoryIds) {
        await txn.insert('album_category', {
          'source': sid.source,
          'album_id': sid.id,
          'category_id': id,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    });
  }

  /// 每个分类下的本子数量
  Future<Map<int, int>> categoryCounts() async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      'SELECT category_id, COUNT(*) AS n FROM album_category '
      'GROUP BY category_id',
    );
    return {
      for (final row in rows)
        row['category_id'] as int: (row['n'] as int?) ?? 0,
    };
  }

  /// 分类 id -> 该分类下所有本子的 key（形如 `jm:1474516`）
  ///
  /// 一次取全表，书架页按分类筛选时就不用反复查库了。
  Future<Map<int, Set<String>>> albumKeysByCategory() async {
    final db = await _db.database;
    final rows = await db.query('album_category');
    final out = <int, Set<String>>{};
    for (final row in rows) {
      final id = row['category_id'] as int;
      final key = '${row['source']}:${row['album_id']}';
      (out[id] ??= <String>{}).add(key);
    }
    return out;
  }

  /// 按分类筛选书架；[categoryId] 为 null 表示全部
  Future<List<BookshelfItem>> listBookshelfByCategory(int? categoryId) async {
    if (categoryId == null) return listBookshelf();
    final db = await _db.database;
    final rows = await db.rawQuery(
      '''
      SELECT b.* FROM bookshelf b
      INNER JOIN album_category ac
        ON ac.source = b.source AND ac.album_id = b.album_id
      WHERE ac.category_id = ?
      ORDER BY b.last_read_at DESC, b.created_at DESC
    ''',
      [categoryId],
    );
    return rows.map(BookshelfItem.fromRow).toList();
  }
}
