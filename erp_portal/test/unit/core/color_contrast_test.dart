import 'package:erp_portal/core/theme/app_colors.dart';
import 'package:erp_portal/core/widgets/status_badge.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// WCAG 2.2 contrast ratio between two opaque colours.
double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  const aaText = 4.5;

  group('Text tokens meet WCAG AA (4.5:1) on their backgrounds', () {
    final pairs = <String, (Color, Color)>{
      'primary text on surface': (AppColors.textPrimary, AppColors.surface),
      'secondary text on surface': (AppColors.textSecondary, AppColors.surface),
      'muted text on surface': (AppColors.textMuted, AppColors.surface),
      'muted text on canvas': (AppColors.textMuted, AppColors.canvas),
      'primary link on surface': (AppColors.primary, AppColors.surface),
      'white on primary button': (AppColors.surface, AppColors.primary),
      'white on danger button': (AppColors.surface, AppColors.danger),
      'danger text on surface': (AppColors.danger, AppColors.surface),
      'success text on surface': (AppColors.success, AppColors.surface),
      'warning text on surface': (AppColors.warning, AppColors.surface),
      'selected nav text': (AppColors.primaryHover, AppColors.primarySoft),
      'error summary text': (AppColors.dangerText, AppColors.dangerSoft),
      'toast text': (AppColors.surface, AppColors.ink),
    };
    pairs.forEach((name, pair) {
      test(name, () {
        expect(contrast(pair.$1, pair.$2), greaterThanOrEqualTo(aaText));
      });
    });
  });

  group('Every status badge tone is readable', () {
    for (final tone in StatusTone.values) {
      test(tone.name, () {
        expect(
          contrast(tone.foreground, tone.background),
          greaterThanOrEqualTo(aaText),
        );
      });
    }
  });
}
