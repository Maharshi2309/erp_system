import 'package:flutter/painting.dart';

/// Colour tokens from the Staffline design system (design board S01).
///
/// Widgets use these names, never raw hex values, so a token change applies
/// everywhere. Status colour is always paired with a word or icon.
abstract final class AppColors {
  static const primary = Color(0xFF2B4ACB);
  static const primaryHover = Color(0xFF213CA8);
  static const primaryBusy = Color(0xFF4A63D6);
  static const primarySoft = Color(0xFFEEF1FD);
  static const primarySelected = Color(0xFFF7F8FE);

  static const success = Color(0xFF0B7A62);
  static const successSoft = Color(0xFFE6F5F0);
  static const successText = Color(0xFF0B5E4B);

  static const warning = Color(0xFF9A5B00);
  static const warningSoft = Color(0xFFFFF3DB);
  static const warningText = Color(0xFF6B4100);

  static const danger = Color(0xFFB42318);
  static const dangerSoft = Color(0xFFFDECEA);
  static const dangerText = Color(0xFF8A1C12);
  static const dangerBorder = Color(0xFFF3C6C1);

  static const canvas = Color(0xFFF5F6F8);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceMuted = Color(0xFFF9FAFB);
  static const neutralSoft = Color(0xFFF0F2F5);
  static const border = Color(0xFFE2E5EA);
  static const borderStrong = Color(0xFFCDD2DA);
  static const divider = Color(0xFFF0F2F5);

  static const textPrimary = Color(0xFF0E1A2B);
  static const textSecondary = Color(0xFF475467);
  static const textMuted = Color(0xFF667085);

  /// Only for disabled controls, which WCAG exempts from contrast rules.
  static const textDisabled = Color(0xFF8A94A6);

  /// Dark brand surface: welcome pane, toasts, organisation mark.
  static const ink = Color(0xFF0E1A2B);
  static const scrim = Color(0x660E1A2B);
}
