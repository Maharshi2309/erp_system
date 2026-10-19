import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'status_badge.dart';

/// Key-number card, e.g. "Present today · 196 · 79% of scheduled".
///
/// When [onTap] is set the card opens the matching filtered list (PRD §13.1).
/// Values must come from data, never be hard-coded.
class KpiCard extends StatelessWidget {
  const KpiCard({
    super.key,
    required this.label,
    required this.value,
    this.caption,
    this.captionTone,
    this.onTap,
  });

  final String label;
  final String value;
  final String? caption;

  /// Colours the caption, e.g. warning for "2 waiting over 48h".
  final StatusTone? captionTone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final captionColor = switch (captionTone) {
      StatusTone.success => AppColors.success,
      StatusTone.warning => AppColors.warning,
      StatusTone.danger => AppColors.danger,
      StatusTone.info => AppColors.primary,
      _ => AppColors.textMuted,
    };
    return Semantics(
      button: onTap != null,
      label: [label, value, ?caption].join(', '),
      excludeSemantics: true,
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: AppColors.border),
          borderRadius: BorderRadius.circular(AppRadius.lg - 2),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: AppTypography.helper.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(value, style: AppTypography.kpiValue),
                if (caption != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    caption!,
                    style: AppTypography.helper.copyWith(color: captionColor),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
