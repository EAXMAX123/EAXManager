/// 书架「已打包」页：本地生成过的分享 PDF
///
/// 这些文件会一直留在地下载目录下的「已打包」文件夹里，
/// 关掉软件再进来也能直接分享，不用重新拼图。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../data/app_database.dart';
import '../../services/pdf_share_service.dart';
import '../../services/platform_service.dart';
import '../../services/shelf_sizes.dart';
import '../../state/app_services.dart';
import '../widgets/retained_tabs.dart';
import '../widgets/source_badge.dart';
import 'detail_page.dart';

class PackedPdfsView extends StatefulWidget {
  const PackedPdfsView({super.key});

  @override
  State<PackedPdfsView> createState() => _PackedPdfsViewState();
}

enum _PackedAction { share, detail, delete }

class _PackedPdfsViewState extends State<PackedPdfsView> {
  final _search = TextEditingController();
  List<PdfPackageItem> _items = const [];
  bool _loading = true;
  bool _active = true;
  int? _sharingId;

  @override
  void initState() {
    super.initState();
    AppServices.I.pdfPackagesRevision.addListener(_onPackagesChanged);
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final active = PageActivity.of(context);
    final becameActive = active && !_active;
    _active = active;
    if (becameActive) _load();
  }

  @override
  void dispose() {
    _search.dispose();
    AppServices.I.pdfPackagesRevision.removeListener(_onPackagesChanged);
    super.dispose();
  }

  void _onPackagesChanged() {
    if (mounted) _load();
  }

  Future<void> _load() async {
    final items = await PdfShareService.listPackages();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  List<PdfPackageItem> get _filtered {
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) return _items;
    return _items.where((item) {
      return item.title.toLowerCase().contains(query) ||
          item.albumId.contains(query) ||
          PdfShareService.formatChapters(item.chapters).contains(query);
    }).toList();
  }

  Future<void> _share(PdfPackageItem item) async {
    if (_sharingId != null) return;
    if (!await File(item.filePath).exists()) {
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('这个 PDF 已经不在本地了，已从列表移除')));
      return;
    }

    setState(() => _sharingId = item.id);
    try {
      final shared = await PlatformService.shareFile(
        path: item.filePath,
        title: p.basename(item.filePath),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            shared ? '已打开分享面板，可以发到 QQ、微信等' : 'PDF 保存在：${item.filePath}',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _sharingId = null);
    }
  }

  Future<void> _delete(PdfPackageItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除已打包的 PDF'),
        content: Text(
          '只会删掉这份 PDF 文件，不会动已经下载好的漫画图片。\n\n'
          '《${item.title}》${PdfShareService.formatChapters(item.chapters)}',
        ),
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

    await PdfShareService.deletePackage(item);
    await _load();
  }

  Future<void> _openDetail(PdfPackageItem item) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DetailPage(sid: item.sid, title: item.title),
      ),
    );
    if (mounted) await _load();
  }

  void _onAction(PdfPackageItem item, _PackedAction action) {
    switch (action) {
      case _PackedAction.share:
        _share(item);
      case _PackedAction.detail:
        _openDetail(item);
      case _PackedAction.delete:
        _delete(item);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final filtered = _filtered;
    final totalBytes = _items.fold<int>(0, (sum, item) => sum + item.sizeBytes);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              isDense: true,
              hintText: '搜索已打包 · 名称 / 章节 / ID',
              hintStyle: const TextStyle(fontSize: 14),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 10,
              ),
              prefixIcon: const Icon(Icons.search, size: 20),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 38,
                minHeight: 32,
              ),
              suffixIconConstraints: const BoxConstraints(
                minWidth: 38,
                minHeight: 32,
              ),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: '清空搜索',
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => setState(_search.clear),
                    ),
            ),
          ),
        ),
        if (_items.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 2, 18, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '共 ${_items.length} 份 · ${ShelfSizes.formatBytes(totalBytes)}',
                style: TextStyle(fontSize: 12, color: scheme.outline),
              ),
            ),
          ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : filtered.isEmpty
              ? _emptyState()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    key: const PageStorageKey('packed-pdfs'),
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(0, 6, 0, 24),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final item = filtered[index];
                      return _PackedTile(
                        item: item,
                        sharing: _sharingId == item.id,
                        onTap: () => _share(item),
                        onLongPress: () => _delete(item),
                        onAction: (action) => _onAction(item, action),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _emptyState() {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.picture_as_pdf_outlined,
              size: 56,
              color: scheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              _search.text.trim().isNotEmpty
                  ? '没有匹配的已打包 PDF\n试试名称、章节或作品 ID'
                  : '还没有打包好的 PDF\n在详情页点「分享 PDF」生成\n之后会一直留在这里，随时能再分享',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.outline, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _PackedTile extends StatelessWidget {
  const _PackedTile({
    required this.item,
    required this.sharing,
    required this.onTap,
    required this.onLongPress,
    required this.onAction,
  });

  final PdfPackageItem item;
  final bool sharing;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final ValueChanged<_PackedAction> onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final date = _formatDate(item.createdAt);

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: sharing ? null : onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 58,
                decoration: BoxDecoration(
                  color: scheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: sharing
                    ? const Padding(
                        padding: EdgeInsets.all(13),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        Icons.picture_as_pdf,
                        color: scheme.onErrorContainer,
                        size: 28,
                      ),
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
                            item.title.isEmpty ? '未命名' : item.title,
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
                    Text(
                      PdfShareService.formatChapters(item.chapters),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: scheme.primary),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${item.pageCount} 页 · ${ShelfSizes.formatBytes(item.sizeBytes)}'
                      '${date.isEmpty ? '' : ' · $date'}',
                      style: TextStyle(fontSize: 11, color: scheme.outline),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<_PackedAction>(
                tooltip: '更多',
                onSelected: onAction,
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: _PackedAction.share,
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.share_outlined),
                      title: Text('分享'),
                    ),
                  ),
                  PopupMenuItem(
                    value: _PackedAction.detail,
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.menu_book_outlined),
                      title: Text('打开本子详情'),
                    ),
                  ),
                  PopupMenuItem(
                    value: _PackedAction.delete,
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.delete_outline),
                      title: Text('删除 PDF'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatDate(int millis) {
    if (millis <= 0) return '';
    final date = DateTime.fromMillisecondsSinceEpoch(millis);
    String two(int value) => value.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)} '
        '${two(date.hour)}:${two(date.minute)}';
  }
}
