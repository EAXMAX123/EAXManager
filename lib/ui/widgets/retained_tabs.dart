import 'package:flutter/material.dart';

class PageActivity extends InheritedWidget {
  const PageActivity({super.key, required this.active, required super.child});

  final bool active;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PageActivity>()?.active ??
      true;

  @override
  bool updateShouldNotify(PageActivity oldWidget) => active != oldWidget.active;
}

class RetainedTabs extends StatefulWidget {
  const RetainedTabs({super.key, required this.index, required this.builders});

  final int index;
  final List<WidgetBuilder> builders;

  @override
  State<RetainedTabs> createState() => _RetainedTabsState();
}

class _RetainedTabsState extends State<RetainedTabs>
    with SingleTickerProviderStateMixin {
  final Set<int> _visited = {};
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
    value: 1,
  );
  late final CurvedAnimation _opacity = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );

  @override
  void didUpdateWidget(RetainedTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) {
      if (MediaQuery.disableAnimationsOf(context)) {
        _controller.value = 1;
      } else {
        _controller.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _opacity.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _visited.add(widget.index);
    return Stack(
      fit: StackFit.expand,
      children: [
        for (var index = 0; index < widget.builders.length; index++)
          if (_visited.contains(index))
            Offstage(
              key: ValueKey(index),
              offstage: index != widget.index,
              child: TickerMode(
                enabled: index == widget.index,
                child: ExcludeFocus(
                  excluding: index != widget.index,
                  child: PageActivity(
                    active: index == widget.index,
                    child: FadeTransition(
                      opacity: _opacity,
                      child: RepaintBoundary(
                        child: Builder(builder: widget.builders[index]),
                      ),
                    ),
                  ),
                ),
              ),
            ),
      ],
    );
  }
}
