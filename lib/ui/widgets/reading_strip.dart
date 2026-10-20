import 'package:flutter/material.dart';

class ReadingStrip extends StatelessWidget {
  const ReadingStrip({
    super.key,
    required this.controller,
    required this.initialIndex,
    required this.itemCount,
    required this.itemBuilder,
    this.itemExtentBuilder,
  });

  final ScrollController controller;
  final int initialIndex;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double? Function(int index)? itemExtentBuilder;
  static const _center = ValueKey('reading-start');

  @override
  Widget build(BuildContext context) {
    final extent = itemExtentBuilder;

    Widget buildSliver({
      Key? key,
      required int count,
      required int Function(int index) itemIndex,
    }) {
      if (extent == null) {
        return SliverList.builder(
          key: key,
          itemCount: count,
          itemBuilder: (context, index) =>
              itemBuilder(context, itemIndex(index)),
        );
      }
      return SliverVariedExtentList.builder(
        key: key,
        itemCount: count,
        itemExtentBuilder: (index, _) => extent(itemIndex(index)),
        itemBuilder: (context, index) =>
            itemBuilder(context, itemIndex(index)),
      );
    }

    return CustomScrollView(
      controller: controller,
      center: _center,
      physics: const BouncingScrollPhysics(),
      slivers: [
        buildSliver(
          count: initialIndex,
          itemIndex: (index) => initialIndex - index - 1,
        ),
        buildSliver(
          key: _center,
          count: itemCount - initialIndex,
          itemIndex: (index) => initialIndex + index,
        ),
      ],
    );
  }
}
