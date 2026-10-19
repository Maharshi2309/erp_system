import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/password_rules.dart';

enum NoticeTone { error, success, info }

/// Coloured message box, e.g. the failed sign-in banner (S03) or the
/// "reset link sent" confirmation (S07).
class AuthNotice extends StatelessWidget {
  const AuthNotice({super.key, required this.message, required this.tone});

  final String message;
  final NoticeTone tone;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, icon) = switch (tone) {
      NoticeTone.error => (
        AppColors.dangerSoft,
        AppColors.dangerText,
        Icons.error_outline,
      ),
      NoticeTone.success => (
        AppColors.successSoft,
        AppColors.successText,
        Icons.check,
      ),
      NoticeTone.info => (
        AppColors.primarySoft,
        AppColors.primaryHover,
        Icons.info_outline,
      ),
    };
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1, right: AppSpacing.sm + 2),
              child: Icon(icon, size: 18, color: fg),
            ),
            Expanded(
              child: Text(
                message,
                style: AppTypography.small.copyWith(color: fg),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Large one-time-code input (boards S05, S06).
class CodeField extends StatelessWidget {
  const CodeField({
    super.key,
    required this.label,
    required this.controller,
    required this.message,
    this.hasError = false,
    this.isBackupCode = false,
    this.enabled = true,
    this.onChanged,
    this.onSubmitted,
  });

  final String label;
  final TextEditingController controller;

  /// Help or error text under the field.
  final String message;
  final bool hasError;
  final bool isBackupCode;
  final bool enabled;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: c, width: w),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExcludeSemantics(child: Text(label, style: AppTypography.label)),
        const SizedBox(height: 6),
        Semantics(
          label: label,
          child: TextField(
            controller: controller,
            enabled: enabled,
            autofocus: true,
            textAlign: TextAlign.center,
            keyboardType: isBackupCode
                ? TextInputType.text
                : TextInputType.number,
            textCapitalization: TextCapitalization.characters,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: isBackupCode
                ? [
                    FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9-]')),
                    _UpperCase(),
                    LengthLimitingTextInputFormatter(9),
                  ]
                : [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
            style: TextStyle(
              fontFamily: AppTypography.mono,
              fontSize: isBackupCode ? 22 : 26,
              fontWeight: FontWeight.w500,
              letterSpacing: isBackupCode ? 3 : 12,
              color: AppColors.textPrimary,
            ),
            decoration: InputDecoration(
              hintText: isBackupCode ? 'XXXX-XXXX' : '••••••',
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
              enabledBorder: border(
                hasError ? AppColors.danger : AppColors.borderStrong,
              ),
              focusedBorder: border(
                hasError ? AppColors.danger : AppColors.primary,
                1.5,
              ),
            ),
            onChanged: onChanged,
            onSubmitted: onSubmitted,
          ),
        ),
        const SizedBox(height: 6),
        Semantics(
          liveRegion: true,
          child: Text(
            message,
            style: AppTypography.helper.copyWith(
              color: hasError ? AppColors.danger : AppColors.textMuted,
            ),
          ),
        ),
      ],
    );
  }
}

class _UpperCase extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => newValue.copyWith(text: newValue.text.toUpperCase());
}

/// Strength bar plus the live rule list under a new-password field (S04).
class PasswordRulesList extends StatelessWidget {
  const PasswordRulesList({super.key, required this.rules});

  final List<PasswordRule> rules;

  @override
  Widget build(BuildContext context) {
    final met = rules.where((r) => r.isMet).length;
    final barColor = met == rules.length
        ? AppColors.success
        : AppColors.warning;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: Row(
            children: [
              for (var i = 0; i < rules.length; i++) ...[
                if (i > 0) const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: i < met ? barColor : AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        for (final rule in rules)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Semantics(
              label: '${rule.label}, ${rule.isMet ? 'met' : 'not met'}',
              excludeSemantics: true,
              child: Row(
                children: [
                  SizedBox(
                    width: 16,
                    child: Text(
                      rule.isMet ? '✓' : '·',
                      textAlign: TextAlign.center,
                      style: AppTypography.small.copyWith(
                        fontWeight: FontWeight.w600,
                        color: rule.isMet
                            ? AppColors.success
                            : AppColors.textMuted,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      rule.label,
                      style: AppTypography.small.copyWith(
                        color: rule.isMet
                            ? AppColors.success
                            : AppColors.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Checkbox with a wrapping label and an optional inline error (S04, S09).
class LabeledCheckbox extends StatelessWidget {
  const LabeledCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    required this.label,
    this.errorText,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final Widget label;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MergeSemantics(
          child: InkWell(
            onTap: () => onChanged(!value),
            borderRadius: BorderRadius.circular(AppSpacing.xs),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 32),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox.square(
                    dimension: 24,
                    child: Checkbox(
                      value: value,
                      onChanged: (v) => onChanged(v ?? false),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      side: BorderSide(
                        color: errorText != null
                            ? AppColors.danger
                            : AppColors.borderStrong,
                        width: 1.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm + 2),
                  Expanded(
                    child: DefaultTextStyle(
                      style: AppTypography.small,
                      child: label,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(left: 34, top: 2),
            child: Semantics(
              liveRegion: true,
              child: Text(
                errorText!,
                style: AppTypography.helper.copyWith(color: AppColors.danger),
              ),
            ),
          ),
      ],
    );
  }
}
