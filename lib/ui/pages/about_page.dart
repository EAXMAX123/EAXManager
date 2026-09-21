/// 关于：更新公告、使用说明、软件信息
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_info.dart';
import '../../data/app_docs.dart';

/// 交流群（群号可以长按复制）
const List<String> _groupNumbers = ['1077681089', '279654219'];

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: '公告'),
            Tab(text: '说明'),
            Tab(text: '关于软件'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: const [_Announcements(), _Guide(), _AboutApp()],
          ),
        ),
      ],
    );
  }
}

// ==================== 公告 ====================

class _Announcements extends StatelessWidget {
  const _Announcements();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
      itemCount: Changelog.entries.length,
      itemBuilder: (context, index) {
        final entry = Changelog.entries[index];
        final isCurrent = entry.version == AppInfo.version;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 0,
          color: isCurrent
              ? scheme.primaryContainer
              : scheme.surfaceContainerLow,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      'v${entry.version}',
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    if (isCurrent) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '当前版本',
                          style: TextStyle(
                            fontSize: 10,
                            color: scheme.onPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                    const Spacer(),
                    Text(
                      entry.date,
                      style: TextStyle(fontSize: 12, color: scheme.outline),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  entry.summary,
                  style: TextStyle(fontSize: 13, color: scheme.outline),
                ),
                if (entry.features.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _ChangeGroup(
                    title: '新增',
                    items: entry.features,
                    color: scheme.primary,
                  ),
                ],
                if (entry.fixes.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _ChangeGroup(
                    title: '修复',
                    items: entry.fixes,
                    color: scheme.tertiary,
                  ),
                ],
              ],
            ),
          ),
        );
      },
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
            Container(width: 3, height: 12, color: color),
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
            padding: const EdgeInsets.only(left: 9, bottom: 5),
            child: Text(
              '· $item',
              style: const TextStyle(fontSize: 13, height: 1.5),
            ),
          ),
      ],
    );
  }
}

// ==================== 说明 ====================

class _Guide extends StatelessWidget {
  const _Guide();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
      itemCount: UsageGuide.tips.length,
      itemBuilder: (context, index) {
        final tip = UsageGuide.tips[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          elevation: 0,
          color: scheme.surfaceContainerLow,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.lightbulb_outline,
                      size: 16,
                      color: scheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        tip.title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  tip.body,
                  style: const TextStyle(fontSize: 13, height: 1.6),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ==================== 关于软件 ====================

class _AboutApp extends StatelessWidget {
  const _AboutApp();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 20, 12, 32),
      children: [
        Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Image.asset(
                'assets/app_icon.png',
                width: 72,
                height: 72,
                errorBuilder: (context, error, stack) => Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(
                    Icons.collections_bookmark,
                    size: 36,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              AppInfo.name,
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(
              AppInfo.fullVersionText,
              style: TextStyle(fontSize: 13, color: scheme.outline),
            ),
          ],
        ),
        const SizedBox(height: 24),
        _SectionTitle(title: '交流群', icon: Icons.forum_outlined),
        const SizedBox(height: 8),
        Card(
          elevation: 0,
          color: scheme.surfaceContainerLow,
          child: Column(
            children: [
              for (final number in _groupNumbers)
                ListTile(
                  dense: true,
                  leading: Icon(Icons.tag, size: 18, color: scheme.outline),
                  title: Text(
                    number,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                  subtitle: const Text('点一下复制群号'),
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: number));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text('已复制群号 $number')));
                  },
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _TappableImage(
          asset: 'assets/qq_group_1077681089.jpg',
          caption: '扫码加入交流群',
          height: 240,
        ),
        const SizedBox(height: 26),
        _SectionTitle(title: '支持作者', icon: Icons.favorite_outline),
        const SizedBox(height: 8),
        _TappableImage(
          asset: 'assets/reward_code.png',
          caption: '赞赏码 · 点一下看大图',
          height: 260,
        ),
        const SizedBox(height: 12),
        Text(
          '软件完全免费，觉得好用可以随缘支持一下。',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: scheme.outline),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.icon});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 16, color: scheme.primary),
        const SizedBox(width: 6),
        Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: scheme.primary,
          ),
        ),
      ],
    );
  }
}

/// 可点击放大的图片
class _TappableImage extends StatelessWidget {
  const _TappableImage({
    required this.asset,
    required this.caption,
    required this.height,
  });

  final String asset;
  final String caption;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showDialog<void>(
          context: context,
          builder: (ctx) => Dialog(
            insetPadding: const EdgeInsets.all(16),
            backgroundColor: Colors.transparent,
            child: InteractiveViewer(maxScale: 5, child: Image.asset(asset)),
          ),
        ),
        child: Column(
          children: [
            SizedBox(
              height: height,
              width: double.infinity,
              child: Image.asset(
                asset,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stack) => Center(
                  child: Text(
                    '图片缺失',
                    style: TextStyle(color: scheme.outline, fontSize: 12),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                caption,
                style: TextStyle(fontSize: 12, color: scheme.outline),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
