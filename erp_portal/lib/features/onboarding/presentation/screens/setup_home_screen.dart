import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/route_names.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/responsive/responsive_grid.dart';
import '../../../../core/responsive/responsive_page.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/initials.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/progress_ring.dart';
import '../../../../core/widgets/skeleton.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../auth/presentation/widgets/auth_layout.dart';
import '../../../organization/domain/branch.dart';
import '../../../organization/domain/setup_progress.dart';
import '../../../organization/presentation/providers/organization_providers.dart';
import 'overview_screen.dart';

/// Boards S15, S17, S23, S24, S25 — the owner's home while the
/// organization is being set up. Nothing here blocks the rest of the app.
class SetupHomeScreen extends ConsumerWidget {
  const SetupHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(setupOverviewProvider);
    return overview.when(
      loading: () => const ResponsivePage(child: _SetupSkeleton()),
      error: (error, _) => ErrorState(
        message: userMessageFor(error),
        onRetry: () => ref.invalidate(setupOverviewProvider),
      ),
      data: (data) => ResponsivePage(child: _SetupHome(data: data)),
    );
  }
}

class _SetupHome extends ConsumerWidget {
  const _SetupHome({required this.data});

  final SetupOverview data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final owner = data.owner;
    final branches = data.branches;
    final n = branches.length;
    final ready = data.readyCount;
    final firstName = owner?.fullName.split(' ').first;

    final greeting = (owner != null || n > 0) && firstName != null
        ? 'Welcome, $firstName'
        : 'Welcome to ${data.organization.name}';
    final status = owner == null
        ? 'Your workspace is created. Add your owner profile, then your first branch.'
        : n == 0
        ? 'Owner profile saved. Set up your first branch so your team can start.'
        : ready == n
        ? (n == 1
              ? 'Your branch is ready. Add employees whenever you like.'
              : 'All $n branches are ready.')
        : '$ready of $n ${n == 1 ? 'branch' : 'branches'} ready. Finish the '
              'rest whenever it suits you.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _OrganizationLogo(data: data),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(greeting, style: AppTypography.pageTitle),
                  ),
                  Text(status, style: AppTypography.small),
                ],
              ),
            ),
            if (ready > 0)
              AppButton(
                label: 'Open full dashboard',
                size: AppButtonSize.small,
                variant: AppButtonVariant.secondary,
                onPressed: () =>
                    ref.read(dashboardChosenProvider.notifier).set(true),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        _ReturningBanner(data: data),
        if (data.stepsDone < 3)
          _SetupCard(data: data)
        else
          _SetupSummary(branchCount: n),
        const SizedBox(height: AppSpacing.xl),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: const Text(
                      'Branches',
                      style: AppTypography.sectionTitle,
                    ),
                  ),
                  Text(
                    n == 0
                        ? 'Each branch keeps its own hours, holidays and rules.'
                        : '$n ${n == 1 ? 'branch' : 'branches'} · $ready ready · '
                              '${n - ready} in progress',
                    style: AppTypography.helper,
                  ),
                ],
              ),
            ),
            if (n > 0)
              AppButton(
                label: 'Add branch',
                icon: Icons.add,
                size: AppButtonSize.small,
                variant: AppButtonVariant.secondary,
                onPressed: () => context.go(AppRoutes.newBranch),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (n == 0)
          AppCard(
            child: EmptyState(
              icon: Icons.location_on_outlined,
              title: 'No branches yet',
              message:
                  'A branch is one location — its address, working hours and '
                  'its own rules. Most teams start with their main office.',
              actions: [
                AppButton(
                  label: 'Set Up Your First Branch',
                  variant: owner == null
                      ? AppButtonVariant.secondary
                      : AppButtonVariant.primary,
                  onPressed: () => context.go(AppRoutes.newBranch),
                ),
              ],
            ),
          )
        else
          ResponsiveGrid(
            minItemWidth: 280,
            maxColumns: 3,
            children: [for (final b in branches) _BranchCard(branch: b)],
          ),
        if (n > 0) ...[
          const SizedBox(height: AppSpacing.xl),
          Semantics(
            header: true,
            child: const Text(
              'Quick actions',
              style: AppTypography.sectionTitle,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _QuickActions(branches: branches),
        ],
      ],
    );
  }
}

class _OrganizationLogo extends StatelessWidget {
  const _OrganizationLogo({required this.data});

  final SetupOverview data;

  @override
  Widget build(BuildContext context) {
    final logo = data.organization.logo;
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: logo != null
          ? Image.memory(
              logo,
              fit: BoxFit.cover,
              width: 44,
              height: 44,
              // A damaged file shows a broken-image mark, not an error.
              errorBuilder: (_, _, _) =>
                  const Icon(Icons.broken_image_outlined),
            )
          : Text(
              initialsOf(data.organization.name),
              style: AppTypography.label.copyWith(color: AppColors.surface),
            ),
    );
  }
}

class _ReturningBanner extends ConsumerWidget {
  const _ReturningBanner({required this.data});

  final SetupOverview data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dismissed = ref.watch(returningBannerDismissedProvider);
    final bookmark = ref.watch(setupBookmarkProvider).value;
    if (dismissed || data.isComplete || bookmark == null) {
      return const SizedBox.shrink();
    }
    final branch = data.branches
        .where((b) => b.id == bookmark.branchId)
        .firstOrNull;
    final progress = branch == null ? null : SetupProgress(branch);
    if (branch == null || progress!.isReady) return const SizedBox.shrink();

    final saved = SetupStep.values
        .where((s) => s.name == bookmark.step)
        .firstOrNull;
    final step = saved != null && !progress.isComplete(saved)
        ? saved
        : (progress.next ?? SetupStep.review);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Semantics(
        container: true,
        liveRegion: true,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: AppColors.ink,
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.history, color: AppColors.surface, size: 20),
                  const SizedBox(width: AppSpacing.md),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Welcome back — pick up where you left off',
                          style: AppTypography.label.copyWith(
                            color: AppColors.surface,
                          ),
                        ),
                        Text(
                          'You were setting up ${branch.name} '
                          '(${progress.percent}%). Next: '
                          '${step.title.toLowerCase()}.',
                          style: AppTypography.helper.copyWith(
                            color: const Color(0xFFB8C0CC),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              Wrap(
                spacing: AppSpacing.sm,
                children: [
                  AppButton(
                    label: 'Later',
                    size: AppButtonSize.small,
                    variant: AppButtonVariant.secondary,
                    onPressed: () => ref
                        .read(returningBannerDismissedProvider.notifier)
                        .set(),
                  ),
                  AppButton(
                    label: 'Continue setup',
                    size: AppButtonSize.small,
                    variant: AppButtonVariant.secondary,
                    onPressed: () {
                      ref.read(returningBannerDismissedProvider.notifier).set();
                      context.go(
                        '${AppRoutes.branchSetup(branch.id)}?step=${step.name}',
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SetupCard extends StatelessWidget {
  const _SetupCard({required this.data});

  final SetupOverview data;

  @override
  Widget build(BuildContext context) {
    final owner = data.owner;
    final hasBranch = data.branches.isNotEmpty;
    final first = hasBranch ? data.branches.first : null;
    final steps = [
      _Step(
        number: 1,
        title: 'Organisation created',
        description:
            '${data.organization.name} · ${data.organization.employeeRange} people',
        done: true,
      ),
      _Step(
        number: 2,
        title: 'Set up owner profile',
        description: owner != null
            ? '${owner.fullName}${owner.designation.isEmpty ? '' : ' · ${owner.designation}'}'
            : 'Your name, photo and contact — about 30 seconds.',
        done: owner != null,
        action: 'Set Up Owner Profile',
        primary: owner == null,
        onAction: () => context.go(AppRoutes.ownerProfile),
      ),
      _Step(
        number: 3,
        title: 'Set up your first branch',
        description: first != null
            ? '${first.name} · ${SetupProgress(first).percent}% configured'
            : 'Address and working hours. Rules come later.',
        done: hasBranch,
        action: 'Set Up Your First Branch',
        primary: owner != null && !hasBranch,
        onAction: () => context.go(AppRoutes.newBranch),
      ),
    ];
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.sm,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Get ${data.organization.name} ready',
                      style: AppTypography.cardTitle,
                    ),
                    const Text(
                      'Your workspace is live. A few steps remain before your '
                      'team can start.',
                      style: AppTypography.helper,
                    ),
                  ],
                ),
                Semantics(
                  label: '${data.stepsDone} of 3 setup steps done',
                  excludeSemantics: true,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${data.stepsDone} of 3', style: AppTypography.code),
                      const SizedBox(width: AppSpacing.sm),
                      SizedBox(
                        width: 64,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: data.stepsDone / 3,
                            minHeight: 6,
                            color: AppColors.success,
                            backgroundColor: AppColors.border,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          for (final step in steps) ...[const Divider(height: 1), step],
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.number,
    required this.title,
    required this.description,
    required this.done,
    this.action,
    this.primary = false,
    this.onAction,
  });

  final int number;
  final String title;
  final String description;
  final bool done;
  final String? action;
  final bool primary;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: primary ? const Color(0xFFFAFBFF) : AppColors.surface,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          _StepIcon(number: number, done: done),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Semantics(
              label: '$title, ${done ? 'completed' : 'not done yet'}',
              excludeSemantics: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTypography.label),
                  Text(description, style: AppTypography.helper),
                ],
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          if (done)
            Text(
              'Done',
              style: AppTypography.helper.copyWith(
                color: AppColors.success,
                fontWeight: FontWeight.w600,
              ),
            )
          else if (action != null)
            AppButton(
              label: action!,
              size: AppButtonSize.small,
              variant: primary
                  ? AppButtonVariant.primary
                  : AppButtonVariant.secondary,
              onPressed: onAction,
            ),
        ],
      ),
    );
  }
}

class _StepIcon extends StatelessWidget {
  const _StepIcon({required this.number, required this.done});

  final int number;
  final bool done;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: done ? AppColors.success : AppColors.surface,
        shape: BoxShape.circle,
        border: done
            ? null
            : Border.all(color: const Color(0xFFB6BDC8), width: 1.5),
      ),
      child: done
          ? const Icon(Icons.check, size: 16, color: AppColors.surface)
          : Text(
              '$number',
              style: AppTypography.helper.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
    );
  }
}

class _SetupSummary extends StatelessWidget {
  const _SetupSummary({required this.branchCount});

  final int branchCount;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.sm,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check, size: 16, color: AppColors.success),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  'Organisation set up · owner profile saved · $branchCount '
                  '${branchCount == 1 ? 'branch' : 'branches'} created',
                  style: AppTypography.small,
                ),
              ),
            ],
          ),
          TextLink(
            'Edit owner profile',
            onTap: () => context.go(AppRoutes.ownerProfile),
          ),
        ],
      ),
    );
  }
}

class _BranchCard extends StatelessWidget {
  const _BranchCard({required this.branch});

  final Branch branch;

  @override
  Widget build(BuildContext context) {
    final progress = SetupProgress(branch);
    final status = setupStatusOf(branch);
    final attention = progress.attention;
    final ready = progress.isReady;
    final next = attention.isNotEmpty
        ? 'Fix: ${attention.first.title.toLowerCase()}'
        : (ready
              ? 'Everything required is set · ${hoursSummary(branch.hours)}'
              : 'Next: ${progress.next!.title.toLowerCase()}');
    final primaryLabel = ready
        ? 'View setup'
        : (progress.percent >= 75 ? 'Complete Setup' : 'Continue Setup');
    final step = attention.firstOrNull ?? progress.next;
    final tone = switch (status) {
      BranchSetupStatus.complete => StatusTone.success,
      BranchSetupStatus.needsAttention => StatusTone.warning,
      _ => StatusTone.info,
    };

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ProgressRing(
                percent: progress.percent,
                attention: attention.isNotEmpty,
                size: 48,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(branch.name, style: AppTypography.label),
                    Text(
                      '${branch.address}, ${branch.city}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.helper,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    StatusBadge(label: status.label, tone: tone),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(next, style: AppTypography.helper),
          const SizedBox(height: AppSpacing.md),
          OverflowBar(
            spacing: AppSpacing.sm,
            overflowSpacing: AppSpacing.sm,
            children: [
              AppButton(
                label: primaryLabel,
                size: AppButtonSize.small,
                variant: ready
                    ? AppButtonVariant.secondary
                    : AppButtonVariant.primary,
                onPressed: () => context.go(
                  ready || step == null
                      ? AppRoutes.branchSetup(branch.id)
                      : '${AppRoutes.branchSetup(branch.id)}?step=${step.name}',
                ),
              ),
              AppButton(
                label: 'Manage Branch',
                size: AppButtonSize.small,
                variant: AppButtonVariant.secondary,
                onPressed: () => context.go(AppRoutes.branch(branch.id)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.branches});

  final List<Branch> branches;

  @override
  Widget build(BuildContext context) {
    final incomplete = branches
        .where((b) => !SetupProgress(b).isReady)
        .firstOrNull;
    final anyReady = branches.any((b) => SetupProgress(b).isReady);
    final actions = <(String, IconData, String)>[
      ('Add branch', Icons.add, AppRoutes.newBranch),
      if (incomplete != null)
        (
          'Configure policies',
          Icons.description_outlined,
          '${AppRoutes.branchSetup(incomplete.id)}?step='
              '${(SetupProgress(incomplete).attention.firstOrNull ?? SetupProgress(incomplete).next!).name}',
        ),
      ('Manage employees', Icons.people_outline, AppRoutes.employees),
      if (anyReady)
        ('View attendance', Icons.schedule_outlined, AppRoutes.attendance),
    ];
    return ResponsiveGrid(
      minItemWidth: 180,
      maxColumns: 5,
      children: [
        for (final (label, icon, path) in actions)
          Material(
            color: AppColors.surface,
            shape: RoundedRectangleBorder(
              side: const BorderSide(color: AppColors.border),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: InkWell(
              onTap: () => context.go(path),
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.md,
                ),
                child: Row(
                  children: [
                    Icon(icon, size: 18, color: AppColors.primary),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: Text(label, style: AppTypography.label)),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SetupSkeleton extends StatelessWidget {
  const _SetupSkeleton();

  @override
  Widget build(BuildContext context) {
    return const LoadingSkeleton(
      label: 'Loading your organisation',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox(width: 260, height: 24),
          SizedBox(height: AppSpacing.sm),
          SkeletonBox(width: 380, height: 12),
          SizedBox(height: AppSpacing.xl),
          SkeletonBox(height: 120, radius: AppRadius.lg),
          SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(child: SkeletonBox(height: 90, radius: AppRadius.lg)),
              SizedBox(width: AppSpacing.md),
              Expanded(child: SkeletonBox(height: 90, radius: AppRadius.lg)),
            ],
          ),
        ],
      ),
    );
  }
}
