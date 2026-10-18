import 'package:flutter/material.dart';

import '../theme.dart';
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
    const assetDir = AppTheme.navigationAssetDir;
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
                    assetDir: assetDir,
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
    required this.assetDir,
    required this.onTap,
    this.horizontal = false,
  });

  final String label;
  final MascotRole role;
  final int activation;
  final bool selected;
  final bool reducedMotion;
  final ColorScheme colorScheme;
  final String assetDir;
  final VoidCallback onTap;

  /// 电脑上的左侧导航用横向排布：角色在左，文字在右
  final bool horizontal;

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
      // 不再挂 Tooltip：电脑上鼠标扫过会冒出一个黑框写着「发现」「书架」，
      // 名字本来就印在旁边，多余又碍眼
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: AnimatedContainer(
          duration: duration,
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          padding: horizontal
              ? const EdgeInsets.symmetric(horizontal: 10, vertical: 8)
              : const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
          decoration: BoxDecoration(
            color: selected ? selectedColor : Colors.transparent,
            borderRadius: BorderRadius.circular(horizontal ? 14 : 16),
          ),
          child: horizontal
              ? _horizontalBody(context, labelColor, duration)
              : _verticalBody(context, labelColor, duration),
        ),
      ),
    );
  }

  Widget _verticalBody(
    BuildContext context,
    Color labelColor,
    Duration duration,
  ) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        MascotActor(
          role: role,
          selected: selected,
          activation: activation,
          assetDir: assetDir,
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
    );
  }

  Widget _horizontalBody(
    BuildContext context,
    Color labelColor,
    Duration duration,
  ) {
    return Row(
      children: [
        MascotActor(
          role: role,
          selected: selected,
          activation: activation,
          size: 34,
          assetDir: assetDir,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: AnimatedDefaultTextStyle(
            duration: duration,
            curve: Curves.easeOutCubic,
            style: Theme.of(context).textTheme.titleSmall!.copyWith(
              color: labelColor,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
    );
  }
}

/// 电脑上的左侧导航：竖着排一列，点一下角色照样会动
class MascotNavigationRail extends StatefulWidget {
  const MascotNavigationRail({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  /// 导航栏占的宽度，外层的布局也照这个数留位置
  static const double width = 200;

  @override
  State<MascotNavigationRail> createState() => _MascotNavigationRailState();
}

class _MascotNavigationRailState extends State<MascotNavigationRail> {
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
    const assetDir = AppTheme.navigationAssetDir;

    return Material(
      color: scheme.surface,
      child: SafeArea(
        right: false,
        child: SizedBox(
          width: MascotNavigationRail.width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 14),
              for (var index = 0; index < _destinations.length; index++)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 2,
                  ),
                  child: _MascotDestination(
                    key: ValueKey('rail-${_destinations[index].$2}'),
                    label: _destinations[index].$1,
                    role: MascotRole.values[index],
                    activation: _activations[index],
                    selected: widget.selectedIndex == index,
                    reducedMotion: reducedMotion,
                    colorScheme: scheme,
                    assetDir: assetDir,
                    horizontal: true,
                    onTap: () {
                      setState(() => _activations[index]++);
                      widget.onDestinationSelected(index);
                    },
                  ),
                ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}
