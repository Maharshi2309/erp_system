import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/route_names.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/permissions/permissions.dart';
import '../../../../core/responsive/responsive_page.dart';
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
import '../../../../core/widgets/page_header.dart';
import '../../../../core/widgets/skeleton.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../../shared/models/app_session.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../organization/domain/branch.dart';
import '../../../organization/presentation/providers/organization_providers.dart';
import '../../data/employee_files.dart';
import '../../data/spreadsheet.dart';
import '../../domain/employee.dart';
import '../../domain/employee_query.dart';
import '../providers/employee_providers.dart';
import '../widgets/employee_widgets.dart';

/// Optional table columns (board S39 "Columns"; S40 "Choose columns").
enum DirectoryColumn {
  department('Department'),
  branch('Branch'),
  manager('Manager'),
  employment('Employment'),
  account('Account'),
  joined('Joined');

  const DirectoryColumn(this.label);

  final String label;
}

final directoryColumnsProvider =
    NotifierProvider<DirectoryColumnsNotifier, Set<DirectoryColumn>>(
      DirectoryColumnsNotifier.new,
    );

class DirectoryColumnsNotifier extends Notifier<Set<DirectoryColumn>> {
  @override
  Set<DirectoryColumn> build() => DirectoryColumn.values.toSet();

  void toggle(DirectoryColumn c) =>
      state = state.contains(c) ? ({...state}..remove(c)) : {...state, c};
}

/// Boards S39 (desktop table), S40 (tablet: 3 columns + filter panel) and
/// S41 (phone: cards + "Load 25 more").
class EmployeeDirectoryScreen extends ConsumerStatefulWidget {
  const EmployeeDirectoryScreen({super.key});

  @override
  ConsumerState<EmployeeDirectoryScreen> createState() =>
      _EmployeeDirectoryScreenState();
}

class _EmployeeDirectoryScreenState
    extends ConsumerState<EmployeeDirectoryScreen> {
  late final _search = TextEditingController(
    text: ref.read(directoryQueryProvider).search,
  );
  final _selected = <String>{};

  /// Cards shown on phones ("Load 25 more").
  int _cardCount = 25;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  EmployeeQuery get _query => ref.read(directoryQueryProvider);
  void _setQuery(EmployeeQuery q) {
    ref.read(directoryQueryProvider.notifier).set(q);
    setState(() {
      _selected.clear();
      _cardCount = 25;
    });
  }

  bool _can(PermissionModule m, PermissionAction a) =>
      ref.read(sessionProvider)?.permissions.can(m, a) ?? false;

  /// The member's branch when their role covers exactly one (locked filter).
  String? _lockedBranch(AppSession s) =>
      s.branchIds.length == 1 ? s.branchIds.single : null;

  void _clearFilters() {
    _search.clear();
    final session = ref.read(sessionProvider)!;
    _setQuery(
      EmployeeQuery(
        branchId: _lockedBranch(session),
        pageSize: _query.pageSize,
        sort: _query.sort,
        ascending: _query.ascending,
      ),
    );
  }

  void _downloadTemplate() {
    final fields = ref.read(customFieldsProvider).value ?? const [];
    ref
        .read(fileDownloadsProvider)
        .save(
          'staffline_employee_template.xlsx',
          buildXlsx('Employees', templateRows(fields)),
          mimeType: xlsxMimeType,
        );
    showAppToast(context, 'Template downloaded');
  }

  void _export(List<Employee> rows) {
    final session = ref.read(sessionProvider)!;
    final bytes = buildXlsx(
      'Employees',
      exportRows(
        rows,
        branches: ref.read(branchesProvider).value ?? const [],
        everyone: ref.read(employeesProvider).value ?? const [],
        fields: ref.read(customFieldsProvider).value ?? const [],
        includeSensitive:
            session.scope == DataScope.organization &&
            _can(PermissionModule.employees, PermissionAction.edit),
      ),
    );
    ref
        .read(fileDownloadsProvider)
        .save('employees.xlsx', bytes, mimeType: xlsxMimeType);
    showAppToast(context, 'Exported ${rows.length} people');
  }

  Future<void> _resendInvites(List<String> ids) async {
    try {
      final sent = await ref
          .read(employeesProvider.notifier)
          .resendInvites(ids);
      if (!mounted) return;
      setState(_selected.clear);
      showAppToast(
        context,
        sent == 0
            ? 'Nobody to invite — everyone selected has already signed in'
            : 'Invitation sent to $sent ${sent == 1 ? 'person' : 'people'}',
      );
    } on Failure catch (f) {
      if (mounted) showAppToast(context, f.message, icon: Icons.error_outline);
    }
  }

  Future<void> _deactivate(List<Employee> people) async {
    final n = people.length;
    final input = await showLifecycleDialog(
      context,
      title: n == 1
          ? 'Deactivate ${people.single.fullName}?'
          : 'Deactivate $n people?',
      message:
          'Removes sign-in access. Attendance, leave and audit history are '
          'kept, and they can be reactivated later.',
      confirmLabel: n == 1 ? 'Deactivate' : 'Deactivate $n people',
      destructive: true,
    );
    if (input == null || !mounted) return;
    final refused = await ref.read(employeesProvider.notifier).deactivateAll([
      for (final p in people) p.id,
    ], input.reason);
    if (!mounted) return;
    setState(_selected.clear);
    final done = n - refused.length;
    showAppToast(
      context,
      refused.isEmpty
          ? (n == 1
                ? '${people.single.fullName} deactivated'
                : '$n people deactivated')
          : '$done deactivated · ${refused.length} skipped: ${refused.values.first}',
      icon: refused.isEmpty ? Icons.check : Icons.info_outline,
    );
  }

  Future<void> _changeBranch(List<Employee> people) async {
    final result = await showDialog<int>(
      context: context,
      builder: (_) => ChangeBranchDialog(people: people),
    );
    if (result == null || !mounted) return;
    setState(_selected.clear);
    showAppToast(context, '$result ${result == 1 ? 'person' : 'people'} moved');
  }

  Future<void> _openFilters(
    List<Branch> branches,
    int Function(EmployeeQuery) count,
  ) async {
    final session = ref.read(sessionProvider)!;
    await showSidePanelRoute<void>(
      context,
      barrierLabel: 'Filters',
      builder: (context) => _FilterPanel(
        initial: _query,
        branches: branches,
        branchLocked: _lockedBranch(session) != null,
        count: count,
        onApply: _setQuery,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    if (session == null) return const SizedBox.shrink();
    final employees = ref.watch(visibleEmployeesProvider);
    final branches = ref.watch(branchesProvider).value ?? const <Branch>[];
    final everyone = ref.watch(employeesProvider).value ?? const <Employee>[];
    final query = ref.watch(directoryQueryProvider);
    final columns = ref.watch(directoryColumnsProvider);
    final canCreate = session.permissions.can(
      PermissionModule.employees,
      PermissionAction.create,
    );
    final canEdit = session.permissions.can(
      PermissionModule.employees,
      PermissionAction.edit,
    );
    final canDeactivate = session.permissions.can(
      PermissionModule.employees,
      PermissionAction.deactivate,
    );
    final canExport = session.permissions.can(
      PermissionModule.employees,
      PermissionAction.export,
    );
    final canImport = session.permissions.can(
      PermissionModule.importExport,
      PermissionAction.create,
    );
    final canManageFields = session.permissions.can(
      PermissionModule.settings,
      PermissionAction.edit,
    );
    final visibleBranches = [
      for (final b in branches)
        if (session.coversBranch(b.id)) b,
    ];
    String branchName(String id) =>
        branches.where((b) => b.id == id).firstOrNull?.name ?? '—';
    String managerName(String? id) =>
        everyone.where((e) => e.id == id).firstOrNull?.fullName ?? '—';

    return ResponsivePage(
      child: employees.when(
        loading: () => const LoadingSkeleton(
          label: 'Loading employees',
          child: SkeletonList(rows: 8),
        ),
        error: (error, _) => ErrorState(
          message: userMessageFor(error),
          onRetry: () => ref.invalidate(employeesProvider),
        ),
        data: (all) {
          final filtered = applyQuery(all, query);
          final page = pageOf(filtered, query);
          final branchCount = all.map((e) => e.branchId).toSet().length;
          final scopeLabel = query.branchId == null
              ? null
              : 'in ${branchName(query.branchId!)}';
          final selectedPeople = [
            for (final e in all)
              if (_selected.contains(e.id)) e,
          ];

          return LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final phone = width < 600;
              final wide = width >= 900;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PageHeader(
                    title: 'Employees',
                    subtitle: all.length == 1
                        ? '1 person'
                        : '${all.length} people across $branchCount '
                              '${branchCount == 1 ? 'branch' : 'branches'}',
                    actions: [
                      if (canImport && !phone) ...[
                        AppButton(
                          label: 'Template',
                          icon: Icons.download_outlined,
                          variant: AppButtonVariant.secondary,
                          onPressed: _downloadTemplate,
                        ),
                        AppButton(
                          label: 'Import',
                          icon: Icons.upload_file_outlined,
                          variant: AppButtonVariant.secondary,
                          onPressed: () => context.go(AppRoutes.employeeImport),
                        ),
                      ],
                      if (canExport && !phone)
                        AppButton(
                          label: 'Export',
                          icon: Icons.file_download_outlined,
                          variant: AppButtonVariant.secondary,
                          onPressed: filtered.isEmpty
                              ? null
                              : () => _export(filtered),
                        ),
                      if (canCreate)
                        AppButton(
                          label: 'Add employee',
                          icon: Icons.add,
                          onPressed: () => context.go(AppRoutes.newEmployee),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  if (wide)
                    _FilterBar(
                      search: _search,
                      query: query,
                      branches: visibleBranches,
                      lockedBranch: _lockedBranch(session) == null
                          ? null
                          : branchName(_lockedBranch(session)!),
                      columns: columns,
                      canManageFields: canManageFields,
                      onQuery: _setQuery,
                      onClear: _clearFilters,
                    )
                  else
                    _CompactFilterBar(
                      search: _search,
                      query: query,
                      phone: phone,
                      lockedBranch: _lockedBranch(session) != null,
                      branchName: branchName,
                      onQuery: _setQuery,
                      onClear: _clearFilters,
                      onOpenFilters: () => _openFilters(
                        visibleBranches,
                        (q) => applyQuery(all, q).length,
                      ),
                      resultLabel:
                          '${filtered.length} ${filtered.length == 1 ? 'person' : 'people'}',
                    ),
                  const SizedBox(height: AppSpacing.md),
                  if (_selected.isNotEmpty)
                    _BulkBar(
                      count: _selected.length,
                      onResend: canEdit
                          ? () => _resendInvites(_selected.toList())
                          : null,
                      onChangeBranch: canEdit
                          ? () => _changeBranch(selectedPeople)
                          : null,
                      onDeactivate: canDeactivate
                          ? () => _deactivate(
                              selectedPeople
                                  .where((e) => e.status.isEmployed)
                                  .toList(),
                            )
                          : null,
                      onClear: () => setState(_selected.clear),
                    ),
                  if (all.isEmpty)
                    AppCard(
                      child: EmptyState(
                        icon: Icons.people_outline,
                        title: 'No employees yet',
                        message:
                            'Add people one by one, or import a spreadsheet '
                            'with everyone at once.',
                        actions: [
                          if (canCreate)
                            AppButton(
                              label: 'Add employee',
                              onPressed: () =>
                                  context.go(AppRoutes.newEmployee),
                            ),
                          if (canImport)
                            AppButton(
                              label: 'Import employees',
                              variant: AppButtonVariant.secondary,
                              onPressed: () =>
                                  context.go(AppRoutes.employeeImport),
                            ),
                        ],
                      ),
                    )
                  else if (filtered.isEmpty)
                    AppCard(
                      child: EmptyState(
                        icon: Icons.filter_alt_off_outlined,
                        title: 'No one matches',
                        message:
                            'Try a different name, ID or email, or clear the filters.',
                        actions: [
                          AppButton(
                            label: 'Clear filters',
                            variant: AppButtonVariant.secondary,
                            onPressed: _clearFilters,
                          ),
                        ],
                      ),
                    )
                  else if (phone)
                    _CardList(
                      people: filtered.take(_cardCount).toList(),
                      total: filtered.length,
                      onMore: () => setState(() => _cardCount += 25),
                    )
                  else
                    AppDataTable(
                      minWidth: wide ? 1040 : 520,
                      sortColumnIndex: switch (query.sort) {
                        EmployeeSort.name => 1,
                        EmployeeSort.joined
                            when wide &&
                                columns.contains(DirectoryColumn.joined) =>
                          2 +
                              DirectoryColumn.values
                                  .where(
                                    (c) =>
                                        columns.contains(c) &&
                                        c.index < DirectoryColumn.joined.index,
                                  )
                                  .length,
                        _ => null,
                      },
                      sortAscending: query.ascending,
                      columns: [
                        DataColumn(
                          label: Checkbox(
                            value:
                                page.isNotEmpty &&
                                    page.every((e) => _selected.contains(e.id))
                                ? true
                                : (page.any((e) => _selected.contains(e.id))
                                      ? null
                                      : false),
                            tristate: true,
                            semanticLabel: 'Select all on this page',
                            onChanged: (_) => setState(() {
                              final all = page.every(
                                (e) => _selected.contains(e.id),
                              );
                              for (final e in page) {
                                all
                                    ? _selected.remove(e.id)
                                    : _selected.add(e.id);
                              }
                            }),
                          ),
                        ),
                        DataColumn(
                          label: const Text('EMPLOYEE'),
                          onSort: (_, asc) => _setQuery(
                            query.copyWith(
                              sort: EmployeeSort.name,
                              ascending: asc,
                            ),
                          ),
                        ),
                        if (wide) ...[
                          for (final c in DirectoryColumn.values)
                            if (columns.contains(c))
                              DataColumn(
                                label: Text(c.label.toUpperCase()),
                                onSort: c == DirectoryColumn.joined
                                    ? (_, asc) => _setQuery(
                                        query.copyWith(
                                          sort: EmployeeSort.joined,
                                          ascending: asc,
                                        ),
                                      )
                                    : null,
                              ),
                        ] else ...[
                          const DataColumn(label: Text('DEPARTMENT')),
                          const DataColumn(label: Text('STATUS')),
                        ],
                        const DataColumn(label: Text('ACTIONS')),
                      ],
                      rows: [
                        for (final e in page)
                          DataRow(
                            selected: _selected.contains(e.id),
                            cells: [
                              DataCell(
                                Checkbox(
                                  value: _selected.contains(e.id),
                                  semanticLabel: 'Select ${e.fullName}',
                                  onChanged: (v) => setState(
                                    () => v == true
                                        ? _selected.add(e.id)
                                        : _selected.remove(e.id),
                                  ),
                                ),
                              ),
                              DataCell(_NameCell(employee: e)),
                              if (wide) ...[
                                for (final c in DirectoryColumn.values)
                                  if (columns.contains(c))
                                    DataCell(switch (c) {
                                      DirectoryColumn.department => Text(
                                        e.department,
                                      ),
                                      DirectoryColumn.branch => Text(
                                        branchName(e.branchId),
                                      ),
                                      DirectoryColumn.manager => Text(
                                        managerName(e.managerId),
                                      ),
                                      DirectoryColumn.employment =>
                                        EmploymentBadge(e.status),
                                      DirectoryColumn.account => AccountBadge(
                                        e.accountStatus,
                                      ),
                                      DirectoryColumn.joined => Text(
                                        employeeDateFormat.format(
                                          e.joiningDate,
                                        ),
                                        style: AppTypography.code,
                                      ),
                                    }),
                              ] else ...[
                                DataCell(Text(e.department)),
                                DataCell(EmploymentBadge(e.status)),
                              ],
                              DataCell(
                                _RowActions(
                                  employee: e,
                                  canEdit: canEdit,
                                  canDeactivate: canDeactivate,
                                  onResend: () => _resendInvites([e.id]),
                                  onDeactivate: () => _deactivate([e]),
                                ),
                              ),
                            ],
                          ),
                      ],
                      footer: PaginationBar(
                        firstIndex: query.page * query.pageSize,
                        pageSize: query.pageSize,
                        totalCount: filtered.length,
                        itemLabel: scopeLabel,
                        onPageChanged: (first) => _setQuery(
                          query.copyWith(page: first ~/ query.pageSize),
                        ),
                        onPageSizeChanged: (size) =>
                            _setQuery(query.copyWith(pageSize: size)),
                      ),
                    ),
                  if (!wide && !phone)
                    const Padding(
                      padding: EdgeInsets.only(top: AppSpacing.sm),
                      child: Text(
                        'On tablets the table keeps 3 columns. Branch, manager '
                        'and joining date are on each person’s profile.',
                        style: AppTypography.helper,
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _NameCell extends StatelessWidget {
  const _NameCell({required this.employee});

  final Employee employee;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.go(AppRoutes.employee(employee.id)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            EmployeeAvatar(employee: employee, size: 32),
            const SizedBox(width: AppSpacing.sm + 2),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    employee.name,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodyStrong.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                  Text(
                    '${employee.code} · ${employee.designation}',
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.helper,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RowActions extends StatelessWidget {
  const _RowActions({
    required this.employee,
    required this.canEdit,
    required this.canDeactivate,
    required this.onResend,
    required this.onDeactivate,
  });

  final Employee employee;
  final bool canEdit;
  final bool canDeactivate;
  final VoidCallback onResend;
  final VoidCallback onDeactivate;

  @override
  Widget build(BuildContext context) {
    final e = employee;
    final canInvite =
        canEdit &&
        e.status.isEmployed &&
        e.accountStatus != AccountStatus.signedIn &&
        e.workEmail.isNotEmpty;
    return PopupMenuButton<String>(
      tooltip: 'Actions for ${e.fullName}',
      icon: const Icon(Icons.more_horiz, color: AppColors.textSecondary),
      onSelected: (v) => switch (v) {
        'view' => context.go(AppRoutes.employee(e.id)),
        'edit' => context.go(AppRoutes.employeeEdit(e.id)),
        'invite' => onResend(),
        _ => onDeactivate(),
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'view', child: Text('View profile')),
        if (canEdit) const PopupMenuItem(value: 'edit', child: Text('Edit')),
        if (canInvite)
          PopupMenuItem(
            value: 'invite',
            child: Text(
              e.accountStatus == AccountStatus.noAccount
                  ? 'Send invite'
                  : 'Resend invite',
            ),
          ),
        if (canDeactivate && e.status.isEmployed)
          const PopupMenuItem(value: 'deactivate', child: Text('Deactivate…')),
      ],
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.search,
    required this.query,
    required this.branches,
    required this.lockedBranch,
    required this.columns,
    required this.canManageFields,
    required this.onQuery,
    required this.onClear,
  });

  final TextEditingController search;
  final EmployeeQuery query;
  final List<Branch> branches;
  final String? lockedBranch;
  final Set<DirectoryColumn> columns;
  final bool canManageFields;
  final ValueChanged<EmployeeQuery> onQuery;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    Widget select<T>(
      String label,
      T? value,
      List<AppDropdownOption<T?>> options,
      ValueChanged<T?> onChanged,
    ) => SizedBox(
      width: 150,
      child: _CompactSelect<T>(
        label: label,
        value: value,
        options: options,
        onChanged: onChanged,
      ),
    );

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 260,
          child: _SearchField(
            controller: search,
            hint: 'Search name, ID or email',
            onChanged: (text) => onQuery(query.copyWith(search: text)),
          ),
        ),
        if (lockedBranch != null)
          _LockedChip(label: 'Branch: $lockedBranch')
        else
          select<String>('Branch', query.branchId, [
            const AppDropdownOption(null, 'All branches'),
            for (final b in branches) AppDropdownOption(b.id, b.name),
          ], (v) => onQuery(query.copyWith(branchId: v))),
        select<String>(
          'Department',
          query.department,
          [
            const AppDropdownOption(null, 'All departments'),
            for (final d in departments) AppDropdownOption(d, d),
          ],
          (v) => onQuery(query.copyWith(department: v)),
        ),
        select<EmploymentStatus>('Status', query.status, [
          const AppDropdownOption(null, 'Any status'),
          for (final s in EmploymentStatus.values)
            AppDropdownOption(s, s.label),
        ], (v) => onQuery(query.copyWith(status: v))),
        select<EmploymentType>('Type', query.type, [
          const AppDropdownOption(null, 'Any type'),
          for (final t in EmploymentType.values) AppDropdownOption(t, t.label),
        ], (v) => onQuery(query.copyWith(type: v))),
        if (query.isFiltered &&
            query.activeFilters + (query.search.isEmpty ? 0 : 1) >
                (lockedBranch == null ? 0 : 1))
          AppButton(
            label: 'Clear',
            variant: AppButtonVariant.ghost,
            onPressed: onClear,
          ),
        _ColumnsMenu(columns: columns, canManageFields: canManageFields),
      ],
    );
  }
}

class _ColumnsMenu extends ConsumerWidget {
  const _ColumnsMenu({required this.columns, required this.canManageFields});

  final Set<DirectoryColumn> columns;
  final bool canManageFields;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<Object>(
      tooltip: 'Choose columns',
      onSelected: (v) {
        if (v is DirectoryColumn) {
          ref.read(directoryColumnsProvider.notifier).toggle(v);
        } else {
          context.go(AppRoutes.employeeFields);
        }
      },
      itemBuilder: (_) => [
        for (final c in DirectoryColumn.values)
          CheckedPopupMenuItem<Object>(
            value: c,
            checked: columns.contains(c),
            child: Text(c.label),
          ),
        if (canManageFields) ...[
          const PopupMenuDivider(),
          const PopupMenuItem<Object>(
            value: 'fields',
            child: Text('Manage employee fields'),
          ),
        ],
      ],
      child: IgnorePointer(
        child: AppButton(
          label: 'Columns',
          icon: Icons.view_column_outlined,
          variant: AppButtonVariant.secondary,
          onPressed: () {},
        ),
      ),
    );
  }
}

class _CompactFilterBar extends StatelessWidget {
  const _CompactFilterBar({
    required this.search,
    required this.query,
    required this.phone,
    required this.lockedBranch,
    required this.branchName,
    required this.onQuery,
    required this.onClear,
    required this.onOpenFilters,
    required this.resultLabel,
  });

  final TextEditingController search;
  final EmployeeQuery query;
  final bool phone;
  final bool lockedBranch;
  final String Function(String) branchName;
  final ValueChanged<EmployeeQuery> onQuery;
  final VoidCallback onClear;
  final VoidCallback onOpenFilters;
  final String resultLabel;

  @override
  Widget build(BuildContext context) {
    final chips = <(String, VoidCallback?)>[
      if (query.branchId != null)
        (
          'Branch: ${branchName(query.branchId!)}',
          lockedBranch ? null : () => onQuery(query.copyWith(branchId: null)),
        ),
      if (query.department != null)
        (
          'Department: ${query.department}',
          () => onQuery(query.copyWith(department: null)),
        ),
      if (query.status != null)
        (
          'Status: ${query.status!.label}',
          () => onQuery(query.copyWith(status: null)),
        ),
      if (query.type != null)
        (
          'Type: ${query.type!.label}',
          () => onQuery(query.copyWith(type: null)),
        ),
    ];
    final removable = chips.where((c) => c.$2 != null).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _SearchField(
                controller: search,
                hint: phone ? 'Name or ID' : 'Search name, ID or mobile',
                onChanged: (text) => onQuery(query.copyWith(search: text)),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Badge(
              isLabelVisible: removable > 0,
              label: Text('$removable'),
              backgroundColor: AppColors.primary,
              child: AppButton(
                label: phone ? '' : 'Filters',
                icon: Icons.filter_alt_outlined,
                variant: AppButtonVariant.secondary,
                onPressed: onOpenFilters,
              ),
            ),
          ],
        ),
        if (chips.isNotEmpty || query.search.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final (label, onRemove) in chips)
                onRemove == null
                    ? _LockedChip(label: label)
                    : InputChip(
                        label: Text(label),
                        onDeleted: onRemove,
                        deleteButtonTooltipMessage: 'Remove filter $label',
                        backgroundColor: AppColors.primarySoft,
                        labelStyle: AppTypography.small.copyWith(
                          color: AppColors.primaryHover,
                        ),
                        side: BorderSide.none,
                      ),
              Text(resultLabel, style: AppTypography.small),
              if (removable > 0)
                AppButton(
                  label: 'Clear all',
                  size: AppButtonSize.small,
                  variant: AppButtonVariant.ghost,
                  onPressed: onClear,
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _LockedChip extends StatelessWidget {
  const _LockedChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 40),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
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
          Flexible(child: Text(label, style: AppTypography.small)),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.hint,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Search employees',
      textField: true,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: const Icon(Icons.search, size: 18),
        ),
      ),
    );
  }
}

/// A small select without a visible label (the label is the first option).
class _CompactSelect<T> extends StatelessWidget {
  const _CompactSelect({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final T? value;
  final List<AppDropdownOption<T?>> options;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      child: InputDecorator(
        decoration: const InputDecoration(
          contentPadding: EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: 2,
          ),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T?>(
            value: value,
            isExpanded: true,
            style: AppTypography.body.copyWith(color: AppColors.textPrimary),
            items: [
              for (final o in options)
                DropdownMenuItem(
                  value: o.value,
                  child: Text(o.label, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }
}

class _BulkBar extends StatelessWidget {
  const _BulkBar({
    required this.count,
    required this.onResend,
    required this.onChangeBranch,
    required this.onDeactivate,
    required this.onClear,
  });

  final int count;
  final VoidCallback? onResend;
  final VoidCallback? onChangeBranch;
  final VoidCallback? onDeactivate;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Semantics(
            liveRegion: true,
            child: Text('$count selected', style: AppTypography.bodyStrong),
          ),
          if (onResend != null)
            AppButton(
              label: 'Resend invite',
              size: AppButtonSize.small,
              variant: AppButtonVariant.secondary,
              onPressed: onResend,
            ),
          if (onChangeBranch != null)
            AppButton(
              label: 'Change branch',
              size: AppButtonSize.small,
              variant: AppButtonVariant.secondary,
              onPressed: onChangeBranch,
            ),
          if (onDeactivate != null)
            AppButton(
              label: 'Deactivate',
              size: AppButtonSize.small,
              variant: AppButtonVariant.dangerOutline,
              onPressed: onDeactivate,
            ),
          AppButton(
            label: 'Clear selection',
            size: AppButtonSize.small,
            variant: AppButtonVariant.ghost,
            onPressed: onClear,
          ),
        ],
      ),
    );
  }
}

class _CardList extends StatelessWidget {
  const _CardList({
    required this.people,
    required this.total,
    required this.onMore,
  });

  final List<Employee> people;
  final int total;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final e in people)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm + 2),
            child: Material(
              color: AppColors.surface,
              shape: RoundedRectangleBorder(
                side: const BorderSide(color: AppColors.border),
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                onTap: () => context.go(AppRoutes.employee(e.id)),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          EmployeeAvatar(employee: e, size: 40),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(e.name, style: AppTypography.bodyStrong),
                                Text(e.designation, style: AppTypography.small),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right,
                            color: AppColors.textDisabled,
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm + 2),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.xs,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.neutralSoft,
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                            ),
                            child: Text(e.code, style: AppTypography.code),
                          ),
                          Text(e.department, style: AppTypography.helper),
                          EmploymentBadge(e.status),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        if (people.length < total)
          AppButton(
            label: 'Load ${(total - people.length).clamp(0, 25)} more',
            variant: AppButtonVariant.secondary,
            expand: true,
            onPressed: onMore,
          ),
      ],
    );
  }
}

class _FilterPanel extends StatefulWidget {
  const _FilterPanel({
    required this.initial,
    required this.branches,
    required this.branchLocked,
    required this.count,
    required this.onApply,
  });

  final EmployeeQuery initial;
  final List<Branch> branches;
  final bool branchLocked;
  final int Function(EmployeeQuery) count;
  final ValueChanged<EmployeeQuery> onApply;

  @override
  State<_FilterPanel> createState() => _FilterPanelState();
}

class _FilterPanelState extends State<_FilterPanel> {
  late EmployeeQuery _q = widget.initial;

  @override
  Widget build(BuildContext context) {
    final n = widget.count(_q);
    return SidePanelFrame(
      title: 'Filters',
      onClose: () => Navigator.of(context).pop(),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!widget.branchLocked) ...[
            AppDropdownField<String?>(
              label: 'Branch',
              value: _q.branchId,
              options: [
                const AppDropdownOption(null, 'All branches'),
                for (final b in widget.branches)
                  AppDropdownOption(b.id, b.name),
              ],
              onChanged: (v) => setState(() => _q = _q.copyWith(branchId: v)),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          AppDropdownField<String?>(
            label: 'Department',
            value: _q.department,
            options: [
              const AppDropdownOption(null, 'All departments'),
              for (final d in departments) AppDropdownOption(d, d),
            ],
            onChanged: (v) => setState(() => _q = _q.copyWith(department: v)),
          ),
          const SizedBox(height: AppSpacing.md),
          AppDropdownField<EmploymentStatus?>(
            label: 'Status',
            value: _q.status,
            options: [
              const AppDropdownOption(null, 'Any status'),
              for (final s in EmploymentStatus.values)
                AppDropdownOption(s, s.label),
            ],
            onChanged: (v) => setState(() => _q = _q.copyWith(status: v)),
          ),
          const SizedBox(height: AppSpacing.md),
          AppDropdownField<EmploymentType?>(
            label: 'Type',
            value: _q.type,
            options: [
              const AppDropdownOption(null, 'Any type'),
              for (final t in EmploymentType.values)
                AppDropdownOption(t, t.label),
            ],
            onChanged: (v) => setState(() => _q = _q.copyWith(type: v)),
          ),
        ],
      ),
      footer: Row(
        children: [
          AppButton(
            label: 'Reset',
            variant: AppButtonVariant.secondary,
            onPressed: () => setState(
              () => _q = _q.copyWith(
                branchId: widget.branchLocked ? _q.branchId : null,
                department: null,
                status: null,
                type: null,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: AppButton(
              label: 'Show $n ${n == 1 ? 'person' : 'people'}',
              expand: true,
              onPressed: () {
                widget.onApply(_q);
                Navigator.of(context).pop();
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Bulk "Change branch": new branch, effective date and the manager people
/// report to there (PRD §6.3: managers must belong to the new branch).
class ChangeBranchDialog extends ConsumerStatefulWidget {
  const ChangeBranchDialog({super.key, required this.people});

  final List<Employee> people;

  @override
  ConsumerState<ChangeBranchDialog> createState() => _ChangeBranchDialogState();
}

class _ChangeBranchDialogState extends ConsumerState<ChangeBranchDialog> {
  String? _branchId;
  String? _managerId;
  late DateTime _effective = ref.read(_today);
  Map<String, String> _errors = {};
  bool _busy = false;

  static final _today = Provider<DateTime>((ref) {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  });

  Future<void> _save() async {
    setState(() {
      _errors = {
        if (_branchId == null) 'branch': 'Choose a branch.',
        if (_managerId == null)
          'manager': 'Choose who they report to at the new branch.',
      };
    });
    if (_errors.isNotEmpty) return;
    setState(() => _busy = true);
    try {
      final moved = await ref
          .read(employeesProvider.notifier)
          .changeBranch(
            [for (final p in widget.people) p.id],
            branchId: _branchId!,
            managerId: _managerId,
            effectiveFrom: _effective,
          );
      if (mounted) Navigator.of(context).pop(moved);
    } on Failure catch (f) {
      if (mounted) setState(() => _errors = {'form': f.message});
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final branches = [
      for (final b in ref.watch(branchesProvider).value ?? const <Branch>[])
        if (b.isActive && (session?.coversBranch(b.id) ?? false)) b,
    ];
    final ids = {for (final p in widget.people) p.id};
    final managers = [
      for (final e in ref.watch(employeesProvider).value ?? const <Employee>[])
        if (e.branchId == _branchId &&
            e.status.isEmployed &&
            !ids.contains(e.id))
          e,
    ]..sort((a, b) => a.fullName.compareTo(b.fullName));
    final n = widget.people.length;
    return Dialog(
      insetPadding: const EdgeInsets.all(AppSpacing.lg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(
                  n == 1
                      ? 'Move ${widget.people.single.fullName}'
                      : 'Move $n people',
                  style: AppTypography.sectionTitle,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                'Their schedule switches to the new branch’s General shift and '
                'its holiday calendar from the effective date. Past attendance '
                'is unchanged.',
                style: AppTypography.bodySecondary,
              ),
              if (_errors['form'] case final message?) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  message,
                  style: AppTypography.small.copyWith(color: AppColors.danger),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              AppDropdownField<String>(
                label: 'New branch',
                isRequired: true,
                value: _branchId,
                hintText: 'Choose a branch',
                errorText: _errors['branch'],
                options: [
                  for (final b in branches) AppDropdownOption(b.id, b.name),
                ],
                onChanged: (v) => setState(() {
                  _branchId = v;
                  _managerId = null;
                }),
              ),
              const SizedBox(height: AppSpacing.md),
              AppDateField(
                label: 'Effective from',
                isRequired: true,
                value: _effective,
                firstDate: DateTime(2020),
                onChanged: (d) => setState(() => _effective = d ?? _effective),
              ),
              const SizedBox(height: AppSpacing.md),
              AppDropdownField<String>(
                label: 'Reports to',
                isRequired: true,
                value: _managerId,
                hintText: _branchId == null
                    ? 'Choose a branch first'
                    : 'Choose a manager',
                helperText: 'Must be someone at the new branch.',
                errorText: _errors['manager'],
                options: [
                  for (final m in managers)
                    AppDropdownOption(m.id, '${m.fullName} — ${m.designation}'),
                ],
                onChanged: _branchId == null
                    ? null
                    : (v) => setState(() => _managerId = v),
              ),
              const SizedBox(height: AppSpacing.xl),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  AppButton(
                    label: 'Cancel',
                    variant: AppButtonVariant.secondary,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  AppButton(
                    label: n == 1 ? 'Move' : 'Move $n people',
                    busy: _busy,
                    busyLabel: 'Moving…',
                    onPressed: _save,
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
