import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../auth/presentation/widgets/auth_layout.dart';

/// Board S12 — first-time user with no organization.
class OnboardingStartScreen extends ConsumerWidget {
  const OnboardingStartScreen({super.key});

  static const _journey = [
    'Create organisation',
    'Owner profile',
    'First branch',
    'Configure at your pace',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(authControllerProvider.notifier).currentAccount;
    final firstName = account?.fullName.split(' ').first;
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
                  const Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: StafflineLogo(),
                    ),
                  ),
                  if (account != null &&
                      MediaQuery.sizeOf(context).width >= 600)
                    Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.md),
                      child: Text(
                        'Signed in as ${account.email}',
                        style: AppTypography.helper,
                      ),
                    ),
                  TextLink(
                    'Sign out',
                    onTap: () =>
                        ref.read(authControllerProvider.notifier).signOut(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 80),
                      child: Column(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: AppColors.primarySoft,
                              borderRadius: BorderRadius.circular(AppRadius.lg),
                            ),
                            child: const Icon(
                              Icons.apartment_outlined,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          Semantics(
                            header: true,
                            child: Text(
                              firstName == null
                                  ? 'Welcome to Staffline'
                                  : 'Welcome to Staffline, $firstName',
                              textAlign: TextAlign.center,
                              style: AppTypography.pageTitle,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          const Text(
                            'Create your organisation workspace and get '
                            'everything ready for your team.',
                            textAlign: TextAlign.center,
                            style: AppTypography.bodySecondary,
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          AppButton(
                            label: 'Set Up Your Organisation',
                            size: AppButtonSize.large,
                            onPressed: () =>
                                context.go(AppRoutes.createOrganization),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          const Text(
                            'Takes about a minute. Branches, schedules and '
                            'policies come later, at your pace.',
                            textAlign: TextAlign.center,
                            style: AppTypography.helper,
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: AppSpacing.sm,
                            runSpacing: AppSpacing.sm,
                            children: [
                              for (var i = 0; i < _journey.length; i++)
                                _JourneyChip(
                                  number: i + 1,
                                  label: _journey[i],
                                  current: i == 0,
                                ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: AppSpacing.xs,
                            children: [
                              const Text(
                                'Joining an existing team instead?',
                                style: AppTypography.small,
                              ),
                              TextLink(
                                'Use your invitation',
                                onTap: () async {
                                  await ref
                                      .read(authControllerProvider.notifier)
                                      .signOut();
                                  if (context.mounted) {
                                    context.go(AppRoutes.acceptInvite);
                                  }
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _JourneyChip extends StatelessWidget {
  const _JourneyChip({
    required this.number,
    required this.label,
    required this.current,
  });

  final int number;
  final String label;
  final bool current;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 4, 12, 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: current ? AppColors.primary : AppColors.neutralSoft,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$number',
              style: AppTypography.helper.copyWith(
                fontSize: 11,
                color: current ? AppColors.surface : AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.helper.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
