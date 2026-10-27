import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../app/router/route_names.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/file_download.dart';
import '../../../../core/utils/image_picking.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_data_table.dart';
import '../../../../core/widgets/app_date_field.dart';
import '../../../../core/widgets/app_dropdown_field.dart';
import '../../../../core/widgets/app_overlays.dart';
import '../../../../core/widgets/selection_controls.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../dashboard/presentation/dashboard_widgets.dart';
import '../../../employees/data/spreadsheet.dart';
import '../../../employees/domain/employee.dart';
import '../../../employees/domain/employee_import.dart';
import '../../../employees/domain/employee_rules.dart';
import '../../../organization/domain/branch.dart';
import '../../domain/holiday_import.dart';
import '../../domain/work_calendar.dart';
import '../calendar_providers.dart';
import '../holiday_widgets.dart';
import 'holiday_section.dart';

/// Board S65 — import holidays from a spreadsheet and export a year.
class HolidayImportScreen extends ConsumerStatefulWidget {
  const HolidayImportScreen({super.key});

  @override
  ConsumerState<HolidayImportScreen> createState() =>
      _HolidayImportScreenState();
}

class _HolidayImportScreenState extends ConsumerState<HolidayImportScreen> {
  String? _fileName;
  List<HolidayRow>? _rows;
  String? _problem;
  bool _busy = false;
  int? _year;
  String? _branch;
  bool _csv = false;

  Future<void> _pick(HolidayScope scope) async {
    final PickedImage? chosen;
    try {
      chosen = await ref.read(spreadsheetPickingProvider).pickSpreadsheet();
    } on Failure catch (f) {
      if (mounted) {
        showAppToast(context, f.message, icon: Icons.error_outline);
      }
      return;
    }
    final picked = chosen;
    if (picked == null || !mounted) return;
    try {
      final table = readSpreadsheet(picked.name, picked.bytes);
      setState(() {
        _fileName = picked.name;
        _problem = null;
        _rows = checkHolidayRows(
          [table.headers, ...table.rows]
              .skipWhile(
                (r) => r.isNotEmpty && r.first.trim().toLowerCase() == 'date',
              )
              .toList(),
          existing: scope.holidays,
          branches: scope.allBranches,
          today: scope.today,
        );
      });
    } on ImportFileProblem catch (p) {
      setState(() {
        _fileName = picked.name;
        _rows = null;
        // The reader is shared with the employee import.
        _problem = '${p.title}. ${p.detail}'
            .replaceAll('employees', 'holidays')
            .replaceAll('employee', 'holiday')
            .replaceAll('Employee ID, First name', 'Date, Holiday');
      });
    }
  }

  Future<void> _add(List<HolidayRow> ready) async {
    setState(() => _busy = true);
    try {
      final saved = await ref.read(companyHolidaysProvider.notifier).import([
        for (final r in ready) r.holiday!,
      ]);
      if (!mounted) return;
      showAppToast(context, '${saved.length} holidays added');
      setState(() {
        _rows = null;
        _fileName = null;
      });
    } on Failure catch (f) {
      if (mounted) setState(() => _problem = f.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => HolidaySection(
    current: AppRoutes.holidayImport,
    body: (context, scope) {
      final rows = _rows;
      final ready = [
        for (final r in rows ?? const <HolidayRow>[])
          if (r.status == HolidayRowStatus.ready) r,
      ];
      final dupes =
          rows?.where((r) => r.status == HolidayRowStatus.duplicate).length ??
          0;
      final invalid =
          rows?.where((r) => r.status == HolidayRowStatus.invalid).length ?? 0;
      final year = _year ?? scope.today.year;
      final toExport = [
        for (final h in scope.visible)
          if (h.date.year == year && (_branch == null || h.appliesTo(_branch)))
            h,
      ];

      void export() {
        final table = [
          holidayTemplateHeaders,
          for (final h in toExport)
            for (final d in h.days)
              [
                DateFormat('dd/MM/yyyy').format(d),
                h.name,
                h.optional
                    ? 'Optional'
                    : (h.orgWide
                          ? 'All branches'
                          : h.branchIds.map(scope.branchName).join(', ')),
                categoryLabel(h.category),
              ],
        ];
        final name =
            'holidays_$year${_branch == null ? '' : '_${scope.branchName(_branch!).toLowerCase().replaceAll(' ', '_')}'}';
        if (_csv) {
          startDownload(
            context,
            ref,
            '$name.csv',
            csvBytes(buildCsv(table)),
            mimeType: csvMimeType,
            done: '${toExport.length} holidays exported',
          );
        } else {
          startDownload(
            context,
            ref,
            '$name.xlsx',
            buildXlsx('Holidays $year', table),
            mimeType: xlsxMimeType,
            done: '${toExport.length} holidays exported',
          );
        }
      }

      void template() {
        startDownload(
          context,
          ref,
          'holiday_import_template.xlsx',
          buildXlsx('Holidays', [
            holidayTemplateHeaders,
            [
              '14/01/${scope.today.year + 1}',
              'Uttarayan',
              'All branches',
              'Festival',
            ],
            [
              '28/08/${scope.today.year + 1}',
              'Raksha Bandhan',
              'Surat',
              'Festival',
            ],
            [
              '25/12/${scope.today.year + 1}',
              'Christmas',
              'Optional',
              'Festival',
            ],
          ]),
          mimeType: xlsxMimeType,
        );
      }

      final importCard = AppCard(
        header: CardHeader(
          title: _fileName == null ? 'Import' : 'Import · $_fileName',
          subtitle: rows == null
              ? 'Columns: Date (DD/MM/YYYY), Holiday, Applies to (All branches, branch names or Optional), Category'
              : '${rows.length} rows checked · nothing saved yet',
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_problem != null)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: Text(
                  _problem!,
                  style: AppTypography.small.copyWith(color: AppColors.danger),
                ),
              ),
            if (rows != null) ...[
              Semantics(
                liveRegion: true,
                child: Text(
                  '✓ ${ready.length} ready · $dupes ${dupes == 1 ? 'duplicate' : 'duplicates'} · $invalid invalid',
                  style: AppTypography.bodyStrong,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              AppDataTable(
                minWidth: 640,
                columns: const [
                  DataColumn(label: Text('Row'), numeric: true),
                  DataColumn(label: Text('Date')),
                  DataColumn(label: Text('Holiday')),
                  DataColumn(label: Text('Scope')),
                  DataColumn(label: Text('Result')),
                ],
                rows: [
                  for (final r in rows)
                    DataRow(
                      cells: [
                        DataCell(Text('${r.row}', style: AppTypography.code)),
                        DataCell(Text(r.dateText, style: AppTypography.code)),
                        DataCell(Text(r.name)),
                        DataCell(Text(r.scopeText, style: AppTypography.small)),
                        DataCell(
                          Wrap(
                            spacing: AppSpacing.sm,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              StatusBadge(
                                label: switch (r.status) {
                                  HolidayRowStatus.ready => 'Ready',
                                  HolidayRowStatus.duplicate => 'Duplicate',
                                  HolidayRowStatus.invalid => 'Invalid',
                                },
                                tone: switch (r.status) {
                                  HolidayRowStatus.ready => StatusTone.success,
                                  HolidayRowStatus.duplicate => StatusTone.info,
                                  HolidayRowStatus.invalid => StatusTone.danger,
                                },
                              ),
                              if (r.note.isNotEmpty)
                                Text(r.note, style: AppTypography.helper),
                            ],
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                'Duplicates and invalid rows will be skipped.',
                style: AppTypography.helper,
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            Wrap(
              alignment: WrapAlignment.end,
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                AppButton(
                  label: rows == null ? 'Choose file' : 'Choose another file',
                  icon: Icons.upload_file_outlined,
                  variant: rows == null
                      ? AppButtonVariant.primary
                      : AppButtonVariant.secondary,
                  onPressed: _busy ? null : () => _pick(scope),
                ),
                if (rows != null)
                  AppButton(
                    label:
                        'Add ${ready.length} ${ready.length == 1 ? 'holiday' : 'holidays'}',
                    busy: _busy,
                    busyLabel: 'Adding…',
                    onPressed: ready.isEmpty ? null : () => _add(ready),
                  ),
              ],
            ),
          ],
        ),
      );

      final exportCard = AppCard(
        header: const CardHeader(title: 'Export'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DashboardSelect<int>(
              label: 'Year',
              value: year,
              options: [
                for (
                  var y = scope.today.year - 1;
                  y <= scope.today.year + 1;
                  y++
                )
                  (y, '$y'),
              ],
              onChanged: (v) => setState(() => _year = v),
            ),
            const SizedBox(height: AppSpacing.sm),
            DashboardSelect<String?>(
              label: 'Scope',
              value: _branch,
              options: [
                (null, 'All branches'),
                for (final b in scope.branches) (b.id, b.name),
              ],
              onChanged: (v) => setState(() => _branch = v),
            ),
            const SizedBox(height: AppSpacing.md),
            ChoiceChips<bool>(
              options: const [(false, 'XLSX'), (true, 'CSV')],
              selected: _csv,
              onSelected: (v) => setState(() => _csv = v),
            ),
            const SizedBox(height: AppSpacing.md),
            AppButton(
              label:
                  'Download ${toExport.length} ${toExport.length == 1 ? 'holiday' : 'holidays'}',
              icon: Icons.download_outlined,
              onPressed: toExport.isEmpty ? null : export,
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              onPressed: template,
              child: const Text('Download blank import template'),
            ),
          ],
        ),
      );

      return LayoutBuilder(
        builder: (context, c) => c.maxWidth >= 1000
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: importCard),
                  const SizedBox(width: AppSpacing.lg),
                  SizedBox(width: 320, child: exportCard),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  importCard,
                  const SizedBox(height: AppSpacing.lg),
                  exportCard,
                ],
              ),
      );
    },
  );
}

/// UTF-8 bytes of a CSV, with a BOM so Excel reads Gujarati names.
Uint8List csvBytes(String text) =>
    Uint8List.fromList(utf8.encode('\uFEFF$text'));

/// Board S66 — dated schedule assignments, most specific wins.
class SchedulesScreen extends ConsumerStatefulWidget {
  const SchedulesScreen({super.key});

  @override
  ConsumerState<SchedulesScreen> createState() => _SchedulesScreenState();
}

class _SchedulesScreenState extends ConsumerState<SchedulesScreen> {
  ScheduleLevel _level = ScheduleLevel.group;
  String? _target;
  String? _shift;
  int? _weeklyOff;
  DateTime? _from;
  bool _busy = false;
  String? _error;

  @override
  Widget build(BuildContext context) => HolidaySection(
    current: AppRoutes.schedules,
    body: (context, scope) {
      final assignments =
          ref.watch(scheduleAssignmentsProvider).value ??
          const <ScheduleAssignment>[];
      final people = [
        for (final e in scope.employees)
          if (e.status.isEmployed && scope.session.coversBranch(e.branchId)) e,
      ];
      final groups = [
        for (final a in assignments)
          if (a.level == ScheduleLevel.group) a,
      ];
      final canEdit = scope.canEdit;

      // Rows: dated assignments plus each branch's own hours.
      String offText(int? d, Branch? b) => d != null
          ? weekdayLong[d]
          : (b == null
                ? 'Branch closed days'
                : [
                    for (var i = 0; i < 7; i++)
                      if (!b.hours[i].open) weekdayLong[i],
                  ].join(', '));
      final rows = <(String, String, String, String, String, int, bool)>[
        for (final b in scope.branches)
          (
            b.name,
            'Branch',
            shiftsFor(b).map(shiftLabel).join(' · '),
            offText(null, b),
            b.openedOn == null
                ? 'From setup'
                : 'Since ${DateFormat('d MMM y').format(b.openedOn!)}',
            people.where((e) => e.branchId == b.id).length,
            false,
          ),
        for (final a in assignments)
          (
            a.name,
            a.level.label,
            a.shift ?? 'Keeps current shift',
            offText(
              a.weeklyOff,
              scope.allBranches.where((b) => b.id == a.branchId).firstOrNull,
            ),
            a.effectiveFrom.isAfter(scope.today)
                ? 'From ${DateFormat('d MMM y').format(a.effectiveFrom)} · scheduled'
                : 'Since ${DateFormat('d MMM y').format(a.effectiveFrom)}',
            people.where(a.appliesTo).length,
            a.effectiveFrom.isAfter(scope.today),
          ),
      ];

      // The new assignment being drafted.
      final targets = <(String, String)>[
        if (_level == ScheduleLevel.group)
          for (final g in groups) (g.id, g.name),
        if (_level == ScheduleLevel.branch)
          for (final b in scope.branches) (b.id, b.name),
        if (_level == ScheduleLevel.organization)
          ('org', 'Organization default'),
        if (_level == ScheduleLevel.employee)
          for (final e
              in people..sort((a, b) => a.fullName.compareTo(b.fullName)))
            (e.id, '${e.fullName} · ${e.code}'),
      ];
      final target = targets.any((t) => t.$1 == _target)
          ? _target
          : targets.firstOrNull?.$1;
      final group = groups.where((g) => g.id == target).firstOrNull;
      final draft = target == null
          ? null
          : ScheduleAssignment(
              id: 'draft',
              level: _level,
              name: switch (_level) {
                ScheduleLevel.group => group?.name ?? '',
                ScheduleLevel.branch => scope.branchName(target),
                ScheduleLevel.organization => 'Organization default',
                ScheduleLevel.employee =>
                  people.where((e) => e.id == target).firstOrNull?.fullName ??
                      '',
              },
              effectiveFrom: _from ?? scope.today,
              branchId: _level == ScheduleLevel.branch
                  ? target
                  : group?.branchId,
              employeeIds: switch (_level) {
                ScheduleLevel.group => group?.employeeIds ?? const [],
                ScheduleLevel.employee => [target],
                _ => const [],
              },
              shift: _shift,
              weeklyOff: _weeklyOff,
              createdBy: scope.session.displayName,
            );
      final shiftOptions = <String>{
        for (final b in scope.branches)
          for (final s in shiftsFor(b)) s.name,
      };
      // Who actually changes, and who keeps a more specific schedule.
      final date = _from ?? scope.today;
      final before = WorkCalendar(assignments);
      final after = draft == null
          ? before
          : WorkCalendar([...assignments, draft]);
      final reached = draft == null
          ? const <Employee>[]
          : people.where(draft.appliesTo).toList();
      final moved = reached.where((e) {
        final a = before.scheduleFor(e, date);
        final b = after.scheduleFor(e, date);
        return a.shift != b.shift || a.weeklyOff != b.weeklyOff;
      }).toList();
      final kept = reached.length - moved.length;

      Future<void> submit() async {
        if (draft == null) return;
        setState(() {
          _busy = true;
          _error = null;
        });
        try {
          await ref.read(scheduleAssignmentsProvider.notifier).add(draft);
          if (!mounted || !context.mounted) return;
          showAppToast(
            context,
            '${draft.name}: change scheduled for ${DateFormat('EEE d MMM').format(draft.effectiveFrom)}',
          );
        } on Failure catch (f) {
          if (mounted) {
            setState(
              () => _error = f is ValidationFailure && f.fieldErrors.isNotEmpty
                  ? f.fieldErrors.values.first
                  : f.message,
            );
          }
        } finally {
          if (mounted) setState(() => _busy = false);
        }
      }

      final form = AppCard(
        header: const CardHeader(title: 'New assignment'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppDropdownField<ScheduleLevel>(
              label: 'Level',
              value: _level,
              options: [
                for (final l in ScheduleLevel.values)
                  AppDropdownOption(l, l.label),
              ],
              onChanged: (v) => setState(() {
                _level = v ?? _level;
                _target = null;
              }),
            ),
            const SizedBox(height: AppSpacing.md),
            AppDropdownField<String>(
              label: 'Apply to',
              value: target,
              options: [for (final t in targets) AppDropdownOption(t.$1, t.$2)],
              onChanged: (v) => setState(() => _target = v),
            ),
            const SizedBox(height: AppSpacing.md),
            AppDropdownField<String?>(
              label: 'Schedule',
              value: _shift,
              options: [
                const AppDropdownOption(null, 'Keep current shift'),
                for (final s in shiftOptions) AppDropdownOption(s, s),
              ],
              onChanged: (v) => setState(() => _shift = v),
            ),
            const SizedBox(height: AppSpacing.md),
            AppDropdownField<int?>(
              label: 'Weekly off',
              value: _weeklyOff,
              options: [
                const AppDropdownOption(null, 'Branch closed days'),
                for (var i = 0; i < 7; i++)
                  AppDropdownOption(i, weekdayLong[i]),
              ],
              onChanged: (v) => setState(() => _weeklyOff = v),
            ),
            const SizedBox(height: AppSpacing.md),
            AppDateField(
              label: 'Effective from',
              isRequired: true,
              value: _from ?? scope.today,
              firstDate: scope.today,
              lastDate: DateTime(scope.today.year + 1, 12, 31),
              errorText: _error,
              onChanged: (d) => setState(() => _from = d),
            ),
            const SizedBox(height: AppSpacing.md),
            if (draft != null)
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      moved.isEmpty
                          ? 'Nobody’s schedule changes on ${DateFormat('EEE d MMM').format(date)}.'
                          : '${moved.length} ${moved.length == 1 ? 'person moves' : 'people move'} to the new schedule from ${DateFormat('EEE d MMM').format(date)}.'
                                '${kept > 0 ? ' $kept ${kept == 1 ? 'has' : 'have'} a more specific schedule and ${kept == 1 ? 'keeps it' : 'keep theirs'}.' : ''}',
                      style: AppTypography.small.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Attendance before ${DateFormat('d MMM').format(date)} stays calculated against the old schedule.',
                      style: AppTypography.helper,
                    ),
                  ],
                ),
              ),
            const SizedBox(height: AppSpacing.md),
            AppButton(
              label: 'Schedule change',
              busy: _busy,
              busyLabel: 'Saving…',
              onPressed: draft == null || moved.isEmpty ? null : submit,
            ),
          ],
        ),
      );

      final list = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppCard(
            header: const CardHeader(
              title: 'Which schedule applies — most specific wins',
            ),
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (var i = 0; i < ScheduleLevel.values.length; i++) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: i == 0 ? AppColors.primary : AppColors.primarySoft,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text(
                      '${i + 1} · ${ScheduleLevel.values[i].label}',
                      style: AppTypography.small.copyWith(
                        color: i == 0
                            ? AppColors.surface
                            : AppColors.primaryHover,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (i < ScheduleLevel.values.length - 1)
                    const ExcludeSemantics(
                      child: Text('›', style: AppTypography.body),
                    ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppDataTable(
            minWidth: 680,
            columns: const [
              DataColumn(label: Text('Applies to')),
              DataColumn(label: Text('Schedule')),
              DataColumn(label: Text('Weekly off')),
              DataColumn(label: Text('Effective')),
              DataColumn(label: Text('People'), numeric: true),
            ],
            rows: [
              for (final (name, level, sched, off, eff, n, upcoming) in rows)
                DataRow(
                  color: upcoming
                      ? const WidgetStatePropertyAll(Color(0xFFFFFBF2))
                      : null,
                  cells: [
                    DataCell(
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name, style: AppTypography.bodyStrong),
                          Text(level, style: AppTypography.helper),
                        ],
                      ),
                    ),
                    DataCell(Text(sched, style: AppTypography.small)),
                    DataCell(Text(off, style: AppTypography.small)),
                    DataCell(
                      Text(
                        eff,
                        style: AppTypography.small.copyWith(
                          color: upcoming ? AppColors.warningText : null,
                        ),
                      ),
                    ),
                    DataCell(Text('$n', style: AppTypography.code)),
                  ],
                ),
            ],
          ),
        ],
      );

      return LayoutBuilder(
        builder: (context, c) => !canEdit
            ? list
            : (c.maxWidth >= 1100
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: list),
                        const SizedBox(width: AppSpacing.lg),
                        SizedBox(width: 360, child: form),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        list,
                        const SizedBox(height: AppSpacing.lg),
                        form,
                      ],
                    )),
      );
    },
  );
}

const weekdayLong = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];
