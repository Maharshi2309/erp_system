import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// White panel with a 1 px border and 12 px corners.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.header,
    this.padding = const EdgeInsets.all(AppSpacing.xl - 4),
  });

  final Widget child;
  final CardHeader? header;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Padding(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (header != null) ...[
                // Edge-to-edge cards (tables) still pad their header.
                if (padding == EdgeInsets.zero)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.xl - 4,
                      AppSpacing.lg,
                      AppSpacing.xl - 4,
                      0,
                    ),
                    child: header,
                  )
                else
                  header!,
                const SizedBox(height: AppSpacing.lg),
              ],
              child,
            ],
          ),
        ),
      ),
    );
  }
}

/// Card title row: title, optional subtitle, optional trailing action.
class CardHeader extends StatelessWidget {
  const CardHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(title, style: AppTypography.cardTitle),
        ),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(subtitle!, style: AppTypography.helper),
          ),
      ],
    );
    if (trailing == null) return titleBlock;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Narrow cards put the actions under the title.
        if (constraints.maxWidth < 420) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              titleBlock,
              const SizedBox(height: AppSpacing.sm),
              trailing!,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: titleBlock),
            const SizedBox(width: AppSpacing.md),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.6),
              child: trailing,
            ),
          ],
        );
      },
    );
  }
}
