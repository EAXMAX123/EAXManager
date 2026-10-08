import 'dart:math' as math;

import 'package:flutter/material.dart';

enum MascotRole { discover, library, downloads, settings, about }

class MascotActor extends StatefulWidget {
  const MascotActor({
    super.key,
    required this.role,
    required this.selected,
    this.activation = 0,
    this.size = 34,
  });

  final MascotRole role;
  final bool selected;
  final int activation;
  final double size;

  @override
  State<MascotActor> createState() => _MascotActorState();
}

class _MascotActorState extends State<MascotActor>
    with TickerProviderStateMixin {
  late final AnimationController _pose = AnimationController(
    vsync: this,
    value: widget.selected ? 1 : 0,
    duration: const Duration(milliseconds: 280),
  );
  late final AnimationController _replay = AnimationController(
    vsync: this,
    value: 1,
    duration: const Duration(milliseconds: 400),
  );
  late final Listenable _animation = Listenable.merge([_pose, _replay]);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) _settle();
  }

  void _settle() {
    _pose.value = widget.selected ? 1 : 0;
    _replay.value = 1;
  }

  @override
  void didUpdateWidget(MascotActor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (MediaQuery.disableAnimationsOf(context)) {
      _settle();
    } else if (widget.selected != oldWidget.selected) {
      _replay.value = 1;
      _pose.animateTo(widget.selected ? 1 : 0, curve: Curves.easeInOutCubic);
    } else if (widget.selected && widget.activation != oldWidget.activation) {
      _replay.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _pose.dispose();
    _replay.dispose();
    super.dispose();
  }

  Widget _sprite({required bool active}) => Image.asset(
    'assets/navigation/${widget.role.name}${active ? "_active" : ""}.png',
    fit: BoxFit.contain,
    cacheWidth: widget.size > 80 ? 224 : 144,
    filterQuality: FilterQuality.medium,
    gaplessPlayback: true,
    excludeFromSemantics: true,
  );

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: RepaintBoundary(
      child: SizedBox.square(
        dimension: widget.size,
        child: AnimatedBuilder(
          animation: _animation,
          child: _sprite(active: true),
          builder: (context, activeSprite) {
            final separatePoses = widget.role == MascotRole.discover;
            final replayDip = _replay.isAnimating
                ? (separatePoses ? 1.0 : 0.65) *
                      math.sin(_replay.value * math.pi)
                : 0.0;
            final action = (_pose.value * (1 - replayDip)).clamp(0.0, 1.0);
            final idleOpacity = separatePoses
                ? (1 - action * 2).clamp(0.0, 1.0)
                : 1 - action;
            final activeOpacity = separatePoses
                ? (action * 2 - 1).clamp(0.0, 1.0)
                : action;
            return Stack(
              fit: StackFit.expand,
              children: [
                Opacity(
                  key: ValueKey('mascot-${widget.role.name}-idle'),
                  opacity: idleOpacity,
                  alwaysIncludeSemantics: false,
                  child: _sprite(active: false),
                ),
                Opacity(
                  key: ValueKey('mascot-${widget.role.name}-active'),
                  opacity: activeOpacity,
                  child: activeSprite,
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
}
