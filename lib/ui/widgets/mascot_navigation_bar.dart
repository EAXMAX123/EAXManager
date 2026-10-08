import 'package:flutter/material.dart';

import 'mascot_actor.dart';

class MascotNavigationBar extends StatefulWidget {
  const MascotNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  State<MascotNavigationBar> createState() => _MascotNavigationBarState();
}

class _MascotNavigationBarState extends State<MascotNavigationBar> {
  final _activations = List.filled(5, 0);

  static const _destinations = [
    ('发现', 'discover'),
    ('书架', 'library'),
    ('下载', 'downloads'),
    ('设置', 'settings'),
    ('关于', 'about'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    return Material(
      color: scheme.surface.withValues(alpha: 0.96),
      elevation: 3,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 46 + MediaQuery.textScalerOf(context).scale(14),
          child: Row(
            children: [
              for (var index = 0; index < _destinations.length; index++)
                Expanded(
                  child: _MascotDestination(
                    key: ValueKey(_destinations[index].$2),
                    label: _destinations[index].$1,
                    role: MascotRole.values[index],
                    activation: _activations[index],
                    selected: widget.selectedIndex == index,
                    reducedMotion: reducedMotion,
                    colorScheme: scheme,
                    onTap: () {
                      setState(() => _activations[index]++);
                      widget.onDestinationSelected(index);
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MascotDestination extends StatelessWidget {
  const _MascotDestination({
    super.key,
    required this.label,
    required this.role,
    required this.activation,
    required this.selected,
    required this.reducedMotion,
    required this.colorScheme,
    required this.onTap,
  });

  final String label;
  final MascotRole role;
  final int activation;
  final bool selected;
  final bool reducedMotion;
  final ColorScheme colorScheme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final selectedColor = colorScheme.primaryContainer;
    final labelColor = selected
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurfaceVariant;
    final duration = reducedMotion
        ? Duration.zero
        : const Duration(milliseconds: 180);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: AnimatedContainer(
            duration: duration,
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
            decoration: BoxDecoration(
              color: selected ? selectedColor : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                MascotActor(
                  role: role,
                  selected: selected,
                  activation: activation,
                ),
                AnimatedDefaultTextStyle(
                  duration: duration,
                  curve: Curves.easeOutCubic,
                  style: Theme.of(context).textTheme.labelSmall!.copyWith(
                    color: labelColor,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                  child: Text(label, maxLines: 1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
