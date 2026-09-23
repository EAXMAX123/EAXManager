/// 关键词搜索结果页
///
/// 从「识图」页点进来：识图认出来的作品名多半不在 JM 上，所以照旧让用户
/// 自己勾源，四个源一起搜，和搜索页的行为完全一致。
library;

import 'package:flutter/material.dart';

import '../../jm/jm_exception.dart';
import '../../source/comic_source.dart';
import '../../state/app_services.dart';
import '../widgets/album_tile.dart';
import 'detail_page.dart';

class KeywordSearchPage extends StatefulWidget {
  const KeywordSearchPage({super.key, required this.query, this.autoRun = true});

  final String query;

  /// 进来就自动搜一次
  final bool autoRun;

  @override
  State<KeywordSearchPage> createState() => _KeywordSearchPageState();
}

class _KeywordSearchPageState extends State<KeywordSearchPage> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.query,
  );

  bool _loading = false;
  String? _error;
  List<ComicItem> _items = const [];
  int _page = 1;
  String _lastQuery = '';

  @override
  void initState() {
    super.initState();
    if (widget.autoRun && widget.query.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _run());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _message(Object e) {
    if (e is JmException) return e.friendlyMessage;
    if (e is SourceException) return e.message;
    return e.toString();
  }

  Future<void> _run({int page = 1}) async {
    final query = _controller.text.trim();
    if (query.isEmpty) {
      setState(() => _error = '请输入关键词');
      return;
    }
    _lastQuery = query;

    final picked = AppServices.I.sources.ofKeys(
      AppServices.I.settings.value.enabledSources,
    );
    if (picked.isEmpty) {
      setState(() => _error = '请至少选择一个搜索源');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    // 没登录的源直接跳过，不然每次搜索都要弹一次「哔咔需要登录」
    final usable = <ComicSource>[];
    final skipped = <String>[];
    for (final source in picked) {
      if (await source.ready()) {
        usable.add(source);
      } else {
        skipped.add(source.name);
      }
    }

    if (!mounted) return;
    if (usable.isEmpty) {
      setState(() {
        _loading = false;
        _error =
            '勾选的源都还没登录（${skipped.join('、')}）\n'
            '到「设置 → 账号」登录后就能搜了';
      });
      return;
    }

    final pages = await Future.wait([
      for (final source in usable) _safeSearch(source, query, page),
    ]);

    if (!mounted) return;

    if (skipped.isNotEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已跳过未登录的源：${skipped.join('、')}')));
    }

    final perSource = <List<ComicItem>>[];
    final failed = <String>[];
    for (var i = 0; i < pages.length; i++) {
      final result = pages[i];
      if (result.error != null) {
        failed.add('${usable[i].name}：${result.error}');
        perSource.add(const []);
      } else {
        perSource.add(result.items);
      }
    }

    final merged = _interleave(perSource);
    setState(() {
      _items = page == 1 ? merged : [..._items, ...merged];
      _loading = false;
      _page = page;
      _error = merged.isEmpty && failed.isNotEmpty ? failed.join('\n') : null;
    });

    if (failed.isNotEmpty && merged.isNotEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('部分源搜索失败：${failed.join('；')}')));
    }
  }

  Future<ComicSearchPage> _safeSearch(
    ComicSource source,
    String query,
    int page,
  ) async {
    try {
      return await source.search(query, mode: SearchMode.site, page: page);
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

  void _openDetail(ComicItem item) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DetailPage(sid: item.sid, title: item.title),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('搜索')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
            child: TextField(
              controller: _controller,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _run(),
              decoration: InputDecoration(
                hintText: '搜索本子 / 作者 / 标签',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: () => _run(),
                ),
              ),
            ),
          ),
          _sourceChips(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('至少要保留一个搜索源')));
      return;
    }
    await AppServices.I.setEnabledSources(next);
    if (!mounted) return;
    setState(() {});
    if (_lastQuery.isNotEmpty) _run();
  }

  Widget _buildBody() {
    if (_loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_items.isEmpty && _error != null) {
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
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: () => _run(), child: const Text('重试')),
            ],
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Text(
          '没有搜到结果',
          style: TextStyle(color: Theme.of(context).colorScheme.outline),
        ),
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (note) {
        if (note.metrics.pixels >
            note.metrics.maxScrollExtent - 400) {
          if (!_loading && _lastQuery.isNotEmpty) {
            _run(page: _page + 1);
          }
        }
        return false;
      },
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 24),
        itemCount: _items.length + (_loading ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _items.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final item = _items[index];
          return AlbumTile(item: item, onTap: () => _openDetail(item));
        },
      ),
    );
  }
}
