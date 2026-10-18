/// 装好新版本后第一次打开时的更新公告
///
/// 内容直接取「关于 → 公告」里当前版本那一条，只负责排版和返回用户的选择。
library;

import 'package:flutter/material.dart';

import '../../data/app_docs.dart';

class ChangelogDialog extends StatelessWidget {
  const ChangelogDialog({super.key, required this.entry});

  final ChangeEntry entry;

  /// 返回 true 表示用户想去看完整的更新记录
  static Future<bool?> show(BuildContext context, ChangeEntry entry) {
    return showDialog<bool>(
      context: context,
      builder: (_) => ChangelogDialog(entry: entry),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
      actionsPadding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.auto_stories_rounded,
                  size: 21,
                  color: scheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '已更新到 v${entry.version}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                entry.date,
                style: TextStyle(fontSize: 11, color: scheme.outline),
              ),
            ],
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                entry.summary,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: scheme.outline,
                ),
              ),
              if (entry.features.isNotEmpty) ...[
                const SizedBox(height: 14),
                _ChangeGroup(
                  title: '新增',
                  items: entry.features,
                  color: scheme.primary,
                ),
              ],
              if (entry.fixes.isNotEmpty) ...[
                const SizedBox(height: 14),
                _ChangeGroup(
                  title: '修复',
                  items: entry.fixes,
                  color: scheme.tertiary,
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('查看更新记录'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('知道了'),
        ),
      ],
    );
  }
}

class _ChangeGroup extends StatelessWidget {
  const _ChangeGroup({
    required this.title,
    required this.items,
    required this.color,
  });

  final String title;
  final List<String> items;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '· ',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                Expanded(
                  child: Text(
                    item,
                    style: const TextStyle(fontSize: 13, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
