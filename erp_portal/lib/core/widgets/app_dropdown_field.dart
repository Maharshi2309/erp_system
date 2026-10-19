import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'form_field_frame.dart';

class AppDropdownOption<T> {
  const AppDropdownOption(this.value, this.label, {this.enabled = true});

  final T value;
  final String label;

  /// Disabled options stay visible (e.g. an inactive branch).
  final bool enabled;
}

/// Labelled select field. The selected [value] is controlled by the caller.
class AppDropdownField<T> extends StatelessWidget {
  const AppDropdownField({
    super.key,
    required this.label,
    required this.options,
    required this.value,
    required this.onChanged,
    this.hintText,
    this.helperText,
    this.errorText,
    this.isRequired = false,
    this.isOptional = false,
  });

  final String label;
  final List<AppDropdownOption<T>> options;
  final T? value;
  final ValueChanged<T?>? onChanged;
  final String? hintText;
  final String? helperText;
  final String? errorText;
  final bool isRequired;
  final bool isOptional;

  @override
  Widget build(BuildContext context) {
    final hasError = errorText != null;
    final enabled = onChanged != null;
    return FormFieldFrame(
      label: label,
      isRequired: isRequired,
      isOptional: isOptional,
      helperText: helperText,
      errorText: errorText,
      child: Semantics(
        label: FormFieldFrame.semanticLabelFor(label, isRequired: isRequired),
        child: InputDecorator(
          isEmpty: value == null,
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: 2,
            ),
            enabled: enabled,
            enabledBorder: hasError
                ? OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    borderSide: const BorderSide(color: AppColors.danger),
                  )
                : null,
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              isExpanded: true,
              hint: hintText == null
                  ? null
                  : Text(
                      hintText!,
                      style: AppTypography.body.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
              style: AppTypography.body,
              borderRadius: BorderRadius.circular(AppRadius.md),
              icon: const Icon(
                Icons.keyboard_arrow_down,
                color: AppColors.textSecondary,
              ),
              onChanged: onChanged,
              items: [
                for (final option in options)
                  DropdownMenuItem<T>(
                    value: option.value,
                    enabled: option.enabled,
                    child: Text(
                      option.label,
                      overflow: TextOverflow.ellipsis,
                      style: option.enabled
                          ? null
                          : const TextStyle(color: AppColors.textDisabled),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
