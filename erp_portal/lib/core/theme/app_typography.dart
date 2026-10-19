import 'package:flutter/painting.dart';

import 'app_colors.dart';

/// Type scale from the design system (board S01).
///
/// IBM Plex Sans for text; IBM Plex Mono for numbers, codes, IDs and times.
abstract final class AppTypography {
  static const sans = 'IBMPlexSans';
  static const mono = 'IBMPlexMono';

  static const pageTitle = TextStyle(
    fontFamily: sans,
    fontSize: 24,
    height: 32 / 24,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static const sectionTitle = TextStyle(
    fontFamily: sans,
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static const cardTitle = TextStyle(
    fontFamily: sans,
    fontSize: 15,
    height: 22 / 15,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static const body = TextStyle(
    fontFamily: sans,
    fontSize: 14,
    height: 22 / 14,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
  );

  static const bodyStrong = TextStyle(
    fontFamily: sans,
    fontSize: 14,
    height: 22 / 14,
    fontWeight: FontWeight.w500,
    color: AppColors.textPrimary,
  );

  static const bodySecondary = TextStyle(
    fontFamily: sans,
    fontSize: 14,
    height: 22 / 14,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
  );

  static const label = TextStyle(
    fontFamily: sans,
    fontSize: 13,
    height: 18 / 13,
    fontWeight: FontWeight.w500,
    color: AppColors.textPrimary,
  );

  static const small = TextStyle(
    fontFamily: sans,
    fontSize: 13,
    height: 20 / 13,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
  );

  static const helper = TextStyle(
    fontFamily: sans,
    fontSize: 12,
    height: 18 / 12,
    fontWeight: FontWeight.w400,
    color: AppColors.textMuted,
  );

  static const tableHeader = TextStyle(
    fontFamily: sans,
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.4,
    color: AppColors.textMuted,
  );

  static const button = TextStyle(
    fontFamily: sans,
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w500,
  );

  static const metric = TextStyle(
    fontFamily: mono,
    fontSize: 30,
    height: 36 / 30,
    fontWeight: FontWeight.w500,
    color: AppColors.textPrimary,
  );

  static const kpiValue = TextStyle(
    fontFamily: mono,
    fontSize: 22,
    height: 30 / 22,
    fontWeight: FontWeight.w500,
    color: AppColors.textPrimary,
  );

  static const code = TextStyle(
    fontFamily: mono,
    fontSize: 13,
    height: 18 / 13,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
  );
}
