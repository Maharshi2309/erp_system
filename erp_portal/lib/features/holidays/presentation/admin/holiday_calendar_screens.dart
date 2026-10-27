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
import '../../../../core/widgets/app_data_table.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../attendance/presentation/admin/attendance_section.dart';
import '../../../dashboard/presentation/dashboard_widgets.dart';
import '../../../employees/data/spreadsheet.dart';
import '../../../leave/presentation/leave_widgets.dart';
import '../../../organization/domain/branch.dart';
import '../../domain/company_holiday.dart';
import '../../domain/holiday_import.dart';
import '../holiday_widgets.dart';
import 'holiday_section.dart';

enum _View { month, year, list }

/// A tag like "Festival" or "Optional holiday".
class HolidayTag extends StatelessWidget {
  const HolidayTag({super.key, required this.holiday});

  final CompanyHoliday holiday;

  @override
  Widget build(BuildContext context) {
    final look = HolidayLook.of(holiday);
    final (bg, fg) = switch (look) {
      HolidayLook.org => (AppColors.primarySoft, AppColors.primaryHover),
      HolidayLook.branch => (const Color(0xFFFBEDE6), const Color(0xFF8A3A12)),
      HolidayLook.optional => (AppColors.neutralSoft, const Color(0xFF344054)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        holiday.optional ? 'Optional' : categoryLabel(holiday.category),
        style: AppTypography.helper.copyWith(
          color: fg,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

/// Board S62 — month, year and list views of the holiday calendar.
class HolidayCalendarScreen extends ConsumerStatefulWidget {
  const HolidayCalendarScreen({super.key});

  @override
  ConsumerState<HolidayCalendarScreen> createState() =>
      _HolidayCalendarScreenState();
}

class _HolidayCalendarScreenState extends ConsumerState<HolidayCalendarScreen> {
  int _offset = 0;
  String? _branch;
  _View _view = _View.month;

  @override
  Widget build(BuildContext context) => HolidaySection(
    current: AppRoutes.holidays,
    body: (context, scope) {
      final today = scope.today;
      final month = DateTime(today.year, today.month + _offset);
      final year = month.year;
      final branch = scope.branches.where((b) => b.id == _branch).firstOrNull;
      final inYear = [
        for (final h in scope.visible)
          if (h.date.year == year && (branch == null || h.appliesTo(branch.id)))
            h,
      ];
      final org = inYear.where((h) => h.orgWide && !h.optional).length;
      final specific = inYear.where((h) => !h.orgWide && !h.optional).length;
      final optional = inYear.where((h) => h.optional).length;

      List<CompanyHoliday> on(DateTime d) => [
        for (final h in inYear)
          if (h.covers(d)) h,
      ];
      bool off(DateTime d) => branch != null
          ? !branch.hours[d.weekday - 1].open
          : scope.branches.isNotEmpty &&
                scope.branches.every((b) => !b.hours[d.weekday - 1].open);
      final offDays = [
        for (var i = 0; i < 7; i++)
          if (branch != null
              ? !branch.hours[i].open
              : scope.branches.isNotEmpty &&
                    scope.branches.every((b) => !b.hours[i].open))
            weekdayShort[i],
      ];

      CalendarDay dayOf(DateTime d) {
        final list = on(d);
        // Holidays from the branch's own setup list (board S21).
        final fromSetup = branch == null || list.isNotEmpty
            ? null
            : scope.calendar.holidayFor(branch, d, includeOptional: true);
        final isToday = d == today;
        final events = [
          for (final h in list)
            (
              '${h.name}${branch == null && !h.orgWide && !h.optional ? ' · ${h.branchIds.map(scope.branchName).join(', ')}' : ''}',
              HolidayLook.of(h),
            ),
          if (fromSetup != null) (fromSetup.name, HolidayLook.branch),
        ];
        return CalendarDay(
          background: off(d) ? AppColors.surfaceMuted : AppColors.surface,
          foreground: isToday
              ? AppColors.primary
              : (off(d) ? AppColors.textMuted : AppColors.textPrimary),
          border: isToday
              ? Border.all(color: AppColors.primary, width: 2)
              : null,
          bold: isToday,
          events: events,
          semantics: [
            DateFormat('d MMMM').format(d),
            if (off(d)) 'weekly off',
            for (final e in events) e.$1,
            if (isToday) 'today',
          ].join(', '),
        );
      }

      void open(CompanyHoliday h) => context.go(AppRoutes.holidayEdit(h.id));

      Widget row(CompanyHoliday h) => Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.divider)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 150,
              child: Text(holidayDates(h), style: AppTypography.code),
            ),
            Expanded(
              child: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(h.name, style: AppTypography.bodyStrong),
                  HolidayTag(holiday: h),
                  Text(
                    holidayScope(h, scope.allBranches),
                    style: AppTypography.helper,
                  ),
                ],
              ),
            ),
            if (scope.canEdit)
              TextButton(
                onPressed: () => open(h),
                child: Text(
                  h.endDate.isBefore(today) ? 'View' : 'Edit',
                  semanticsLabel:
                      '${h.endDate.isBefore(today) ? 'View' : 'Edit'} ${h.name}',
                ),
              ),
          ],
        ),
      );

      final monthList = [
        for (final h in inYear)
          if (!h.endDate.isBefore(month) &&
              !h.date.isAfter(DateTime(month.year, month.month + 1, 0)))
            h,
      ];

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      'Holiday calendar $year',
                      style: AppTypography.pageTitle,
                    ),
                  ),
                  Text(
                    '${inYear.length} holidays · $org organization-wide · $specific branch-specific${optional == 0 ? '' : ' · $optional optional'}',
                    style: AppTypography.small,
                  ),
                ],
              ),
              if (scope.canEdit)
                Wrap(
                  spacing: AppSpacing.sm,
                  children: [
                    AppButton(
                      label: 'Import / export',
                      variant: AppButtonVariant.secondary,
                      onPressed: () => context.go(AppRoutes.holidayImport),
                    ),
                    AppButton(
                      label: 'Add holiday',
                      icon: Icons.add,
                      onPressed: () => context.go(AppRoutes.newHoliday),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.sm,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: _view == _View.month
                              ? 'Previous month'
                              : 'Previous year',
                          onPressed: () => setState(
                            () => _offset -= _view == _View.month ? 1 : 12,
                          ),
                          icon: const Icon(Icons.chevron_left),
                        ),
                        SizedBox(
                          width: 150,
                          child: Semantics(
                            header: true,
                            liveRegion: true,
                            child: Text(
                              _view == _View.month
                                  ? DateFormat('MMMM y').format(month)
                                  : '$year',
                              textAlign: TextAlign.center,
                              style: AppTypography.sectionTitle,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: _view == _View.month
                              ? 'Next month'
                              : 'Next year',
                          onPressed: () => setState(
                            () => _offset += _view == _View.month ? 1 : 12,
                          ),
                          icon: const Icon(Icons.chevron_right),
                        ),
                      ],
                    ),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (scope.branches.length > 1)
                          SizedBox(
                            width: 180,
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
                        SegmentToggle<_View>(
                          label: 'View',
                          options: const [
                            (_View.month, 'Month'),
                            (_View.year, 'Year'),
                            (_View.list, 'List'),
                          ],
                          value: _view,
                          onChanged: (v) => setState(() => _view = v),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.md,
                  runSpacing: 4,
                  children: [
                    const LegendSwatch(
                      label: 'Organization-wide',
                      color: AppColors.primary,
                    ),
                    LegendSwatch(
                      label: 'Branch-specific',
                      border: HolidayLook.branch.border,
                    ),
                    LegendSwatch(
                      label: 'Optional / floating',
                      striped: true,
                      border: HolidayLook.optional.border,
                    ),
                    if (offDays.isNotEmpty)
                      LegendSwatch(
                        label: 'Weekly off (${offDays.join(', ')})',
                        color: AppColors.surfaceMuted,
                        border: Border.all(color: AppColors.divider),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                switch (_view) {
                  _View.month => MonthCalendar(
                    month: month,
                    tall: true,
                    dayOf: dayOf,
                    onTap: scope.canEdit
                        ? (d) {
                            final h = on(d).firstOrNull;
                            if (h != null) open(h);
                          }
                        : null,
                  ),
                  _View.year => Column(
                    children: [
                      for (var m = 1; m <= 12; m++)
                        () {
                          final items = [
                            for (final h in inYear)
                              if (h.date.month == m)
                                '${DateFormat('d MMM').format(h.date)} ${h.name}${h.optional ? ' (optional)' : (h.orgWide ? '' : ' (${h.branchIds.map(scope.branchName).join(', ')})')}',
                          ];
                          return Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: const BoxDecoration(
                              border: Border(
                                bottom: BorderSide(color: AppColors.divider),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 110,
                                  child: Text(
                                    DateFormat(
                                      'MMMM',
                                    ).format(DateTime(year, m)),
                                    style: AppTypography.bodyStrong,
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    items.isEmpty ? '—' : items.join(' · '),
                                    style: AppTypography.small.copyWith(
                                      color: items.isEmpty
                                          ? AppColors.textMuted
                                          : AppColors.textPrimary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }(),
                    ],
                  ),
                  _View.list => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (inYear.isEmpty)
                        const Text('No holidays.', style: AppTypography.small),
                      for (final h in inYear) row(h),
                    ],
                  ),
                },
              ],
            ),
          ),
          if (_view == _View.month) ...[
            const SizedBox(height: AppSpacing.lg),
            AppCard(
              header: CardHeader(
                title: 'In ${DateFormat('MMMM').format(month)}',
              ),
              child: monthList.isEmpty
                  ? const Text(
                      'No holidays this month.',
                      style: AppTypography.small,
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [for (final h in monthList) row(h)],
                    ),
            ),
          ],
        ],
      );
    },
  );
}

enum _Scope { all, org, branch, optional }

/// Board S63 — the holiday list with search, filters and export.
class HolidayListScreen extends ConsumerStatefulWidget {
  const HolidayListScreen({super.key});

  @override
  ConsumerState<HolidayListScreen> createState() => _HolidayListScreenState();
}

class _HolidayListScreenState extends ConsumerState<HolidayListScreen> {
  String _search = '';
  int? _year;
  _Scope _scope = _Scope.all;

  @override
  Widget build(BuildContext context) => HolidaySection(
    current: AppRoutes.holidayList,
    body: (context, scope) {
      final year = _year ?? scope.today.year;
      final q = _search.trim().toLowerCase();
      final rows = [
        for (final h in scope.visible)
          if (h.date.year == year &&
              (q.isEmpty || h.name.toLowerCase().contains(q)) &&
              switch (_scope) {
                _Scope.all => true,
                _Scope.org => h.orgWide && !h.optional,
                _Scope.branch => !h.orgWide && !h.optional,
                _Scope.optional => h.optional,
              })
            h,
      ];
      // Holidays kept on a branch's own list from setup (board S21).
      final fromSetup = <(HolidayItem, List<Branch>)>[];
      if (_scope == _Scope.all || _scope == _Scope.branch) {
        for (final b in scope.branches) {
          for (final item in b.holidays?.items ?? const <HolidayItem>[]) {
            if (!item.observed ||
                item.date.year != year ||
                (q.isNotEmpty && !item.name.toLowerCase().contains(q)) ||
                scope.holidays.any(
                  (h) => h.covers(item.date) && h.appliesTo(b.id),
                )) {
              continue;
            }
            final same = fromSetup.indexWhere(
              (x) => x.$1.name == item.name && x.$1.date == item.date,
            );
            if (same >= 0) {
              fromSetup[same] = (item, [...fromSetup[same].$2, b]);
            } else {
              fromSetup.add((item, [b]));
            }
          }
        }
        fromSetup.sort((a, b) => a.$1.date.compareTo(b.$1.date));
      }

      void export() {
        startDownload(
          context,
          ref,
          'holidays_$year.xlsx',
          buildXlsx('Holidays $year', [
            holidayTemplateHeaders,
            for (final h in rows)
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
          ]),
          mimeType: xlsxMimeType,
          done: '${rows.length} holidays exported',
        );
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            children: [
              Semantics(
                header: true,
                child: const Text(
                  'Holiday list',
                  style: AppTypography.pageTitle,
                ),
              ),
              if (scope.canEdit)
                AppButton(
                  label: 'Add holiday',
                  icon: Icons.add,
                  onPressed: () => context.go(AppRoutes.newHoliday),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 240,
                child: SearchBox(
                  label: 'Search holidays',
                  hint: 'Holiday name',
                  onChanged: (v) => setState(() => _search = v),
                ),
              ),
              SizedBox(
                width: 120,
                child: DashboardSelect<int>(
                  label: 'Year',
                  value: year,
                  options: [
                    for (
                      var y = scope.today.year;
                      y <= scope.today.year + 1;
                      y++
                    )
                      (y, '$y'),
                  ],
                  onChanged: (v) => setState(() => _year = v),
                ),
              ),
              SizedBox(
                width: 200,
                child: DashboardSelect<_Scope>(
                  label: 'Scope',
                  value: _scope,
                  options: const [
                    (_Scope.all, 'All scopes'),
                    (_Scope.org, 'Organization-wide'),
                    (_Scope.branch, 'Branch-specific'),
                    (_Scope.optional, 'Optional'),
                  ],
                  onChanged: (v) => setState(() => _scope = v ?? _Scope.all),
                ),
              ),
              if (scope.canExport)
                AppButton(
                  label: 'Export',
                  icon: Icons.download_outlined,
                  variant: AppButtonVariant.secondary,
                  onPressed: rows.isEmpty ? null : export,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (rows.isEmpty && fromSetup.isEmpty)
            const AppCard(
              child: EmptyState(
                icon: Icons.event_busy_outlined,
                title: 'No holidays',
                message: 'Nothing matches these filters.',
              ),
            )
          else
            AppDataTable(
              minWidth: 900,
              columns: const [
                DataColumn(label: Text('Date ↑')),
                DataColumn(label: Text('Holiday')),
                DataColumn(label: Text('Category')),
                DataColumn(label: Text('Applies to')),
                DataColumn(label: Text('Status')),
                DataColumn(label: Text('Actions')),
              ],
              rows: [
                for (final h in rows)
                  () {
                    final status = scope.statusOf(h);
                    final past = status == 'Past';
                    return DataRow(
                      cells: [
                        DataCell(
                          Text(holidayDates(h), style: AppTypography.code),
                        ),
                        DataCell(Text(h.name, style: AppTypography.bodyStrong)),
                        DataCell(HolidayTag(holiday: h)),
                        DataCell(
                          Text(
                            holidayScope(h, scope.allBranches),
                            style: AppTypography.small,
                          ),
                        ),
                        DataCell(
                          Text(
                            status,
                            style: AppTypography.small.copyWith(
                              color: past
                                  ? AppColors.textMuted
                                  : (status.contains('weekly')
                                        ? AppColors.warningText
                                        : AppColors.successText),
                            ),
                          ),
                        ),
                        DataCell(
                          scope.canEdit
                              ? TextButton(
                                  onPressed: () =>
                                      context.go(AppRoutes.holidayEdit(h.id)),
                                  child: Text(
                                    past ? 'View' : 'Edit',
                                    semanticsLabel:
                                        '${past ? 'View' : 'Edit'} ${h.name}',
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    );
                  }(),
                for (final (item, bs) in fromSetup)
                  DataRow(
                    cells: [
                      DataCell(
                        Text(
                          DateFormat('EEE d MMM').format(item.date),
                          style: AppTypography.code,
                        ),
                      ),
                      DataCell(
                        Text(item.name, style: AppTypography.bodyStrong),
                      ),
                      DataCell(
                        Text(
                          categoryLabel(item.category),
                          style: AppTypography.small,
                        ),
                      ),
                      DataCell(
                        Text(
                          '${bs.map((b) => b.name).join(', ')} · branch setup',
                          style: AppTypography.small,
                        ),
                      ),
                      DataCell(
                        Text(
                          item.date.isBefore(scope.today) ? 'Past' : 'Upcoming',
                          style: AppTypography.small,
                        ),
                      ),
                      DataCell(
                        scope.session.permissions.can(
                              PermissionModule.organization,
                              PermissionAction.edit,
                            )
                            ? TextButton(
                                onPressed: () => context.go(
                                  '${AppRoutes.branchSetup(bs.first.id)}?step=holidays',
                                ),
                                child: const Text('Branch setup'),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
              ],
              footer: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Text(
                  '${rows.length} holidays in $year${fromSetup.isEmpty ? '' : ' + ${fromSetup.length} from branch setup lists'} · past holidays can’t be edited because attendance already used them',
                  style: AppTypography.helper,
                ),
              ),
            ),
        ],
      );
    },
  );
}
