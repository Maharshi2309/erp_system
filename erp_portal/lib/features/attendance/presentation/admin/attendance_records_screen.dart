import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/router/route_names.dart';
import '../../../../core/permissions/permissions.dart';
import '../../../../core/responsive/responsive_grid.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/file_download.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_date_field.dart';
import '../../../../core/widgets/app_overlays.dart';
import '../../../../core/widgets/kpi_card.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../dashboard/presentation/dashboard_widgets.dart';
import '../../../employees/data/spreadsheet.dart';
import '../../../employees/domain/employee.dart';
import '../../domain/attendance_book.dart';
import '../attendance_widgets.dart';
import 'attendance_overview_screen.dart' show OverviewView, periodDays;
import 'attendance_section.dart';

/// Board S53 — one day's records with a detail panel.
class AttendanceRecordsScreen extends ConsumerStatefulWidget {
  const AttendanceRecordsScreen({super.key, this.date, this.branchId});

  final DateTime? date;
  final String? branchId;

  @override
  ConsumerState<AttendanceRecordsScreen> createState() =>
      _AttendanceRecordsScreenState();
}

enum _Filter { exceptions, late, missing, all }

class _AttendanceRecordsScreenState
    extends ConsumerState<AttendanceRecordsScreen> {
  DateTime? _date;
  late String? _branch = widget.branchId;
  String? _department;
  String _search = '';
  _Filter _filter = _Filter.exceptions;
  OverviewView _view = OverviewView.daily;
  String? _selectedId;

  void _export(List<DayRecord> rows, AttendanceBook book) {
    final data = [
      [
        'Employee ID',
        'Name',
        'Branch',
        'Date',
        'In',
        'Out',
        'Worked',
        'Break (min)',
        'Status',
        'Corrected',
      ],
      for (final r in rows)
        [
          r.employee.code,
          r.employee.fullName,
          book.branchOf(r.employee)?.name ?? '',
          DateFormat('dd/MM/yyyy').format(r.date),
          r.firstIn == null ? '' : clockTime(r.firstIn!, r.zone),
          r.lastOut == null ? '' : clockTime(r.lastOut!, r.zone),
          formatMinutes(r.workedMinutes),
          '${r.breakMinutes}',
          r.status.label,
          r.corrected ? 'Yes · ${r.correctedBy}' : '',
        ],
    ];
    ref
        .read(fileDownloadsProvider)
        .save(
          'attendance_${isoDate(rows.first.date)}.xlsx',
          buildXlsx('Attendance', data),
          mimeType: xlsxMimeType,
        );
    showAppToast(context, 'Exported ${rows.length} records');
  }

  @override
  Widget build(BuildContext context) {
    return AttendanceSection(
      current: AppRoutes.attendanceRecords,
      body: (context, scope) {
        final book = scope.book;
        final date = _date ?? widget.date ?? book.today;
        final canCorrect = scope.session.permissions.can(
          PermissionModule.attendance,
          PermissionAction.correct,
        );
        final canExport = scope.session.permissions.can(
          PermissionModule.attendance,
          PermissionAction.export,
        );
        final people = [
          for (final e in scope.people)
            if ((_branch == null || e.branchId == _branch) &&
                (_department == null || e.department == _department) &&
                (_search.isEmpty ||
                    '${e.fullName} ${e.code}'.toLowerCase().contains(
                      _search.toLowerCase(),
                    )))
              e,
        ];
        final all =
            book
                .daysOn(date, people)
                .where((r) => r.status != DayStatus.none)
                .toList()
              ..sort(
                (a, b) => a.employee.fullName.compareTo(b.employee.fullName),
              );
        final counts = AttendanceBook.count(all);
        bool keep(DayRecord r) => switch (_filter) {
          _Filter.exceptions => r.status.isException,
          _Filter.late => r.lateMinutes > 0,
          _Filter.missing => r.status == DayStatus.missingPunch,
          _Filter.all => true,
        };
        final rows = all.where(keep).toList();
        final selected = all
            .where((r) => r.employee.id == _selectedId)
            .firstOrNull;
        final branchName = _branch == null
            ? (scope.branches.length == 1
                  ? scope.branches.single.name
                  : 'All branches')
            : scope.branches.where((b) => b.id == _branch).firstOrNull?.name ??
                  '';

        final header = AttendanceHeader(
          title: 'Attendance records',
          subtitle:
              '${DateFormat('EEEE, d MMMM y').format(date)} · $branchName',
          actions: [
            SegmentToggle<OverviewView>(
              label: 'View',
              value: _view,
              options: const [
                (OverviewView.daily, 'Daily'),
                (OverviewView.weekly, 'Weekly'),
                (OverviewView.monthly, 'Monthly'),
              ],
              onChanged: (v) => setState(() => _view = v),
            ),
            IconButton(
              tooltip: 'Previous day',
              onPressed: () => setState(
                () => _date = DateTime(date.year, date.month, date.day - 1),
              ),
              icon: const Icon(Icons.chevron_left),
            ),
            SizedBox(
              width: 170,
              child: AppDateField(
                label: 'Attendance date',
                value: date,
                lastDate: book.today,
                onChanged: (d) => setState(() => _date = d ?? date),
              ),
            ),
            IconButton(
              tooltip: 'Next day',
              onPressed: date.isBefore(book.today)
                  ? () => setState(
                      () =>
                          _date = DateTime(date.year, date.month, date.day + 1),
                    )
                  : null,
              icon: const Icon(Icons.chevron_right),
            ),
            if (canExport)
              AppButton(
                label: 'Export',
                variant: AppButtonVariant.secondary,
                onPressed: all.isEmpty ? null : () => _export(all, book),
              ),
          ],
        );

        final filters = Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 220,
              child: Semantics(
                label: 'Search employee',
                textField: true,
                child: TextField(
                  onChanged: (t) => setState(() => _search = t),
                  decoration: const InputDecoration(
                    hintText: 'Employee',
                    prefixIcon: Icon(Icons.search, size: 18),
                  ),
                ),
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
            for (final (f, label) in const [
              (_Filter.exceptions, 'Exceptions only'),
              (_Filter.late, 'Late arrivals'),
              (_Filter.missing, 'Missing punch'),
            ])
              FilterChip(
                label: Text(label),
                selected: _filter == f,
                onSelected: (on) =>
                    setState(() => _filter = on ? f : _Filter.all),
              ),
          ],
        );

        if (_view != OverviewView.daily) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              const SizedBox(height: AppSpacing.lg),
              filters,
              const SizedBox(height: AppSpacing.md),
              _Totals(book: book, people: people, view: _view, date: date),
            ],
          );
        }

        final list = AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (rows.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: EmptyState(
                    icon: Icons.check_circle_outline,
                    iconTone: AppColors.success,
                    title: all.isEmpty
                        ? 'No records for this day'
                        : 'No exceptions',
                    message: all.isEmpty
                        ? 'Nobody was scheduled, or the day hasn’t started.'
                        : 'Everyone shown is on time and complete.',
                  ),
                )
              else
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 760),
                    child: DataTable(
                      showCheckboxColumn: false,
                      columns: const [
                        DataColumn(label: Text('EMPLOYEE')),
                        DataColumn(label: Text('IN')),
                        DataColumn(label: Text('OUT')),
                        DataColumn(label: Text('WORKED')),
                        DataColumn(label: Text('BREAK')),
                        DataColumn(label: Text('VS EXPECTED')),
                        DataColumn(label: Text('STATUS')),
                      ],
                      rows: [
                        for (final r in rows)
                          DataRow(
                            selected: r.employee.id == _selectedId,
                            onSelectChanged: (_) =>
                                _select(context, r, canCorrect),
                            cells: [
                              DataCell(
                                Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      r.employee.fullName,
                                      style: AppTypography.bodyStrong,
                                    ),
                                    Text(
                                      '${r.employee.code} · ${r.employee.department}',
                                      style: AppTypography.helper,
                                    ),
                                  ],
                                ),
                              ),
                              DataCell(
                                _time(r.firstIn, r, late: r.lateMinutes > 0),
                              ),
                              DataCell(_time(r.lastOut, r)),
                              DataCell(
                                Text(
                                  r.workedMinutes == 0
                                      ? '—'
                                      : formatMinutes(r.workedMinutes),
                                  style: AppTypography.code,
                                ),
                              ),
                              DataCell(
                                Text(
                                  r.sessions.isEmpty
                                      ? '—'
                                      : '${r.breakMinutes}m',
                                  style: AppTypography.code,
                                ),
                              ),
                              DataCell(
                                Text(
                                  r.status == DayStatus.working
                                      ? '—'
                                      : formatDelta(
                                          r.workedMinutes,
                                          r.expectedMinutes,
                                        ),
                                  style: AppTypography.code.copyWith(
                                    color: r.workedMinutes < r.expectedMinutes
                                        ? AppColors.warning
                                        : AppColors.success,
                                  ),
                                ),
                              ),
                              DataCell(DayStatusBadge(r.status)),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: AppSpacing.md,
                  children: [
                    Text(
                      _filter == _Filter.all
                          ? '${all.length} records'
                          : '${rows.length} ${_filter == _Filter.exceptions ? 'exceptions' : 'records'} of ${all.length} records',
                      style: AppTypography.small,
                    ),
                    if (_filter != _Filter.all)
                      AppButton(
                        label: 'Show all records',
                        size: AppButtonSize.small,
                        variant: AppButtonVariant.ghost,
                        onPressed: () => setState(() => _filter = _Filter.all),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            const SizedBox(height: AppSpacing.lg),
            ResponsiveGrid(
              minItemWidth: 130,
              maxColumns: 5,
              children: [
                KpiCard(label: 'Present', value: '${counts.present}'),
                KpiCard(label: 'Late', value: '${counts.late}'),
                KpiCard(label: 'Absent', value: '${counts.absent}'),
                KpiCard(label: 'On leave', value: '${counts.onLeave}'),
                KpiCard(label: 'Incomplete', value: '${counts.missing}'),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            filters,
            const SizedBox(height: AppSpacing.md),
            LayoutBuilder(
              builder: (context, c) {
                if (selected == null || c.maxWidth < 1000) return list;
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: list),
                    const SizedBox(width: AppSpacing.lg),
                    SizedBox(
                      width: 340,
                      child: AppCard(
                        child: RecordDetail(
                          record: selected,
                          canCorrect: canCorrect,
                          onClose: () => setState(() => _selectedId = null),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        );
      },
    );
  }

  void _select(BuildContext context, DayRecord r, bool canCorrect) {
    if (MediaQuery.sizeOf(context).width >= 1000 + 248) {
      setState(() => _selectedId = r.employee.id);
      return;
    }
    showSidePanelRoute<void>(
      context,
      barrierLabel: 'Close record',
      builder: (ctx) => SidePanelFrame(
        title: r.employee.fullName,
        subtitle:
            '${DateFormat('EEE d MMM').format(r.date)} · ${r.employee.designation}',
        onClose: () => Navigator.of(ctx).pop(),
        body: RecordDetail(
          record: r,
          canCorrect: canCorrect,
          showHeader: false,
        ),
      ),
    );
  }

  Widget _time(DateTime? at, DayRecord r, {bool late = false}) => Text(
    at == null ? '—' : clockTime(at, r.zone),
    style: AppTypography.code.copyWith(
      color: at == null && r.status == DayStatus.missingPunch
          ? AppColors.danger
          : (late ? AppColors.warning : AppColors.textPrimary),
    ),
  );
}

/// The record panel: alert, timeline, worked vs expected, "Correct…".
class RecordDetail extends StatelessWidget {
  const RecordDetail({
    super.key,
    required this.record,
    required this.canCorrect,
    this.onClose,
    this.showHeader = true,
  });

  final DayRecord record;
  final bool canCorrect;
  final VoidCallback? onClose;
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    final r = record;
    final openIndex = r.sessions.indexWhere((s) => s.isOpen);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showHeader) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.employee.fullName, style: AppTypography.cardTitle),
                    Text(
                      '${DateFormat('EEE d MMM').format(r.date)} · ${r.employee.designation}',
                      style: AppTypography.helper,
                    ),
                  ],
                ),
              ),
              if (onClose != null)
                IconButton(
                  tooltip: 'Close detail',
                  onPressed: onClose,
                  icon: const Icon(Icons.close, size: 18),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        if (r.status == DayStatus.missingPunch)
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            margin: const EdgeInsets.only(bottom: AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.dangerSoft,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Text(
              r.sessions.any((s) => s.isOrphanOut)
                  ? 'There is no punch-in. Worked time excludes this session until corrected.'
                  : 'Session ${openIndex + 1} has no punch-out. Worked time excludes it until corrected.',
              style: AppTypography.small.copyWith(color: AppColors.dangerText),
            ),
          ),
        if (r.pendingCorrection case final c?)
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            margin: const EdgeInsets.only(bottom: AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Text(
              'A correction by ${c.by} is waiting for approval${c.approverNote.isEmpty ? '' : ' by ${c.approverNote}'}.',
              style: AppTypography.small.copyWith(
                color: AppColors.primaryHover,
              ),
            ),
          ),
        PunchTimeline(record: r),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: _Fact(
                'Worked (confirmed)',
                r.workedMinutes == 0 ? '—' : formatMinutes(r.workedMinutes),
              ),
            ),
            Expanded(
              child: _Fact('Expected', formatMinutes(r.expectedMinutes)),
            ),
          ],
        ),
        if (r.corrected) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Corrected by ${r.correctedBy} — “${r.correctionReason}”',
            style: AppTypography.helper.copyWith(color: AppColors.primary),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        if (canCorrect &&
            r.status != DayStatus.working &&
            r.status != DayStatus.upcoming &&
            r.status != DayStatus.notYet) ...[
          AppButton(
            label: 'Correct attendance…',
            expand: true,
            onPressed: r.pendingCorrection != null
                ? null
                : () => context.go(
                    AppRoutes.correctAttendance(r.employee.id, r.date),
                  ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        Text(
          r.timeline.isEmpty && r.status == DayStatus.absent
              ? 'Scheduled ${r.shift?.label ?? ''} · no punches.'
              : '',
          style: AppTypography.helper,
        ),
        const Text(
          'Corrections need a reason and are kept alongside the original punches in the history.',
          style: AppTypography.helper,
        ),
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: AppTypography.helper),
      Text(
        value,
        style: AppTypography.code.copyWith(color: AppColors.textPrimary),
      ),
    ],
  );
}

/// Weekly / monthly totals per employee.
class _Totals extends StatelessWidget {
  const _Totals({
    required this.book,
    required this.people,
    required this.view,
    required this.date,
  });

  final AttendanceBook book;
  final List<Employee> people;
  final OverviewView view;
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final days = [
      for (final d in periodDays(view, date))
        if (!d.isAfter(book.today)) d,
    ];
    final rows = [
      for (final e in [
        ...people,
      ]..sort((a, b) => a.fullName.compareTo(b.fullName)))
        (e, AttendanceBook.count([for (final d in days) book.day(e, d)])),
    ];
    return AppCard(
      padding: EdgeInsets.zero,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 760),
          child: DataTable(
            columns: const [
              DataColumn(label: Text('EMPLOYEE')),
              DataColumn(label: Text('PRESENT'), numeric: true),
              DataColumn(label: Text('LATE'), numeric: true),
              DataColumn(label: Text('ABSENT'), numeric: true),
              DataColumn(label: Text('MISSING'), numeric: true),
              DataColumn(label: Text('WORKED'), numeric: true),
              DataColumn(label: Text('VS EXPECTED'), numeric: true),
            ],
            rows: [
              for (final (e, c) in rows)
                DataRow(
                  cells: [
                    DataCell(Text(e.fullName, style: AppTypography.bodyStrong)),
                    DataCell(
                      Text(
                        '${c.present} / ${c.scheduled}',
                        style: AppTypography.code,
                      ),
                    ),
                    DataCell(Text('${c.late}', style: AppTypography.code)),
                    DataCell(Text('${c.absent}', style: AppTypography.code)),
                    DataCell(
                      Text(
                        '${c.missing}',
                        style: AppTypography.code.copyWith(
                          color: c.missing > 0 ? AppColors.danger : null,
                        ),
                      ),
                    ),
                    DataCell(
                      Text(
                        formatMinutes(c.workedMinutes),
                        style: AppTypography.code,
                      ),
                    ),
                    DataCell(
                      Text(
                        formatDelta(c.workedMinutes, c.expectedMinutes),
                        style: AppTypography.code,
                      ),
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
