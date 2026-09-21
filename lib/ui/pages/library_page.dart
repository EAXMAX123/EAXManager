/// 书架：已下载/在下载的漫画
library;

import 'dart:io';

import 'package:flutter/material.dart';

import '../../data/app_database.dart';
import '../../jm/jm_storage.dart';
import '../../services/local_library.dart';
import '../../services/shelf_sizes.dart';
import '../../state/app_services.dart';
import '../widgets/album_cover.dart';
import '../widgets/source_badge.dart';
import 'detail_page.dart';
import 'reader_page.dart';
import 'subscriptions_view.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  /// 当前选中的分类；null 表示「全部」
  int? _categoryId;

  List<ShelfCategory> _categories = const [];

  /// 分类 id -> 本子 key 集合，用于本地筛选
  Map<int, Set<String>> _categoryAlbums = const {};

  /// 各本子占用的磁盘空间，键是 SourceId.key
  ///
  /// 只有按大小排序时才算——走一遍磁盘是有成本的，不该每次进书架都做。
  Map<String, int> _sizes = const {};
  bool _sizesLoading = false;
  String _sizesRoot = '';

  /// 排序方式：数据库里的默认顺序就是「最近阅读优先」，其余在这里排
  static const Map<String, String> _sortLabels = {
    'read': '最近阅读',
    'addedDesc': '加入时间 ↓',
    'addedAsc': '加入时间 ↑',
    'sizeDesc': '占用空间 ↓',
    'sizeAsc': '占用空间 ↑',
    'title': '名称',
  };

  /// 封面路径缓存
  ///
  /// 之前每次界面重建都对每个本子做一次磁盘探测，而下载中每 200 毫秒就会
  /// 重建一次——书架上有 100 本时等于每秒几百次系统调用，界面自然卡。
  final Map<String, String> _coverCache = {};
  String _coverCacheRoot = '';
  DateTime _coverCacheAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// 正在打开一本，防止连点两次推两个页面
  bool _opening = false;
  DateTime _categoriesAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    AppServices.I.library.addListener(_refresh);
    AppServices.I.downloads.addListener(_refresh);
    _loadCategories();
    AppServices.I.reloadLibrary();
    if (_needsSizes) _ensureSizes();
  }

  @override
  void dispose() {
    _tabs.dispose();
    AppServices.I.library.removeListener(_refresh);
    AppServices.I.downloads.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {});
    // 下载目录换了，之前数出来的占用空间就不作数了
    if (_needsSizes && _sizesRoot != AppServices.I.rootDir.value) {
      _ensureSizes();
    }
    // 归属关系可能刚在详情页改过，最多每秒重读一次分类
    final now = DateTime.now();
    if (now.difference(_categoriesAt) > const Duration(seconds: 1)) {
      _categoriesAt = now;
      _loadCategories();
    }
  }

  /// 重新读取分类与归属关系
  Future<void> _loadCategories() async {
    final dao = AppServices.I.dao;
    final categories = await dao.listCategories();
    final albums = await dao.albumKeysByCategory();
    if (!mounted) return;
    setState(() {
      _categories = categories;
      _categoryAlbums = albums;
      if (_categoryId != null && !categories.any((c) => c.id == _categoryId)) {
        _categoryId = null;
      }
    });
  }

  List<BookshelfItem> _filterByCategory(List<BookshelfItem> items) {
    final id = _categoryId;
    if (id == null) return items;
    final members = _categoryAlbums[id] ?? const <String>{};
    return items.where((e) => members.contains(e.sid.key)).toList();
  }

  String get _sortMode => AppServices.I.settings.value.shelfSort;

  /// 是不是按占用空间排序（只有这几种才需要去数磁盘）
  bool get _needsSizes => _sortMode.startsWith('size');

  int _sizeOf(BookshelfItem item) => _sizes[item.sid.key] ?? 0;

  /// 按当前设置排一遍；默认顺序由数据库给出，不用重排
  List<BookshelfItem> _sortItems(List<BookshelfItem> items) {
    final sorted = [...items];
    switch (_sortMode) {
      case 'addedAsc':
        sorted.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      case 'addedDesc':
        sorted.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case 'sizeAsc':
        sorted.sort((a, b) => _sizeOf(a).compareTo(_sizeOf(b)));
      case 'sizeDesc':
        sorted.sort((a, b) => _sizeOf(b).compareTo(_sizeOf(a)));
      case 'title':
        sorted.sort((a, b) => a.title.compareTo(b.title));
      default:
        break;
    }
    return sorted;
  }

  /// 数一遍每个本子占了多少空间（后台 isolate 里做，不卡界面）
  Future<void> _ensureSizes({bool force = false}) async {
    final roots = _sizeRoots();
    if (roots.isEmpty || _sizesLoading) return;

    final signature = roots.join('|');
    if (!force && _sizesRoot == signature && _sizes.isNotEmpty) return;

    setState(() => _sizesLoading = true);
    final sizes = await ShelfSizes.scan(roots);
    if (!mounted) return;
    setState(() {
      _sizes = sizes;
      _sizesRoot = signature;
      _sizesLoading = false;
    });
  }

  /// 要统计的根目录：当前下载目录 + 每本书当初落盘的目录
  ///
  /// 换过下载目录的话，老书不在当前目录里，少算一个根就会显示成 0。
  List<String> _sizeRoots() {
    final roots = <String>[AppServices.I.rootDir.value];
    for (final item in AppServices.I.library.value) {
      if (item.rootPath.isNotEmpty) roots.add(item.rootPath);
    }
    return roots;
  }

  Future<void> _pickSort() async {
    final current = _sortMode;
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '书架排序',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
            for (final entry in _sortLabels.entries)
              ListTile(
                leading: Icon(
                  entry.key == current
                      ? Icons.check_circle
                      : Icons.circle_outlined,
                  color: entry.key == current
                      ? Theme.of(ctx).colorScheme.primary
                      : Theme.of(ctx).colorScheme.outlineVariant,
                ),
                title: Text(entry.value),
                onTap: () => Navigator.pop(ctx, entry.key),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked == null) return;

    await AppServices.I.updateSettings(
      AppServices.I.settings.value.copyWith(shelfSort: picked),
    );
    if (!mounted) return;
    setState(() {});
    if (_needsSizes) await _ensureSizes();
  }

  /// 打开书架里的一本
  ///
  /// 不能直接按「上次读到第几话」打开：那一话很可能根本没下载
  /// （比如只下了第 2 话，上次读的还是第 1 话），点进去就报
  /// 「本章还没有下载」，看着就像软件坏了。这里先确认本地真有图，
  /// 没有就退到详情页让用户自己挑一话。
  Future<void> _openItem(BookshelfItem item) async {
    if (_opening) return;
    _opening = true;
    try {
      final chapter = item.downloaded > 0 ? await _openableChapter(item) : null;
      if (!mounted) return;

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => chapter == null
              ? DetailPage(sid: item.sid, title: item.title)
              : ReaderPage(
                  sid: item.sid,
                  albumTitle: item.title,
                  chapterIndex: chapter,
                  chapterCount: item.chapterCount,
                ),
        ),
      );
    } finally {
      _opening = false;
    }
  }

  /// 本地真有图的章节里，挑一话给阅读器
  ///
  /// 优先「上次读到的那一话」；它没下载就用本地最靠前的一话。
  Future<int?> _openableChapter(BookshelfItem item) async {
    final local = await LocalLibrary.chapters(item.sid);
    if (local.isEmpty) return null;
    return local.contains(item.lastChapter) ? item.lastChapter : local.first;
  }

  String _localCover(BookshelfItem item) {
    final root = AppServices.I.rootDir.value;
    if (root.isEmpty) return '';

    // 缓存 5 秒：新下载的封面最多晚 5 秒出现，但省下大量磁盘探测
    final now = DateTime.now();
    if (_coverCacheRoot != root ||
        now.difference(_coverCacheAt) > const Duration(seconds: 5)) {
      _coverCache.clear();
      _coverCacheRoot = root;
      _coverCacheAt = now;
    }
    final cached = _coverCache[item.sid.key];
    if (cached != null) return cached;

    // 先看当前下载目录，再看这本书当初落盘的目录——换过目录也还找得到封面
    final bases = <String>[root, if (item.rootPath.isNotEmpty) item.rootPath];
    for (final base in bases) {
      if (base.startsWith('(')) continue;
      final dir = JmStorage.photoDir(
        JmStorage.sourceRoot(base, item.source),
        item.albumId,
        1,
      );
      for (final name in ['00001.jpg', '00001.png', '00001.webp']) {
        final f = File('$dir/$name');
        if (f.existsSync()) {
          _coverCache[item.sid.key] = f.path;
          return f.path;
        }
      }
    }
    _coverCache[item.sid.key] = '';
    return '';
  }

  Future<void> _remove(BookshelfItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除本地文件'),
        content: Text('将删除《${item.title}》的全部已下载图片，且不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final root = AppServices.I.rootDir.value;
    if (root.isNotEmpty && !root.startsWith('(')) {
      await JmStorage.deleteAlbum(
        JmStorage.sourceRoot(root, item.source),
        item.albumId,
      );
    }
    await AppServices.I.dao.removeBookshelf(item.sid);
    await AppServices.I.dao.deleteTasksByAlbum(item.sid);
    _coverCache.remove(item.sid.key);
    await AppServices.I.downloads.reload();
    await AppServices.I.reloadLibrary();
    await _loadCategories();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: '已下载'),
            Tab(text: '追更'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [_buildShelf(), const SubscriptionsView()],
          ),
        ),
      ],
    );
  }

  /// 分类筛选条：全部 + 各个分类 + 新建
  Widget _categoryBar() {
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              label: const Text('全部'),
              selected: _categoryId == null,
              onSelected: (_) => setState(() => _categoryId = null),
            ),
          ),
          for (final category in _categories)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(
                  '${category.name}'
                  '（${_categoryAlbums[category.id]?.length ?? 0}）',
                ),
                selected: _categoryId == category.id,
                onSelected: (_) => setState(() => _categoryId = category.id),
              ),
            ),
          ActionChip(
            avatar: Icon(Icons.add, size: 16, color: scheme.primary),
            label: const Text('新建分类'),
            onPressed: _createCategory,
          ),
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: ActionChip(
              avatar: Icon(Icons.sort, size: 16, color: scheme.primary),
              label: Text('排序：${_sortLabels[_sortMode] ?? '最近阅读'}'),
              onPressed: _pickSort,
            ),
          ),
        ],
      ),
    );
  }

  /// 在书架页直接建一个空分类，方便先把分类铺好再往里放书
  Future<void> _createCategory() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建分类'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '比如「已看完」'),
          onSubmitted: (value) => Navigator.pop(ctx, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty) return;

    final id = await AppServices.I.dao.createCategory(name);
    await _loadCategories();
    if (!mounted || id == 0) return;
    setState(() => _categoryId = id);
  }

  Widget _emptyState(bool shelfEmpty) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.collections_bookmark_outlined,
            size: 56,
            color: scheme.outline,
          ),
          const SizedBox(height: 12),
          Text(
            shelfEmpty ? '书架还是空的\n去「发现」页搜索并下载吧' : '这个分类下还没有本子\n在详情页点「加入书架」可以归类',
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.outline),
          ),
        ],
      ),
    );
  }

  Widget _buildShelf() {
    return Column(
      children: [
        _categoryBar(),
        if (_sizesLoading) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: ValueListenableBuilder<List<BookshelfItem>>(
            valueListenable: AppServices.I.library,
            builder: (context, items, _) {
              final filtered = _filterByCategory(items);
              if (filtered.isEmpty) return _emptyState(items.isEmpty);
              final sorted = _sortItems(filtered);

              return RefreshIndicator(
                onRefresh: () async {
                  if (_needsSizes) await _ensureSizes(force: true);
                  await AppServices.I.reloadLibrary();
                  await _loadCategories();
                },
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: sorted.length,
                  itemBuilder: (context, index) {
                    final item = sorted[index];
                    return _LibraryTile(
                      item: item,
                      coverUrl: item.coverUrl,
                      headers:
                          AppServices.I.sources.of(item.source)?.imageHeaders ??
                          const {},
                      localCover: _localCover(item),
                      sizeText: _needsSizes
                          ? ShelfSizes.formatBytes(_sizeOf(item))
                          : '',
                      onTap: () {
                        _openItem(item);
                      },
                      onLongPress: () => _remove(item),
                      onOpenDetail: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              DetailPage(sid: item.sid, title: item.title),
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _LibraryTile extends StatelessWidget {
  const _LibraryTile({
    required this.item,
    required this.coverUrl,
    required this.headers,
    required this.localCover,
    required this.sizeText,
    required this.onTap,
    required this.onLongPress,
    required this.onOpenDetail,
  });

  final BookshelfItem item;
  final String coverUrl;
  final Map<String, String> headers;
  final String localCover;

  /// 这个本子占了多少空间；按大小排序时才显示
  final String sizeText;

  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onOpenDetail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            AlbumCover(
              albumId: item.albumId,
              coverUrl: coverUrl,
              httpHeaders: headers,
              localPath: localCover,
              width: 72,
              height: 96,
              show: AppServices.I.settings.value.showCoverInList,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      const SizedBox(width: 6),
                      SourceBadge(source: item.source),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.author,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: scheme.outline),
                        ),
                      ),
                      if (sizeText.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Text(
                          sizeText,
                          style: TextStyle(fontSize: 12, color: scheme.outline),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: item.progress,
                            minHeight: 6,
                            backgroundColor: scheme.surfaceContainerHighest,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${item.downloaded}/${item.chapterCount}',
                        style: TextStyle(fontSize: 11, color: scheme.outline),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.info_outline),
              tooltip: '详情',
              onPressed: onOpenDetail,
            ),
          ],
        ),
      ),
    );
  }
}
