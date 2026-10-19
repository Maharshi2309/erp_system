import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/router/route_names.dart';
import '../../../core/errors/failure.dart';
import '../../../core/responsive/responsive_grid.dart';
import '../../../core/responsive/responsive_page.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_data_table.dart';
import '../../../core/widgets/app_date_field.dart';
import '../../../core/widgets/app_overlays.dart';
import '../../../core/widgets/kpi_card.dart';
import '../../../core/widgets/selection_controls.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../core/widgets/tab_strip.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../../dashboard/presentation/dashboard_widgets.dart';
import '../../organization/presentation/providers/organization_providers.dart';
import '../domain/reports.dart';
import 'report_providers.dart';

const _tabs = [
  ('Report center', AppRoutes.reports),
  ('Export history', AppRoutes.exportHistory),
];

Widget _frame(BuildContext context, String current, Widget child) =>
    ResponsivePage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: const Text('Reports', style: AppTypography.pageTitle),
          ),
          const Text(
            'Reports only include branches and fields your role can access.',
            style: AppTypography.small,
          ),
          const SizedBox(height: AppSpacing.sm),
          AppTabStrip(
            tabs: [for (final t in _tabs) t.$1],
            selected: _tabs.indexWhere((t) => t.$2 == current),
            onSelected: (i) => context.go(_tabs[i].$2),
          ),
          const SizedBox(height: AppSpacing.lg),
          child,
        ],
      ),
    );

const _loading = ResponsivePage(
  child: LoadingSkeleton(
    label: 'Loading reports',
    child: SkeletonList(rows: 6),
  ),
);

/// Default period: this month so far (one day for daily reports).
ReportFilter defaultFilter(ReportKind kind, DateTime today) => ReportFilter(
  kind: kind,
  from: kind.singleDay ? today : DateTime(today.year, today.month),
  to: today,
  columns: {
    for (final c in kind.columns)
      if (!c.restricted) c.key,
  },
);

/// Board S73 — catalogue, configuration and recent exports.
class ReportCenterScreen extends ConsumerStatefulWidget {
  const ReportCenterScreen({super.key});

  @override
  ConsumerState<ReportCenterScreen> createState() => _ReportCenterScreenState();
}

class _ReportCenterScreenState extends ConsumerState<ReportCenterScreen> {
  ReportFilter? _f;
  bool _csv = false;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final sources = ref.watch(reportSourcesProvider);
    if (session == null || sources == null) return _loading;
    final today = DateUtils.dateOnly(ref.watch(orgNowProvider)());
    const kinds = ReportKind.values;
    final firstOpen = kinds.firstWhere(
      (k) => reportBlock(k, session, sources.format) == null,
      orElse: () => ReportKind.holidays,
    );
    final f = _f ?? defaultFilter(firstOpen, today);
    final table = buildReport(f, sources, session);
    final exportBlock = reportBlock(
      f.kind,
      session,
      sources.format,
      export: true,
    );
    final history = ref.watch(exportHistoryProvider).value ?? const [];
    final departments = {for (final e in sources.people) e.department}.toList()
      ..sort();

    Future<void> export() async {
      setState(() => _busy = true);
      try {
        final r = await ref.read(reportServiceProvider).export(f, csv: _csv);
        if (mounted) {
          showAppToast(this.context, '${r.kind.label} exported as ${r.format}');
        }
      } on Failure catch (e) {
        if (mounted) {
          showAppToast(this.context, e.message, icon: Icons.error_outline);
        }
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }

    final catalogue = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final g in {for (final k in kinds) k.group}) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Semantics(
              header: true,
              child: Text(g, style: AppTypography.cardTitle),
            ),
          ),
          ResponsiveGrid(
            minItemWidth: 220,
            maxColumns: 2,
            children: [
              for (final k in kinds.where((k) => k.group == g))
                () {
                  final block = reportBlock(k, session, sources.format);
                  final selected = k == f.kind;
                  return Semantics(
                    button: block == null,
                    selected: selected,
                    child: InkWell(
                      onTap: block != null
                          ? null
                          : () => setState(() => _f = defaultFilter(k, today)),
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      child: Container(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(AppRadius.lg),
                          border: Border.all(
                            color: selected
                                ? AppColors.primary
                                : AppColors.border,
                            width: selected ? 2 : 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              k.label,
                              style: AppTypography.bodyStrong.copyWith(
                                color: block == null
                                    ? AppColors.textPrimary
                                    : AppColors.textMuted,
                              ),
                            ),
                            Text(k.description, style: AppTypography.helper),
                            const SizedBox(height: 4),
                            Text(
                              block ?? 'XLSX · CSV',
                              style: AppTypography.helper.copyWith(
                                color: block == null
                                    ? null
                                    : AppColors.warningText,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }(),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
        AppCard(
          padding: EdgeInsets.zero,
          header: CardHeader(
            title: 'Recent exports',
            subtitle:
                'Download links expire after ${sources.format.linkDays} days',
            trailing: TextButton(
              onPressed: () => context.go(AppRoutes.exportHistory),
              child: const Text('All exports'),
            ),
          ),
          child: history.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(AppSpacing.lg),
                  child: Text(
                    'Nothing exported yet.',
                    style: AppTypography.small,
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final r in history.take(3))
                      _ExportRow(record: r, linkDays: sources.format.linkDays),
                  ],
                ),
        ),
      ],
    );

    final columns = [
      for (final c in f.kind.columns)
        (c, columnAllowed(c, session, sources.format)),
    ];
    final configure = AppCard(
      header: CardHeader(title: f.kind.label, subtitle: 'Configure'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: AppDateField(
                  label: f.kind.singleDay ? 'Day' : 'From',
                  value: f.from,
                  firstDate: DateTime(today.year - 2),
                  lastDate: DateTime(today.year + 1, 12, 31),
                  onChanged: (d) => setState(
                    () => _f = f.copyWith(
                      from: d,
                      to: f.kind.singleDay || (d != null && f.to.isBefore(d))
                          ? d
                          : f.to,
                    ),
                  ),
                ),
              ),
              if (!f.kind.singleDay) ...[
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: AppDateField(
                    label: 'To',
                    value: f.to,
                    firstDate: f.from,
                    lastDate: DateTime(today.year + 1, 12, 31),
                    onChanged: (d) => setState(() => _f = f.copyWith(to: d)),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          DashboardSelect<String?>(
            label: 'Branch',
            value: f.branchId,
            options: [
              (
                null,
                sources.branches.length == 1
                    ? sources.branches.single.name
                    : 'All branches (${sources.branches.where((b) => b.isActive).length})',
              ),
              if (sources.branches.length > 1)
                for (final b in sources.branches)
                  if (b.isActive) (b.id, b.name),
            ],
            onChanged: (v) => setState(() => _f = f.copyWith(branchId: v)),
          ),
          const SizedBox(height: AppSpacing.sm),
          DashboardSelect<String?>(
            label: 'Department',
            value: f.department,
            options: [
              (null, 'All departments'),
              for (final d in departments) (d, d),
            ],
            onChanged: (v) => setState(() => _f = f.copyWith(department: v)),
          ),
          const SizedBox(height: AppSpacing.md),
          const Text('Columns', style: AppTypography.label),
          // Own Material so the tiles' ink shows on the card.
          Material(
            type: MaterialType.transparency,
            child: Column(
              children: [
                for (final (c, ok) in columns)
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: c.always || (ok && f.columns.contains(c.key)),
                    onChanged: c.always || !ok
                        ? null
                        : (on) => setState(
                            () => _f = f.copyWith(
                              columns:
                                  on! ? {...f.columns, c.key} : {...f.columns}
                                    ..remove(c.key),
                            ),
                          ),
                    title: Text(c.label, style: AppTypography.small),
                    subtitle: c.always
                        ? const Text(
                            'always included',
                            style: AppTypography.helper,
                          )
                        : (!ok
                              ? const Text(
                                  'not permitted for your role',
                                  style: AppTypography.helper,
                                )
                              : null),
                  ),
              ],
            ),
          ),
          const Divider(height: AppSpacing.lg),
          const Text('Preview', style: AppTypography.label),
          Text('${table.rows.length} rows', style: AppTypography.sectionTitle),
          if (table.note.isNotEmpty)
            Text(table.note, style: AppTypography.helper),
          const SizedBox(height: AppSpacing.md),
          ChoiceChips<bool>(
            options: const [(false, 'XLSX'), (true, 'CSV')],
            selected: _csv,
            onSelected: (v) => setState(() => _csv = v),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              AppButton(
                label: 'View results',
                variant: AppButtonVariant.secondary,
                onPressed: () => context.go(
                  Uri(
                    path: AppRoutes.reportResults,
                    queryParameters: f.toQuery(),
                  ).toString(),
                ),
              ),
              AppButton(
                label: 'Export',
                icon: Icons.download_outlined,
                busy: _busy,
                busyLabel: 'Exporting…',
                onPressed: exportBlock == null ? export : null,
              ),
            ],
          ),
          if (exportBlock != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(exportBlock, style: AppTypography.helper),
            ),
        ],
      ),
    );

    return _frame(
      context,
      AppRoutes.reports,
      LayoutBuilder(
        builder: (context, c) => c.maxWidth >= 1000
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: catalogue),
                  const SizedBox(width: AppSpacing.lg),
                  SizedBox(width: 380, child: configure),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  configure,
                  const SizedBox(height: AppSpacing.lg),
                  catalogue,
                ],
              ),
      ),
    );
  }
}

class _ExportRow extends ConsumerWidget {
  const _ExportRow({required this.record, required this.linkDays});

  final ExportRecord record;
  final int linkDays;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = record;
    final now = ref.watch(orgNowProvider)();
    final expired = !r.failed && r.expired(now, linkDays);
    final (label, tone) = r.failed
        ? ('Failed', StatusTone.danger)
        : (expired
              ? ('Expired', StatusTone.neutral)
              : ('Ready', StatusTone.success));
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: 10,
      ),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppSpacing.md,
        runSpacing: 4,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.kind.label, style: AppTypography.bodyStrong),
                Text(
                  '${r.filters} · ${r.requestedBy} · ${DateFormat('d MMM, HH:mm').format(r.at)}',
                  style: AppTypography.helper,
                ),
              ],
            ),
          ),
          Wrap(
            spacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              StatusBadge(label: label, tone: tone),
              if (!r.failed && !expired)
                TextButton(
                  onPressed: () => ref.read(reportServiceProvider).download(r),
                  child: Text(
                    'Download ${r.format} · ${r.size < 1024 ? '<1' : (r.size / 1024).round()} KB',
                    semanticsLabel: 'Download ${r.kind.label}',
                  ),
                )
              else if (expired)
                const Text('Run again to download', style: AppTypography.helper)
              else
                TextButton(
                  onPressed: () => context.go(AppRoutes.reports),
                  child: Text('Retry', semanticsLabel: 'Retry ${r.kind.label}'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Board S74 — the report on screen, sortable and paged.
class ReportResultsScreen extends ConsumerStatefulWidget {
  const ReportResultsScreen({super.key, required this.query});

  final Map<String, String> query;

  @override
  ConsumerState<ReportResultsScreen> createState() =>
      _ReportResultsScreenState();
}

class _ReportResultsScreenState extends ConsumerState<ReportResultsScreen> {
  int? _sort;
  bool _asc = false;
  int _page = 0;
  int _per = 10;
  bool _busy = false;

  ReportFilter? _filter(DateTime today) {
    final q = widget.query;
    final kind = ReportKind.values
        .where((k) => k.name == q['report'])
        .firstOrNull;
    if (kind == null) return null;
    DateTime? d(String? v) => v == null ? null : DateTime.tryParse(v);
    final base = defaultFilter(kind, today);
    return base.copyWith(
      from: d(q['from']) ?? base.from,
      to: d(q['to']) ?? base.to,
      branchId: q['branch'],
      department: q['dept'],
      columns: q['cols'] == null ? base.columns : q['cols']!.split(',').toSet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final sources = ref.watch(reportSourcesProvider);
    if (session == null || sources == null) return _loading;
    final now = ref.watch(orgNowProvider)();
    final f = _filter(DateUtils.dateOnly(now));
    if (f == null) {
      return const ErrorState(
        headline: '404',
        title: 'Report not found',
        message: 'Choose a report in the report center.',
      );
    }
    final block = reportBlock(f.kind, session, sources.format);
    if (block != null) {
      return ErrorState(
        headline: '403',
        title: 'You can’t run this report',
        message: block,
      );
    }
    final t = buildReport(f, sources, session);
    final rows = [...t.rows];
    if (_sort != null) {
      int cmp(List<String> a, List<String> b) {
        final x = a[_sort!], y = b[_sort!];
        final nx = double.tryParse(x.replaceAll('%', ''));
        final ny = double.tryParse(y.replaceAll('%', ''));
        final c = nx != null && ny != null ? nx.compareTo(ny) : x.compareTo(y);
        return _asc ? c : -c;
      }

      rows.sort(cmp);
    }
    final pages = (rows.length / _per).ceil();
    final page = _page.clamp(0, pages == 0 ? 0 : pages - 1);
    final slice = rows.skip(page * _per).take(_per).toList();
    final exportBlock = reportBlock(
      f.kind,
      session,
      sources.format,
      export: true,
    );

    Future<void> export(bool csv) async {
      setState(() => _busy = true);
      try {
        await ref.read(reportServiceProvider).export(f, csv: csv);
        if (mounted) {
          showAppToast(
            this.context,
            '${f.kind.label} exported as ${csv ? 'CSV' : 'XLSX'}',
          );
        }
      } on Failure catch (e) {
        if (mounted) {
          showAppToast(this.context, e.message, icon: Icons.error_outline);
        }
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }

    return ResponsivePage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => context.go(AppRoutes.reports),
              icon: const Icon(Icons.chevron_left),
              label: const Text('Reports'),
            ),
          ),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            children: [
              Semantics(
                header: true,
                child: Text(f.kind.label, style: AppTypography.pageTitle),
              ),
              if (exportBlock == null)
                Wrap(
                  spacing: AppSpacing.sm,
                  children: [
                    AppButton(
                      label: 'Export CSV',
                      variant: AppButtonVariant.secondary,
                      onPressed: _busy ? null : () => export(true),
                    ),
                    AppButton(
                      label: 'Export XLSX',
                      busy: _busy,
                      onPressed: () => export(false),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final part in f.describe(sources.branches).split(' · '))
                Chip(label: Text(part, style: AppTypography.small)),
              TextButton(
                onPressed: () => context.go(AppRoutes.reports),
                child: const Text('Change filters'),
              ),
            ],
          ),
          Text(
            'Generated ${DateFormat('d MMM y, HH:mm').format(now)} · ${t.rows.length} rows${t.note.isEmpty ? '' : ' · ${t.note}'}',
            style: AppTypography.helper,
          ),
          if (exportBlock != null)
            Text(exportBlock, style: AppTypography.helper),
          const SizedBox(height: AppSpacing.md),
          if (t.totals.isNotEmpty)
            ResponsiveGrid(
              minItemWidth: 150,
              maxColumns: 5,
              children: [
                for (final (k, v) in t.totals) KpiCard(label: k, value: v),
              ],
            ),
          const SizedBox(height: AppSpacing.md),
          if (rows.isEmpty)
            const AppCard(
              child: EmptyState(
                icon: Icons.filter_alt_off_outlined,
                title: 'No rows',
                message: 'Nothing matches these filters.',
              ),
            )
          else
            AppDataTable(
              minWidth: 160.0 * t.headers.length,
              sortColumnIndex: _sort,
              sortAscending: _asc,
              columns: [
                for (var i = 0; i < t.headers.length; i++)
                  DataColumn(
                    label: Text(t.headers[i]),
                    numeric: t.numeric.contains(i),
                    onSort: (c, asc) => setState(() {
                      _sort = c;
                      _asc = asc;
                      _page = 0;
                    }),
                  ),
              ],
              rows: [
                for (final r in slice)
                  DataRow(
                    cells: [
                      for (final v in r)
                        DataCell(
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 280),
                            child: Text(
                              v,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.small.copyWith(
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
              ],
              footer: Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: AppSpacing.md,
                  children: [
                    Text(
                      '${page * _per + 1}–${page * _per + slice.length} of ${rows.length}',
                      style: AppTypography.helper,
                    ),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: AppSpacing.sm,
                      children: [
                        SizedBox(
                          width: 110,
                          child: DashboardSelect<int>(
                            label: 'Rows',
                            value: _per,
                            options: const [(10, '10 rows'), (50, '50 rows')],
                            onChanged: (v) => setState(() {
                              _per = v ?? 10;
                              _page = 0;
                            }),
                          ),
                        ),
                        TextButton(
                          onPressed: page == 0
                              ? null
                              : () => setState(() => _page = page - 1),
                          child: const Text('Previous'),
                        ),
                        TextButton(
                          onPressed: page >= pages - 1
                              ? null
                              : () => setState(() => _page = page + 1),
                          child: const Text('Next'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Board S75 — every export the member may see.
class ExportHistoryScreen extends ConsumerStatefulWidget {
  const ExportHistoryScreen({super.key});

  @override
  ConsumerState<ExportHistoryScreen> createState() =>
      _ExportHistoryScreenState();
}

class _ExportHistoryScreenState extends ConsumerState<ExportHistoryScreen> {
  bool _mine = false;
  ReportKind? _kind;
  int _days = 30;

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final history = ref.watch(exportHistoryProvider);
    final sources = ref.watch(reportSourcesProvider);
    if (session == null || !history.hasValue || sources == null) {
      return _loading;
    }
    final now = ref.watch(orgNowProvider)();
    final rows = [
      for (final r in history.value!)
        if ((!_mine || r.requestedById == session.userId) &&
            (_kind == null || r.kind == _kind) &&
            now.difference(r.at).inDays <= _days)
          r,
    ];
    return _frame(
      context,
      AppRoutes.exportHistory,
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            children: [
              SizedBox(
                width: 220,
                child: DashboardSelect<bool>(
                  label: 'Requested by',
                  value: _mine,
                  options: const [
                    (false, 'Anyone you can see'),
                    (true, 'Only me'),
                  ],
                  onChanged: (v) => setState(() => _mine = v ?? false),
                ),
              ),
              SizedBox(
                width: 240,
                child: DashboardSelect<ReportKind?>(
                  label: 'Report type',
                  value: _kind,
                  options: [
                    (null, 'All reports'),
                    for (final k in ReportKind.values) (k, k.label),
                  ],
                  onChanged: (v) => setState(() => _kind = v),
                ),
              ),
              SizedBox(
                width: 170,
                child: DashboardSelect<int>(
                  label: 'Period',
                  value: _days,
                  options: const [
                    (7, 'Last 7 days'),
                    (30, 'Last 30 days'),
                    (90, 'Last 90 days'),
                  ],
                  onChanged: (v) => setState(() => _days = v ?? 30),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          AppCard(
            padding: EdgeInsets.zero,
            child: rows.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(AppSpacing.lg),
                    child: EmptyState(
                      icon: Icons.history,
                      title: 'No exports',
                      message: 'Nothing matches these filters.',
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final r in rows)
                        _ExportRow(
                          record: r,
                          linkDays: sources.format.linkDays,
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Downloads use the same permissions as the data. Links expire after ${sources.format.linkDays} days and every download is logged.',
            style: AppTypography.helper,
          ),
        ],
      ),
    );
  }
}
