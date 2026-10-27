import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/router/route_names.dart';
import '../../../core/errors/failure.dart';
import '../../../core/permissions/permissions.dart';
import '../../../core/permissions/system_roles.dart';
import '../../../core/responsive/responsive_grid.dart';
import '../../../core/responsive/responsive_page.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/kpi_card.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_badge.dart';
import '../../attendance/domain/attendance_book.dart';
import '../../attendance/presentation/attendance_providers.dart';
import '../../attendance/presentation/attendance_widgets.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../../auth/presentation/widgets/auth_layout.dart';
import '../../employees/domain/custom_field.dart';
import '../../employees/domain/employee.dart';
import '../../employees/domain/employee_import.dart';
import '../../employees/domain/employee_query.dart';
import '../../employees/presentation/providers/employee_providers.dart';
import '../../holidays/presentation/calendar_providers.dart';
import '../../leave/domain/leave.dart';
import '../../leave/presentation/leave_providers.dart';
import '../../organization/domain/branch.dart';
import '../../organization/domain/setup_progress.dart';
import '../../organization/presentation/providers/organization_providers.dart';
import '../domain/dashboard_metrics.dart';
import 'dashboard_widgets.dart';

/// A value screens can read and replace (dashboard filters).
class ValueHolder<T> extends Notifier<T> {
  ValueHolder(this._initial);

  final T _initial;

  @override
  T build() => _initial;

  void set(T value) => state = value;
}

final _dashboardBranchProvider =
    NotifierProvider<ValueHolder<String?>, String?>(() => ValueHolder(null));
final _dashboardPeriodProvider =
    NotifierProvider<ValueHolder<DashboardPeriod>, DashboardPeriod>(
      () => ValueHolder(DashboardPeriod.last14),
    );

/// When the dashboard data was last reloaded ("Updated 2 min ago").
final _refreshedAtProvider =
    NotifierProvider<ValueHolder<DateTime?>, DateTime?>(
      () => ValueHolder(null),
    );

/// Boards S30 (desktop), S31 (tablet) and S32 (phone) — owner and HR admin.
class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    if (session == null) return const SizedBox.shrink();
    final employees = ref.watch(visibleEmployeesProvider);
    final branchesValue = ref.watch(branchesProvider);
    final imports = ref.watch(importsProvider).value ?? const <ImportRecord>[];
    final fields =
        ref.watch(customFieldsProvider).value ?? const <CustomField>[];
    final now = ref.watch(orgNowProvider)();
    final branchId = ref.watch(_dashboardBranchProvider);
    final period = ref.watch(_dashboardPeriodProvider);
    final refreshedAt = ref.watch(_refreshedAtProvider);

    if (employees.isLoading || branchesValue.isLoading) {
      return const ResponsivePage(
        child: LoadingSkeleton(
          label: 'Loading dashboard',
          child: SkeletonList(rows: 6),
        ),
      );
    }
    if (employees.hasError) {
      return ErrorState(
        message: userMessageFor(employees.error!),
        onRetry: () => ref.invalidate(employeesProvider),
      );
    }
    final branches = [
      for (final b in branchesValue.value ?? const <Branch>[])
        if (session.coversBranch(b.id)) b,
    ];
    // Branch-scoped members (who can open this page by URL) see only theirs.
    final allBranches = session.branchIds.isEmpty
        ? 'All branches'
        : 'All my branches';
    final m = DashboardMetrics.compute(
      employees: employees.value!,
      branches: branches,
      imports: imports,
      fields: fields,
      period: period,
      now: now,
      calendar: ref.watch(workCalendarProvider),
      branchId: branchId,
    );
    final isOwner = session.role == SystemRole.owner;
    final canCreate = session.permissions.can(
      PermissionModule.employees,
      PermissionAction.create,
    );
    final canSeeBranches = session.permissions.canView(
      PermissionModule.organization,
    );
    final active = branches.where((b) => b.isActive).toList();
    final selected = branches.where((b) => b.id == branchId).firstOrNull;
    final firstName = session.displayName.split(' ').first;

    void openDirectory(EmployeeQuery q) {
      ref.read(directoryQueryProvider.notifier).set(q);
      context.go(AppRoutes.employees);
    }

    void refresh() {
      ref
        ..invalidate(attendanceDataProvider)
        ..invalidate(employeesProvider)
        ..invalidate(branchesProvider)
        ..invalidate(importsProvider);
      ref.read(_refreshedAtProvider.notifier).set(ref.read(orgNowProvider)());
    }

    // Attendance figures (Phase 5); "—" while the records load.
    final book = ref.watch(attendanceBookProvider).value;
    final scoped = [
      for (final e in employees.value!)
        if (e.status.isEmployed && (branchId == null || e.branchId == branchId))
          e,
    ];
    final today = book?.today;
    final todayCounts = book == null
        ? null
        : AttendanceBook.count(book.daysOn(today!, scoped));
    final periodDays = book == null
        ? const <DateTime>[]
        : [
            for (
              var d = period.startFor(now);
              !d.isAfter(today!);
              d = DateTime(d.year, d.month, d.day + 1)
            )
              d,
          ];
    final periodRecords = book == null
        ? const <DayRecord>[]
        : [for (final d in periodDays) ...book.daysOn(d, scoped)];
    final periodCounts = AttendanceBook.count(
      periodRecords.where((r) => r.status != DayStatus.working),
    );
    final missing = book == null
        ? 0
        : book
              .missingPunches(scoped)
              .where((r) => r.date.isBefore(book.todayFor(r.employee)))
              .length;
    final notYet = book == null
        ? 0
        : book
              .daysOn(today!, scoped)
              .where((r) => r.status == DayStatus.notYet)
              .length;

    // Leave figures (Phase 6) for the people in scope.
    final leave = ref.watch(leaveBookProvider).value;
    final scopedIds = {for (final e in scoped) e.id};
    final pendingLeave = leave == null
        ? const <LeaveRequest>[]
        : (leave
              .visibleTo(
                role: session.role,
                self: ref.watch(selfEmployeeProvider),
                branchIds: session.branchIds,
              )
              .where(
                (r) =>
                    r.status == LeaveStatus.pending &&
                    scopedIds.contains(r.employeeId),
              )
              .toList()
            ..sort((a, b) => a.createdAt.compareTo(b.createdAt)));
    final waitingLong = pendingLeave
        .where((r) => now.difference(r.createdAt).inHours >= 48)
        .length;
    final taken = leave == null || today == null
        ? const <String, double>{}
        : leave.takenByType(scoped, period.startFor(now), today);
    final takenRows = [
      for (final t in leave?.data.types ?? const <LeaveType>[])
        if ((taken[t.key] ?? 0) > 0) (t, taken[t.key]!),
    ]..sort((a, b) => b.$2.compareTo(a.$2));

    final next = m.upcomingHolidays.firstOrNull;
    final kpis = [
      KpiCard(
        label: 'Total employees',
        value: '${m.total}',
        caption: m.joined == 0
            ? 'No one joined ${period.phrase}'
            : '+${m.joined} ${period.phrase}',
        onTap: () => openDirectory(EmployeeQuery(branchId: branchId)),
      ),
      KpiCard(
        label: 'Active',
        value: '${m.active}',
        caption: '${m.inactiveOrInvited} inactive or invited',
        onTap: () => openDirectory(
          EmployeeQuery(branchId: branchId, status: EmploymentStatus.active),
        ),
      ),
      KpiCard(
        label: 'Present today',
        value: todayCounts == null ? '—' : '${todayCounts.present}',
        caption: todayCounts == null
            ? 'Loading attendance'
            : '${todayCounts.rate}% of scheduled',
        captionTone: StatusTone.success,
        onTap: () => context.go(AppRoutes.attendance),
      ),
      KpiCard(
        label: 'Absent · late',
        value: todayCounts == null
            ? '—'
            : '${todayCounts.absent} · ${todayCounts.late}',
        caption: todayCounts == null || todayCounts.late == 0
            ? 'Nobody late'
            : 'late by ${todayCounts.averageLate} min on average',
        captionTone: StatusTone.warning,
        onTap: () => context.go(AppRoutes.attendanceRecords),
      ),
      KpiCard(
        label: 'Working now',
        value: todayCounts == null ? '—' : '${todayCounts.working}',
        caption: 'Punched in, no punch-out',
        onTap: () => context.go(AppRoutes.attendance),
      ),
      KpiCard(
        label: 'Pending leave',
        value: leave == null ? '—' : '${pendingLeave.length}',
        caption: waitingLong == 0
            ? 'None waiting over 48h'
            : '$waitingLong waiting over 48h',
        captionTone: waitingLong == 0 ? null : StatusTone.warning,
        onTap: () => context.go(AppRoutes.leave),
      ),
      KpiCard(
        label: 'Upcoming holidays',
        value: '${m.upcomingHolidays.length}',
        caption: next == null
            ? 'None in the next 30 days'
            : 'Next: ${next.name}, ${DateFormat('d MMM').format(next.date)}',
      ),
    ];

    final setupStrip = isOwner && active.any((b) => !SetupProgress(b).isReady)
        ? _SetupStrip(branches: active)
        : null;

    return ResponsivePage(
      child: LayoutBuilder(
        builder: (context, c) {
          final phone = c.maxWidth < 600;
          final wide = c.maxWidth >= 1000;
          final filters = Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: phone ? c.maxWidth : 180,
                child: DashboardSelect<String?>(
                  label: 'Branch',
                  value: branchId,
                  options: [
                    (null, 'All branches'),
                    for (final b in active) (b.id, b.name),
                  ],
                  onChanged: (v) =>
                      ref.read(_dashboardBranchProvider.notifier).set(v),
                ),
              ),
              SizedBox(
                width: phone ? c.maxWidth : 180,
                child: DashboardSelect<DashboardPeriod>(
                  label: 'Date range',
                  value: period,
                  options: [
                    for (final p in DashboardPeriod.values) (p, p.label),
                  ],
                  onChanged: (v) => ref
                      .read(_dashboardPeriodProvider.notifier)
                      .set(v ?? period),
                ),
              ),
              AppButton(
                label: refreshedAt == null
                    ? 'Updated just now'
                    : 'Updated ${_ago(refreshedAt, now)}',
                icon: Icons.refresh,
                variant: AppButtonVariant.ghost,
                onPressed: refresh,
              ),
              if (canCreate)
                AppButton(
                  label: 'Add employee',
                  icon: Icons.add,
                  onPressed: () => context.go(AppRoutes.newEmployee),
                ),
            ],
          );

          final headcount = DashboardPanel(
            title: 'Headcount by branch',
            child: m.headcount.isEmpty
                ? const Text('No active branches.', style: AppTypography.small)
                : Column(
                    children: [
                      for (final h in m.headcount)
                        HeadcountBar(
                          label: h.branch.name,
                          value: h.count,
                          max: m.headcount.first.count,
                          onTap: canSeeBranches
                              ? () => context.go(AppRoutes.branch(h.branch.id))
                              : null,
                        ),
                    ],
                  ),
          );
          // Only items the member can open: import results need the
          // import permission (D-81).
          final attention = [
            for (final a in m.attention)
              if (a.kind != AttentionKind.import ||
                  session.permissions.canView(PermissionModule.importExport))
                a,
          ];
          final attentionPanel = DashboardPanel(
            title: 'Needs attention',
            child: attention.isEmpty && missing == 0
                ? const Text(
                    'Nothing needs attention.',
                    style: AppTypography.small,
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (missing > 0)
                        AttentionRow(
                          item: AttentionItem(
                            kind: AttentionKind.missingPunch,
                            title:
                                '$missing open ${missing == 1 ? 'session' : 'sessions'}',
                            subtitle:
                                'Missing punches in the last 30 days · worked time excluded until corrected',
                          ),
                          onTap: () => context.go(AppRoutes.missingPunches),
                        ),
                      for (final a in attention)
                        AttentionRow(
                          item: a,
                          onTap: () => switch (a.kind) {
                            AttentionKind.import => context.go(
                              AppRoutes.importResult(a.importId!),
                            ),
                            AttentionKind.invite when a.employeeId != null =>
                              context.go(AppRoutes.employee(a.employeeId!)),
                            AttentionKind.change => context.go(
                              AppRoutes.employee(a.employeeId!),
                            ),
                            _ => openDirectory(
                              EmployeeQuery(branchId: branchId),
                            ),
                          },
                        ),
                    ],
                  ),
          );
          final approvals = DashboardPanel(
            title: 'Pending leave approvals · ${pendingLeave.length}',
            trailing: TextButton(
              onPressed: () => context.go(AppRoutes.leave),
              child: const Text('Open inbox'),
            ),
            child: pendingLeave.isEmpty
                ? const DashboardEmpty(
                    icon: Icons.event_available_outlined,
                    message: 'Nothing waiting for a decision.',
                  )
                : Column(
                    children: [
                      for (final r in pendingLeave.take(4))
                        PendingLeaveRow(
                          book: leave!,
                          request: r,
                          now: now,
                          onTap: () =>
                              context.go('${AppRoutes.leave}?request=${r.id}'),
                        ),
                    ],
                  ),
          );
          final charts = [
            DashboardPanel(
              title: 'Attendance trend',
              subtitle:
                  '${period.label} · employees per day · weekly offs and holidays excluded',
              trailing: const ChartLegend(
                items: [
                  ('On time', AttendanceColors.onTime),
                  ('Late', AttendanceColors.late),
                  ('Absent', AttendanceColors.absent),
                ],
              ),
              child: book == null
                  ? const DashboardEmpty(
                      icon: Icons.stacked_bar_chart,
                      message: 'Loading attendance…',
                    )
                  : StackedBarChart(
                      height: 160,
                      semanticLabel:
                          'Attendance per working day, ${period.label.toLowerCase()}',
                      bars: [
                        for (final d in periodDays)
                          if (scoped.any((e) => book.isScheduled(e, d)))
                            () {
                              final c = AttendanceBook.count(
                                book.daysOn(d, scoped),
                              );
                              return (
                                label: '${d.day}',
                                segments: [
                                  (c.onTime, AttendanceColors.onTime),
                                  (c.late, AttendanceColors.late),
                                  (c.absent, AttendanceColors.absent),
                                ],
                                muted: false,
                              );
                            }(),
                      ],
                    ),
            ),
            DashboardPanel(
              title: 'Today, so far',
              subtitle: todayCounts == null
                  ? null
                  : '${todayCounts.scheduled} scheduled · as of ${DateFormat('HH:mm').format(now)}',
              child: todayCounts == null
                  ? const DashboardEmpty(
                      icon: Icons.donut_large_outlined,
                      message: 'Loading attendance…',
                    )
                  : TodayBreakdown(
                      items: [
                        (
                          'On time',
                          todayCounts.onTime,
                          AttendanceColors.onTime,
                        ),
                        ('Late', todayCounts.late, AttendanceColors.late),
                        (
                          'On leave',
                          todayCounts.onLeave,
                          const Color(0xFF9AA9E8),
                        ),
                        ('Absent', todayCounts.absent, AttendanceColors.absent),
                        ('Not punched yet', notYet, AppColors.borderStrong),
                      ],
                      headline: '${todayCounts.rate}% present',
                    ),
            ),
            headcount,
            DashboardPanel(
              title: 'Leave taken by type',
              subtitle: 'days, ${period.label.toLowerCase()}',
              child: takenRows.isEmpty
                  ? const DashboardEmpty(
                      icon: Icons.bar_chart,
                      message: 'No leave taken in this period.',
                    )
                  : Column(
                      children: [
                        for (final (t, d) in takenRows)
                          HeadcountBar(
                            label: t.name.replaceAll(' leave', ''),
                            value: d,
                            max: takenRows.first.$2,
                            unit: 'days',
                            valueText: formatDays(d),
                          ),
                      ],
                    ),
            ),
            DashboardPanel(
              title: 'Scheduled vs worked hours',
              subtitle: period.label,
              child: book == null
                  ? const DashboardEmpty(
                      icon: Icons.schedule_outlined,
                      message: 'Loading attendance…',
                    )
                  : WorkedVsScheduled(
                      scheduledMinutes: periodCounts.expectedMinutes,
                      workedMinutes: periodCounts.workedMinutes,
                      missingDays: periodCounts.missing,
                    ),
            ),
          ];

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(
                  '${greetingFor(now)}, $firstName',
                  style: AppTypography.pageTitle,
                ),
              ),
              Text(
                '${DateFormat(phone ? 'EEE d MMM' : 'EEEE, d MMMM y').format(now)} · '
                '${selected?.name ?? allBranches} · '
                '${selected == null ? '${active.length} ${active.length == 1 ? 'branch' : 'branches'}, ' : ''}'
                '${m.total} ${m.total == 1 ? 'employee' : 'employees'}',
                style: AppTypography.small,
              ),
              const SizedBox(height: AppSpacing.lg),
              filters,
              const SizedBox(height: AppSpacing.lg),
              if (setupStrip != null) ...[
                setupStrip,
                const SizedBox(height: AppSpacing.lg),
              ],
              ResponsiveGrid(
                minItemWidth: phone ? 140 : 180,
                maxColumns: wide ? 7 : (phone ? 2 : 3),
                children: kpis,
              ),
              const SizedBox(height: AppSpacing.lg),
              if (wide) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: charts[0]),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(flex: 2, child: charts[1]),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                ResponsiveGrid(
                  minItemWidth: 280,
                  maxColumns: 3,
                  spacing: AppSpacing.lg,
                  children: charts.sublist(2),
                ),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: approvals),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(child: attentionPanel),
                    if (isOwner) ...[
                      const SizedBox(width: AppSpacing.lg),
                      Expanded(
                        child: _SetupChecklist(
                          branches: active,
                          employees: employees.value!,
                          upcoming: m.upcomingHolidays,
                        ),
                      ),
                    ],
                  ],
                ),
              ] else ...[
                if (!phone) ...[
                  charts[0],
                  const SizedBox(height: AppSpacing.lg),
                ],
                ResponsiveGrid(
                  minItemWidth: 280,
                  maxColumns: 2,
                  spacing: AppSpacing.lg,
                  children: [headcount, attentionPanel],
                ),
                const SizedBox(height: AppSpacing.lg),
                approvals,
                if (isOwner) ...[
                  const SizedBox(height: AppSpacing.lg),
                  _SetupChecklist(
                    branches: active,
                    employees: employees.value!,
                    upcoming: m.upcomingHolidays,
                  ),
                ],
              ],
            ],
          );
        },
      ),
    );
  }

  static String _ago(DateTime then, DateTime now) {
    final mins = now.difference(then).inMinutes;
    return mins < 1 ? 'just now' : '$mins min ago';
  }
}

class _SetupStrip extends StatelessWidget {
  const _SetupStrip({required this.branches});

  final List<Branch> branches;

  @override
  Widget build(BuildContext context) {
    final ready = branches.where((b) => SetupProgress(b).isReady).length;
    return AppCard(
      header: CardHeader(
        title: 'Branch setup',
        subtitle:
            '$ready of ${branches.length} branches fully set up · each branch is tracked on its own',
      ),
      child: ResponsiveGrid(
        minItemWidth: 240,
        maxColumns: 3,
        spacing: AppSpacing.lg,
        children: [
          for (final b in branches)
            () {
              final p = SetupProgress(b);
              final next = p.attention.firstOrNull ?? p.next;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(b.name, style: AppTypography.bodyStrong),
                      ),
                      Text('${p.percent}%', style: AppTypography.code),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: p.percent / 100,
                      minHeight: 6,
                      backgroundColor: AppColors.border,
                      color: p.isReady ? AppColors.success : AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: AppSpacing.sm,
                    children: [
                      Text(
                        p.isReady
                            ? 'Setup complete'
                            : 'Next: ${next?.title.toLowerCase() ?? ''}',
                        style: AppTypography.helper,
                      ),
                      TextLink(
                        p.isReady ? 'View setup' : 'Continue setup',
                        onTap: () => context.go(
                          p.isReady || next == null
                              ? AppRoutes.branchSetup(b.id)
                              : '${AppRoutes.branchSetup(b.id)}?step=${next.name}',
                        ),
                      ),
                    ],
                  ),
                ],
              );
            }(),
        ],
      ),
    );
  }
}

class _SetupChecklist extends ConsumerWidget {
  const _SetupChecklist({
    required this.branches,
    required this.employees,
    required this.upcoming,
  });

  final List<Branch> branches;
  final List<Employee> employees;
  final List<UpcomingHoliday> upcoming;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final owner = ref.watch(ownerProfileProvider).value;
    final now = ref.watch(orgNowProvider)();
    final nextYear = now.year + 1;
    final items = [
      ('Organization profile', owner != null, null),
      ('First branch', branches.isNotEmpty, AppRoutes.newBranch),
      (
        'Work & leave policies',
        branches.any((b) => b.attendance != null && b.leave != null),
        branches.isEmpty
            ? null
            : '${AppRoutes.branchSetup(branches.first.id)}?step=leave',
      ),
      ('Add employees', employees.isNotEmpty, AppRoutes.newEmployee),
      (
        'Invite an HR admin',
        employees.any((e) => e.role == SystemRole.hrAdmin),
        AppRoutes.newEmployee,
      ),
      (
        'Set up $nextYear holidays',
        branches.any(
          (b) => b.holidays?.items.any((h) => h.date.year == nextYear) ?? false,
        ),
        AppRoutes.holidays,
      ),
    ];
    final done = items.where((i) => i.$2).length;
    return DashboardPanel(
      title: 'Setup checklist',
      subtitle: '$done of ${items.length} done',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (label, ok, route) in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Icon(
                    ok ? Icons.check_circle : Icons.radio_button_unchecked,
                    size: 18,
                    color: ok ? AppColors.success : AppColors.textDisabled,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      label,
                      style: AppTypography.small.copyWith(
                        color: ok
                            ? AppColors.textSecondary
                            : AppColors.textPrimary,
                      ),
                    ),
                  ),
                  if (!ok && route != null)
                    TextLink('Start', onTap: () => context.go(route)),
                ],
              ),
            ),
          const Divider(height: AppSpacing.xl),
          const Text('Upcoming holidays', style: AppTypography.label),
          const SizedBox(height: AppSpacing.xs),
          if (upcoming.isEmpty)
            const Text('None in the next 30 days.', style: AppTypography.small)
          else
            for (final h in upcoming.take(3))
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    Expanded(child: Text(h.name, style: AppTypography.small)),
                    Text(
                      DateFormat('EEE d MMM').format(h.date),
                      style: AppTypography.code,
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

/// Status badge tone for an attention item.
StatusTone attentionTone(AttentionKind k) => switch (k) {
  AttentionKind.missingPunch => StatusTone.danger,
  AttentionKind.import => StatusTone.danger,
  AttentionKind.invite => StatusTone.danger,
  AttentionKind.incomplete => StatusTone.warning,
  AttentionKind.change => StatusTone.info,
};
