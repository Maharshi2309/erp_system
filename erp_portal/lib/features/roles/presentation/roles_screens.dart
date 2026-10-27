import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/router/route_names.dart';
import '../../../core/errors/failure.dart';
import '../../../core/permissions/permissions.dart';
import '../../../core/permissions/system_roles.dart';
import '../../../core/responsive/responsive_grid.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_data_table.dart';
import '../../../core/widgets/app_dropdown_field.dart';
import '../../../core/widgets/app_overlays.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/kpi_card.dart';
import '../../../core/widgets/selection_controls.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_badge.dart';
import '../../audit/presentation/audit_providers.dart';
import '../../dashboard/presentation/dashboard_widgets.dart';
import '../../employees/domain/employee.dart';
import '../../employees/presentation/providers/employee_providers.dart';
import '../../leave/presentation/leave_widgets.dart';
import '../../organization/presentation/providers/organization_providers.dart';
import '../../settings/presentation/settings_providers.dart';
import '../domain/access.dart';
import '../domain/access_levels.dart';
import 'access_providers.dart';
import 'access_widgets.dart';
import 'roles_section.dart';

class _TwoLine extends StatelessWidget {
  const _TwoLine(this.top, this.bottom);

  final String top;
  final String bottom;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        top,
        style: AppTypography.small.copyWith(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w500,
        ),
      ),
      Text(
        bottom,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.helper,
      ),
    ],
  );
}

IconData roleIcon(RoleDefinition r) => switch (r.base) {
  SystemRole.owner => Icons.workspace_premium_outlined,
  SystemRole.hrAdmin => Icons.badge_outlined,
  SystemRole.branchManager => Icons.storefront_outlined,
  SystemRole.attendanceManager => Icons.schedule_outlined,
  SystemRole.leaveApprover => Icons.fact_check_outlined,
  SystemRole.employee => Icons.person_outline,
};

/// Board S67, redesigned (D-79): each role as a card that says in plain
/// words who they see and what they can do; or all roles side by side.
class RoleDirectoryScreen extends ConsumerStatefulWidget {
  const RoleDirectoryScreen({super.key});

  @override
  ConsumerState<RoleDirectoryScreen> createState() =>
      _RoleDirectoryScreenState();
}

class _RoleDirectoryScreenState extends ConsumerState<RoleDirectoryScreen> {
  bool _compare = false;

  Future<void> _create(RolesScope scope) async {
    final from = await showDialog<String>(
      context: context,
      builder: (_) => _TemplateDialog(roles: scope.data.roles),
    );
    if (from == null || !mounted) return;
    context.go(
      from.isEmpty ? AppRoutes.newRole : '${AppRoutes.newRole}?from=$from',
    );
  }

  @override
  Widget build(BuildContext context) => RolesSection(
    current: AppRoutes.roles,
    body: (context, scope) => Column(
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
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'A role is a job’s set of access. Give people a role instead of setting access one by one.',
                  style: AppTypography.small,
                ),
                Text(
                  '${scope.data.roles.length} roles · ${scope.data.roles.where((r) => !r.isSystem).length} made by you',
                  style: AppTypography.helper,
                ),
              ],
            ),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ChoiceChips<bool>(
                  options: const [(false, 'Roles'), (true, 'Compare roles')],
                  selected: _compare,
                  onSelected: (v) => setState(() => _compare = v),
                ),
                if (scope.canCreate)
                  AppButton(
                    label: 'Create role',
                    icon: Icons.add,
                    onPressed: () => _create(scope),
                  ),
              ],
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (_compare)
          _CompareRoles(roles: scope.data.roles)
        else
          ResponsiveGrid(
            minItemWidth: 320,
            maxColumns: 3,
            children: [
              for (final r in scope.data.roles)
                _RoleCard(
                  role: r,
                  people: scope.holders(r.id),
                  canEdit: !r.isSystem && scope.canEdit,
                  canDuplicate: scope.canCreate && !r.isOwner,
                ),
            ],
          ),
        const SizedBox(height: AppSpacing.sm),
        const Text(
          'Built-in roles can be viewed and copied, not changed. The last owner can’t be removed or downgraded.',
          style: AppTypography.helper,
        ),
      ],
    ),
  );
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.role,
    required this.people,
    required this.canEdit,
    required this.canDuplicate,
  });

  final RoleDefinition role;
  final int people;
  final bool canEdit;
  final bool canDuplicate;

  @override
  Widget build(BuildContext context) {
    final r = role;
    final areas = [
      for (final m in PermissionModule.values)
        if (levelOf(r.grants, m) != AccessLevel.none)
          (accessAreas[m]!.name, levelOf(r.grants, m)),
    ];
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(roleIcon(r), color: AppColors.primary),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: () => context.go(AppRoutes.role(r.id)),
                      child: Text(r.name, style: AppTypography.cardTitle),
                    ),
                    const SizedBox(height: 2),
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      children: [
                        StatusBadge(
                          label: r.isSystem ? 'Built-in' : 'Made by you',
                          tone: r.isSystem
                              ? StatusTone.neutral
                              : StatusTone.info,
                        ),
                        if (!r.active)
                          const StatusBadge(
                            label: 'Switched off',
                            tone: StatusTone.warning,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (r.description.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(r.description, style: AppTypography.small),
          ],
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Sees: ${scopeQuestionLabel(r.scope)}',
            style: AppTypography.label,
          ),
          const SizedBox(height: AppSpacing.xs),
          if (areas.isEmpty)
            const Text(
              'Only their own self-service pages',
              style: AppTypography.helper,
            )
          else
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final (name, level) in areas.take(6))
                  _LevelChip(name: name, level: level),
                if (areas.length > 6)
                  Text(
                    '+${areas.length - 6} more',
                    style: AppTypography.helper,
                  ),
              ],
            ),
          const Divider(height: AppSpacing.xl),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.sm,
            children: [
              TextButton(
                onPressed: () => context.go('${AppRoutes.people}?role=${r.id}'),
                child: Text(
                  '$people ${people == 1 ? 'person' : 'people'}',
                  semanticsLabel: '$people people with ${r.name}',
                ),
              ),
              Wrap(
                spacing: AppSpacing.xs,
                children: [
                  TextButton(
                    onPressed: () => context.go(AppRoutes.role(r.id)),
                    child: Text(
                      canEdit ? 'Edit' : 'View',
                      semanticsLabel: '${canEdit ? 'Edit' : 'View'} ${r.name}',
                    ),
                  ),
                  if (canDuplicate)
                    TextButton(
                      onPressed: () =>
                          context.go('${AppRoutes.newRole}?from=${r.id}'),
                      child: Text(
                        'Copy',
                        semanticsLabel: 'Duplicate ${r.name}',
                      ),
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "People · Can edit" as a small pill; stronger levels look stronger.
class _LevelChip extends StatelessWidget {
  const _LevelChip({required this.name, required this.level});

  final String name;
  final AccessLevel level;

  @override
  Widget build(BuildContext context) {
    final strong = level == AccessLevel.full || level == AccessLevel.edit;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: strong ? AppColors.primarySoft : AppColors.neutralSoft,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        '$name · ${level.label}',
        style: AppTypography.helper.copyWith(
          color: strong ? AppColors.primaryHover : AppColors.textSecondary,
        ),
      ),
    );
  }
}

/// Every area against every role, in level words.
class _CompareRoles extends StatelessWidget {
  const _CompareRoles({required this.roles});

  final List<RoleDefinition> roles;

  @override
  Widget build(BuildContext context) {
    final shown = roles.where((r) => r.active).toList();
    Widget cell(AccessLevel l) => Center(
      child: l == AccessLevel.none
          ? const Text('—', style: AppTypography.helper)
          : _LevelChip(name: '', level: l),
    );
    return AppCard(
      padding: EdgeInsets.zero,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Table(
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          columnWidths: {
            0: const FixedColumnWidth(200),
            for (var i = 1; i <= shown.length; i++)
              i: const FixedColumnWidth(150),
          },
          border: const TableBorder(
            horizontalInside: BorderSide(color: AppColors.divider),
          ),
          children: [
            TableRow(
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Text('Area', style: AppTypography.tableHeader),
                ),
                for (final r in shown)
                  Text(
                    r.name,
                    textAlign: TextAlign.center,
                    style: AppTypography.tableHeader,
                  ),
              ],
            ),
            TableRow(
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    'Whose information',
                    style: AppTypography.bodyStrong,
                  ),
                ),
                for (final r in shown)
                  Text(
                    scopeQuestionLabel(r.scope),
                    textAlign: TextAlign.center,
                    style: AppTypography.small,
                  ),
              ],
            ),
            for (final m in PermissionModule.values)
              TableRow(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      accessAreas[m]!.name,
                      style: AppTypography.bodyStrong,
                    ),
                  ),
                  for (final r in shown) cell(levelOf(r.grants, m)),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// "Create role": start from an existing role, or from nothing.
class _TemplateDialog extends StatelessWidget {
  const _TemplateDialog({required this.roles});

  final List<RoleDefinition> roles;

  @override
  Widget build(BuildContext context) {
    Widget option({
      required String title,
      required String text,
      required String value,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: OptionCard(
        title: title,
        description: text,
        selected: false,
        onTap: () => Navigator.of(context).pop(value),
      ),
    );
    return Dialog(
      insetPadding: const EdgeInsets.all(AppSpacing.lg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: const Text(
                      'Start a new role',
                      style: AppTypography.sectionTitle,
                    ),
                  ),
                  const Text(
                    'Copy the role closest to the job, then change what’s different.',
                    style: AppTypography.small,
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                children: [
                  for (final r in roles)
                    if (!r.isOwner)
                      option(
                        title: 'Like ${r.name}',
                        text: r.description.isEmpty
                            ? 'Sees: ${scopeQuestionLabel(r.scope)}'
                            : r.description,
                        value: r.id,
                      ),
                  option(
                    title: 'Start from scratch',
                    text: 'No access to start with — you choose everything.',
                    value: '',
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Align(
                alignment: Alignment.centerRight,
                child: AppButton(
                  label: 'Cancel',
                  variant: AppButtonVariant.secondary,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Board S70 — who holds which role, and changing it.
class PeopleAccessScreen extends ConsumerStatefulWidget {
  const PeopleAccessScreen({super.key, this.roleId});

  final String? roleId;

  @override
  ConsumerState<PeopleAccessScreen> createState() => _PeopleAccessScreenState();
}

class _PeopleAccessScreenState extends ConsumerState<PeopleAccessScreen> {
  String _search = '';
  late String _role = widget.roleId ?? 'above';
  int _shown = 25;

  @override
  Widget build(BuildContext context) => RolesSection(
    current: AppRoutes.people,
    body: (context, scope) {
      final q = _search.trim().toLowerCase();
      final rows = [
        for (final r in scope.rows)
          if ((switch (_role) {
                'above' => r.role.id != SystemRole.employee.name,
                'all' => true,
                _ => r.role.id == _role,
              }) &&
              (q.isEmpty ||
                  r.name.toLowerCase().contains(q) ||
                  r.email.toLowerCase().contains(q)))
            r,
      ];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            children: [
              SizedBox(
                width: 260,
                child: SearchBox(
                  label: 'Search people',
                  hint: 'Name or email',
                  onChanged: (v) => setState(() {
                    _search = v;
                    _shown = 25;
                  }),
                ),
              ),
              SizedBox(
                width: 240,
                child: DashboardSelect<String>(
                  label: 'Role',
                  value: _role,
                  options: [
                    ('above', 'Roles above Employee'),
                    ('all', 'Everyone'),
                    for (final r in scope.data.roles) (r.id, r.name),
                  ],
                  onChanged: (v) => setState(() {
                    _role = v ?? 'above';
                    _shown = 25;
                  }),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (rows.isEmpty)
            const AppCard(
              child: EmptyState(
                icon: Icons.person_search_outlined,
                title: 'No one matches',
                message: 'Try another name or role.',
              ),
            )
          else
            AppDataTable(
              minWidth: 860,
              columns: [
                const DataColumn(label: Text('Person')),
                const DataColumn(label: Text('Role')),
                const DataColumn(label: Text('Sees')),
                const DataColumn(label: Text('Membership')),
                if (scope.canEdit) const DataColumn(label: Text('Actions')),
              ],
              rows: [
                for (final r in rows.take(_shown))
                  DataRow(
                    cells: [
                      DataCell(_TwoLine(r.name, r.email)),
                      DataCell(Text(r.role.name, style: AppTypography.small)),
                      DataCell(
                        Text(scope.scopeOf(r), style: AppTypography.small),
                      ),
                      DataCell(_membership(r.employee)),
                      if (scope.canEdit)
                        DataCell(
                          TextButton(
                            onPressed: () => _change(context, scope, r),
                            child: Text(
                              'Change role',
                              semanticsLabel: 'Change role of ${r.name}',
                            ),
                          ),
                        ),
                    ],
                  ),
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
                      'Showing ${rows.length < _shown ? rows.length : _shown} of ${rows.length} · role changes apply on the person’s next page load',
                      style: AppTypography.helper,
                    ),
                    if (rows.length > _shown)
                      AppButton(
                        label: 'Show more',
                        size: AppButtonSize.small,
                        variant: AppButtonVariant.secondary,
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

  static Widget _membership(Employee? e) {
    final (label, tone) = switch (e?.accountStatus) {
      null || AccountStatus.signedIn => ('Active', StatusTone.success),
      AccountStatus.invited => ('Invited', StatusTone.info),
      AccountStatus.inviteExpired => ('Invite expired', StatusTone.warning),
      AccountStatus.noAccount => ('No account', StatusTone.neutral),
    };
    return StatusBadge(label: label, tone: tone);
  }

  Future<void> _change(
    BuildContext context,
    RolesScope scope,
    AccessRow r,
  ) async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => ChangeRoleDialog(scope: scope, row: r),
    );
    if (result != null && context.mounted) showAppToast(context, result);
  }
}

/// The S70 dialog: pick a role (and branches), with the last-owner and
/// high-impact rules.
class ChangeRoleDialog extends ConsumerStatefulWidget {
  const ChangeRoleDialog({super.key, required this.scope, required this.row});

  final RolesScope scope;
  final AccessRow row;

  @override
  ConsumerState<ChangeRoleDialog> createState() => _ChangeRoleDialogState();
}

class _ChangeRoleDialogState extends ConsumerState<ChangeRoleDialog> {
  late String _role = widget.row.role.id;
  late List<String> _branches = widget.row.branchIds.isEmpty
      ? [if (widget.row.employee != null) widget.row.employee!.branchId]
      : widget.row.branchIds;
  bool _busy = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final scope = widget.scope;
    final r = widget.row;
    final owners = scope.holders(SystemRole.owner.name);
    final lastOwner = r.role.isOwner && owners <= 1;
    final pick = scope.data.role(_role)!;
    final changed =
        _role != r.role.id ||
        (pick.scope == DataScope.assignedBranches &&
            _branches.join(',') != r.branchIds.join(','));
    final high =
        _role != r.role.id &&
        (pick.isOwner ||
            pick.id == SystemRole.hrAdmin.name ||
            r.role.isOwner ||
            r.role.id == SystemRole.hrAdmin.name);
    final impact = pick.isOwner
        ? '${r.name} will get full control, including deleting the organization.'
        : pick.id == SystemRole.hrAdmin.name
        ? '${r.name} will see every employee record in all branches.'
        : (r.role.scope == DataScope.organization &&
                  pick.scope != DataScope.organization
              ? '${r.name} loses organization-wide access immediately.'
              : '');
    // People without an employee record (the owner) can only be owners.
    final options = [
      for (final x in scope.data.roles)
        if (x.active && (r.employee != null || x.isOwner)) x,
    ];
    final can =
        changed &&
        !lastOwner &&
        !_busy &&
        (pick.scope != DataScope.assignedBranches || _branches.isNotEmpty);

    Future<void> save() async {
      setState(() {
        _busy = true;
        _error = null;
      });
      try {
        await ref
            .read(accessServiceProvider)
            .assign(
              key: r.key,
              roleId: _role,
              branchIds: pick.scope == DataScope.assignedBranches
                  ? _branches
                  : const [],
              employee: r.employee,
            );
        if (context.mounted) {
          Navigator.of(context).pop(
            '${r.name} is now ${pick.name}. They’ll see the change at next page load.',
          );
        }
      } on Failure catch (f) {
        if (mounted) setState(() => _error = f.message);
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }

    return Dialog(
      insetPadding: const EdgeInsets.all(AppSpacing.lg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(
                  'Change role · ${r.name}',
                  style: AppTypography.sectionTitle,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              if (lastOwner)
                Text(
                  '${r.name} is the only owner. Make someone else an owner first, then you can change this.',
                  style: AppTypography.small.copyWith(
                    color: AppColors.warningText,
                  ),
                )
              else ...[
                AppDropdownField<String>(
                  label: 'New role',
                  value: _role,
                  options: [
                    for (final x in options) AppDropdownOption(x.id, x.name),
                  ],
                  onChanged: (v) => setState(() => _role = v ?? _role),
                ),
                if (pick.scope == DataScope.assignedBranches) ...[
                  const SizedBox(height: AppSpacing.md),
                  const Text('Branches', style: AppTypography.label),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      for (final b in scope.branches)
                        if (b.isActive)
                          FilterChip(
                            label: Text(b.name),
                            selected: _branches.contains(b.id),
                            onSelected: (on) => setState(
                              () => _branches = on
                                  ? [..._branches, b.id]
                                  : [
                                      for (final x in _branches)
                                        if (x != b.id) x,
                                    ],
                            ),
                          ),
                    ],
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceMuted,
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'With ${pick.name}, ${r.name.split(' ').first}:',
                        style: AppTypography.label,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      PlainSummary(role: pick, maxItems: 6),
                    ],
                  ),
                ),
                if (impact.isNotEmpty && changed) ...[
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.warningSoft,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Text(
                      impact,
                      style: AppTypography.small.copyWith(
                        color: AppColors.warningText,
                      ),
                    ),
                  ),
                ],
              ],
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _error!,
                  style: AppTypography.small.copyWith(color: AppColors.danger),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  AppButton(
                    label: 'Cancel',
                    variant: AppButtonVariant.secondary,
                    onPressed: _busy ? null : () => Navigator.of(context).pop(),
                  ),
                  if (!lastOwner)
                    AppButton(
                      label: high ? 'Confirm high-impact change' : 'Save',
                      variant: high
                          ? AppButtonVariant.danger
                          : AppButtonVariant.primary,
                      busy: _busy,
                      busyLabel: 'Saving…',
                      onPressed: can ? save : null,
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

enum _InviteState { waiting, expired, bounced, accepted }

/// Board S71 — invitations not yet accepted.
class InvitationsScreen extends ConsumerStatefulWidget {
  const InvitationsScreen({super.key});

  @override
  ConsumerState<InvitationsScreen> createState() => _InvitationsScreenState();
}

class _InvitationsScreenState extends ConsumerState<InvitationsScreen> {
  String _filter = 'open';
  bool _busy = false;

  @override
  Widget build(BuildContext context) => RolesSection(
    current: AppRoutes.invitations,
    body: (context, scope) {
      final now = ref.watch(orgNowProvider)();
      // Invitation links last this many days (board S83).
      final validDays =
          ref.watch(orgSettingsProvider).value?.security.inviteDays ?? 7;
      _InviteState? stateOf(Employee e) {
        if (scope.data.bounces.containsKey(e.code)) return _InviteState.bounced;
        if (e.accountStatus == AccountStatus.inviteExpired) {
          return _InviteState.expired;
        }
        if (e.accountStatus == AccountStatus.invited) {
          final sent = e.invitedAt;
          return sent != null && now.difference(sent).inDays >= validDays
              ? _InviteState.expired
              : _InviteState.waiting;
        }
        if (e.accountStatus == AccountStatus.signedIn &&
            e.invitedAt != null &&
            now.difference(e.invitedAt!).inDays <= 30) {
          return _InviteState.accepted;
        }
        return null;
      }

      final all = [
        for (final e in scope.employees)
          if (e.status.isEmployed && stateOf(e) != null) (e, stateOf(e)!),
      ];
      int count(_InviteState s) => all.where((x) => x.$2 == s).length;
      final rows = [
        for (final x in all)
          if (switch (_filter) {
            'open' => x.$2 != _InviteState.accepted,
            'waiting' => x.$2 == _InviteState.waiting,
            'expired' => x.$2 == _InviteState.expired,
            'bounced' => x.$2 == _InviteState.bounced,
            _ => true,
          })
            x,
      ]..sort((a, b) => a.$2.index.compareTo(b.$2.index));
      final expired = [
        for (final x in all)
          if (x.$2 == _InviteState.expired) x.$1,
      ];
      final canInvite = scope.session.permissions.can(
        PermissionModule.employees,
        PermissionAction.create,
      );

      Future<void> resend(List<Employee> people) async {
        setState(() => _busy = true);
        try {
          final n = await ref.read(employeesProvider.notifier).resendInvites([
            for (final e in people) e.id,
          ]);
          for (final e in people) {
            await ref.read(accessServiceProvider).clearBounce(e.code);
          }
          if (context.mounted) {
            showAppToast(
              context,
              n == 1
                  ? 'Invitation sent to ${people.single.workEmail}'
                  : '$n invitations sent',
            );
          }
        } on Failure catch (f) {
          if (context.mounted) {
            showAppToast(context, f.message, icon: Icons.error_outline);
          }
        } finally {
          if (mounted) setState(() => _busy = false);
        }
      }

      Future<void> editEmail(Employee e) async {
        final email = await showDialog<String>(
          context: context,
          builder: (_) => _EmailDialog(employee: e),
        );
        if (email == null) return;
        await ref
            .read(employeesProvider.notifier)
            .save(
              e.copyWith(workEmail: email),
              notes: ['Work email corrected for the invitation'],
            );
        final fresh = ref
            .read(employeesProvider)
            .value!
            .firstWhere((x) => x.id == e.id);
        await resend([fresh]);
      }

      Future<void> revoke(Employee e) async {
        final ok = await showConfirmDialog(
          context,
          title: 'Revoke the invitation?',
          message:
              'The link to ${e.workEmail} stops working. ${e.firstName} keeps their employee record and can be invited again.',
          confirmLabel: 'Revoke',
          destructive: true,
        );
        if (!ok) return;
        await ref
            .read(employeesProvider.notifier)
            .save(
              e.copyWith(
                accountStatus: AccountStatus.noAccount,
                invitedAt: null,
              ),
              notes: ['Invitation revoked'],
            );
        await ref.read(accessServiceProvider).clearBounce(e.code);
        await ref
            .read(auditRecorderProvider)
            .record(
              action: 'invite.revoke',
              entityType: 'Invitation',
              entityId: e.id,
              entityLabel: e.fullName,
              branchId: e.branchId,
              summary: 'Invitation to ${e.workEmail} revoked',
            );
        if (context.mounted) showAppToast(context, 'Invitation revoked');
      }

      final f = DateFormat('d MMM');
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ResponsiveGrid(
            minItemWidth: 150,
            maxColumns: 4,
            children: [
              KpiCard(
                label: 'Waiting',
                value: '${count(_InviteState.waiting)}',
              ),
              KpiCard(
                label: 'Expired',
                value: '${count(_InviteState.expired)}',
                captionTone: StatusTone.warning,
              ),
              KpiCard(
                label: 'Not delivered',
                value: '${count(_InviteState.bounced)}',
              ),
              KpiCard(
                label: 'Accepted (30 days)',
                value: '${count(_InviteState.accepted)}',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            children: [
              SizedBox(
                width: 220,
                child: DashboardSelect<String>(
                  label: 'Status',
                  value: _filter,
                  options: const [
                    ('open', 'Not yet accepted'),
                    ('waiting', 'Waiting'),
                    ('expired', 'Expired'),
                    ('bounced', 'Not delivered'),
                    ('all', 'All, incl. accepted'),
                  ],
                  onChanged: (v) => setState(() => _filter = v ?? 'open'),
                ),
              ),
              if (canInvite)
                AppButton(
                  label: 'Resend all expired (${expired.length})',
                  variant: AppButtonVariant.secondary,
                  busy: _busy,
                  onPressed: expired.isEmpty ? null : () => resend(expired),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (rows.isEmpty)
            const AppCard(
              child: EmptyState(
                icon: Icons.mark_email_read_outlined,
                title: 'Nothing waiting',
                message: 'Every invitation has been accepted.',
              ),
            )
          else
            AppDataTable(
              minWidth: 980,
              columns: [
                const DataColumn(label: Text('Person')),
                const DataColumn(label: Text('Role · branch')),
                const DataColumn(label: Text('Invited')),
                const DataColumn(label: Text('Expires')),
                const DataColumn(label: Text('Status')),
                if (canInvite) const DataColumn(label: Text('Actions')),
              ],
              rows: [
                for (final (e, st) in rows)
                  DataRow(
                    cells: [
                      DataCell(_TwoLine(e.fullName, e.workEmail)),
                      DataCell(
                        Text(
                          '${scope.rows.where((r) => r.key == e.code).firstOrNull?.role.name ?? e.role.label} · ${scope.branchName(e.branchId)}',
                          style: AppTypography.small,
                        ),
                      ),
                      DataCell(
                        Text(
                          e.invitedAt == null ? '—' : f.format(e.invitedAt!),
                          style: AppTypography.small,
                        ),
                      ),
                      DataCell(
                        Text(
                          e.invitedAt == null
                              ? '—'
                              : f.format(
                                  e.invitedAt!.add(Duration(days: validDays)),
                                ),
                          style: AppTypography.small.copyWith(
                            color: st == _InviteState.expired
                                ? AppColors.warningText
                                : null,
                          ),
                        ),
                      ),
                      DataCell(
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            StatusBadge(
                              label: switch (st) {
                                _InviteState.waiting => 'Waiting',
                                _InviteState.expired => 'Expired',
                                _InviteState.bounced => 'Not delivered',
                                _InviteState.accepted => 'Accepted',
                              },
                              tone: switch (st) {
                                _InviteState.waiting => StatusTone.info,
                                _InviteState.expired => StatusTone.warning,
                                _InviteState.bounced => StatusTone.danger,
                                _InviteState.accepted => StatusTone.success,
                              },
                            ),
                            if (st == _InviteState.bounced)
                              Text(
                                scope.data.bounces[e.code]!.reason,
                                style: AppTypography.helper,
                              ),
                          ],
                        ),
                      ),
                      if (canInvite)
                        DataCell(
                          st == _InviteState.accepted
                              ? const SizedBox.shrink()
                              : Wrap(
                                  children: [
                                    TextButton(
                                      onPressed: _busy
                                          ? null
                                          : () => st == _InviteState.bounced
                                                ? editEmail(e)
                                                : resend([e]),
                                      child: Text(
                                        st == _InviteState.bounced
                                            ? 'Edit email'
                                            : 'Resend',
                                        semanticsLabel:
                                            '${st == _InviteState.bounced ? 'Edit email of' : 'Resend to'} ${e.fullName}',
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: _busy ? null : () => revoke(e),
                                      child: Text(
                                        'Revoke',
                                        semanticsLabel: 'Revoke ${e.fullName}',
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                    ],
                  ),
              ],
            ),
          const SizedBox(height: AppSpacing.sm),
          const Text(
            'People set their own password from the invitation link. Passwords are never shown or emailed.',
            style: AppTypography.helper,
          ),
        ],
      );
    },
  );
}

class _EmailDialog extends StatefulWidget {
  const _EmailDialog({required this.employee});

  final Employee employee;

  @override
  State<_EmailDialog> createState() => _EmailDialogState();
}

class _EmailDialogState extends State<_EmailDialog> {
  late final _email = TextEditingController(text: widget.employee.workEmail);
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Fix ${widget.employee.firstName}’s email'),
      content: SizedBox(
        width: 380,
        child: AppTextField(
          label: 'Work email',
          isRequired: true,
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          errorText: _error,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final v = _email.text.trim();
            if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v)) {
              setState(() => _error = 'Enter an email like name@company.in.');
              return;
            }
            Navigator.of(context).pop(v);
          },
          child: const Text('Save and resend'),
        ),
      ],
    );
  }
}
