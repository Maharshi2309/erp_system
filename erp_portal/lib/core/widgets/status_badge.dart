import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

enum StatusTone {
  success(AppColors.successSoft, AppColors.successText, AppColors.success),
  warning(AppColors.warningSoft, AppColors.warningText, AppColors.warning),
  danger(AppColors.dangerSoft, AppColors.dangerText, AppColors.danger),
  info(AppColors.primarySoft, AppColors.primaryHover, AppColors.primary),
  neutral(AppColors.neutralSoft, AppColors.textSecondary, AppColors.textMuted);

  const StatusTone(this.background, this.foreground, this.dot);

  final Color background;
  final Color foreground;
  final Color dot;
}

/// Status pill with a dot and a word. Status is never shown by colour alone.
class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.label, required this.tone});

  final String label;
  final StatusTone tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: tone.background,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: tone.dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.helper.copyWith(
                color: tone.foreground,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
