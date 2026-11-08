import 'package:flutter/material.dart';

import '../../core/app_theme.dart';

class AppTopBar extends StatelessWidget {
  const AppTopBar({super.key, required this.onToggleTheme, this.onBack});

  final VoidCallback onToggleTheme;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final width = MediaQuery.sizeOf(context).width;
    return Container(
      color: palette.headerBar,
      child: SafeArea(
        bottom: false,
        child: Container(
          height: 61,
          padding: EdgeInsets.only(
            left: onBack != null ? 10 : pageInset(width),
            right: 16,
          ),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: palette.cardBorder, width: 0.7),
            ),
            boxShadow: [
              BoxShadow(
                color: palette.shadow.withValues(alpha: 0.06),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              if (onBack != null) ...[
                _CircleButton(
                  size: 48,
                  onPressed: onBack!,
                  child: Icon(
                    Icons.arrow_back_rounded,
                    size: 24,
                    color: palette.textPrimary,
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Text(
                'FaceUpAgents',
                style: AppTypography.brand.copyWith(color: palette.textPrimary),
              ),
              const Spacer(),
              _CircleButton(
                size: 44,
                onPressed: onToggleTheme,
                child: Icon(
                  isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                  size: 22,
                  color: palette.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.size,
    required this.onPressed,
    required this.child,
  });

  final double size;
  final VoidCallback onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Material(
      color: palette.card,
      shape: CircleBorder(side: BorderSide(color: palette.cardBorder)),
      elevation: 1,
      shadowColor: palette.shadow,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: size,
          height: size,
          child: Center(child: child),
        ),
      ),
    );
  }
}
