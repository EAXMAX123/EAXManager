import 'package:flutter/material.dart';

class ReadingStrip extends StatelessWidget {
  const ReadingStrip({
    super.key,
    required this.controller,
    required this.initialIndex,
    required this.itemCount,
    required this.itemBuilder,
  });

  final ScrollController controller;
  final int initialIndex;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  static const _center = ValueKey('reading-start');

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      controller: controller,
      center: _center,
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverList.builder(
          itemCount: initialIndex,
          itemBuilder: (context, index) =>
              itemBuilder(context, initialIndex - index - 1),
        ),
        SliverList.builder(
          key: _center,
          itemCount: itemCount - initialIndex,
          itemBuilder: (context, index) =>
              itemBuilder(context, initialIndex + index),
        ),
      ],
    );
  }
}
