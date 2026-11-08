import 'package:flutter/material.dart';

import '../../core/app_theme.dart';

class FloatingNav extends StatelessWidget {
  const FloatingNav({
    super.key,
    required this.index,
    required this.onSelect,
    required this.labels,
  });

  static const _itemWidth = 70.0;
  static const _circleSize = 48.0;
  static const _height = 69.0;

  final int index;
  final ValueChanged<int> onSelect;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      width: _itemWidth * labels.length,
      height: _height,
      decoration: BoxDecoration(
        color: palette.nav,
        borderRadius: BorderRadius.circular(35),
        border: Border.all(color: palette.navBorder, width: 0.8),
        boxShadow: [
          BoxShadow(
            color: palette.shadow.withValues(alpha: 0.18),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Stack(
        children: [
          AnimatedPositioned(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            left: index * _itemWidth + (_itemWidth - _circleSize) / 2,
            top: (_height - _circleSize) / 2,
            width: _circleSize,
            height: _circleSize,
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: palette.navActiveFill,
                  border: Border.all(color: palette.navBorder, width: 0.8),
                ),
              ),
            ),
          ),
          Row(
            children: [
              _NavItem(
                label: labels[0],
                icon: Icons.key_rounded,
                active: index == 0,
                onTap: () => onSelect(0),
              ),
              _NavItem(
                label: labels[1],
                icon: Icons.chat_bubble_rounded,
                active: index == 1,
                onTap: () => onSelect(1),
              ),
              _NavItem(
                label: labels[2],
                icon: Icons.settings_rounded,
                active: index == 2,
                onTap: () => onSelect(2),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Expanded(
      child: Tooltip(
        message: label,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Center(
            child: SizedBox(
              width: FloatingNav._circleSize,
              height: FloatingNav._circleSize,
              child: TweenAnimationBuilder<Color?>(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOut,
                tween: ColorTween(
                  begin: palette.navMuted,
                  end: active ? palette.navActive : palette.navMuted,
                ),
                builder: (context, color, _) =>
                    Icon(icon, size: 26, color: color),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
