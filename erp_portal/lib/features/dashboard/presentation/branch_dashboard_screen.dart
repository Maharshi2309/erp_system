import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/router/route_names.dart';
import '../../../core/errors/failure.dart';
import '../../../core/permissions/permissions.dart';
import '../../../core/responsive/responsive_grid.dart';
import '../../../core/responsive/responsive_page.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/kpi_card.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_badge.dart';
import '../../attendance/domain/attendance.dart';
import '../../attendance/domain/attendance_book.dart';
import '../../attendance/presentation/attendance_providers.dart';
import '../../attendance/presentation/attendance_widgets.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../../auth/presentation/widgets/auth_layout.dart';
import '../../employees/domain/employee.dart';
import '../../employees/presentation/providers/employee_providers.dart';
import '../../holidays/presentation/calendar_providers.dart';
import '../../leave/domain/leave.dart';
import '../../leave/domain/leave_book.dart';
import '../../leave/presentation/leave_providers.dart';
import '../../organization/presentation/providers/organization_providers.dart';
import '../domain/dashboard_metrics.dart';
import 'admin_dashboard_screen.dart';
import 'dashboard_widgets.dart';

enum _BranchPeriod {
  today('Today'),
  week('This week'),
  month('This month');

  const _BranchPeriod(this.label);

  final String label;
}

final _branchPickProvider = NotifierProvider<ValueHolder<String?>, String?>(
  () => ValueHolder(null),
);
final _periodProvider =
    NotifierProvider<ValueHolder<_BranchPeriod>, _BranchPeriod>(
      () => ValueHolder(_BranchPeriod.today),
    );

/// Board S33 — the branch manager's own branch only.
class BranchDashboardScreen extends ConsumerWidget {
  const BranchDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    if (session == null) return const SizedBox.shrink();
    final employees = ref.watch(visibleEmployeesProvider);
    final branchesValue = ref.watch(branchesProvider);
    final now = ref.watch(orgNowProvider)();
    final period = ref.watch(_periodProvider);

    if (employees.isLoading || branchesValue.isLoading) {
      return const ResponsivePage(
        child: LoadingSkeleton(
          label: 'Loading dashboard',
          child: SkeletonList(rows: 6),
        ),
      );
    }
    if (employees.hasError || branchesValue.hasError) {
      return ErrorState(
        message: userMessageFor(employees.error ?? branchesValue.error!),
        onRetry: () => ref
          ..invalidate(employeesProvider)
          ..invalidate(branchesProvider),
      );
    }
    final mine = [
      for (final b in branchesValue.value!)
        if (b.isActive && session.coversBranch(b.id)) b,
    ];
    if (mine.isEmpty) {
      return const ResponsivePage(
        child: AppCard(
          child: EmptyState(
            icon: Icons.location_off_outlined,
            title: 'No branch assigned',
            message: 'Ask the owner to assign you to a branch.',
          ),
        ),
      );
    }
    final picked = ref.watch(_branchPickProvider);
    final branch = mine.where((b) => b.id == picked).firstOrNull ?? mine.first;
    final people = [
      for (final e in employees.value!)
        if (e.branchId == branch.id && e.status != EmploymentStatus.terminated)
          e,
    ];
    final rows = departmentsToday(people, branch, now);
    final firstName = session.displayName.split(' ').first;

    // Branch holidays and closed days this week (Mon–Sun).
    final monday = DateTime(now.year, now.month, now.day - (now.weekday - 1));
    final sunday = monday.add(const Duration(days: 6));
    final holidays = ref
        .watch(workCalendarProvider)
        .holidaysBetween(branch, monday, sunday);

    // Attendance for the period (Phase 5).
    final book = ref.watch(attendanceBookProvider).value;
    final employed = [
      for (final e in people)
        if (e.status.isEmployed) e,
    ];
    final today = book?.todayFor(employed.firstOrNull ?? people.first) ?? now;
    final start = switch (period) {
      _BranchPeriod.today => today,
      _BranchPeriod.week => DateTime(
        today.year,
        today.month,
        today.day - (today.weekday - 1),
      ),
      _BranchPeriod.month => DateTime(today.year, today.month),
    };
    final records = book == null
        ? const <DayRecord>[]
        : [
            for (
              var d = start;
              !d.isAfter(today);
              d = DateTime(d.year, d.month, d.day + 1)
            )
              ...book.daysOn(d, employed),
          ];
    final c = AttendanceBook.count(records);
    final todayRecords = book == null
        ? const <DayRecord>[]
        : book.daysOn(today, employed);
    final missing = book == null
        ? const <DayRecord>[]
        : book
              .missingPunches(employed)
              .where((r) => r.date.isBefore(today))
              .toList();
    final requests = book == null
        ? const <CorrectionRequest>[]
        : book.data.requests
              .where(
                (r) =>
                    r.status == RequestStatus.open &&
                    employed.any((e) => e.id == r.employeeId),
              )
              .toList();
    // Leave (Phase 6): requests this member can decide, and who is off.
    final leave = ref.watch(leaveBookProvider).value;
    final self = ref.watch(selfEmployeeProvider);
    final employedIds = {for (final e in employed) e.id};
    final leaveWaiting =
        leave == null ||
            !session.permissions.can(
              PermissionModule.leave,
              PermissionAction.approve,
            )
        ? const <LeaveRequest>[]
        : (leave.data.requests
              .where(
                (r) =>
                    employedIds.contains(r.employeeId) &&
                    leave.canDecide(
                      r,
                      role: session.role,
                      self: self,
                      branchIds: session.branchIds,
                    ),
              )
              .toList()
            ..sort((a, b) => a.createdAt.compareTo(b.createdAt)));
    final offThisWeek = leave == null
        ? const <LeaveRequest>[]
        : (leave.data.requests
              .where(
                (r) =>
                    r.status == LeaveStatus.approved &&
                    employedIds.contains(r.employeeId) &&
                    !r.to.isBefore(monday) &&
                    !r.from.isAfter(sunday),
              )
              .toList()
            ..sort((a, b) => a.from.compareTo(b.from)));
    String v(int n) => book == null ? '—' : '$n';
    final kpis = [
      KpiCard(
        label: 'Present',
        value: v(c.present),
        caption: 'of ${c.scheduled} scheduled · ${c.rate}%',
        captionTone: StatusTone.success,
      ),
      KpiCard(
        label: 'Late',
        value: v(c.late),
        caption: c.late == 0 ? 'Nobody late' : 'avg ${c.averageLate} min',
        captionTone: StatusTone.warning,
      ),
      KpiCard(
        label: 'Absent',
        value: v(c.absent),
        caption: 'scheduled, no punch',
      ),
      KpiCard(
        label: 'On leave',
        value: v(c.onLeave),
        caption: leaveWaiting.isEmpty
            ? 'approved leave'
            : '${leaveWaiting.length} ${leaveWaiting.length == 1 ? 'request' : 'requests'} waiting',
        onTap: () => context.go(AppRoutes.leave),
      ),
      KpiCard(
        label: 'Working now',
        value: v(AttendanceBook.count(todayRecords).working),
        caption: 'punched in',
      ),
      KpiCard(
        label: 'Missing punches',
        value: v(missing.length),
        caption: 'last 30 days',
        captionTone: StatusTone.danger,
        onTap: () => context.go(AppRoutes.missingPunches),
      ),
    ];

    return ResponsivePage(
      child: LayoutBuilder(
        builder: (context, c) {
          final wide = c.maxWidth >= 1000;
          final table = AppCard(
            header: CardHeader(
              title:
                  '${period == _BranchPeriod.today ? 'Today' : period.label} by department',
              subtitle:
                  'Coverage = present ÷ scheduled. People on approved leave are not scheduled.',
            ),
            padding: EdgeInsets.zero,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: wide ? c.maxWidth * 0.6 : 560,
                ),
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('DEPARTMENT')),
                    DataColumn(label: Text('PEOPLE'), numeric: true),
                    DataColumn(label: Text('SCHEDULED'), numeric: true),
                    DataColumn(label: Text('PRESENT'), numeric: true),
                    DataColumn(label: Text('LATE'), numeric: true),
                    DataColumn(label: Text('ON LEAVE'), numeric: true),
                    DataColumn(label: Text('COVERAGE')),
                  ],
                  rows: [
                    for (final r in rows)
                      DataRow(
                        cells: [
                          DataCell(
                            Text(r.department, style: AppTypography.bodyStrong),
                          ),
                          DataCell(
                            Text('${r.people}', style: AppTypography.code),
                          ),
                          DataCell(
                            Text('${r.scheduled}', style: AppTypography.code),
                          ),
                          ...() {
                            final dept = AttendanceBook.count(
                              records.where(
                                (x) => x.employee.department == r.department,
                              ),
                            );
                            final cover = dept.scheduled == 0
                                ? 0
                                : (dept.present / dept.scheduled * 100).round();
                            return [
                              DataCell(
                                Text(
                                  v(dept.present),
                                  style: AppTypography.code,
                                ),
                              ),
                              DataCell(
                                Text(
                                  v(dept.late),
                                  style: AppTypography.code.copyWith(
                                    color: AppColors.warning,
                                  ),
                                ),
                              ),
                              DataCell(
                                Text(
                                  v(dept.onLeave),
                                  style: AppTypography.code,
                                ),
                              ),
                              DataCell(
                                book == null
                                    ? const Text(
                                        '—',
                                        style: AppTypography.helper,
                                      )
                                    : SizedBox(
                                        width: 150,
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(3),
                                                child: LinearProgressIndicator(
                                                  value: cover / 100,
                                                  minHeight: 6,
                                                  backgroundColor:
                                                      AppColors.neutralSoft,
                                                  color: cover < 75
                                                      ? AttendanceColors.absent
                                                      : AppColors.success,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(
                                              width: AppSpacing.sm,
                                            ),
                                            Text(
                                              '$cover%',
                                              style: AppTypography.helper,
                                            ),
                                          ],
                                        ),
                                      ),
                              ),
                            ];
                          }(),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          );
          final side = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DashboardPanel(
                title: 'Waiting for you',
                trailing: TextLink(
                  'All exceptions',
                  onTap: () => context.go(AppRoutes.missingPunches),
                ),
                child:
                    missing.isEmpty && requests.isEmpty && leaveWaiting.isEmpty
                    ? const DashboardEmpty(
                        icon: Icons.inbox_outlined,
                        message: 'Nothing waiting for you.',
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final r in leaveWaiting.take(4))
                            PendingLeaveRow(
                              book: leave!,
                              request: r,
                              now: now,
                              onTap: () => context.go(
                                '${AppRoutes.leave}?request=${r.id}',
                              ),
                            ),
                          for (final r in missing.reversed.take(5))
                            InkWell(
                              onTap: () => context.go(
                                AppRoutes.correctAttendance(
                                  r.employee.id,
                                  r.date,
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${r.employee.fullName} · ${r.missingWhat}',
                                            style: AppTypography.bodyStrong,
                                          ),
                                          Text(
                                            '${DateFormat('EEE d MMM').format(r.date)}${requests.any((q) => q.employeeId == r.employee.id) ? ' · correction requested' : ''}',
                                            style: AppTypography.helper,
                                          ),
                                        ],
                                      ),
                                    ),
                                    Text(
                                      '${today.difference(r.date).inDays} d',
                                      style: AppTypography.helper.copyWith(
                                        color: AppColors.warning,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
              ),
              const SizedBox(height: AppSpacing.lg),
              DashboardPanel(
                title: 'Off this week',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (holidays.isEmpty)
                      const Text(
                        'No holidays this week.',
                        style: AppTypography.small,
                      )
                    else
                      for (final h in holidays)
                        Text(
                          '${h.name} · ${DateFormat('EEE d MMM').format(h.date)} (branch closed)',
                          style: AppTypography.small.copyWith(
                            color: AppColors.textPrimary,
                          ),
                        ),
                    const SizedBox(height: AppSpacing.sm),
                    if (offThisWeek.isEmpty)
                      const Text(
                        'Nobody on approved leave this week.',
                        style: AppTypography.small,
                      )
                    else
                      for (final r in offThisWeek.take(6))
                        Text(
                          '${leave!.person(r.employeeId)?.fullName ?? r.employeeId} · ${leaveRange(r.from, r.to)}${r.half == HalfDay.full ? '' : ' (half)'}',
                          style: AppTypography.small.copyWith(
                            color: AppColors.textPrimary,
                          ),
                        ),
                    if (offThisWeek.length > 6)
                      Text(
                        '+${offThisWeek.length - 6} more',
                        style: AppTypography.helper,
                      ),
                  ],
                ),
              ),
            ],
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.end,
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          '${greetingFor(now)}, $firstName',
                          style: AppTypography.pageTitle,
                        ),
                      ),
                      Text(
                        '${DateFormat('EEEE, d MMMM y').format(now)} · ${branch.name} · '
                        '${people.length} ${people.length == 1 ? 'employee' : 'employees'}',
                        style: AppTypography.small,
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (mine.length == 1)
                        Container(
                          constraints: const BoxConstraints(minHeight: 40),
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceMuted,
                            border: Border.all(color: AppColors.border),
                            borderRadius: BorderRadius.circular(AppRadius.md),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.lock_outline,
                                size: 14,
                                color: AppColors.textSecondary,
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Flexible(
                                child: Text(
                                  'Branch: ${branch.name}',
                                  style: AppTypography.small,
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        SizedBox(
                          width: 180,
                          child: DashboardSelect<String?>(
                            label: 'Branch',
                            value: branch.id,
                            options: [for (final b in mine) (b.id, b.name)],
                            onChanged: (v) =>
                                ref.read(_branchPickProvider.notifier).set(v),
                          ),
                        ),
                      SizedBox(
                        width: 150,
                        child: DashboardSelect<_BranchPeriod>(
                          label: 'Period',
                          value: period,
                          options: [
                            for (final p in _BranchPeriod.values) (p, p.label),
                          ],
                          onChanged: (v) => ref
                              .read(_periodProvider.notifier)
                              .set(v ?? period),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              ResponsiveGrid(minItemWidth: 150, maxColumns: 6, children: kpis),
              const SizedBox(height: AppSpacing.lg),
              if (wide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: table),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(flex: 2, child: side),
                  ],
                )
              else ...[
                table,
                const SizedBox(height: AppSpacing.lg),
                side,
              ],
              const SizedBox(height: AppSpacing.md),
              Text(
                'You see ${mine.map((b) => b.name).join(', ')} only. '
                'Organization-wide numbers are available to the owner and HR.',
                style: AppTypography.helper,
              ),
            ],
          );
        },
      ),
    );
  }
}
