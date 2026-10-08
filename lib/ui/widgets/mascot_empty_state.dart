import 'package:flutter/material.dart';

import 'mascot_actor.dart';

class MascotEmptyState extends StatefulWidget {
  const MascotEmptyState({super.key, required this.message});

  final String message;

  @override
  State<MascotEmptyState> createState() => _MascotEmptyStateState();
}

class _MascotEmptyStateState extends State<MascotEmptyState> {
  bool _looking = false;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final pictureSize = (constraints.maxHeight * 0.48).clamp(48.0, 112.0);
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                button: true,
                toggled: _looking,
                label: _looking ? '点击小助手，放下放大镜' : '点击小助手，举起放大镜',
                child: Tooltip(
                  message: _looking ? '再点一下，放下放大镜' : '点一下，举起放大镜',
                  child: InkResponse(
                    onTap: () => setState(() {
                      _looking = !_looking;
                    }),
                    radius: pictureSize / 2,
                    child: MascotActor(
                      role: MascotRole.discover,
                      selected: _looking,
                      size: pictureSize,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                widget.message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
