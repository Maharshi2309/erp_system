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
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_data_table.dart';
import '../../../../core/widgets/app_dropdown_field.dart';
import '../../../../core/widgets/page_header.dart';
import '../../../../core/widgets/skeleton.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../auth/presentation/widgets/auth_layout.dart';
import '../../domain/branch.dart';
import '../../domain/organization.dart';
import '../../domain/setup_progress.dart';
import '../providers/organization_providers.dart';

enum _StatusFilter { any, active, inactive }

enum _Sort {
  employees('Employees (high–low)'),
  name('Name (A–Z)'),
  setup('Setup (low–high)');

  const _Sort(this.label);

  final String label;
}

/// Board S36 — every branch with address, manager, people, setup progress
/// and status. Inactive branches stay listed; their history is kept.
class BranchesScreen extends ConsumerStatefulWidget {
  const BranchesScreen({super.key});

  @override
  ConsumerState<BranchesScreen> createState() => _BranchesScreenState();
}

class _BranchesScreenState extends ConsumerState<BranchesScreen> {
  final _search = TextEditingController();
  _StatusFilter _status = _StatusFilter.any;
  _Sort _sort = _Sort.employees;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Branch> _filtered(List<Branch> all) {
    final q = _search.text.trim().toLowerCase();
    final list = all.where((b) {
      final statusOk = switch (_status) {
        _StatusFilter.any => true,
        _StatusFilter.active => b.isActive,
        _StatusFilter.inactive => !b.isActive,
      };
      final text = '${b.name} ${b.code} ${b.city}'.toLowerCase();
      return statusOk && (q.isEmpty || text.contains(q));
    }).toList();
    switch (_sort) {
      case _Sort.employees:
        list.sort((a, b) => b.employeeCount.compareTo(a.employeeCount));
      case _Sort.name:
        list.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
      case _Sort.setup:
        list.sort(
          (a, b) =>
              SetupProgress(a).percent.compareTo(SetupProgress(b).percent),
        );
    }
    return list;
  }

  void _clear() => setState(() {
    _search.clear();
    _status = _StatusFilter.any;
  });

  @override
  Widget build(BuildContext context) {
    final branches = ref.watch(branchesProvider);
    final organization = ref.watch(organizationProvider).value;
    final canEdit =
        ref
            .watch(sessionProvider)
            ?.permissions
            .can(PermissionModule.organization, PermissionAction.edit) ??
        false;

    return ResponsivePage(
      child: branches.when(
        loading: () => const LoadingSkeleton(
          label: 'Loading branches',
          child: SkeletonList(rows: 4),
        ),
        error: (error, _) => ErrorState(
          message: userMessageFor(error),
          onRetry: () => ref.invalidate(branchesProvider),
        ),
        data: (all) {
          final active = all.where((b) => b.isActive).length;
          final people = all.fold<int>(0, (s, b) => s + b.employeeCount);
          final rows = _filtered(all);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(
                title: 'Branches',
                subtitle:
                    '$active active · ${all.length - active} inactive · $people employees',
                actions: [
                  if (canEdit)
                    AppButton(
                      label: 'Create branch',
                      icon: Icons.add,
                      onPressed: () => context.go(AppRoutes.newBranch),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              if (all.isEmpty)
                AppCard(
                  child: EmptyState(
                    icon: Icons.location_on_outlined,
                    title: 'No branches yet',
                    message:
                        'A branch is one location with its own hours, holidays '
                        'and rules.',
                    actions: [
                      if (canEdit)
                        AppButton(
                          label: 'Create branch',
                          onPressed: () => context.go(AppRoutes.newBranch),
                        ),
                    ],
                  ),
                )
              else ...[
                _Filters(
                  search: _search,
                  status: _status,
                  sort: _sort,
                  onChanged: () => setState(() {}),
                  onStatus: (s) => setState(() => _status = s),
                  onSort: (s) => setState(() => _sort = s),
                ),
                const SizedBox(height: AppSpacing.md),
                if (rows.isEmpty)
                  AppCard(
                    child: EmptyState(
                      icon: Icons.filter_alt_off_outlined,
                      title: 'No branches match',
                      message: 'Try a different name, code or city.',
                      actions: [
                        AppButton(
                          label: 'Clear filters',
                          variant: AppButtonVariant.secondary,
                          onPressed: _clear,
                        ),
                      ],
                    ),
                  )
                else
                  AppDataTable(
                    minWidth: 900,
                    columns: const [
                      DataColumn(label: Text('BRANCH')),
                      DataColumn(label: Text('ADDRESS')),
                      DataColumn(label: Text('TIME ZONE')),
                      DataColumn(label: Text('MANAGER')),
                      DataColumn(label: Text('EMPLOYEES'), numeric: true),
                      DataColumn(label: Text('SETUP')),
                      DataColumn(label: Text('STATUS')),
                      DataColumn(label: Text('')),
                    ],
                    rows: [
                      for (final b in rows)
                        _row(context, b, organization?.timeZone, canEdit),
                    ],
                    footer: Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Text(
                        '${all.length} branches · inactive branches keep all '
                        'history and stay in reports',
                        style: AppTypography.helper,
                      ),
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }

  DataRow _row(
    BuildContext context,
    Branch b,
    String? orgTimeZone,
    bool canEdit,
  ) {
    final percent = SetupProgress(b).percent;
    final manager = switch (b.roles) {
      null => 'No manager',
      final r when r.manager == BranchManagerChoice.owner => 'Owner',
      final r => r.managerEmail,
    };
    final zone = b.timeZone ?? 'Inherited · ${orgTimeZone ?? defaultTimeZone}';
    return DataRow(
      cells: [
        DataCell(
          InkWell(
            onTap: () => context.go(AppRoutes.branch(b.id)),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  b.name,
                  style: AppTypography.bodyStrong.copyWith(
                    color: AppColors.primary,
                  ),
                ),
                Text(b.code, style: AppTypography.code),
              ],
            ),
          ),
        ),
        DataCell(
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 200),
            child: Text(
              '${b.address}, ${b.city}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        DataCell(Text(zone, style: AppTypography.small)),
        DataCell(
          Text(
            manager,
            style: AppTypography.small.copyWith(
              color: b.roles == null
                  ? AppColors.textMuted
                  : AppColors.textPrimary,
            ),
          ),
        ),
        DataCell(Text('${b.employeeCount}', style: AppTypography.code)),
        DataCell(
          InkWell(
            onTap: canEdit && b.isActive
                ? () => context.go(AppRoutes.branchSetup(b.id))
                : null,
            child: Semantics(
              label: '$percent percent set up',
              excludeSemantics: true,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 64,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: percent / 100,
                        minHeight: 5,
                        color: percent == 100
                            ? AppColors.success
                            : AppColors.primary,
                        backgroundColor: AppColors.border,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text('$percent%', style: AppTypography.code),
                ],
              ),
            ),
          ),
        ),
        DataCell(
          StatusBadge(
            label: b.isActive ? 'Active' : 'Inactive',
            tone: b.isActive ? StatusTone.success : StatusTone.neutral,
          ),
        ),
        DataCell(
          canEdit
              ? TextLink(
                  'Edit',
                  onTap: () => context.go(AppRoutes.branchEdit(b.id)),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _Filters extends StatelessWidget {
  const _Filters({
    required this.search,
    required this.status,
    required this.sort,
    required this.onChanged,
    required this.onStatus,
    required this.onSort,
  });

  final TextEditingController search;
  final _StatusFilter status;
  final _Sort sort;
  final VoidCallback onChanged;
  final ValueChanged<_StatusFilter> onStatus;
  final ValueChanged<_Sort> onSort;

  @override
  Widget build(BuildContext context) {
    final searchField = Semantics(
      label: 'Search branches',
      child: TextField(
        controller: search,
        onChanged: (_) => onChanged(),
        decoration: const InputDecoration(
          hintText: 'Name, code or city',
          prefixIcon: Icon(Icons.search, size: 18),
        ),
      ),
    );
    final statusField = AppDropdownField<_StatusFilter>(
      label: 'Status',
      value: status,
      options: const [
        AppDropdownOption(_StatusFilter.any, 'Any status'),
        AppDropdownOption(_StatusFilter.active, 'Active'),
        AppDropdownOption(_StatusFilter.inactive, 'Inactive'),
      ],
      onChanged: (v) => onStatus(v ?? _StatusFilter.any),
    );
    final sortField = AppDropdownField<_Sort>(
      label: 'Sort',
      value: sort,
      options: [for (final s in _Sort.values) AppDropdownOption(s, s.label)],
      onChanged: (v) => onSort(v ?? _Sort.employees),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 640) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              searchField,
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(child: statusField),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: sortField),
                ],
              ),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: searchField),
            const SizedBox(width: AppSpacing.md),
            SizedBox(width: 180, child: statusField),
            const SizedBox(width: AppSpacing.md),
            SizedBox(width: 220, child: sortField),
          ],
        );
      },
    );
  }
}
