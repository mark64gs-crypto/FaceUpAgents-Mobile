import 'package:flutter/material.dart';

import '../../core/app_theme.dart';

class PageHeading extends StatelessWidget {
  const PageHeading({
    super.key,
    required this.title,
    required this.description,
    this.trailing,
  });

  final String title;
  final String description;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTypography.screenTitle.copyWith(color: palette.textPrimary),
        ),
        const SizedBox(height: 8),
        Text(
          description,
          style: AppTypography.description.copyWith(
            color: palette.textSecondary,
          ),
        ),
      ],
    );
    if (trailing == null) return column;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: column),
        const SizedBox(width: 12),
        trailing!,
      ],
    );
  }
}
