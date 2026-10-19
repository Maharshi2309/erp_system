import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/router/route_names.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/permissions/permissions.dart';
import '../../../../core/responsive/responsive_grid.dart';
import '../../../../core/responsive/responsive_page.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_overlays.dart';
import '../../../../core/widgets/kpi_card.dart';
import '../../../../core/widgets/selection_controls.dart';
import '../../../../core/widgets/skeleton.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../../core/widgets/tab_strip.dart';
import '../../../attendance/domain/attendance_book.dart';
import '../../../attendance/presentation/attendance_providers.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../auth/presentation/widgets/auth_layout.dart';
import '../../../employees/domain/employee.dart';
import '../../../employees/presentation/providers/employee_providers.dart';
import '../../domain/branch.dart';
import '../../domain/organization.dart';
import '../../domain/setup_progress.dart';
import '../providers/organization_providers.dart';
import '../setup_text.dart';

/// Board S38 — one branch in tabs, with its setup progress.
class BranchDetailScreen extends ConsumerStatefulWidget {
  const BranchDetailScreen({super.key, required this.branchId});

  final String branchId;

  @override
  ConsumerState<BranchDetailScreen> createState() => _BranchDetailScreenState();
}

class _BranchDetailScreenState extends ConsumerState<BranchDetailScreen> {
  static const _tabs = [
    'Overview',
    'Employees',
    'Schedule & policies',
    'Holidays',
    'Managers & approvers',
    'Activity',
  ];
  int _tab = 0;

  Future<void> _setStatus(Branch branch, BranchStatus status) async {
    final deactivate = status == BranchStatus.inactive;
    final confirmed = await showConfirmDialog(
      context,
      title: deactivate
          ? 'Deactivate ${branch.name}?'
          : 'Reactivate ${branch.name}?',
      message: deactivate
          ? 'No new punches or leave at this branch. Attendance, leave and '
                'reports history are kept.'
          : 'Employees can be added here again and setup continues where it '
                'left off.',
      confirmLabel: deactivate ? 'Deactivate' : 'Reactivate',
      destructive: deactivate,
    );
    if (!confirmed || !mounted) return;
    try {
      await ref.read(branchesProvider.notifier).setStatus(branch.id, status);
      if (mounted) {
        showAppToast(
          context,
          deactivate
              ? '${branch.name} deactivated'
              : '${branch.name} reactivated',
        );
      }
    } on Failure catch (failure) {
      if (mounted) {
        showAppToast(context, failure.message, icon: Icons.error_outline);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final branch = ref.watch(branchProvider(widget.branchId));
    final orgZone =
        ref.watch(organizationProvider).value?.timeZone ?? defaultTimeZone;
    final canEdit =
        ref
            .watch(sessionProvider)
            ?.permissions
            .can(PermissionModule.organization, PermissionAction.edit) ??
        false;

    return branch.when(
      loading: () => const ResponsivePage(
        child: LoadingSkeleton(
          label: 'Loading branch',
          child: SkeletonList(rows: 5),
        ),
      ),
      error: (error, _) => ErrorState(
        message: userMessageFor(error),
        onRetry: () => ref.invalidate(branchesProvider),
      ),
      data: (b) {
        if (b == null) {
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
        final progress = SetupProgress(b);
        final zone = b.timeZone ?? '$orgZone (inherited)';
        final manager = switch (b.roles) {
          null => 'No manager yet',
          final r when r.manager == BranchManagerChoice.owner =>
            'Managed by the owner',
          final r => 'Manager: ${r.managerEmail}',
        };
        return ResponsivePage(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: AppSpacing.sm,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Semantics(
                            header: true,
                            child: Text(b.name, style: AppTypography.pageTitle),
                          ),
                          Text(b.code, style: AppTypography.code),
                          StatusBadge(
                            label: b.isActive ? 'Active' : 'Inactive',
                            tone: b.isActive
                                ? StatusTone.success
                                : StatusTone.neutral,
                          ),
                        ],
                      ),
                      Text(
                        '${b.address}, ${b.city} · $zone · $manager',
                        style: AppTypography.small,
                      ),
                    ],
                  ),
                  if (canEdit)
                    Wrap(
                      spacing: AppSpacing.sm,
                      children: [
                        if (b.isActive)
                          AppButton(
                            label: 'Deactivate…',
                            variant: AppButtonVariant.dangerOutline,
                            onPressed: () =>
                                _setStatus(b, BranchStatus.inactive),
                          )
                        else
                          AppButton(
                            label: 'Reactivate…',
                            variant: AppButtonVariant.secondary,
                            onPressed: () => _setStatus(b, BranchStatus.active),
                          ),
                        AppButton(
                          label: 'Edit branch',
                          onPressed: () =>
                              context.go(AppRoutes.branchEdit(b.id)),
                        ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              if (b.isActive && !progress.isReady) ...[
                _SetupBanner(branch: b, canEdit: canEdit),
                const SizedBox(height: AppSpacing.lg),
              ],
              AppTabStrip(
                tabs: _tabs,
                selected: _tab,
                onSelected: (i) => setState(() => _tab = i),
              ),
              const SizedBox(height: AppSpacing.lg),
              switch (_tab) {
                0 => _OverviewTab(branch: b, zone: zone),
                1 => const _Later(
                  'Employees of this branch appear here once employee records '
                  'are built (Phase 4).',
                ),
                2 => _ScheduleTab(branch: b),
                3 => _HolidaysTab(branch: b),
                4 => _ManagersTab(branch: b),
                _ => const _Later(
                  'Changes to this branch will be listed here with the audit log '
                  '(Phase 7).',
                ),
              },
            ],
          ),
        );
      },
    );
  }
}

class _SetupBanner extends StatelessWidget {
  const _SetupBanner({required this.branch, required this.canEdit});

  final Branch branch;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    final progress = SetupProgress(branch);
    final next = progress.attention.firstOrNull ?? progress.next;
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
              SizedBox(
                width: 120,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: progress.percent / 100,
                    minHeight: 6,
                    backgroundColor: AppColors.border,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Flexible(
                child: Text(
                  '${progress.percent}% set up'
                  '${next == null ? '' : ' · next: ${next.title.toLowerCase()}'}',
                  style: AppTypography.small.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          if (canEdit)
            TextLink(
              'Continue setup',
              onTap: () => context.go(
                next == null
                    ? AppRoutes.branchSetup(branch.id)
                    : '${AppRoutes.branchSetup(branch.id)}?step=${next.name}',
              ),
            ),
        ],
      ),
    );
  }
}

class _OverviewTab extends ConsumerWidget {
  const _OverviewTab({required this.branch, required this.zone});

  final Branch branch;
  final String zone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Today's attendance at the branch; "—" while records load.
    final book = ref.watch(attendanceBookProvider).value;
    final people = [
      for (final e in ref.watch(employeesProvider).value ?? const <Employee>[])
        if (e.branchId == branch.id && e.status.isEmployed) e,
    ];
    final today = book == null || people.isEmpty
        ? null
        : AttendanceBook.count(
            book.daysOn(book.todayFor(people.first), people),
          );
    final missing = book
        ?.missingPunches(people)
        .where((r) => r.date.isBefore(book.todayFor(r.employee)))
        .length;
    final closed = [
      for (var i = 0; i < 7; i++)
        if (!branch.hours[i].open) weekdayNames[i],
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ResponsiveGrid(
          minItemWidth: 200,
          maxColumns: 4,
          children: [
            KpiCard(
              label: 'Employees',
              value: '${people.isEmpty ? branch.employeeCount : people.length}',
              caption: 'employed at this branch',
            ),
            KpiCard(
              label: 'Present today',
              value: today == null ? '—' : '${today.present}',
              caption: today == null
                  ? 'No attendance yet'
                  : 'of ${today.scheduled} scheduled',
              captionTone: StatusTone.success,
            ),
            KpiCard(
              label: 'On leave',
              value: today == null ? '—' : '${today.onLeave}',
              caption: 'approved leave today',
            ),
            KpiCard(
              label: 'Missing punches',
              value: missing == null ? '—' : '$missing',
              caption: 'last 30 days',
              captionTone: StatusTone.danger,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        AppCard(
          header: const CardHeader(title: 'Details'),
          child: _Facts(
            facts: [
              ('Address', '${branch.address}, ${branch.city} ${branch.pin}'),
              ('Phone', branch.phone),
              ('Email', branch.email),
              ('Time zone', zone),
              ('Weekly off', closed.isEmpty ? 'None' : closed.join(', ')),
              (
                'Opened',
                branch.openedOn == null
                    ? ''
                    : DateFormat('d MMM y').format(branch.openedOn!),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ScheduleTab extends StatelessWidget {
  const _ScheduleTab({required this.branch});

  final Branch branch;

  @override
  Widget build(BuildContext context) {
    final a = branch.attendance;
    final l = branch.leave;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          header: CardHeader(
            title: 'Working hours',
            subtitle: hoursSummary(branch.hours),
          ),
          child: Column(
            children: [
              for (var i = 0; i < 7; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 120,
                        child: Text(
                          weekdayNames[i],
                          style: AppTypography.small,
                        ),
                      ),
                      Text(
                        branch.hours[i].open
                            ? '${TimeField.format(branch.hours[i].opensAt)} – '
                                  '${TimeField.format(branch.hours[i].closesAt)}'
                            : 'Closed',
                        style: AppTypography.code.copyWith(
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        AppCard(
          header: const CardHeader(title: 'Attendance rules'),
          child: a == null
              ? const Text('Not set up yet.', style: AppTypography.small)
              : _Facts(
                  facts: [
                    ('How people punch in', punchMethodLabel(a.method)),
                    ('Grace period', '${a.graceMinutes} min'),
                    ('Early departure after', '${a.earlyLeaveMinutes} min'),
                    ('Half day if late by', '${a.halfDayLateMinutes} min'),
                    (
                      'Shifts',
                      a.shiftMode == ShiftMode.branchHours
                          ? 'Branch working hours'
                          : 'Several shifts',
                    ),
                  ],
                ),
        ),
        const SizedBox(height: AppSpacing.lg),
        AppCard(
          header: CardHeader(
            title: 'Leave policies',
            subtitle: l == null
                ? null
                : 'Approval: ${leaveApprovalLabel(l.approval)}',
          ),
          child: l == null
              ? const Text('Not set up yet.', style: AppTypography.small)
              : _Facts(
                  facts: [
                    for (final t in l.types)
                      (
                        t.name,
                        !t.enabled
                            ? 'Off'
                            : (t.tracksBalance
                                  ? '${t.daysPerYear} days a year'
                                  : 'On'),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _HolidaysTab extends StatelessWidget {
  const _HolidaysTab({required this.branch});

  final Branch branch;

  @override
  Widget build(BuildContext context) {
    final h = branch.holidays;
    if (h == null) {
      return const AppCard(
        child: EmptyState(
          icon: Icons.calendar_month_outlined,
          title: 'No holiday calendar yet',
          message: 'Choose one on the setup checklist.',
        ),
      );
    }
    final items = h.items.where((i) => i.observed).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    final format = DateFormat('EEE d MMM y');
    return AppCard(
      header: CardHeader(
        title: holidaySourceLabel(h.source),
        subtitle: '${items.length} observed',
      ),
      child: Column(
        children: [
          for (final i in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 140,
                    child: Text(
                      format.format(i.date),
                      style: AppTypography.code,
                    ),
                  ),
                  Expanded(child: Text(i.name, style: AppTypography.small)),
                  if (i.custom)
                    const StatusBadge(
                      label: 'Branch-specific',
                      tone: StatusTone.info,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ManagersTab extends StatelessWidget {
  const _ManagersTab({required this.branch});

  final Branch branch;

  @override
  Widget build(BuildContext context) {
    final r = branch.roles;
    if (r == null) {
      return const AppCard(
        child: EmptyState(
          icon: Icons.verified_user_outlined,
          title: 'No manager set',
          message: 'Choose who manages this branch on the setup checklist.',
        ),
      );
    }
    String yes(bool v) => v ? 'Yes' : 'No';
    return AppCard(
      header: CardHeader(
        title: 'Management',
        subtitle: stepNote(branch, SetupStep.roles),
      ),
      child: _Facts(
        facts: [
          if (r.manager == BranchManagerChoice.invite) ...[
            ('Approves leave', yes(r.managerCanApproveLeave)),
            ('Corrects attendance', yes(r.managerCanCorrectAttendance)),
            ('Sees and exports reports', yes(r.managerCanSeeReports)),
            ('Adds and edits employees', yes(r.managerCanEditPeople)),
          ],
          ('Employees request leave', yes(r.employeesCanRequestLeave)),
          ('Employees see who’s off', yes(r.employeesCanSeeTeamOff)),
        ],
      ),
    );
  }
}

class _Facts extends StatelessWidget {
  const _Facts({required this.facts});

  final List<(String, String)> facts;

  @override
  Widget build(BuildContext context) {
    return ResponsiveGrid(
      minItemWidth: 200,
      maxColumns: 3,
      spacing: AppSpacing.lg,
      children: [
        for (final (label, value) in facts)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppTypography.helper),
              Text(
                value.isEmpty ? '—' : value,
                style: AppTypography.small.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _Later extends StatelessWidget {
  const _Later(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: EmptyState(
        icon: Icons.construction_outlined,
        iconTone: AppColors.warning,
        title: 'Not built yet',
        message: message,
      ),
    );
  }
}
