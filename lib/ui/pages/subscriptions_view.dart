/// 追更列表：查看订阅的本子，手动检查是否有新章节
library;

import 'package:flutter/material.dart';

import '../../data/app_database.dart';
import '../../services/subscription_service.dart';
import '../../state/app_services.dart';
import '../widgets/album_cover.dart';
import '../widgets/source_badge.dart';
import 'detail_page.dart';

class SubscriptionsView extends StatefulWidget {
  const SubscriptionsView({super.key});

  @override
  State<SubscriptionsView> createState() => _SubscriptionsViewState();
}

class _SubscriptionsViewState extends State<SubscriptionsView> {
  /// 最近一次检查发现的新章节：source:id -> 新增话数
  final Map<String, int> _updates = {};

  @override
  void initState() {
    super.initState();
    AppServices.I.subscriptions.reload();
    AppServices.I.subscriptions.onUpdates = _onUpdates;
  }

  @override
  void dispose() {
    if (AppServices.I.subscriptions.onUpdates == _onUpdates) {
      AppServices.I.subscriptions.onUpdates = null;
    }
    super.dispose();
  }

  void _onUpdates(List<SubscriptionUpdate> updates) {
    if (!mounted) return;
    setState(() {
      for (final u in updates) {
        _updates[u.sid.key] = u.newChapters;
      }
    });
  }

  Future<void> _check() async {
    final updates = await AppServices.I.subscriptions.checkNow();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          updates.isEmpty ? '检查完成，暂无新章节' : '发现 ${updates.length} 本有新章节',
        ),
      ),
    );
  }

  Future<void> _remove(SubscriptionItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('取消追更'),
        content: Text('不再检查《${item.title}》的更新？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('取消追更'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await AppServices.I.subscriptions.remove(item.sid);
    if (!mounted) return;
    setState(() => _updates.remove(item.sid.key));
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<SubscriptionItem>>(
      valueListenable: AppServices.I.subscriptions.subscriptions,
      builder: (context, items, _) {
        return Column(
          children: [
            _buildHeader(items),
            Expanded(child: _buildBody(items)),
          ],
        );
      },
    );
  }

  Widget _buildHeader(List<SubscriptionItem> items) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              items.isEmpty
                  ? '还没有追更任何本子'
                  : '共 ${items.length} 本，后台每 ${_intervalText()} 检查一次',
              style: TextStyle(fontSize: 12, color: scheme.outline),
            ),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: AppServices.I.subscriptions.checking,
            builder: (context, busy, _) => TextButton.icon(
              onPressed: (busy || items.isEmpty) ? null : _check,
              icon: busy
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh, size: 18),
              label: Text(busy ? '检查中…' : '检查更新'),
            ),
          ),
        ],
      ),
    );
  }

  String _intervalText() {
    final seconds = AppServices.I.settings.value.subscribeCheckInterval;
    if (seconds < 3600) return '${(seconds / 60).round()} 分钟';
    return '${(seconds / 3600).round()} 小时';
  }

  Widget _buildBody(List<SubscriptionItem> items) {
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.notifications_none,
                size: 56,
                color: Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(height: 12),
              Text(
                '在本子详情页点「追更」\n有新章节时会收到通知',
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.outline),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final fresh = _updates[item.sid.key] ?? 0;

        return ListTile(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => DetailPage(sid: item.sid, title: item.title),
            ),
          ),
          onLongPress: () => _remove(item),
          leading: AlbumCover(
            albumId: item.albumId,
            coverUrl: _coverUrl(item),
            httpHeaders:
                AppServices.I.sources.of(item.source)?.imageHeaders ?? const {},
          ),
          title: Row(
            children: [
              Flexible(
                child: Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              SourceBadge(source: item.source),
            ],
          ),
          subtitle: Text(
            fresh > 0 ? '有新章节：+$fresh 话' : '已追 ${item.knownChapters} 话',
            style: TextStyle(
              fontSize: 12,
              color: fresh > 0
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.outline,
            ),
          ),
          trailing: IconButton(
            icon: const Icon(Icons.notifications_off_outlined),
            tooltip: '取消追更',
            onPressed: () => _remove(item),
          ),
        );
      },
    );
  }

  /// 订阅表里没存封面，从书架里找一份
  String _coverUrl(SubscriptionItem item) {
    for (final b in AppServices.I.library.value) {
      if (b.sid == item.sid) return b.coverUrl;
    }
    return '';
  }
}
