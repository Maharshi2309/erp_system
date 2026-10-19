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
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_overlays.dart';
import '../../../../core/widgets/progress_ring.dart';
import '../../../../core/widgets/skeleton.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../auth/presentation/widgets/auth_layout.dart';
import '../../../organization/domain/branch.dart';
import '../../../organization/domain/setup_progress.dart';
import '../../../organization/presentation/providers/organization_providers.dart';
import '../../../organization/presentation/setup_text.dart';
import '../widgets/setup_step_panel.dart';

/// Boards S20–S22 — one branch's setup checklist. Each step opens in a side
/// panel; progress comes only from what is saved.
class BranchSetupScreen extends ConsumerStatefulWidget {
  const BranchSetupScreen({super.key, required this.branchId, this.openStep});

  final String branchId;

  /// Opens this step's panel on arrival (e.g. "Continue setup").
  final String? openStep;

  @override
  ConsumerState<BranchSetupScreen> createState() => _BranchSetupScreenState();
}

class _BranchSetupScreenState extends ConsumerState<BranchSetupScreen> {
  bool _autoOpened = false;

  @override
  void didUpdateWidget(BranchSetupScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new `?step=` link while this page is already showing.
    if (oldWidget.openStep != widget.openStep) _autoOpened = false;
  }

  Future<void> _open(SetupStep step) async {
    final branch = ref.read(branchProvider(widget.branchId)).value;
    if (branch == null) return;
    if (step == SetupStep.basics) {
      context.go(AppRoutes.branchBasics(branch.id));
      return;
    }
    await ref.read(setupBookmarkProvider.notifier).remember(branch.id, step);
    if (!mounted) return;
    final result = await showSetupStepPanel(
      context,
      branch: branch,
      step: step,
    );
    if (!mounted) return;
    switch (result) {
      case StepSaved(:final message):
        showAppToast(context, message);
      case OpenStep(step: final next):
        await _open(next);
      case null:
        break;
    }
  }

  void _maybeAutoOpen(Branch branch) {
    if (_autoOpened || widget.openStep == null) return;
    _autoOpened = true;
    final step = SetupStep.values
        .where((s) => s.name == widget.openStep)
        .firstOrNull;
    if (step == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _open(step);
    });
  }

  @override
  Widget build(BuildContext context) {
    final branch = ref.watch(branchProvider(widget.branchId));
    return branch.when(
      loading: () => const ResponsivePage(
        child: LoadingSkeleton(
          label: 'Loading branch setup',
          child: SkeletonList(rows: 6),
        ),
      ),
      error: (error, _) => ErrorState(
        message: userMessageFor(error),
        onRetry: () => ref.invalidate(branchesProvider),
      ),
      data: (branch) {
        if (branch == null) {
          return ErrorState(
            headline: '404',
            title: 'This branch doesn’t exist',
            message: 'It may have been removed, or the link is mistyped.',
            actions: [
              AppButton(
                label: 'Go to branches',
                onPressed: () => context.go(AppRoutes.branches),
              ),
            ],
          );
        }
        _maybeAutoOpen(branch);
        return ResponsivePage(
          child: _SetupBody(branch: branch, onOpen: _open),
        );
      },
    );
  }
}

class _SetupBody extends StatelessWidget {
  const _SetupBody({required this.branch, required this.onOpen});

  final Branch branch;
  final ValueChanged<SetupStep> onOpen;

  @override
  Widget build(BuildContext context) {
    final progress = SetupProgress(branch);
    final status = setupStatusOf(branch);
    final ready = progress.isReady;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Back to dashboard',
              onPressed: () => context.go(AppRoutes.overview),
              icon: const Icon(Icons.chevron_left),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(branch.name, style: AppTypography.pageTitle),
                  ),
                  Text(
                    '${branch.address}, ${branch.city} ${branch.pin}',
                    style: AppTypography.small,
                  ),
                ],
              ),
            ),
            // Shrinks with large text instead of squeezing the title.
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140),
              child: StatusBadge(
                label: status.label,
                tone: switch (status) {
                  BranchSetupStatus.complete => StatusTone.success,
                  BranchSetupStatus.needsAttention => StatusTone.warning,
                  _ => StatusTone.info,
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        if (ready)
          _CompletedBanner(branch: branch)
        else
          _Hero(branch: branch, progress: progress, onOpen: onOpen),
        const SizedBox(height: AppSpacing.lg),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.xs,
                  children: [
                    Text(
                      ready ? 'Manage branch configuration' : 'Setup checklist',
                      style: AppTypography.cardTitle,
                    ),
                    Text(
                      ready
                          ? 'Changes save immediately and keep the branch ready while valid.'
                          : 'Required steps add to progress · optional ones don’t',
                      style: AppTypography.helper,
                    ),
                  ],
                ),
              ),
              for (final step in SetupStep.values) ...[
                const Divider(height: 1),
                _ChecklistRow(
                  branch: branch,
                  step: step,
                  onOpen: () => onOpen(step),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({
    required this.branch,
    required this.progress,
    required this.onOpen,
  });

  final Branch branch;
  final SetupProgress progress;
  final ValueChanged<SetupStep> onOpen;

  @override
  Widget build(BuildContext context) {
    final attention = progress.attention;
    final next = progress.next;
    final headline = attention.isNotEmpty
        ? 'One step needs attention'
        : progress.percent == 25
        ? 'Basics are done — 5 short steps left'
        : '${progress.requiredDone} of 6 required steps done';
    final lead = attention.isNotEmpty
        ? '${attention.first.title} changed and is no longer complete, so '
              'progress went down. Fix it to continue.'
        : 'Configure at your own pace — you can leave any time and pick up from '
              'here. Employees can already be added to this branch.';
    final target = attention.firstOrNull ?? next;
    final buttonLabel = attention.isNotEmpty
        ? 'Fix ${attention.first.title.toLowerCase()}'
        : (next == SetupStep.review
              ? 'Review & finish'
              : 'Continue: ${next!.title.toLowerCase()}');

    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(headline, style: AppTypography.cardTitle),
        const SizedBox(height: AppSpacing.xs),
        Text(lead, style: AppTypography.small),
        const SizedBox(height: AppSpacing.xs),
        TextLink(
          'How is progress calculated?',
          onTap: () => _showWeights(context, progress),
        ),
      ],
    );
    final button = target == null
        ? const SizedBox.shrink()
        : AppButton(label: buttonLabel, onPressed: () => onOpen(target));

    return AppCard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final ring = ProgressRing(
            percent: progress.percent,
            attention: attention.isNotEmpty,
            size: 88,
            caption: 'set up',
          );
          if (constraints.maxWidth < 560) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ring,
                const SizedBox(height: AppSpacing.md),
                text,
                const SizedBox(height: AppSpacing.md),
                button,
              ],
            );
          }
          return Row(
            children: [
              ring,
              const SizedBox(width: AppSpacing.lg),
              Expanded(child: text),
              const SizedBox(width: AppSpacing.lg),
              button,
            ],
          );
        },
      ),
    );
  }

  static Future<void> _showWeights(
    BuildContext context,
    SetupProgress progress,
  ) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('How progress is calculated'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final step in SetupStep.values)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(step.title, style: AppTypography.small),
                    ),
                    Text(
                      step.isOptional
                          ? 'optional'
                          : '${progress.isComplete(step) ? '✓ ' : ''}${step.weight}%',
                      style: AppTypography.code.copyWith(
                        color: progress.isComplete(step)
                            ? AppColors.successText
                            : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'The percentage comes from what is saved. If a saved step '
              'stops being valid, it goes down until you fix it.',
              style: AppTypography.helper,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

class _CompletedBanner extends StatelessWidget {
  const _CompletedBanner({required this.branch});

  final Branch branch;

  @override
  Widget build(BuildContext context) {
    final summary = [
      ('Working hours', hoursSummary(branch.hours)),
      ('Attendance', stepNote(branch, SetupStep.attendance)),
      ('Holidays', stepNote(branch, SetupStep.holidays)),
      ('Leave', stepNote(branch, SetupStep.leave)),
      ('Management', stepNote(branch, SetupStep.roles)),
    ];
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.success, width: 1.5),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                  color: AppColors.successSoft,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check,
                  color: AppColors.success,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Branch Setup Completed',
                      style: AppTypography.cardTitle,
                    ),
                    Text(
                      '${branch.name} is ready. Employees added here can punch in, '
                      'request leave and see holidays.',
                      style: AppTypography.small,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          ResponsiveGrid(
            minItemWidth: 150,
            maxColumns: 5,
            spacing: AppSpacing.sm,
            children: [
              for (final (label, value) in summary)
                Container(
                  padding: const EdgeInsets.all(AppSpacing.sm + 2),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: AppTypography.helper),
                      Text(value, style: AppTypography.label),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              AppButton(
                label: 'View Branch',
                onPressed: () => context.go(AppRoutes.branch(branch.id)),
              ),
              AppButton(
                label: 'Manage Branch',
                variant: AppButtonVariant.secondary,
                onPressed: () => context.go(AppRoutes.branchEdit(branch.id)),
              ),
              AppButton(
                label: 'Add Another Branch',
                variant: AppButtonVariant.ghost,
                onPressed: () => context.go(AppRoutes.newBranch),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChecklistRow extends StatelessWidget {
  const _ChecklistRow({
    required this.branch,
    required this.step,
    required this.onOpen,
  });

  final Branch branch;
  final SetupStep step;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final progress = SetupProgress(branch);
    final optional = step.isOptional;
    final done = progress.isComplete(step);
    final attention = !optional && progress.needsAttention(step);
    final isNext = !attention && !done && step == progress.next;
    final locked = step == SetupStep.review && !done && !progress.canReview;
    final state = optional
        ? (done ? 'Set' : 'Optional')
        : done
        ? 'Done'
        : attention
        ? 'Needs attention'
        : isNext
        ? 'Up next'
        : 'To do';
    final buttonLabel = step == SetupStep.basics || done
        ? 'Edit'
        : attention
        ? 'Fix'
        : step == SetupStep.review
        ? 'Review'
        : 'Set up';
    final highlight = (isNext || attention) && !locked;

    return Container(
      color: attention
          ? const Color(0xFFFFFBF2)
          : (isNext ? const Color(0xFFFAFBFF) : AppColors.surface),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          _StateIcon(done: done, attention: attention, optional: optional),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Semantics(
              label: '${step.title}, $state',
              excludeSemantics: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: AppSpacing.sm,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(step.title, style: AppTypography.label),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: done
                              ? AppColors.successSoft
                              : AppColors.neutralSoft,
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        child: Text(
                          optional ? 'optional' : '+${step.weight}%',
                          style: AppTypography.helper.copyWith(
                            fontSize: 11,
                            fontFamily: AppTypography.mono,
                            color: done
                                ? AppColors.successText
                                : AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '$state · ${stepNote(branch, step)}',
                    style: AppTypography.helper.copyWith(
                      color: attention
                          ? AppColors.warningText
                          : AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          AppButton(
            label: buttonLabel,
            size: AppButtonSize.small,
            variant: highlight
                ? AppButtonVariant.primary
                : AppButtonVariant.secondary,
            onPressed: onOpen,
          ),
        ],
      ),
    );
  }
}

class _StateIcon extends StatelessWidget {
  const _StateIcon({
    required this.done,
    required this.attention,
    required this.optional,
  });

  final bool done;
  final bool attention;
  final bool optional;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: done
            ? AppColors.success
            : (attention ? AppColors.warningSoft : AppColors.surface),
        shape: BoxShape.circle,
        border: done
            ? null
            : Border.all(
                color: attention
                    ? const Color(0xFFE0B565)
                    : const Color(0xFFB6BDC8),
                width: 1.5,
              ),
      ),
      child: done
          ? const Icon(Icons.check, size: 15, color: AppColors.surface)
          : (attention
                ? const Icon(
                    Icons.priority_high,
                    size: 15,
                    color: AppColors.warning,
                  )
                : null),
    );
  }
}
