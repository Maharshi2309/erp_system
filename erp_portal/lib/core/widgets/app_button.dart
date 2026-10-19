import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'focus_ring.dart';

enum AppButtonVariant {
  /// The one main action on a screen.
  primary,
  secondary,
  ghost,

  /// Filled red, for confirming a destructive action.
  danger,

  /// White with a red outline, e.g. "Reject…", "Deactivate…".
  dangerOutline,
}

enum AppButtonSize {
  small(32),
  medium(40),

  /// Mobile primary actions.
  large(48);

  const AppButtonSize(this.height);

  final double height;
}

/// Button from the design system (board S01).
///
/// Pass `onPressed: null` to disable. While [busy] the button is disabled,
/// shows a spinner and [busyLabel] (e.g. "Saving…"), so a second tap can't
/// send the request twice.
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.size = AppButtonSize.medium,
    this.icon,
    this.busy = false,
    this.busyLabel,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final AppButtonSize size;
  final IconData? icon;
  final bool busy;
  final String? busyLabel;
  final bool expand;

  bool get _enabled => onPressed != null && !busy;

  ({Color bg, Color hover, Color fg, Color border}) _colors() {
    if (busy && variant == AppButtonVariant.primary) {
      return (
        bg: AppColors.primaryBusy,
        hover: AppColors.primaryBusy,
        fg: AppColors.surface,
        border: AppColors.primaryBusy,
      );
    }
    if (!_enabled) {
      final ghost = variant == AppButtonVariant.ghost;
      return (
        bg: ghost ? Colors.transparent : AppColors.neutralSoft,
        hover: ghost ? Colors.transparent : AppColors.neutralSoft,
        fg: AppColors.textDisabled,
        border: ghost ? Colors.transparent : AppColors.border,
      );
    }
    return switch (variant) {
      AppButtonVariant.primary => (
        bg: AppColors.primary,
        hover: AppColors.primaryHover,
        fg: AppColors.surface,
        border: AppColors.primary,
      ),
      AppButtonVariant.secondary => (
        bg: AppColors.surface,
        hover: AppColors.surfaceMuted,
        fg: AppColors.textPrimary,
        border: AppColors.borderStrong,
      ),
      AppButtonVariant.ghost => (
        bg: Colors.transparent,
        hover: AppColors.primarySoft,
        fg: AppColors.primary,
        border: Colors.transparent,
      ),
      AppButtonVariant.danger => (
        bg: AppColors.danger,
        hover: AppColors.dangerText,
        fg: AppColors.surface,
        border: AppColors.danger,
      ),
      AppButtonVariant.dangerOutline => (
        bg: AppColors.surface,
        hover: AppColors.dangerSoft,
        fg: AppColors.danger,
        border: AppColors.dangerBorder,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = _colors();
    final text = busy ? (busyLabel ?? label) : label;
    final textStyle = size == AppButtonSize.large
        ? AppTypography.button.copyWith(fontSize: 15)
        : AppTypography.button.copyWith(
            fontSize: size == AppButtonSize.small ? 13 : 14,
          );
    final horizontal = size == AppButtonSize.small
        ? AppSpacing.md
        : AppSpacing.lg;

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (busy)
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: c.fg),
            ),
          )
        else if (icon != null)
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm - 2),
            child: Icon(icon, size: 18, color: c.fg),
          ),
        Flexible(
          child: Text(text, overflow: TextOverflow.ellipsis, maxLines: 1),
        ),
      ],
    );

    final button = TextButton(
      onPressed: _enabled ? onPressed : null,
      style: ButtonStyle(
        minimumSize: WidgetStatePropertyAll(Size(0, size.height)),
        // Grows with large text instead of squeezing the label.
        padding: WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: horizontal, vertical: 4),
        ),
        textStyle: WidgetStatePropertyAll(textStyle),
        foregroundColor: WidgetStatePropertyAll(c.fg),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.hovered) ? c.hover : c.bg,
        ),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        side: WidgetStatePropertyAll(BorderSide(color: c.border)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: content,
    );

    return FocusRing(
      child: expand ? SizedBox(width: double.infinity, child: button) : button,
    );
  }
}
