import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

class FormErrorItem {
  const FormErrorItem(this.message, {this.onTap});

  final String message;

  /// Usually moves focus to the field with the problem.
  final VoidCallback? onTap;
}

/// Error summary shown at the top of a form after a failed submit, e.g.
/// "Please fix 3 things below. Nothing you entered was lost."
class FormErrorSummary extends StatelessWidget {
  const FormErrorSummary({
    super.key,
    required this.title,
    this.items = const [],
  });

  final String title;
  final List<FormErrorItem> items;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: AppColors.dangerSoft,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 1, right: AppSpacing.sm + 2),
              child: Icon(
                Icons.error_outline,
                size: 18,
                color: AppColors.dangerText,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTypography.small.copyWith(
                      color: AppColors.dangerText,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  for (final item in items)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xs),
                      child: InkWell(
                        onTap: item.onTap,
                        child: Text(
                          item.message,
                          style: AppTypography.small.copyWith(
                            color: AppColors.dangerText,
                            decoration: item.onTap == null
                                ? null
                                : TextDecoration.underline,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
