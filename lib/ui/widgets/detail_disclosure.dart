import 'package:flutter/material.dart';

import '../../core/app_theme.dart';

/// Compact bar that opens and closes extra context: model reasoning or the
/// sources a web search visited.
class DetailDisclosure extends StatelessWidget {
  const DetailDisclosure({
    super.key,
    required this.icon,
    required this.title,
    required this.expanded,
    required this.onTap,
    required this.body,
    this.maxWidth,
    this.badge,
  });

  final IconData icon;
  final String title;
  final bool expanded;
  final VoidCallback onTap;
  final Widget body;
  final double? maxWidth;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final badgeText = badge;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
            decoration: BoxDecoration(
              color: palette.settingsRow,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: palette.cardBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: palette.textSecondary),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (badgeText != null) ...[
                  const SizedBox(width: 6),
                  Container(
                    height: 16,
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: palette.card,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: palette.cardBorder),
                    ),
                    child: Text(
                      badgeText,
                      style: TextStyle(
                        color: palette.textTertiary,
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 4),
                AnimatedRotation(
                  turns: expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  child: Icon(
                    Icons.expand_more_rounded,
                    size: 18,
                    color: palette.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topLeft,
          child: expanded
              ? Container(
                  width: maxWidth,
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: palette.settingsRow,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: palette.cardBorder),
                  ),
                  child: body,
                )
              : SizedBox(width: maxWidth ?? 0, height: 0),
        ),
      ],
    );
  }
}
