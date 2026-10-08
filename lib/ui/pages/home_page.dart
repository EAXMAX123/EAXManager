/// 发现页：多源搜索、排行榜、分类推荐
library;

import 'package:flutter/material.dart';

import '../../jm/jm_constants.dart';
import '../../jm/jm_exception.dart';
import '../../source/comic_source.dart';
import '../../state/app_services.dart';
import '../../state/result_feed.dart';
import '../widgets/album_tile.dart';
import '../widgets/mascot_empty_state.dart';
import 'detail_page.dart';
import 'favorites_page.dart';
import 'image_search_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this);
  final TextEditingController _searchController = TextEditingController();

  String _mode = 'site';
  final _searchFeed = ResultFeed<ComicItem>();
  final _rankFeed = ResultFeed<ComicItem>();
  String _lastQuery = '';
  SearchMode _lastMode = SearchMode.parse('site');
  List<ComicSource> _lastSources = [];

  // 排行参数：源 / 时间 / 分类三行，后两行的内容跟着选中的源变
  String _rankSource = 'jm';
  String _rankTime = '';
  String _rankCategory = '';

  @override
  void initState() {
    super.initState();
    _tabs.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (_tabs.index == 1 && !_rankFeed.initialized) _loadRank();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _searchController.dispose();
    super.dispose();
  }

  String _message(Object e) {
    if (e is JmException) return e.friendlyMessage;
    if (e is SourceException) return e.message;
    return e.toString();
  }

  void _openDetail(ComicItem item) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DetailPage(sid: item.sid, title: item.title),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: '搜索'),
            Tab(text: '排行'),
            Tab(text: '收藏'),
            Tab(text: '识图'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _buildSearchTab(),
              _buildRankTab(),
              const FavoritesPage(),
              const ImageSearchPage(),
            ],
          ),
        ),
      ],
    );
  }

  // ==================== 搜索 ====================

  Widget _buildSearchTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
          child: TextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _doSearch(),
            decoration: InputDecoration(
              hintText: '搜索本子 / 作者 / 标签',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                icon: const Icon(Icons.arrow_forward),
                onPressed: () => _doSearch(),
              ),
            ),
          ),
        ),
        _modeChips(),
        _sourceChips(),
        Expanded(
          child: _buildList(
            feed: _searchFeed,
            tab: 0,
            onRefresh: () => _doSearch(),
            onLoadMore: () => _doSearch(page: _searchFeed.page + 1),
          ),
        ),
      ],
    );
  }

  /// 搜索模式：综合 / 作品 / 作者 / 标签 / 登场角色
  Widget _modeChips() {
    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: jmSearchModeNames.entries
            .map(
              (e) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(
                  label: Text(e.value),
                  selected: _mode == e.key,
                  onSelected: (_) => setState(() => _mode = e.key),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  /// 搜索源：JM / 哔咔 / EH，可多选，多选时结果合并
  Widget _sourceChips() {
    final selected = AppServices.I.settings.value.enabledSources;

    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (final source in AppServices.I.sources.all)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: FilterChip(
                avatar: selected.contains(source.key)
                    ? null
                    : const Icon(Icons.add, size: 16),
                label: Text(source.name),
                selected: selected.contains(source.key),
                onSelected: (on) => _toggleSource(source.key, on),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _toggleSource(String key, bool on) async {
    final next = [...AppServices.I.settings.value.enabledSources];
    if (on) {
      if (!next.contains(key)) next.add(key);
    } else {
      next.remove(key);
    }
    if (next.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('至少要保留一个搜索源')));
      return;
    }
    await AppServices.I.setEnabledSources(next);
    if (mounted) setState(() {});
  }

  Future<void> _doSearch({int page = 1}) async {
    if (page > 1 && _searchFeed.loading) return;
    final query = page == 1 ? _searchController.text.trim() : _lastQuery;
    if (query.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请输入搜索关键词')));
      return;
    }
    if (page == 1) {
      _lastQuery = query;
      _lastMode = SearchMode.parse(_mode);
      _lastSources = AppServices.I.sources.ofKeys(
        AppServices.I.settings.value.enabledSources,
      );
    }
    final picked = List<ComicSource>.of(_lastSources);
    final mode = _lastMode;
    final revision = _searchFeed.begin(reset: page == 1);
    setState(() {});
    if (picked.isEmpty) {
      setState(() => _searchFeed.fail(revision, '请至少选择一个搜索源'));
      return;
    }

    // 没登录的源直接跳过：不然每次搜索都要弹一次「哔咔需要登录」，
    // 反而盖住了真正的结果
    final usable = <ComicSource>[];
    final skipped = <String>[];
    final failed = <String>[];
    for (final source in picked) {
      try {
        if (await source.ready()) {
          usable.add(source);
        } else {
          skipped.add(source.name);
        }
      } on Exception catch (error) {
        failed.add('${source.name}：${_message(error)}');
      }
      if (!mounted || !_searchFeed.accepts(revision)) return;
    }

    if (!mounted || !_searchFeed.accepts(revision)) return;
    if (usable.isEmpty) {
      setState(
        () => _searchFeed.fail(
          revision,
          [
            if (skipped.isNotEmpty)
              '这些源还没登录（${skipped.join('、')}）\n到「设置 → 账号」登录后就能搜了',
            ...failed,
          ].join('\n'),
        ),
      );
      return;
    }

    final pages = await Future.wait([
      for (final source in usable) _safeSearch(source, query, mode, page),
    ]);

    if (!mounted || !_searchFeed.accepts(revision)) return;

    if (skipped.isNotEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已跳过未登录的源：${skipped.join('、')}')));
    }

    final perSource = <List<ComicItem>>[];
    var total = 0;
    for (var i = 0; i < pages.length; i++) {
      final result = pages[i];
      if (result.error != null) {
        failed.add('${usable[i].name}：${result.error}');
        perSource.add(const []);
      } else {
        perSource.add(result.items);
        total += result.total;
      }
    }

    final merged = _interleave(perSource);
    setState(() {
      if (merged.isEmpty && failed.isNotEmpty) {
        _searchFeed.fail(revision, failed.join('\n'));
      } else {
        _searchFeed.complete(revision, merged, page: page, total: total);
      }
    });

    if (failed.isNotEmpty && merged.isNotEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('部分源搜索失败：${failed.join('；')}')));
    }
  }

  /// 单个源失败不影响其它源
  Future<ComicSearchPage> _safeSearch(
    ComicSource source,
    String query,
    SearchMode mode,
    int page,
  ) async {
    try {
      return await source.search(query, mode: mode, page: page);
    } on Exception catch (e) {
      return ComicSearchPage(items: const [], page: page, error: _message(e));
    }
  }

  /// 多源结果轮流取一条，避免第一个源刷屏
  static List<ComicItem> _interleave(List<List<ComicItem>> lists) {
    final out = <ComicItem>[];
    var index = 0;
    while (true) {
      var added = false;
      for (final list in lists) {
        if (index < list.length) {
          out.add(list[index]);
          added = true;
        }
      }
      if (!added) break;
      index++;
    }
    return out;
  }

  // ==================== 排行榜 ====================

  /// 有排行榜的源（按注册顺序）
  List<ComicSource> get _rankSources => [
    for (final source in AppServices.I.sources.all)
      if (source.rankTimes.isNotEmpty) source,
  ];

  ComicSource? get _rankSourceOf => AppServices.I.sources.of(_rankSource);

  List<RankOption> get _rankTimeOptions => _rankSourceOf?.rankTimes ?? const [];

  List<RankOption> get _rankCategoryOptions =>
      _rankSourceOf?.rankCategories(_rankTime) ?? const [];

  /// 把选中的源 / 时间 / 分类拉回到「当前源真的支持」的值上
  ///
  /// 换源、换时间之后原来的选择可能已经不存在了（比如 Pixiv 的「新人」
  /// 只有周榜有），这里统一纠一次，界面就不用到处判空。
  void _normalizeRankSelection() {
    final sources = _rankSources;
    if (sources.isEmpty) return;

    if (AppServices.I.sources.of(_rankSource)?.rankTimes.isEmpty ?? true) {
      _rankSource = sources.first.key;
    }
    final source = _rankSourceOf;
    if (source == null) return;

    final times = source.rankTimes;
    if (!times.any((e) => e.key == _rankTime)) {
      _rankTime = times.first.key;
    }

    final categories = source.rankCategories(_rankTime);
    if (categories.isEmpty) {
      _rankCategory = '';
    } else if (!categories.any((e) => e.key == _rankCategory)) {
      _rankCategory = categories.first.key;
    }
  }

  Future<void> _loadRank({int page = 1}) async {
    if (page > 1 && _rankFeed.loading) return;
    _normalizeRankSelection();
    final source = _rankSourceOf;
    final time = _rankTime;
    final category = _rankCategory;
    final revision = _rankFeed.begin(reset: page == 1);
    setState(() {});
    if (source == null) {
      setState(() => _rankFeed.fail(revision, '这个版本还没有可用的排行榜'));
      return;
    }
    try {
      final result = await source.rank(
        time: time,
        category: category,
        page: page,
      );
      if (!mounted || !_rankFeed.accepts(revision)) return;
      setState(() {
        if (result.error != null) {
          _rankFeed.fail(revision, result.error!);
        } else {
          _rankFeed.complete(
            revision,
            result.items,
            page: page,
            total: result.total,
          );
        }
      });
    } on Exception catch (e) {
      if (!mounted || !_rankFeed.accepts(revision)) return;
      setState(() => _rankFeed.fail(revision, _message(e)));
    }
  }

  /// 换源：时间和分类都要重新落到新源支持的档位上
  void _selectRankSource(String key) {
    if (AppServices.I.sources.of(key) == null) return;
    setState(() {
      _rankSource = key;
      _rankTime = '';
      _rankCategory = '';
    });
    _loadRank();
  }

  void _selectRankTime(String key) {
    setState(() {
      _rankTime = key;
      _rankCategory = '';
    });
    _loadRank();
  }

  void _selectRankCategory(String key) {
    setState(() {
      _rankCategory = key;
    });
    _loadRank();
  }

  Widget _buildRankTab() {
    final times = _rankTimeOptions;
    final categories = _rankCategoryOptions;

    return Column(
      children: [
        // 第 1 行：源
        _chips(
          values: [
            for (final source in _rankSources)
              RankOption(source.key, source.name),
          ],
          selected: _rankSource,
          onSelected: _selectRankSource,
        ),
        // 第 2 行：时间档（每个源不一样，所以是算出来的）
        if (times.isNotEmpty)
          _chips(
            values: times,
            selected: _rankTime,
            onSelected: _selectRankTime,
          ),
        // 第 3 行：分类档；哔咔 / EH 没有这一档，就不显示这一行
        if (categories.isNotEmpty)
          _chips(
            values: categories,
            selected: _rankCategory,
            onSelected: _selectRankCategory,
          ),
        Expanded(
          child: _buildList(
            feed: _rankFeed,
            tab: 1,
            onRefresh: () => _loadRank(),
            onLoadMore: () => _loadRank(page: _rankFeed.page + 1),
          ),
        ),
      ],
    );
  }

  Widget _chips({
    required List<RankOption> values,
    required String selected,
    required ValueChanged<String> onSelected,
  }) {
    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: values
            .map(
              (e) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(
                  label: Text(e.label),
                  selected: selected == e.key,
                  onSelected: (_) => onSelected(e.key),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  // ==================== 列表 ====================

  Widget _buildList({
    required ResultFeed<ComicItem> feed,
    required int tab,
    required Future<void> Function() onRefresh,
    required Future<void> Function() onLoadMore,
  }) {
    if (feed.error != null && feed.items.isEmpty) {
      return _errorView(feed.error!, onRefresh);
    }
    if (feed.loading && feed.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (feed.items.isEmpty) {
      return _emptyView(
        feed.initialized
            ? '没有找到结果，试试更换关键词或筛选条件'
            : tab == 0
            ? '输入关键词开始搜索'
            : '选择上方条件开始浏览',
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.pixels >= n.metrics.maxScrollExtent - 400 &&
              _tabs.index == tab &&
              n.depth == 0 &&
              !feed.loading &&
              feed.error == null &&
              feed.items.length < feed.total) {
            onLoadMore();
          }
          return false;
        },
        child: ListView.builder(
          key: PageStorageKey('discovery-$tab'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 24),
          itemCount:
              feed.items.length + (feed.loading || feed.error != null ? 1 : 0),
          itemBuilder: (context, index) {
            if (index >= feed.items.length) {
              if (feed.error != null) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Text(feed.error!, textAlign: TextAlign.center),
                      TextButton(
                        onPressed: onLoadMore,
                        child: const Text('重试加载'),
                      ),
                    ],
                  ),
                );
              }
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final item = feed.items[index];
            return AlbumTile(item: item, onTap: () => _openDetail(item));
          },
        ),
      ),
    );
  }

  Widget _emptyView(String message) {
    return MascotEmptyState(message: message);
  }

  Widget _errorView(String message, Future<void> Function() onRefresh) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRefresh, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}
