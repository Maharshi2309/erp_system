import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';

/// Page frame for boards S04–S10: logo bar on top, one centred card
/// (max 440 px), canvas background. Scrolls on short screens.
class AuthLayout extends StatelessWidget {
  const AuthLayout({
    super.key,
    required this.child,
    this.trailing,
    this.maxWidth = 440,
    this.plain = false,
  });

  final Widget child;

  /// Right side of the logo bar, e.g. "Have an account? Sign in".
  final Widget? trailing;
  final double maxWidth;

  /// True to place [child] without the white card (organization list).
  final bool plain;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final padding = width < 400 ? AppSpacing.xl - 4 : AppSpacing.xxl;
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.xl,
            AppSpacing.lg,
            AppSpacing.xxxl,
          ),
          child: Column(
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1120),
                child: Row(
                  children: [
                    const StafflineLogo(),
                    const SizedBox(width: AppSpacing.lg),
                    // Takes the remaining width so long text wraps on
                    // narrow phones instead of overflowing.
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: trailing,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: plain
                    ? child
                    : Container(
                        width: double.infinity,
                        padding: EdgeInsets.all(padding),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          border: Border.all(color: AppColors.border),
                          borderRadius: BorderRadius.circular(AppRadius.lg),
                        ),
                        child: child,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "SL Staffline" mark; links back to sign-in.
class StafflineLogo extends StatelessWidget {
  const StafflineLogo({super.key, this.onDark = false});

  final bool onDark;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      link: true,
      label: 'Staffline, go to sign in',
      excludeSemantics: true,
      child: InkWell(
        onTap: () => context.go(AppRoutes.welcome),
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xs),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: onDark ? AppColors.surface : AppColors.ink,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Text(
                  'SL',
                  style: AppTypography.label.copyWith(
                    fontWeight: FontWeight.w600,
                    color: onDark ? AppColors.ink : AppColors.surface,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm + 2),
              Flexible(
                child: Text(
                  'Staffline',
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodyStrong.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: onDark ? AppColors.surface : AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Card heading with an optional lead paragraph.
class AuthHeading extends StatelessWidget {
  const AuthHeading({super.key, required this.title, this.lead});

  final String title;
  final Widget? lead;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            title,
            style: AppTypography.pageTitle.copyWith(
              fontSize: 22,
              height: 30 / 22,
            ),
          ),
        ),
        if (lead != null) ...[
          const SizedBox(height: 6),
          DefaultTextStyle(style: AppTypography.bodySecondary, child: lead!),
        ],
      ],
    );
  }
}

/// Inline text link (14 px primary), e.g. "Forgot password?".
class TextLink extends StatelessWidget {
  const TextLink(this.label, {super.key, required this.onTap, this.style});

  final String label;
  final VoidCallback onTap;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      link: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.xs),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text(
            label,
            style: (style ?? AppTypography.small).copyWith(
              color: AppColors.primary,
              decoration: TextDecoration.underline,
              decorationColor: AppColors.primary,
            ),
          ),
        ),
      ),
    );
  }
}
