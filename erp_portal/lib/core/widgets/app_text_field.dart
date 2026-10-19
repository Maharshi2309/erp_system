import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import 'form_field_frame.dart';

/// Single-line text field with the design system's label, error and helper.
///
/// Validation lives in the caller (domain validators or the form's
/// provider); this widget only displays [errorText]. Text the user typed is
/// never cleared by an error.
class AppTextField extends StatefulWidget {
  const AppTextField({
    super.key,
    required this.label,
    this.controller,
    this.focusNode,
    this.hintText,
    this.helperText,
    this.errorText,
    this.isRequired = false,
    this.isOptional = false,
    this.isPassword = false,
    this.monospace = false,
    this.readOnly = false,
    this.enabled = true,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.inputFormatters,
    this.maxLength,
    this.maxLines = 1,
    this.onChanged,
    this.onSubmitted,
  });

  final String label;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? hintText;
  final String? helperText;
  final String? errorText;
  final bool isRequired;
  final bool isOptional;
  final bool isPassword;
  final bool monospace;
  final bool readOnly;
  final bool enabled;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final List<TextInputFormatter>? inputFormatters;
  final int? maxLength;

  /// Lines shown; more than 1 makes a multi-line box.
  final int maxLines;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  bool _obscured = true;

  @override
  Widget build(BuildContext context) {
    final hasError = widget.errorText != null;
    final field = TextField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      readOnly: widget.readOnly,
      enabled: widget.enabled,
      obscureText: widget.isPassword && _obscured,
      minLines: widget.maxLines > 1 ? widget.maxLines : null,
      maxLines: widget.maxLines,
      enableSuggestions: !widget.isPassword,
      autocorrect: !widget.isPassword,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      autofillHints: widget.autofillHints,
      inputFormatters: [
        if (widget.maxLength != null)
          LengthLimitingTextInputFormatter(widget.maxLength),
        ...?widget.inputFormatters,
      ],
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      style: widget.monospace
          ? AppTypography.body.copyWith(fontFamily: AppTypography.mono)
          : AppTypography.body,
      decoration: InputDecoration(
        hintText: widget.hintText,
        fillColor: widget.readOnly ? AppColors.surfaceMuted : null,
        enabledBorder: hasError
            ? _border(AppColors.danger)
            : (widget.readOnly ? _border(AppColors.border) : null),
        focusedBorder: hasError ? _border(AppColors.danger, 1.5) : null,
        suffixIcon: widget.isPassword
            ? IconButton(
                tooltip: _obscured ? 'Show password' : 'Hide password',
                onPressed: () => setState(() => _obscured = !_obscured),
                icon: Icon(
                  _obscured
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
              )
            : null,
      ),
    );

    return FormFieldFrame(
      label: widget.label,
      isRequired: widget.isRequired,
      isOptional: widget.isOptional,
      helperText: widget.helperText,
      errorText: widget.errorText,
      child: Semantics(
        label: FormFieldFrame.semanticLabelFor(
          widget.label,
          isRequired: widget.isRequired,
        ),
        child: field,
      ),
    );
  }

  static OutlineInputBorder _border(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: color, width: width),
      );
}
