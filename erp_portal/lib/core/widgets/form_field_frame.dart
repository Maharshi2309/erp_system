import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// Label above, control, then an inline error or helper text below — the
/// layout every form field in the design uses.
///
/// The visible label is excluded from semantics; the control announces
/// [semanticLabel] instead so screen readers hear "Branch name, required".
class FormFieldFrame extends StatelessWidget {
  const FormFieldFrame({
    super.key,
    required this.label,
    required this.child,
    this.isRequired = false,
    this.isOptional = false,
    this.helperText,
    this.errorText,
  });

  final String label;
  final Widget child;
  final bool isRequired;
  final bool isOptional;
  final String? helperText;
  final String? errorText;

  /// What the control should announce, e.g. "Branch name, required".
  static String semanticLabelFor(String label, {required bool isRequired}) =>
      isRequired ? '$label, required' : label;

  @override
  Widget build(BuildContext context) {
    final error = errorText;
    final helper = helperText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(
          child: Text.rich(
            TextSpan(
              text: label,
              children: [
                if (isRequired)
                  const TextSpan(
                    text: ' *',
                    style: TextStyle(color: AppColors.danger),
                  ),
                if (isOptional)
                  TextSpan(
                    text: ' (optional)',
                    style: AppTypography.label.copyWith(
                      fontWeight: FontWeight.w400,
                      color: AppColors.textMuted,
                    ),
                  ),
              ],
            ),
            style: AppTypography.label,
          ),
        ),
        const SizedBox(height: 6),
        child,
        if (error != null) ...[
          const SizedBox(height: 6),
          Semantics(
            liveRegion: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2, right: AppSpacing.xs + 2),
                  child: Icon(
                    Icons.error_outline,
                    size: 14,
                    color: AppColors.danger,
                  ),
                ),
                Expanded(
                  child: Text(
                    error,
                    style: AppTypography.helper.copyWith(
                      color: AppColors.danger,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ] else if (helper != null) ...[
          const SizedBox(height: 6),
          Text(helper, style: AppTypography.helper),
        ],
      ],
    );
  }
}
