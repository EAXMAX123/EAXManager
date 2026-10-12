/// 顶栏那颗「求赞助」按两下之后弹出来的赞赏码弹窗。
///
/// 排版照着「关于 → 公告」里那条更新记录来：标题、一句话说明、正文，
/// 只是正文换成了赞赏码的图。右上角有个 ✕，点一下就能关掉。
library;

import 'package:flutter/material.dart';

class RewardCodeDialog extends StatelessWidget {
  const RewardCodeDialog({super.key});

  /// 与「关于 → 支持作者」用的是同一张图
  static const String assetPath = 'assets/reward_code.png';

  static const String title = '支持作者';

  static const String summary = '都按到这里了，那就随缘投喂一下吧～';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxHeight = MediaQuery.sizeOf(context).height - 120;

    return Dialog(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      backgroundColor: scheme.surfaceContainerLow,
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 360,
          maxHeight: maxHeight > 200 ? maxHeight : 200,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.favorite_outline, size: 17, color: scheme.primary),
                  const SizedBox(width: 6),
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, size: 18),
                    tooltip: '关闭',
                    visualDensity: VisualDensity.compact,
                    color: scheme.outline,
                  ),
                ],
              ),
              Text(
                summary,
                style: TextStyle(fontSize: 12.5, color: scheme.outline),
              ),
              const SizedBox(height: 10),
              Flexible(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.asset(
                    assetPath,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.medium,
                    excludeFromSemantics: true,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Center(
                child: Text(
                  '软件完全免费，觉得好用再说 ♪',
                  style: TextStyle(fontSize: 11.5, color: scheme.outline),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
