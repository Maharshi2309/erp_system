import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/router/route_names.dart';
import '../../../../core/responsive/responsive_grid.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/zoned_time.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/kpi_card.dart';
import '../../../auth/presentation/widgets/auth_layout.dart';
import '../../../dashboard/presentation/admin_dashboard_screen.dart';
import '../../../dashboard/presentation/dashboard_widgets.dart';
import '../../../employees/domain/employee.dart';
import '../../domain/attendance_book.dart';
import '../attendance_widgets.dart';
import 'attendance_section.dart';

enum OverviewView { daily, weekly, monthly }

final _viewProvider = NotifierProvider<ValueHolder<OverviewView>, OverviewView>(
  () => ValueHolder(OverviewView.daily),
);
final _branchProvider = NotifierProvider<ValueHolder<String?>, String?>(
  () => ValueHolder(null),
);
final _departmentProvider = NotifierProvider<ValueHolder<String?>, String?>(
  () => ValueHolder(null),
);

/// Days of the period ending today, scheduled-relevant (board S52).
List<DateTime> periodDays(OverviewView view, DateTime today) => switch (view) {
  OverviewView.daily => [today],
  OverviewView.weekly => [
    for (var i = 0; i < 7; i++)
      DateTime(today.year, today.month, today.day - (today.weekday - 1) + i),
  ],
  OverviewView.monthly => [
    for (var d = 1; d <= DateTime(today.year, today.month + 1, 0).day; d++)
      DateTime(today.year, today.month, d),
  ],
};

/// Board S52 — attendance at a glance.
class AttendanceOverviewScreen extends ConsumerWidget {
  const AttendanceOverviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(_viewProvider);
    final branchId = ref.watch(_branchProvider);
    final department = ref.watch(_departmentProvider);
    return AttendanceSection(
      current: AppRoutes.attendance,
      body: (context, scope) {
        final book = scope.book;
        final people = [
          for (final e in scope.people)
            if ((branchId == null || e.branchId == branchId) &&
                (department == null || e.department == department))
              e,
        ];
        final today = book.today;
        final nowLocal = wallTime(book.now, book.orgZone);
        final days = [
          for (final d in periodDays(view, today))
            if (!d.isAfter(today)) d,
        ];
        final records = [for (final d in days) ...book.daysOn(d, people)];
        final counts = AttendanceBook.count(records);
        final todayCounts = AttendanceBook.count(book.daysOn(today, people));
        final yesterdayMissing = book
            .missingPunches(people, days: 30)
            .where((r) => r.date.isBefore(today))
            .toList();
        final onLeave = counts.onLeave;

        final subtitle = switch (view) {
          OverviewView.daily =>
            '${DateFormat('EEEE, d MMMM y').format(today)} · live until shift end',
          OverviewView.weekly =>
            'Week of ${DateFormat('d').format(periodDays(view, today).first)}–${DateFormat('d MMMM y').format(periodDays(view, today).last)}',
          OverviewView.monthly =>
            '${DateFormat('MMMM y').format(today)} so far · ${days.where((d) => people.any((e) => book.isScheduled(e, d))).length} working days',
        };

        final kpis = view == OverviewView.daily
            ? [
                KpiCard(
                  label: 'Present',
                  value: '${counts.present}',
                  caption: 'of ${counts.scheduled} scheduled',
                ),
                KpiCard(
                  label: 'Late',
                  value: '${counts.late}',
                  caption: counts.late == 0
                      ? 'Nobody late'
                      : 'avg ${counts.averageLate} min late',
                ),
                KpiCard(
                  label: 'Absent',
                  value: '${counts.absent}',
                  caption: '$onLeave on leave',
                ),
                KpiCard(
                  label: 'Incomplete',
                  value: '${yesterdayMissing.length}',
                  caption: 'open sessions, last 30 days',
                  onTap: () => context.go(AppRoutes.missingPunches),
                ),
                KpiCard(
                  label: 'Working now',
                  value: '${counts.working}',
                  caption: 'no punch-out yet',
                ),
              ]
            : [
                KpiCard(
                  label: 'Avg present',
                  value: days.isEmpty
                      ? '0'
                      : '${(counts.present / days.where((d) => records.any((r) => r.date == d && r.scheduled)).length.clamp(1, 999)).round()}',
                  caption: 'per working day',
                ),
                KpiCard(
                  label: 'Late arrivals',
                  value: '${counts.late}',
                  caption: counts.present == 0
                      ? ''
                      : '${(counts.late / counts.present * 100).toStringAsFixed(1)}% of punches',
                ),
                KpiCard(
                  label: 'Absent days',
                  value: '${counts.absent}',
                  caption: 'scheduled, no punch',
                ),
                KpiCard(
                  label: 'Missing punches',
                  value: '${counts.missing}',
                  caption: 'open sessions',
                  onTap: () => context.go(AppRoutes.missingPunches),
                ),
                KpiCard(
                  label: 'Attendance rate',
                  value: '${counts.rate}%',
                  caption: 'scheduled days',
                ),
              ];

        final chart = view == OverviewView.daily
            ? _arrivals(book, people, today)
            : _byDay(book, people, periodDays(view, today), today, view);

        final branchRows = [
          for (final b in scope.branches)
            if (branchId == null || b.id == branchId)
              (
                b,
                AttendanceBook.count(
                  records.where((r) => r.employee.branchId == b.id),
                ),
              ),
        ];

        final table = SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 520),
            child: DataTable(
              columns: const [
                DataColumn(label: Text('BRANCH')),
                DataColumn(label: Text('SCHEDULED'), numeric: true),
                DataColumn(label: Text('PRESENT'), numeric: true),
                DataColumn(label: Text('LATE'), numeric: true),
                DataColumn(label: Text('ABSENT'), numeric: true),
                DataColumn(label: Text('RATE'), numeric: true),
              ],
              rows: [
                for (final (b, c) in branchRows)
                  DataRow(
                    cells: [
                      DataCell(
                        TextLink(
                          b.name,
                          onTap: () => context.go(
                            '${AppRoutes.attendanceRecords}?branch=${b.id}',
                          ),
                        ),
                      ),
                      DataCell(
                        Text('${c.scheduled}', style: AppTypography.code),
                      ),
                      DataCell(Text('${c.present}', style: AppTypography.code)),
                      DataCell(
                        Text(
                          '${c.late}',
                          style: AppTypography.code.copyWith(
                            color: AppColors.warning,
                          ),
                        ),
                      ),
                      DataCell(
                        Text(
                          '${c.absent}',
                          style: AppTypography.code.copyWith(
                            color: const Color(0xFF8A3A12),
                          ),
                        ),
                      ),
                      DataCell(
                        Text(
                          '${c.rate}%',
                          style: AppTypography.code.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        );

        final side = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DashboardPanel(
              title: 'Missing punches · ${yesterdayMissing.length}',
              trailing: TextLink(
                'Open queue',
                onTap: () => context.go(AppRoutes.missingPunches),
              ),
              child: yesterdayMissing.isEmpty
                  ? const Text(
                      'No open sessions in the last 30 days.',
                      style: AppTypography.small,
                    )
                  : Column(
                      children: [
                        for (final r in yesterdayMissing.reversed.take(3))
                          InkWell(
                            onTap: () => context.go(
                              AppRoutes.correctAttendance(
                                r.employee.id,
                                r.date,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          r.employee.fullName,
                                          style: AppTypography.bodyStrong,
                                        ),
                                        Text(
                                          '${book.branchOf(r.employee)?.name ?? ''} · ${r.missingWhat} ${DateFormat('d MMM').format(r.date)}',
                                          style: AppTypography.helper,
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    _age(today, r.date),
                                    style: AppTypography.helper.copyWith(
                                      color: book.isOverdue(r)
                                          ? AppColors.danger
                                          : AppColors.warning,
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
              title: 'Working right now · ${todayCounts.working}',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final b in scope.branches)
                    if (branchId == null || b.id == branchId)
                      () {
                        final c = AttendanceBook.count(
                          book.daysOn(
                            today,
                            people.where((e) => e.branchId == b.id),
                          ),
                        );
                        return HeadcountBar(
                          label: '${b.name}  ${c.working} / ${c.scheduled}',
                          value: c.working,
                          max: c.scheduled,
                        );
                      }(),
                  const SizedBox(height: 4),
                  Text(
                    'Punched in with no punch-out yet · updated ${DateFormat('HH:mm').format(nowLocal)}',
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
            AttendanceHeader(
              title: 'Attendance overview',
              subtitle: subtitle,
              actions: [
                SegmentToggle<OverviewView>(
                  label: 'Period',
                  value: view,
                  options: const [
                    (OverviewView.daily, 'Daily'),
                    (OverviewView.weekly, 'Weekly'),
                    (OverviewView.monthly, 'Monthly'),
                  ],
                  onChanged: (v) => ref.read(_viewProvider.notifier).set(v),
                ),
                if (scope.branches.length > 1)
                  SizedBox(
                    width: 170,
                    child: DashboardSelect<String?>(
                      label: 'Branch',
                      value: branchId,
                      options: [
                        (null, 'All branches'),
                        for (final b in scope.branches) (b.id, b.name),
                      ],
                      onChanged: (v) =>
                          ref.read(_branchProvider.notifier).set(v),
                    ),
                  ),
                SizedBox(
                  width: 170,
                  child: DashboardSelect<String?>(
                    label: 'Department',
                    value: department,
                    options: [
                      (null, 'All departments'),
                      for (final d in departments) (d, d),
                    ],
                    onChanged: (v) =>
                        ref.read(_departmentProvider.notifier).set(v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            ResponsiveGrid(minItemWidth: 150, maxColumns: 5, children: kpis),
            const SizedBox(height: AppSpacing.lg),
            LayoutBuilder(
              builder: (context, c) {
                final main = AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      chart,
                      const SizedBox(height: AppSpacing.lg),
                      table,
                    ],
                  ),
                );
                if (c.maxWidth < 900) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      main,
                      const SizedBox(height: AppSpacing.lg),
                      side,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: main),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(flex: 2, child: side),
                  ],
                );
              },
            ),
          ],
        );
      },
    );
  }

  static String _age(DateTime today, DateTime d) {
    final n = today.difference(d).inDays;
    return '$n ${n == 1 ? 'day' : 'days'}';
  }

  /// Punch-ins per 15 minutes today, split on time / late.
  static Widget _arrivals(
    AttendanceBook book,
    List<Employee> people,
    DateTime today,
  ) {
    final buckets = <int, (int, int)>{};
    for (final r in book.daysOn(today, people)) {
      final first = r.firstIn;
      if (first == null) continue;
      final t = wallTime(first, r.zone);
      final key = (t.hour * 60 + t.minute) ~/ 15 * 15;
      final (on, late) = buckets[key] ?? (0, 0);
      buckets[key] = r.lateMinutes > 0 ? (on, late + 1) : (on + 1, late);
    }
    final keys = buckets.keys.toList()..sort();
    final start = keys.isEmpty || keys.first > 8 * 60 + 45
        ? 8 * 60 + 45
        : keys.first;
    final bars = [
      for (var m = start; m <= start + 11 * 15; m += 15)
        (
          label:
              '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}',
          segments: [
            (buckets[m]?.$1 ?? 0, AttendanceColors.onTime),
            (buckets[m]?.$2 ?? 0, AttendanceColors.late),
          ],
          muted: false,
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: AppSpacing.md,
          runSpacing: 4,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Arrivals today', style: AppTypography.cardTitle),
                Text('Punch-ins per 15 minutes', style: AppTypography.helper),
              ],
            ),
            ChartLegend(
              items: [
                ('On time', AttendanceColors.onTime),
                ('Late', AttendanceColors.late),
              ],
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        StackedBarChart(
          bars: bars,
          semanticLabel:
              'Arrivals today. ${[for (final b in bars)
                if (b.segments.any((s) => s.$1 > 0)) '${b.label}: ${b.segments[0].$1} on time, ${b.segments[1].$1} late'].join('; ')}',
        ),
      ],
    );
  }

  static Widget _byDay(
    AttendanceBook book,
    List<Employee> people,
    List<DateTime> days,
    DateTime today,
    OverviewView view,
  ) {
    final bars = [
      for (final d in days)
        if (view == OverviewView.weekly ||
            people.any((e) => book.isScheduled(e, d)))
          () {
            final c = AttendanceBook.count(book.daysOn(d, people));
            final future = d.isAfter(today);
            return (
              label: view == OverviewView.weekly
                  ? DateFormat('EEE d').format(d)
                  : '${d.day}',
              segments: future
                  ? <(int, Color)>[]
                  : [
                      (c.onTime, AttendanceColors.onTime),
                      (c.late, AttendanceColors.late),
                      (c.absent, AttendanceColors.absent),
                    ],
              muted: future,
            );
          }(),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: AppSpacing.md,
          runSpacing: 4,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  view == OverviewView.weekly
                      ? 'This week by day'
                      : '${DateFormat('MMMM').format(today)} by working day',
                  style: AppTypography.cardTitle,
                ),
                const Text(
                  'Employees per day · holidays and weekly offs are excluded',
                  style: AppTypography.helper,
                ),
              ],
            ),
            const ChartLegend(
              items: [
                ('On time', AttendanceColors.onTime),
                ('Late', AttendanceColors.late),
                ('Absent', AttendanceColors.absent),
              ],
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        StackedBarChart(
          bars: bars,
          semanticLabel:
              'Attendance by day. ${[for (final b in bars)
                if (b.segments.isNotEmpty) '${b.label}: ${b.segments[0].$1} on time, ${b.segments[1].$1} late, ${b.segments[2].$1} absent'].join('; ')}',
        ),
      ],
    );
  }
}
