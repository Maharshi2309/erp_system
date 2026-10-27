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
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_data_table.dart';
import '../../../core/widgets/app_dropdown_field.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/kpi_card.dart';
import '../../../core/widgets/page_header.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_badge.dart';
import '../../attendance/presentation/attendance_widgets.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../../dashboard/presentation/dashboard_widgets.dart';
import '../domain/platform_stats.dart';
import 'platform_charts.dart';
import 'platform_providers.dart';

final _n = NumberFormat.decimalPattern('en_IN');
String _num(int n) => _n.format(n);
String _date(DateTime? d) => d == null ? '—' : DateFormat('d MMM y').format(d);

StatusTone _tone(OrgStatus s) => switch (s) {
  OrgStatus.active => StatusTone.success,
  OrgStatus.settingUp => StatusTone.info,
  OrgStatus.quiet => StatusTone.warning,
};

String _ago(DateTime? at, DateTime now) {
  if (at == null) return 'Never';
  final d = now.difference(at);
  if (d.inMinutes < 60) return '${d.inMinutes.clamp(1, 59)} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  if (d.inDays == 1) return 'Yesterday';
  return '${d.inDays} days ago';
}

/// Boards S97–S98 shell: dark sidebar on desktop, dark top bar below 1024 px.
/// Says plainly that only statistics are shown (D-75).
class PlatformShell extends ConsumerWidget {
  const PlatformShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wide = MediaQuery.sizeOf(context).width >= 1024;
    void signOut() => ref.read(authControllerProvider.notifier).signOut();
    const light = TextStyle(color: AppColors.surface);
    final brand = Row(
      children: [
        const Icon(Icons.hub_outlined, color: AppColors.surface),
        const SizedBox(width: AppSpacing.sm),
        Flexible(
          child: Text(
            'Staffline Platform',
            style: AppTypography.sectionTitle.merge(light),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
    final body = Material(color: AppColors.canvas, child: child);
    if (!wide) {
      return Scaffold(
        backgroundColor: AppColors.canvas,
        appBar: AppBar(
          backgroundColor: AppColors.ink,
          foregroundColor: AppColors.surface,
          title: brand,
          actions: [
            IconButton(
              tooltip: 'Sign out',
              icon: const Icon(Icons.logout),
              onPressed: signOut,
            ),
          ],
        ),
        body: body,
      );
    }
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: Row(
        children: [
          Container(
            width: 260,
            color: AppColors.ink,
            padding: const EdgeInsets.all(AppSpacing.lg),
            // Scrolls when large text makes the sidebar taller than the window.
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      brand,
                      const SizedBox(height: AppSpacing.xl),
                      Material(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        child: ListTile(
                          dense: true,
                          leading: const Icon(
                            Icons.apartment_outlined,
                            color: AppColors.surface,
                          ),
                          title: Text(
                            'Organizations',
                            style: AppTypography.label.merge(light),
                          ),
                          onTap: () => context.go(AppRoutes.platform),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxl),
                      Text(
                        'You see statistics about organizations and their use of Staffline — never employee records or personal details.',
                        style: AppTypography.helper.copyWith(
                          color: AppColors.surface.withValues(alpha: 0.7),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        'Signed in as platform admin · 2-step verified',
                        style: AppTypography.helper.copyWith(
                          color: AppColors.surface.withValues(alpha: 0.9),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      OutlinedButton.icon(
                        onPressed: signOut,
                        icon: const Icon(Icons.logout, size: 18),
                        label: const Text('Sign out'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.surface,
                          side: BorderSide(
                            color: AppColors.surface.withValues(alpha: 0.4),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: body),
        ],
      ),
    );
  }
}

/// Loads the snapshot and shows loading and error states.
class _Snapshot extends ConsumerWidget {
  const _Snapshot({required this.builder});

  final Widget Function(BuildContext context, PlatformSnapshot s) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snap = ref.watch(platformSnapshotProvider);
    return snap.when(
      loading: () => const ResponsivePage(
        child: LoadingSkeleton(
          label: 'Loading statistics',
          child: SkeletonList(rows: 6),
        ),
      ),
      error: (e, _) => ErrorState(
        message: userMessageFor(e),
        onRetry: () => ref.invalidate(platformSnapshotProvider),
      ),
      data: (s) => builder(context, s),
    );
  }
}

/// Board S97 (statistics only) — every organization on the platform.
class PlatformOverviewScreen extends ConsumerStatefulWidget {
  const PlatformOverviewScreen({super.key});

  @override
  ConsumerState<PlatformOverviewScreen> createState() =>
      _PlatformOverviewScreenState();
}

class _PlatformOverviewScreenState
    extends ConsumerState<PlatformOverviewScreen> {
  final _search = TextEditingController();
  OrgStatus? _status;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _Snapshot(
    builder: (context, s) {
      final now = s.generatedAt;
      final q = _search.text.trim().toLowerCase();
      final rows =
          s.orgs
              .where(
                (o) =>
                    (_status == null || o.statusAt(now) == _status) &&
                    (q.isEmpty ||
                        o.name.toLowerCase().contains(q) ||
                        o.id.toLowerCase().contains(q) ||
                        o.industry.toLowerCase().contains(q) ||
                        o.state.toLowerCase().contains(q)),
              )
              .toList()
            ..sort((a, b) => b.employees.compareTo(a.employees));
      final byEmployees = [...s.orgs]
        ..sort((a, b) => b.employees.compareTo(a.employees));
      final daily = s.dailyActive;
      final regs = s.registrations();
      final thisMonth = regs.isEmpty ? 0 : regs.last.$2;
      final adoption = s.employees == 0
          ? 0
          : (s.accountsSignedIn * 100 / s.employees).round();

      return ResponsivePage(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: 'Platform overview',
              subtitle:
                  'Statistics only · as of ${DateFormat('d MMM y, HH:mm').format(now.toLocal())}',
            ),
            const SizedBox(height: AppSpacing.lg),
            ResponsiveGrid(
              minItemWidth: 170,
              children: [
                KpiCard(
                  label: 'Organizations',
                  value: _num(s.orgs.length),
                  caption:
                      '$thisMonth new this month · ${s.countWith(OrgStatus.settingUp)} setting up',
                ),
                KpiCard(
                  label: 'Branches',
                  value: _num(s.branches),
                  caption: 'active branches',
                ),
                KpiCard(
                  label: 'Employees',
                  value: _num(s.employees),
                  caption: 'employed, all organizations',
                ),
                KpiCard(
                  label: 'Accounts in use',
                  value: '$adoption%',
                  caption: '${_num(s.accountsSignedIn)} have signed in',
                ),
                KpiCard(
                  label: 'Active today',
                  value: _num(s.activeToday),
                  caption: 'people who punched today',
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            ResponsiveGrid(
              minItemWidth: 420,
              maxColumns: 2,
              children: [
                DashboardPanel(
                  title: 'Daily active employees',
                  subtitle: 'People with a punch each day, last 30 days',
                  child: AreaTrendChart(
                    days: s.days,
                    values: daily,
                    semanticLabel:
                        'Daily active employees over the last 30 days. Today ${daily.isEmpty ? 0 : daily.last}, highest ${daily.fold(0, (a, b) => a > b ? a : b)}.',
                  ),
                ),
                DashboardPanel(
                  title: 'New organizations',
                  subtitle: 'Sign-ups per month, last 12 months',
                  child: StackedBarChart(
                    sparseLabels: true,
                    semanticLabel:
                        'New organizations per month: ${regs.map((r) => '${DateFormat('MMM').format(r.$1)} ${r.$2}').join(', ')}.',
                    bars: [
                      for (final (month, n) in regs)
                        (
                          label: DateFormat('MMM').format(month)[0],
                          segments: [(n, AppColors.success)],
                          muted: false,
                        ),
                    ],
                  ),
                ),
                DashboardPanel(
                  title: 'Share of employees',
                  subtitle: 'Largest organizations; the rest grouped',
                  child: ShareBar(
                    unit: 'employees',
                    parts: [for (final o in byEmployees) (o.name, o.employees)],
                  ),
                ),
                DashboardPanel(
                  title: 'Organization status',
                  child: DonutChart(
                    centerLabel: 'organizations',
                    parts: [
                      (
                        OrgStatus.active.label,
                        s.countWith(OrgStatus.active),
                        PlatformChartColors.active,
                      ),
                      (
                        OrgStatus.settingUp.label,
                        s.countWith(OrgStatus.settingUp),
                        PlatformChartColors.settingUp,
                      ),
                      (
                        OrgStatus.quiet.label,
                        s.countWith(OrgStatus.quiet),
                        PlatformChartColors.quiet,
                      ),
                    ],
                  ),
                ),
                DashboardPanel(
                  title: 'Feature use',
                  subtitle: 'Share of organizations using each feature',
                  child: Wrap(
                    spacing: AppSpacing.md,
                    runSpacing: AppSpacing.lg,
                    children: [
                      for (final (label, pct) in s.featureUse)
                        RingGauge(percent: pct, label: label),
                    ],
                  ),
                ),
                DashboardPanel(
                  title: 'Organizations by industry',
                  child: LollipopChart(
                    unit: 'organizations',
                    items: s.countBy((o) => o.industry),
                  ),
                ),
                DashboardPanel(
                  title: 'Organizations by state',
                  child: HeatTiles(
                    unit: 'organizations',
                    items: s.countBy((o) => o.state),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            AppCard(
              header: CardHeader(
                title: 'Organizations',
                subtitle:
                    '${s.countWith(OrgStatus.active)} active · ${s.countWith(OrgStatus.settingUp)} setting up · ${s.countWith(OrgStatus.quiet)} with no activity in 7 days',
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: AppSpacing.md,
                    runSpacing: AppSpacing.sm,
                    children: [
                      SizedBox(
                        width: 280,
                        child: AppTextField(
                          label: 'Search',
                          controller: _search,
                          hintText: 'Name, ID, industry or state',
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      SizedBox(
                        width: 220,
                        child: AppDropdownField<OrgStatus?>(
                          label: 'Status',
                          value: _status,
                          options: [
                            const AppDropdownOption(null, 'Any status'),
                            for (final st in OrgStatus.values)
                              AppDropdownOption(st, st.label),
                          ],
                          onChanged: (v) => setState(() => _status = v),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (rows.isEmpty)
                    const Text(
                      'No organizations match.',
                      style: AppTypography.small,
                    )
                  else
                    AppDataTable(
                      showCheckboxColumn: false,
                      minWidth: 1000,
                      columns: const [
                        DataColumn(label: Text('Organization')),
                        DataColumn(label: Text('Industry · state')),
                        DataColumn(label: Text('Registered')),
                        DataColumn(label: Text('Branches'), numeric: true),
                        DataColumn(label: Text('Employees'), numeric: true),
                        DataColumn(label: Text('Accounts in use')),
                        DataColumn(label: Text('Active today'), numeric: true),
                        DataColumn(label: Text('Status')),
                        DataColumn(label: Text('Last activity')),
                      ],
                      rows: [
                        for (final o in rows)
                          DataRow(
                            onSelectChanged: (_) =>
                                context.go(AppRoutes.platformOrg(o.id)),
                            cells: [
                              DataCell(
                                Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(o.name, style: AppTypography.label),
                                    Text(o.id, style: AppTypography.code),
                                  ],
                                ),
                              ),
                              DataCell(
                                Text(
                                  '${o.industry.isEmpty ? 'Industry not given' : o.industry} · ${o.state}',
                                ),
                              ),
                              DataCell(Text(_date(o.createdAt))),
                              DataCell(Text('${o.activeBranches}')),
                              DataCell(Text(_num(o.employees))),
                              DataCell(Text('${o.adoption}%')),
                              DataCell(Text(_num(o.activeToday))),
                              DataCell(
                                StatusBadge(
                                  label: o.statusAt(now).label,
                                  tone: _tone(o.statusAt(now)),
                                ),
                              ),
                              DataCell(Text(_ago(o.lastActivity, now))),
                            ],
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// Board S98 (statistics only) — one organization's usage and branches.
class PlatformOrgScreen extends StatelessWidget {
  const PlatformOrgScreen({super.key, required this.orgId});

  final String orgId;

  @override
  Widget build(BuildContext context) => _Snapshot(
    builder: (context, s) {
      final o = s.orgs.where((x) => x.id == orgId).firstOrNull;
      if (o == null) {
        return const ErrorState(
          headline: '404',
          title: 'This organization isn’t registered',
          message: 'Check the link, or go back to the list.',
        );
      }
      final now = s.generatedAt;
      final status = o.statusAt(now);
      final branches = [...o.branches]
        ..sort((a, b) => b.employees.compareTo(a.employees));
      return ResponsivePage(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Breadcrumbs(
              items: [
                BreadcrumbItem(
                  'Organizations',
                  onTap: () => context.go(AppRoutes.platform),
                ),
                BreadcrumbItem(o.name),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            PageHeader(
              title: o.name,
              subtitle:
                  '${o.id} · ${o.industry.isEmpty ? 'Industry not given' : o.industry} · ${o.city}, ${o.state} · registered ${_date(o.createdAt)} · size ${o.sizeRange}',
              actions: [StatusBadge(label: status.label, tone: _tone(status))],
            ),
            const SizedBox(height: AppSpacing.lg),
            ResponsiveGrid(
              minItemWidth: 170,
              children: [
                KpiCard(
                  label: 'Branches',
                  value: '${o.activeBranches}',
                  caption: '${o.branches.length - o.activeBranches} inactive',
                ),
                KpiCard(
                  label: 'Employees',
                  value: _num(o.employees),
                  caption: '${o.inactiveEmployees} inactive',
                ),
                KpiCard(
                  label: 'Accounts in use',
                  value: '${o.adoption}%',
                  caption:
                      '${_num(o.accountsSignedIn)} signed in · ${o.accountsInvited} invited',
                ),
                KpiCard(
                  label: 'Active today',
                  value: _num(o.activeToday),
                  caption: 'last activity ${_ago(o.lastActivity, now)}',
                ),
                KpiCard(
                  label: 'Punches',
                  value: _num(o.punches30),
                  caption: 'last 30 days',
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            ResponsiveGrid(
              minItemWidth: 420,
              maxColumns: 2,
              children: [
                DashboardPanel(
                  title: 'Activity calendar',
                  subtitle:
                      'Share of employees who punched each day, last 30 days',
                  child: CalendarHeatmap(
                    days: s.days,
                    values: o.dailyActive,
                    total: o.employees,
                  ),
                ),
                DashboardPanel(
                  title: 'Features in use',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: RingGauge(
                          percent: o.adoption,
                          label: 'Accounts in use',
                          size: 96,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _Fact(
                        'Selfie punches',
                        o.selfieBranches == 0
                            ? 'Off'
                            : 'On at ${o.selfieBranches} ${o.selfieBranches == 1 ? 'branch' : 'branches'} · ${o.faceEnrolled} faces set up',
                      ),
                      _Fact('Custom employee fields', '${o.customFields}'),
                      _Fact('Employee imports', '${o.imports}'),
                      _Fact(
                        'Branch set-up complete',
                        '${o.branches.where((b) => b.active && b.setupPercent == 100).length} of ${o.activeBranches}',
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            AppCard(
              header: const CardHeader(
                title: 'Branches',
                subtitle: 'Counts only — no people are listed',
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  BulletBars(
                    rows: [
                      for (final b in branches)
                        if (b.active) (b.name, b.activeToday, b.employees),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  AppDataTable(
                    showCheckboxColumn: false,
                    minWidth: 760,
                    columns: const [
                      DataColumn(label: Text('Branch')),
                      DataColumn(label: Text('City')),
                      DataColumn(label: Text('Employees'), numeric: true),
                      DataColumn(label: Text('Active today'), numeric: true),
                      DataColumn(label: Text('Set-up')),
                      DataColumn(label: Text('Selfie punches')),
                      DataColumn(label: Text('Status')),
                    ],
                    rows: [
                      for (final b in branches)
                        DataRow(
                          cells: [
                            DataCell(
                              Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(b.name, style: AppTypography.label),
                                  Text(b.code, style: AppTypography.code),
                                ],
                              ),
                            ),
                            DataCell(Text(b.city)),
                            DataCell(Text(_num(b.employees))),
                            DataCell(Text(_num(b.activeToday))),
                            DataCell(Text('${b.setupPercent}%')),
                            DataCell(Text(b.selfieCheck ? 'On' : 'Off')),
                            DataCell(
                              StatusBadge(
                                label: b.active ? 'Active' : 'Inactive',
                                tone: b.active
                                    ? StatusTone.success
                                    : StatusTone.neutral,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label, style: AppTypography.small)),
          const SizedBox(width: AppSpacing.md),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: AppTypography.label,
            ),
          ),
        ],
      ),
    ),
  );
}
