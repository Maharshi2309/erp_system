import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/router/route_names.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/permissions/system_roles.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/file_download.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_data_table.dart';
import '../../../../core/widgets/app_date_field.dart';
import '../../../../core/widgets/app_dropdown_field.dart';
import '../../../../core/widgets/app_overlays.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../dashboard/presentation/dashboard_widgets.dart';
import '../../../employees/data/spreadsheet.dart';
import '../../../employees/domain/employee.dart';
import '../../../organization/domain/branch.dart';
import '../../../organization/presentation/providers/organization_providers.dart';
import '../../domain/leave.dart';
import '../../domain/leave_book.dart';
import '../leave_providers.dart';
import '../leave_widgets.dart';
import 'leave_section.dart';

/// The list label: approved requests whose dates changed show "Amended".
String displayStatus(LeaveRequest r) =>
    r.amendedFrom != null && r.status == LeaveStatus.approved
    ? 'Amended'
    : r.status.label;

StatusTone displayTone(LeaveRequest r) =>
    displayStatus(r) == 'Amended' ? StatusTone.info : toneOf(r.status);

/// What was decided, by whom (board S61 "Decision").
String decisionText(LeaveBook book, LeaveRequest r, DateTime now) {
  final f = DateFormat('d MMM HH:mm');
  final decided = r.steps.where((s) => s.isDone).lastOrNull;
  return switch (r.status) {
    LeaveStatus.pending =>
      'Waiting for ${r.currentStep == null ? 'approval' : book.approverName(r.currentStep!)} · ${sentAgo(r.createdAt, now)}',
    LeaveStatus.changesRequested => 'Changes requested · “${r.decisionNote}”',
    LeaveStatus.approved when r.amendedFrom != null =>
      'Dates changed by employee · re-approved${decided?.decidedBy == null ? '' : ' by ${decided!.decidedBy}'}',
    LeaveStatus.approved =>
      '${decided?.decidedBy ?? 'Approved'}${decided?.decidedAt == null ? '' : ' · ${f.format(decided!.decidedAt!)}'}',
    LeaveStatus.rejected =>
      '${decided?.decidedBy ?? 'Rejected'} · “${r.decisionNote}”',
    LeaveStatus.withdrawn =>
      'Withdrawn by employee before decision · ${DateFormat('d MMM').format(r.history.last.at)}',
    LeaveStatus.cancelled =>
      'Cancelled by employee ${DateFormat('d MMM').format(r.history.last.at)} · days returned',
  };
}

enum _Period {
  days30('Last 30 days', 30),
  days90('Last 90 days', 90),
  year('This year', 0);

  const _Period(this.label, this.days);

  final String label;
  final int days;
}

/// Board S61 — every request in scope, filterable and exportable.
class LeaveRequestsScreen extends ConsumerStatefulWidget {
  const LeaveRequestsScreen({super.key});

  @override
  ConsumerState<LeaveRequestsScreen> createState() =>
      _LeaveRequestsScreenState();
}

class _LeaveRequestsScreenState extends ConsumerState<LeaveRequestsScreen> {
  String _search = '';
  String? _type;
  String? _branch;
  _Period _period = _Period.days90;
  String _status = 'All';
  int _shown = 25;

  @override
  Widget build(BuildContext context) => LeaveSection(
    current: AppRoutes.leaveRequests,
    body: (context, scope) {
      final book = scope.book;
      final now = ref.watch(orgNowProvider)();
      final branches = ref.watch(branchesProvider).value ?? const <Branch>[];
      String branchName(String? id) =>
          branches.where((b) => b.id == id).firstOrNull?.name ?? '—';
      final since = _period == _Period.year
          ? DateTime(book.today.year)
          : book.today.subtract(Duration(days: _period.days));
      final q = _search.trim().toLowerCase();
      final base = [
        for (final r in scope.requests)
          if (!r.createdAt.isBefore(since) &&
              (_type == null || r.typeKey == _type) &&
              (_branch == null ||
                  book.person(r.employeeId)?.branchId == _branch) &&
              (q.isEmpty ||
                  r.id.toLowerCase().contains(q) ||
                  (book.person(r.employeeId)?.fullName ?? '')
                      .toLowerCase()
                      .contains(q)))
            r,
      ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      const statuses = [
        'All',
        'Pending',
        'Changes requested',
        'Approved',
        'Rejected',
        'Amended',
        'Withdrawn',
        'Cancelled',
      ];
      final rows = _status == 'All'
          ? base
          : base.where((r) => displayStatus(r) == _status).toList();

      void export() {
        startDownload(
          context,
          ref,
          'leave_requests_${isoDate(book.today)}.xlsx',
          buildXlsx('Leave requests', [
            [
              'Request',
              'Sent',
              'Employee ID',
              'Name',
              'Branch',
              'Type',
              'From',
              'To',
              'Half day',
              'Days',
              'Status',
              'Decision',
            ],
            for (final r in rows)
              [
                r.id,
                isoDate(r.createdAt),
                book.person(r.employeeId)?.code ?? '',
                book.person(r.employeeId)?.fullName ?? '',
                branchName(book.person(r.employeeId)?.branchId),
                book.data.type(r.typeKey)?.name ?? r.typeKey,
                isoDate(r.from),
                isoDate(r.to),
                r.half == HalfDay.full ? '' : r.half.label,
                formatDays(book.daysOf(r)),
                displayStatus(r),
                decisionText(book, r, now),
              ],
          ]),
          mimeType: xlsxMimeType,
          done: '${rows.length} requests exported',
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
                  'Leave requests',
                  style: AppTypography.pageTitle,
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
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            children: [
              SizedBox(
                width: 260,
                child: SearchBox(
                  label: 'Search by employee or request ID',
                  hint: 'Employee or request ID',
                  onChanged: (v) => setState(() => _search = v),
                ),
              ),
              SizedBox(
                width: 170,
                child: DashboardSelect<String?>(
                  label: 'Leave type',
                  value: _type,
                  options: [
                    (null, 'All types'),
                    for (final t in book.data.types) (t.key, t.name),
                  ],
                  onChanged: (v) => setState(() => _type = v),
                ),
              ),
              if (scope.session.branchIds.length != 1)
                SizedBox(
                  width: 170,
                  child: DashboardSelect<String?>(
                    label: 'Branch',
                    value: _branch,
                    options: [
                      (null, 'All branches'),
                      for (final b in branches)
                        if (scope.session.coversBranch(b.id)) (b.id, b.name),
                    ],
                    onChanged: (v) => setState(() => _branch = v),
                  ),
                ),
              SizedBox(
                width: 160,
                child: DashboardSelect<_Period>(
                  label: 'Period',
                  value: _period,
                  options: [for (final p in _Period.values) (p, p.label)],
                  onChanged: (v) =>
                      setState(() => _period = v ?? _Period.days90),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final s in statuses)
                if (s == 'All' ||
                    base.any((r) => displayStatus(r) == s) ||
                    s != 'Changes requested')
                  FilterChip(
                    label: Text(
                      '$s ${s == 'All' ? base.length : base.where((r) => displayStatus(r) == s).length}',
                    ),
                    selected: _status == s,
                    showCheckmark: false,
                    onSelected: (_) => setState(() {
                      _status = s;
                      _shown = 25;
                    }),
                  ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (rows.isEmpty)
            AppCard(
              child: EmptyState(
                icon: Icons.event_note_outlined,
                title: 'No requests',
                message:
                    'No requests with this status in ${_period.label.toLowerCase()}.',
              ),
            )
          else
            AppDataTable(
              minWidth: 980,
              columns: const [
                DataColumn(label: Text('Request')),
                DataColumn(label: Text('Employee')),
                DataColumn(label: Text('Type · dates')),
                DataColumn(label: Text('Days'), numeric: true),
                DataColumn(label: Text('Status')),
                DataColumn(label: Text('Decision')),
              ],
              rows: [
                for (final r in rows.take(_shown))
                  () {
                    final e = book.person(r.employeeId);
                    return DataRow(
                      cells: [
                        DataCell(
                          _TwoLine(
                            r.id,
                            'sent ${DateFormat('d MMM').format(r.createdAt)}',
                            link: true,
                          ),
                          onTap: () =>
                              context.go('${AppRoutes.leave}?request=${r.id}'),
                        ),
                        DataCell(
                          _TwoLine(
                            e?.fullName ?? r.employeeId,
                            branchName(e?.branchId),
                          ),
                        ),
                        DataCell(
                          _TwoLine(
                            book.data.type(r.typeKey)?.name ?? r.typeKey,
                            '${r.amendedFrom == null ? '' : '${leaveRange(r.amendedFrom!.$1, r.amendedFrom!.$2)} → '}${leaveRange(r.from, r.to)}${r.half == HalfDay.full ? '' : ' (half)'}',
                          ),
                        ),
                        DataCell(
                          Text(
                            formatDays(book.daysOf(r)),
                            style: AppTypography.code,
                          ),
                        ),
                        DataCell(
                          StatusBadge(
                            label: displayStatus(r),
                            tone: displayTone(r),
                          ),
                        ),
                        DataCell(
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 320),
                            child: Text(
                              decisionText(book, r, now),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.small,
                            ),
                          ),
                        ),
                      ],
                    );
                  }(),
              ],
              footer: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.sm,
                  children: [
                    Text(
                      'Showing ${rows.length < _shown ? rows.length : _shown} of ${rows.length} · decisions are permanent; changes show as amendments',
                      style: AppTypography.helper,
                    ),
                    if (rows.length > _shown)
                      AppButton(
                        label: 'Show more',
                        variant: AppButtonVariant.secondary,
                        size: AppButtonSize.small,
                        onPressed: () => setState(() => _shown += 25),
                      ),
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );
}

class _TwoLine extends StatelessWidget {
  const _TwoLine(this.top, this.bottom, {this.link = false});

  final String top;
  final String bottom;
  final bool link;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          top,
          style: link
              ? AppTypography.code.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w500,
                )
              : AppTypography.small.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
        ),
        Text(bottom, style: AppTypography.helper),
      ],
    );
  }
}

/// "−1.0" in red, "11.5", "1.25".
String balanceText(double v) {
  final s = v.abs() * 4 % 2 == 1
      ? v.abs().toStringAsFixed(2)
      : v.abs().toStringAsFixed(1);
  return v < 0 ? '−$s' : s;
}

/// Board S60 — balances with an adjustment panel.
class LeaveBalancesScreen extends ConsumerStatefulWidget {
  const LeaveBalancesScreen({super.key});

  @override
  ConsumerState<LeaveBalancesScreen> createState() =>
      _LeaveBalancesScreenState();
}

class _LeaveBalancesScreenState extends ConsumerState<LeaveBalancesScreen> {
  String _search = '';
  String? _branch;
  int? _year;
  String? _selected;
  int _shown = 25;

  @override
  Widget build(BuildContext context) => LeaveSection(
    current: AppRoutes.leaveBalances,
    body: (context, scope) {
      final book = scope.book;
      final year = _year ?? book.today.year;
      final branches = [
        for (final b in ref.watch(branchesProvider).value ?? const <Branch>[])
          if (scope.session.coversBranch(b.id) && b.isActive) b,
      ];
      // A leave approver's team is listed whole, whatever the branch.
      final byTeam = scope.session.role == SystemRole.leaveApprover;
      final branch = byTeam
          ? null
          : _branch ??
                (branches.length == 1
                    ? branches.first.id
                    : branches.firstOrNull?.id);
      final types = [
        for (final t in book.data.types)
          if (t.tracksBalance && t.active && !t.optionalHolidaysOnly) t,
      ];
      final q = _search.trim().toLowerCase();
      final people = [
        for (final e in scope.people)
          if ((branch == null || e.branchId == branch) &&
              (q.isEmpty ||
                  e.fullName.toLowerCase().contains(q) ||
                  e.code.toLowerCase().contains(q)))
            e,
      ]..sort((a, b) => a.fullName.compareTo(b.fullName));

      void export() {
        startDownload(
          context,
          ref,
          'leave_balances_$year.xlsx',
          buildXlsx('Leave balances', [
            [
              'Employee ID',
              'Name',
              for (final t in types) ...[
                '${t.name} granted',
                '${t.name} used',
                '${t.name} pending',
                '${t.name} available',
              ],
            ],
            for (final e in people)
              [
                e.code,
                e.fullName,
                for (final t in types)
                  ...() {
                    final b = book.balance(e, t.key, year);
                    return [
                      formatDays(b.total),
                      formatDays(b.used),
                      formatDays(b.pending),
                      formatDays(b.available),
                    ];
                  }(),
              ],
          ]),
          mimeType: xlsxMimeType,
          done: 'Balances for ${people.length} people exported',
        );
      }

      final table = people.isEmpty
          ? const AppCard(
              child: EmptyState(
                icon: Icons.person_search_outlined,
                title: 'No one matches',
                message: 'Try another name or branch.',
              ),
            )
          : AppDataTable(
              minWidth: 640,
              columns: [
                const DataColumn(label: Text('Employee')),
                for (final t in types)
                  DataColumn(
                    label: Text(t.name.replaceAll(' leave', '')),
                    numeric: true,
                  ),
                const DataColumn(label: Text('Pending')),
                if (scope.canEdit) const DataColumn(label: Text('Actions')),
              ],
              rows: [
                for (final e in people.take(_shown))
                  DataRow(
                    selected: e.id == _selected,
                    cells: [
                      DataCell(_TwoLine(e.fullName, e.code)),
                      for (final t in types)
                        () {
                          final v = book.balance(e, t.key, year).available;
                          return DataCell(
                            Text(
                              balanceText(v),
                              style: AppTypography.code.copyWith(
                                color: v < 0
                                    ? AppColors.danger
                                    : AppColors.textPrimary,
                              ),
                            ),
                          );
                        }(),
                      DataCell(
                        Text(() {
                          final n = book
                              .requestsOf(e)
                              .where((r) => r.status.isOpen)
                              .length;
                          return n == 0 ? '—' : '$n req';
                        }(), style: AppTypography.small),
                      ),
                      if (scope.canEdit)
                        DataCell(
                          TextButton(
                            onPressed: () => _adjust(context, e, types, year),
                            child: Text(
                              'Adjust',
                              semanticsLabel: 'Adjust ${e.fullName}',
                            ),
                          ),
                        ),
                    ],
                  ),
              ],
              footer: people.length > _shown
                  ? Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: AppButton(
                          label: 'Show more',
                          variant: AppButtonVariant.secondary,
                          size: AppButtonSize.small,
                          onPressed: () => setState(() => _shown += 25),
                        ),
                      ),
                    )
                  : null,
            );

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
                  'Leave balances',
                  style: AppTypography.pageTitle,
                ),
              ),
              if (scope.canExport)
                AppButton(
                  label: 'Export balances',
                  icon: Icons.download_outlined,
                  variant: AppButtonVariant.secondary,
                  onPressed: people.isEmpty ? null : export,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            children: [
              SizedBox(
                width: 240,
                child: SearchBox(
                  label: 'Search employee',
                  hint: 'Name or ID',
                  onChanged: (v) => setState(() => _search = v),
                ),
              ),
              if (branches.length > 1 && !byTeam)
                SizedBox(
                  width: 180,
                  child: DashboardSelect<String?>(
                    label: 'Branch',
                    value: branch,
                    options: [for (final b in branches) (b.id, b.name)],
                    onChanged: (v) => setState(() {
                      _branch = v;
                      _shown = 25;
                    }),
                  ),
                ),
              SizedBox(
                width: 120,
                child: DashboardSelect<int>(
                  label: 'Year',
                  value: year,
                  options: [
                    for (var y = book.today.year; y >= book.today.year - 1; y--)
                      (y, '$y'),
                  ],
                  onChanged: (v) => setState(() => _year = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          table,
          const SizedBox(height: AppSpacing.sm),
          const Text(
            'Available days. Pending requests are already held. Negative balances are shown in red with a minus sign.',
            style: AppTypography.helper,
          ),
        ],
      );
    },
  );

  Future<void> _adjust(
    BuildContext context,
    Employee e,
    List<LeaveType> types,
    int year,
  ) async {
    setState(() => _selected = e.id);
    await showSidePanel<void>(
      context,
      title: 'Adjust balance',
      body: (_) => AdjustBalanceForm(employee: e, types: types, year: year),
    );
    if (mounted) setState(() => _selected = null);
  }
}

/// Board S60 side form: a signed change with a reason, logged.
class AdjustBalanceForm extends ConsumerStatefulWidget {
  const AdjustBalanceForm({
    super.key,
    required this.employee,
    required this.types,
    required this.year,
  });

  final Employee employee;
  final List<LeaveType> types;
  final int year;

  @override
  ConsumerState<AdjustBalanceForm> createState() => _AdjustBalanceFormState();
}

class _AdjustBalanceFormState extends ConsumerState<AdjustBalanceForm> {
  late String _type = widget.types
      .map((t) => t.key)
      .firstWhere((k) => k == 'earned', orElse: () => widget.types.first.key);
  final _amount = TextEditingController(text: '1');
  final _reason = TextEditingController();
  DateTime? _effective;
  bool _busy = false;
  String? _error;
  LeaveAdjustment? _saved;

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  double? get _days {
    final v = double.tryParse(_amount.text.trim().replaceAll('−', '-'));
    if (v == null || v == 0 || v.abs() > 30) return null;
    return v;
  }

  Future<void> _save(LeaveBook book) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final saved = await ref
          .read(leaveDataProvider.notifier)
          .adjust(
            e: widget.employee,
            typeKey: _type,
            days: _days!,
            effective: _effective ?? book.today,
            reason: _reason.text.trim(),
          );
      if (mounted) setState(() => _saved = saved);
    } on Failure catch (f) {
      if (mounted) setState(() => _error = f.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final book = ref.watch(leaveBookProvider).value;
    if (book == null) return const SizedBox.shrink();
    final type = book.data.type(_type)!;
    final now = book.balance(widget.employee, _type, widget.year).available;
    final days = _days;
    final after = now + (days ?? 0);
    final name = type.name.replaceAll(' leave', '').toLowerCase();
    if (_saved != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            liveRegion: true,
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.successSoft,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Text(
                'Adjustment saved. ${widget.employee.fullName} now has ${balanceText(now)} $name days. Logged as ${_saved!.id}.',
                style: AppTypography.small.copyWith(
                  color: AppColors.successText,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            label: 'Make another',
            variant: AppButtonVariant.secondary,
            onPressed: () => setState(() {
              _saved = null;
              _reason.clear();
              _amount.text = '1';
            }),
          ),
        ],
      );
    }
    final canSave = days != null && _reason.text.trim().length >= 5 && !_busy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.employee.fullName, style: AppTypography.sectionTitle),
        Text(widget.employee.code, style: AppTypography.small),
        const SizedBox(height: AppSpacing.lg),
        AppDropdownField<String>(
          label: 'Leave type',
          value: _type,
          options: [
            for (final t in widget.types) AppDropdownOption(t.key, t.name),
          ],
          onChanged: (v) => setState(() => _type = v ?? _type),
        ),
        const SizedBox(height: AppSpacing.md),
        AppTextField(
          label: 'Change (days)',
          isRequired: true,
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
            signed: true,
          ),
          helperText: 'Use a minus sign to take days away. Up to 30.',
          errorText: _amount.text.isNotEmpty && days == null
              ? 'Enter a number between −30 and 30, not 0.'
              : null,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AppSpacing.md),
        AppDateField(
          label: 'Effective',
          value: _effective ?? book.today,
          firstDate: DateTime(widget.year),
          lastDate: DateTime(widget.year, 12, 31),
          onChanged: (d) => setState(() => _effective = d),
        ),
        const SizedBox(height: AppSpacing.md),
        InfoRow(
          '${type.name.replaceAll(' leave', '')} balance',
          '${balanceText(now)} → ${balanceText(after)}',
          valueStyle: AppTypography.code.copyWith(
            color: after < 0 ? AppColors.danger : AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        AppTextField(
          label: 'Reason',
          isRequired: true,
          controller: _reason,
          maxLines: 3,
          maxLength: 300,
          helperText: 'Shown to the employee and kept in the audit log.',
          errorText: _error,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AppSpacing.lg),
        AppButton(
          label: _reason.text.trim().length >= 5
              ? 'Save adjustment'
              : 'Add a reason to save',
          busy: _busy,
          busyLabel: 'Saving…',
          onPressed: canSave ? () => _save(book) : null,
        ),
      ],
    );
  }
}
