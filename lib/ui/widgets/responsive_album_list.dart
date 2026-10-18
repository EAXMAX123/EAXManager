/// 本子列表：手机上竖着排一列，电脑上按窗口宽度铺成两三列
///
/// 卡片本身的高度是固定的（封面 80 加内边距），所以能直接塞进网格，
/// 不需要改动每张卡片的显示逻辑。
library;

import 'package:flutter/material.dart';

class ResponsiveAlbumList extends StatelessWidget {
  const ResponsiveAlbumList({
    super.key,
    this.storageKey,
    required this.itemCount,
    required this.itemBuilder,
    this.trailerBuilder,
    this.padding = const EdgeInsets.only(bottom: 24),
    this.physics,
  });

  /// 本子数量（不含底部那块「加载中」）
  final int itemCount;

  /// 给滚动位置用的键，切来切去时能记住看到哪了
  final Key? storageKey;

  final Widget Function(BuildContext context, int index) itemBuilder;

  /// 列表末尾的加载中 / 重试提示，没有就留空
  final WidgetBuilder? trailerBuilder;

  final EdgeInsetsGeometry padding;
  final ScrollPhysics? physics;

  /// 卡片高度：封面 80 + 上下内边距 12*2，再加 Card 自带的上下外边距 5*2
  static const double _tileHeight = 114;
  static const double _maxTileWidth = 460;

  @override
  Widget build(BuildContext context) {
    final trailing = trailerBuilder;
    final width = MediaQuery.sizeOf(context).width;

    if (width < 900) {
      return ListView.builder(
        key: storageKey,
        padding: padding,
        physics: physics,
        itemCount: itemCount + (trailing == null ? 0 : 1),
        itemBuilder: (context, index) {
          if (index >= itemCount) return trailing!(context);
          return itemBuilder(context, index);
        },
      );
    }

    return CustomScrollView(
      key: storageKey,
      physics: physics,
      slivers: [
        SliverPadding(
          padding: padding,
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: _maxTileWidth,
              mainAxisExtent: _tileHeight,
            ),
            itemCount: itemCount,
            itemBuilder: itemBuilder,
          ),
        ),
        if (trailing != null)
          SliverToBoxAdapter(child: trailing(context))
        else
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }
}
