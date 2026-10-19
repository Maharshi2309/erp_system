import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/initials.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../auth/presentation/widgets/auth_layout.dart';

/// Full-page form without the sidebar (boards S13, S16, S18): a slim header
/// with the organization mark and "Signed in as …", the form centred below,
/// and on phones a sticky action bar (board S26).
class FocusLayout extends ConsumerWidget {
  const FocusLayout({
    super.key,
    required this.child,
    required this.actions,
    this.organizationName,
    this.headerAction,
    this.maxWidth = 560,
  });

  final Widget child;

  /// Bottom buttons (e.g. "Back to dashboard", "Create Branch").
  final List<Widget> actions;

  /// Shown as the header mark; Staffline when null.
  final String? organizationName;

  /// e.g. "Save & go to dashboard".
  final Widget? headerAction;
  final double maxWidth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final email = ref
        .watch(authControllerProvider.notifier)
        .currentAccount
        ?.email;
    final narrow = MediaQuery.sizeOf(context).width < 600;
    final actionBar = Wrap(
      alignment: WrapAlignment.end,
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: actions,
    );

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(bottom: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: organizationName == null
                          ? const StafflineLogo()
                          : _OrganizationMark(name: organizationName!),
                    ),
                  ),
                  if (email != null && !narrow)
                    Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.md),
                      child: Text(
                        'Signed in as $email',
                        style: AppTypography.helper,
                      ),
                    ),
                  if (headerAction != null)
                    // Shrinks rather than overflows on a phone at large text.
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: headerAction,
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.xl,
                  AppSpacing.lg,
                  AppSpacing.xxl,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxWidth),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        child,
                        if (!narrow) ...[
                          const SizedBox(height: AppSpacing.xl),
                          actionBar,
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (narrow)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  border: Border(top: BorderSide(color: AppColors.border)),
                ),
                child: actionBar,
              ),
          ],
        ),
      ),
    );
  }
}

class _OrganizationMark extends StatelessWidget {
  const _OrganizationMark({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.ink,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Text(
            initialsOf(name),
            style: AppTypography.helper.copyWith(
              color: AppColors.surface,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Flexible(
          child: Text(
            name,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.label.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

/// White form section with a title (e.g. "Branch details").
class FormSection extends StatelessWidget {
  const FormSection({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg + 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(title, style: AppTypography.cardTitle),
                    ),
                    if (subtitle != null)
                      Text(subtitle!, style: AppTypography.helper),
                  ],
                ),
              ),
              if (trailing != null) Flexible(child: trailing!),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          child,
        ],
      ),
    );
  }
}
