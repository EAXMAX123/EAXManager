/// 下载管理页：队列、进度、暂停/继续/重试、清理
library;

import 'package:flutter/material.dart';

import '../../data/app_database.dart';
import '../../state/app_services.dart';
import '../../state/download_manager.dart';
import '../widgets/source_badge.dart';

class DownloadsPage extends StatefulWidget {
  const DownloadsPage({super.key});

  @override
  State<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends State<DownloadsPage> {
  @override
  void initState() {
    super.initState();
    AppServices.I.downloads.addListener(_refresh);
  }

  @override
  void dispose() {
    AppServices.I.downloads.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final manager = AppServices.I.downloads;
    final tasks = manager.tasks;

    if (tasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.download_outlined,
              size: 56,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              '还没有下载任务',
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        _header(manager),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 24),
            itemCount: tasks.length,
            itemBuilder: (context, index) =>
                _TaskTile(task: tasks[index], manager: manager),
          ),
        ),
      ],
    );
  }

  Widget _header(DownloadManager manager) {
    final scheme = Theme.of(context).colorScheme;
    final active = manager.activeCount;
    final pending = manager.pendingCount;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              active > 0
                  ? '正在下载 $active 个章节，等待 $pending 个'
                  : '空闲中，等待 $pending 个任务',
              style: TextStyle(fontSize: 13, color: scheme.outline),
            ),
          ),
          TextButton(
            onPressed: () async {
              await manager.clearFinished();
              await AppServices.I.reloadLibrary();
            },
            child: const Text('清除已完成'),
          ),
        ],
      ),
    );
  }
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({required this.task, required this.manager});

  final DownloadTask task;
  final DownloadManager manager;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        task.albumTitle.isEmpty
                            ? task.chapterTitle
                            : task.albumTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    const SizedBox(width: 6),
                    SourceBadge(source: task.source),
                  ],
                ),
              ),
              _actions(context),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '第 ${task.chapterIndex} 话  ${task.chapterTitle}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: scheme.outline),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: task.progress,
              minHeight: 6,
              backgroundColor: scheme.surfaceContainerHighest,
              color: switch (task.status) {
                DownloadStatus.failed => scheme.error,
                DownloadStatus.done => Colors.green,
                _ => scheme.primary,
              },
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _statusText(),
            style: TextStyle(fontSize: 11, color: scheme.outline),
          ),
        ],
      ),
    );
  }

  String _statusText() {
    switch (task.status) {
      case DownloadStatus.pending:
        return '等待下载';
      case DownloadStatus.running:
        return '下载中 ${task.done}/${task.total}'
            '${task.failed > 0 ? '，失败 ${task.failed}' : ''}';
      case DownloadStatus.paused:
        return '已暂停 ${task.done}/${task.total}';
      case DownloadStatus.done:
        return '已完成 ${task.done} 张${task.error.isEmpty ? '' : '（${task.error}）'}';
      case DownloadStatus.failed:
        return '失败：${task.error}';
    }
  }

  Widget _actions(BuildContext context) {
    switch (task.status) {
      case DownloadStatus.pending:
      case DownloadStatus.running:
        return IconButton(
          icon: const Icon(Icons.pause_circle_outline),
          tooltip: '暂停',
          onPressed: () => manager.cancelTask(task.id),
        );
      case DownloadStatus.paused:
        return IconButton(
          icon: const Icon(Icons.play_circle_outline),
          tooltip: '继续',
          onPressed: () => manager.retryTask(task.id),
        );
      case DownloadStatus.failed:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: '重试',
              onPressed: () => manager.retryTask(task.id),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: '移除',
              onPressed: () => manager.deleteTask(task.id),
            ),
          ],
        );
      case DownloadStatus.done:
        return IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: '移除记录',
          onPressed: () => manager.deleteTask(task.id),
        );
    }
  }
}
