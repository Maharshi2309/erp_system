import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'form_field_frame.dart';

/// Labelled date field that opens the calendar picker. Shows "14 Jul 2025".
class AppDateField extends StatelessWidget {
  const AppDateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.firstDate,
    this.lastDate,
    this.hintText = 'Choose a date',
    this.helperText,
    this.errorText,
    this.isRequired = false,
    this.isOptional = false,
    this.allowClear = false,
  });

  final String label;
  final DateTime? value;

  /// Null makes the field read-only.
  final ValueChanged<DateTime?>? onChanged;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final String hintText;
  final String? helperText;
  final String? errorText;
  final bool isRequired;
  final bool isOptional;
  final bool allowClear;

  static final _format = DateFormat('d MMM y');

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final first = firstDate ?? DateTime(1950);
    final last = lastDate ?? DateTime(now.year + 5, 12, 31);
    var initial = value ?? now;
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      helpText: label,
    );
    if (picked != null) onChanged?.call(picked);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    final text = value == null ? null : _format.format(value!);
    return FormFieldFrame(
      label: label,
      isRequired: isRequired,
      isOptional: isOptional,
      helperText: helperText,
      errorText: errorText,
      child: Semantics(
        button: enabled,
        label:
            '${FormFieldFrame.semanticLabelFor(label, isRequired: isRequired)}, '
            '${text ?? 'not set'}',
        excludeSemantics: true,
        child: InkWell(
          onTap: enabled ? () => _pick(context) : null,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: InputDecorator(
            isEmpty: value == null,
            decoration: InputDecoration(
              enabled: enabled,
              filled: !enabled,
              fillColor: AppColors.surfaceMuted,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: 12,
              ),
              enabledBorder: errorText == null
                  ? null
                  : OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      borderSide: const BorderSide(color: AppColors.danger),
                    ),
              suffixIcon: allowClear && value != null && enabled
                  ? IconButton(
                      tooltip: 'Clear $label',
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => onChanged?.call(null),
                    )
                  : const Icon(Icons.calendar_today_outlined, size: 18),
            ),
            child: Text(
              text ?? hintText,
              style: AppTypography.body.copyWith(
                fontFamily: AppTypography.mono,
                color: text == null
                    ? AppColors.textMuted
                    : (enabled
                          ? AppColors.textPrimary
                          : AppColors.textSecondary),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
