import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/router/route_names.dart';
import '../../../../core/permissions/permissions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/file_download.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_overlays.dart';
import '../../../auth/presentation/widgets/auth_layout.dart';
import '../../../dashboard/presentation/dashboard_widgets.dart';
import '../../../employees/data/spreadsheet.dart';
import '../../../employees/domain/employee.dart';
import '../../domain/attendance_book.dart';
import '../attendance_widgets.dart';
import 'attendance_section.dart';

/// Grid cell colours (board S56 legend).
(Color, Color, Border?) cellStyle(DayStatus s) => switch (s) {
  DayStatus.present ||
  DayStatus.shortShift ||
  DayStatus.leftEarly ||
  DayStatus.working => (AppColors.successSoft, AppColors.success, null),
  DayStatus.late => (AppColors.warningSoft, const Color(0xFF8A4F00), null),
  DayStatus.halfDay => (AppColors.primarySoft, AppColors.primaryHover, null),
  DayStatus.absent => (const Color(0xFFFBEDE6), const Color(0xFF8A3A12), null),
  DayStatus.holiday => (AppColors.primary, AppColors.surface, null),
  DayStatus.onLeave => (const Color(0xFFE5E9FB), AppColors.primaryHover, null),
  DayStatus.weeklyOff => (AppColors.neutralSoft, AppColors.textMuted, null),
  DayStatus.missingPunch => (
    AppColors.surface,
    AppColors.danger,
    Border.all(color: AppColors.danger, width: 1.5),
  ),
  _ => (Colors.transparent, AppColors.textDisabled, null),
};

/// Board S56 — the month as a team grid or one person's day list.
class MonthlySummaryScreen extends ConsumerStatefulWidget {
  const MonthlySummaryScreen({super.key});

  @override
  ConsumerState<MonthlySummaryScreen> createState() =>
      _MonthlySummaryScreenState();
}

class _MonthlySummaryScreenState extends ConsumerState<MonthlySummaryScreen> {
  int _monthsBack = 0;
  bool _grid = true;
  String? _branch;
  String? _department;
  String? _personId;
  int _shown = 25;

  @override
  Widget build(BuildContext context) {
    return AttendanceSection(
      current: AppRoutes.monthlySummary,
      body: (context, scope) {
        final book = scope.book;
        final today = book.today;
        final month = DateTime(today.year, today.month - _monthsBack);
        final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
        final upTo = _monthsBack == 0 ? today.day : daysInMonth;
        final people = [
          for (final e in scope.people)
            if ((_branch == null || e.branchId == _branch) &&
                (_department == null || e.department == _department))
              e,
        ]..sort((a, b) => a.fullName.compareTo(b.fullName));
        final canCorrect = scope.session.permissions.can(
          PermissionModule.attendance,
          PermissionAction.correct,
        );
        final canExport = scope.session.permissions.can(
          PermissionModule.attendance,
          PermissionAction.export,
        );

        List<DayRecord> monthOf(Employee e) => [
          for (var d = 1; d <= daysInMonth; d++)
            book.day(e, DateTime(month.year, month.month, d)),
        ];
        ({double p, int l, int a, int lv}) totals(List<DayRecord> days) => (
          p: days.fold(
            0.0,
            (s, d) =>
                s +
                (d.status == DayStatus.halfDay
                    ? 0.5
                    : (d.status.attended ? 1 : 0)),
          ),
          l: days.where((d) => d.status == DayStatus.late).length,
          a: days.where((d) => d.status == DayStatus.absent).length,
          lv: days.where((d) => d.status == DayStatus.onLeave).length,
        );
        String fmtP(double p) =>
            p == p.roundToDouble() ? '${p.toInt()}' : p.toStringAsFixed(1);

        void export() {
          final rows = [
            [
              'Employee ID',
              'Name',
              for (var d = 1; d <= daysInMonth; d++) '$d',
              'Present',
              'Late',
              'Absent',
              'Leave',
            ],
            for (final e in people)
              () {
                final days = monthOf(e);
                final t = totals(days);
                return [
                  e.code,
                  e.fullName,
                  for (final d in days) d.status.code,
                  fmtP(t.p),
                  '${t.l}',
                  '${t.a}',
                  '${t.lv}',
                ];
              }(),
          ];
          ref
              .read(fileDownloadsProvider)
              .save(
                'attendance_${DateFormat('yyyy_MM').format(month)}.xlsx',
                buildXlsx('Monthly summary', rows),
                mimeType: xlsxMimeType,
              );
          showAppToast(context, 'Monthly summary exported');
        }

        final legend = Wrap(
          spacing: AppSpacing.md,
          runSpacing: 4,
          children: [
            for (final s in const [
              DayStatus.present,
              DayStatus.late,
              DayStatus.halfDay,
              DayStatus.absent,
              DayStatus.holiday,
              DayStatus.weeklyOff,
              DayStatus.missingPunch,
            ])
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Cell(status: s, size: 22),
                  const SizedBox(width: 4),
                  Text(s.label, style: AppTypography.helper),
                ],
              ),
            Text(
              '',
              style: AppTypography.helper.copyWith(color: AppColors.textMuted),
            ),
          ],
        );

        final selected =
            people.where((e) => e.id == _personId).firstOrNull ??
            people.firstOrNull;

        final content = !_grid && selected != null
            ? _DayList(
                book: book,
                person: selected,
                people: people,
                days: monthOf(selected).take(upTo).toList().reversed.toList(),
                totals: totals(monthOf(selected)),
                canCorrect: canCorrect,
                onPerson: (id) => setState(() => _personId = id),
              )
            : AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const SizedBox(
                                  width: 180,
                                  child: Text(
                                    'EMPLOYEE',
                                    style: AppTypography.tableHeader,
                                  ),
                                ),
                                for (var d = 1; d <= daysInMonth; d++)
                                  SizedBox(
                                    width: 28,
                                    child: Column(
                                      children: [
                                        Text(
                                          DateFormat('E')
                                              .format(
                                                DateTime(
                                                  month.year,
                                                  month.month,
                                                  d,
                                                ),
                                              )
                                              .substring(0, 2),
                                          style: AppTypography.helper.copyWith(
                                            fontSize: 10,
                                          ),
                                        ),
                                        Text(
                                          '$d',
                                          style: AppTypography.code.copyWith(
                                            fontSize: 11,
                                            color:
                                                d == today.day &&
                                                    _monthsBack == 0
                                                ? AppColors.primary
                                                : null,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                for (final h in const [
                                  'PRESENT',
                                  'LATE',
                                  'ABSENT',
                                  'LEAVE',
                                ])
                                  SizedBox(
                                    width: 64,
                                    child: Text(
                                      h,
                                      textAlign: TextAlign.end,
                                      style: AppTypography.tableHeader,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            for (final e in people.take(_shown))
                              () {
                                final days = monthOf(e);
                                final t = totals(days);
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 2,
                                  ),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 180,
                                        child: Semantics(
                                          button: true,
                                          label: 'Day list for ${e.fullName}',
                                          child: InkWell(
                                            onTap: () => setState(() {
                                              _personId = e.id;
                                              _grid = false;
                                            }),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  e.fullName,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: AppTypography.small
                                                      .copyWith(
                                                        color:
                                                            AppColors.primary,
                                                        fontWeight:
                                                            FontWeight.w500,
                                                      ),
                                                ),
                                                Text(
                                                  e.code,
                                                  style: AppTypography.helper
                                                      .copyWith(fontSize: 11),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                      for (final d in days)
                                        SizedBox(
                                          width: 28,
                                          child: Center(
                                            child: Tooltip(
                                              message:
                                                  '${DateFormat('d MMM').format(d.date)}: ${d.status.label}',
                                              child: _Cell(
                                                status: d.status,
                                                size: 24,
                                              ),
                                            ),
                                          ),
                                        ),
                                      for (final v in [
                                        fmtP(t.p),
                                        '${t.l}',
                                        '${t.a}',
                                        '${t.lv}',
                                      ])
                                        SizedBox(
                                          width: 64,
                                          child: Text(
                                            v,
                                            textAlign: TextAlign.end,
                                            style: AppTypography.code,
                                          ),
                                        ),
                                    ],
                                  ),
                                );
                              }(),
                          ],
                        ),
                      ),
                    ),
                    if (people.length > _shown)
                      Padding(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: AppButton(
                          label:
                              'Show ${people.length - _shown > 25 ? 25 : people.length - _shown} more',
                          variant: AppButtonVariant.secondary,
                          onPressed: () => setState(() => _shown += 25),
                        ),
                      ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(
                        AppSpacing.md,
                        0,
                        AppSpacing.md,
                        AppSpacing.md,
                      ),
                      child: Text(
                        'Select a name for that person’s day-by-day list. Late counts as present; half day counts 0.5.',
                        style: AppTypography.helper,
                      ),
                    ),
                  ],
                ),
              );

        final branchName = _branch == null
            ? (scope.branches.length == 1
                  ? scope.branches.single.name
                  : 'All branches')
            : scope.branches.firstWhere((b) => b.id == _branch).name;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AttendanceHeader(
              title: DateFormat('MMMM y').format(month),
              subtitle:
                  '$branchName · ${_department ?? 'All departments'} · ${people.length} employees${_monthsBack == 0 ? ' · up to ${DateFormat('d MMM').format(today)}' : ''}',
              actions: [
                SizedBox(
                  width: 170,
                  child: DashboardSelect<int>(
                    label: 'Month',
                    value: _monthsBack,
                    options: [
                      for (var i = 0; i < 3; i++)
                        (
                          i,
                          DateFormat(
                            'MMMM y',
                          ).format(DateTime(today.year, today.month - i)),
                        ),
                    ],
                    onChanged: (v) => setState(() => _monthsBack = v ?? 0),
                  ),
                ),
                if (scope.branches.length > 1)
                  SizedBox(
                    width: 160,
                    child: DashboardSelect<String?>(
                      label: 'Branch',
                      value: _branch,
                      options: [
                        (null, 'All branches'),
                        for (final b in scope.branches) (b.id, b.name),
                      ],
                      onChanged: (v) => setState(() => _branch = v),
                    ),
                  ),
                SizedBox(
                  width: 170,
                  child: DashboardSelect<String?>(
                    label: 'Department',
                    value: _department,
                    options: [
                      (null, 'All departments'),
                      for (final d in departments) (d, d),
                    ],
                    onChanged: (v) => setState(() => _department = v),
                  ),
                ),
                SegmentToggle<bool>(
                  label: 'View',
                  value: _grid,
                  options: const [(true, 'Team grid'), (false, 'Day list')],
                  onChanged: (v) => setState(() => _grid = v),
                ),
                if (canExport)
                  AppButton(
                    label: 'Export',
                    variant: AppButtonVariant.secondary,
                    onPressed: people.isEmpty ? null : export,
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            legend,
            const SizedBox(height: AppSpacing.md),
            content,
          ],
        );
      },
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.status, required this.size});

  final DayStatus status;
  final double size;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, border) = cellStyle(status);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        border: border,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        status.code,
        style: AppTypography.helper.copyWith(
          color: fg,
          fontWeight: FontWeight.w600,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _DayList extends StatelessWidget {
  const _DayList({
    required this.book,
    required this.person,
    required this.people,
    required this.days,
    required this.totals,
    required this.canCorrect,
    required this.onPerson,
  });

  final AttendanceBook book;
  final Employee person;
  final List<Employee> people;
  final List<DayRecord> days;
  final ({double p, int l, int a, int lv}) totals;
  final bool canCorrect;
  final ValueChanged<String?> onPerson;

  @override
  Widget build(BuildContext context) {
    final p = totals.p == totals.p.roundToDouble()
        ? '${totals.p.toInt()}'
        : totals.p.toStringAsFixed(1);
    return AppCard(
      header: CardHeader(
        title: person.fullName,
        subtitle:
            'Present $p · Late ${totals.l} · Absent ${totals.a} · Leave ${totals.lv}',
        trailing: SizedBox(
          width: 220,
          child: DashboardSelect<String?>(
            label: 'Employee',
            value: person.id,
            options: [for (final e in people) (e.id, e.fullName)],
            onChanged: onPerson,
          ),
        ),
      ),
      child: Column(
        children: [
          for (final d in days)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 110,
                    child: Text(
                      DateFormat('EEE d MMM').format(d.date),
                      style: AppTypography.small,
                    ),
                  ),
                  DayStatusBadge(d.status),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      d.workedMinutes == 0
                          ? ''
                          : formatMinutes(d.workedMinutes),
                      style: AppTypography.code,
                    ),
                  ),
                  if (d.status == DayStatus.missingPunch && canCorrect)
                    TextLink(
                      'Correct',
                      onTap: () => context.go(
                        AppRoutes.correctAttendance(d.employee.id, d.date),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
