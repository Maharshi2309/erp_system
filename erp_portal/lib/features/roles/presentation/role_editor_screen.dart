import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/router/route_names.dart';
import '../../../core/errors/failure.dart';
import '../../../core/permissions/permissions.dart';
import '../../../core/permissions/system_roles.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_dropdown_field.dart';
import '../../../core/widgets/app_overlays.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/selection_controls.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_badge.dart';
import '../../auth/presentation/widgets/confirm_password_dialog.dart';
import '../domain/access.dart';
import 'access_providers.dart';
import 'roles_section.dart';

/// Boards S68 (desktop matrix) and S69 (phone sections) — view, create or
/// edit a role.
class RoleEditorScreen extends ConsumerStatefulWidget {
  const RoleEditorScreen({super.key, this.roleId, this.fromId});

  /// Null for a new role.
  final String? roleId;

  /// Duplicate this role as the starting point.
  final String? fromId;

  @override
  ConsumerState<RoleEditorScreen> createState() => _RoleEditorScreenState();
}

class _RoleEditorScreenState extends ConsumerState<RoleEditorScreen> {
  RoleDefinition? _draft;
  RoleDefinition? _saved;
  final _name = TextEditingController();
  final _description = TextEditingController();
  Map<String, String> _errors = const {};
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  void _start(RolesScope scope) {
    if (_draft != null) return;
    final existing = widget.roleId == null
        ? null
        : scope.data.role(widget.roleId!);
    if (existing != null) {
      _saved = existing;
      _draft = existing;
    } else {
      final from =
          scope.data.role(widget.fromId ?? '') ??
          scope.data.role(SystemRole.employee.name)!;
      _draft = from.copyWith(
        id: '',
        name: widget.fromId == null ? '' : '${from.name} (copy)',
        kind: RoleKind.custom,
        base: from.isOwner ? SystemRole.hrAdmin : from.base,
        grants: PermissionSet({
          for (final p in from.grants.grants)
            if (!isOwnerOnly(p.module, p.action)) p,
        }),
        active: true,
      );
    }
    _name.text = _draft!.name;
    _description.text = _draft!.description;
  }

  RoleDefinition get _current =>
      _draft!.copyWith(name: _name.text, description: _description.text.trim());

  ({List<Permission> added, List<Permission> removed}) get _diff =>
      grantDiff(_saved?.grants ?? const PermissionSet.none(), _draft!.grants);

  int get _changeCount {
    if (_saved == null) return 0;
    final d = _diff;
    return d.added.length +
        d.removed.length +
        (_saved!.scope != _draft!.scope ? 1 : 0) +
        (_saved!.active != _draft!.active ? 1 : 0) +
        (_saved!.name != _name.text.trim() ? 1 : 0) +
        (_saved!.description != _description.text.trim() ? 1 : 0);
  }

  void _toggle(PermissionModule m, PermissionAction a, bool on) {
    final grants = {..._draft!.grants.grants};
    final p = Permission(m, a);
    if (on) {
      grants.add(p);
      // Doing anything with a module implies seeing it.
      grants.add(Permission(m, PermissionAction.view));
    } else {
      grants.remove(p);
      if (a == PermissionAction.view) {
        grants.removeWhere((x) => x.module == m);
      }
    }
    setState(() => _draft = _draft!.copyWith(grants: PermissionSet(grants)));
  }

  Future<void> _review(RolesScope scope) async {
    final role = _current;
    final errors = validateRole(role, scope.data.roles);
    setState(() => _errors = errors);
    if (errors.isNotEmpty) return;
    final holders = ref.read(accessServiceProvider).holders(role.id);
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _ReviewDialog(
        diff: _diff,
        scopeChange: _saved != null && _saved!.scope != role.scope
            ? '${scopeLabelOf(_saved!.scope)} → ${scopeLabelOf(role.scope)}'
            : null,
        holders: _saved == null ? const [] : holders,
        isNew: _saved == null,
      ),
    );
    if (reason == null || !mounted) return;
    if (!await confirmItsYou(context, why: 'change role permissions')) return;
    setState(() => _busy = true);
    try {
      final saved = await ref
          .read(accessServiceProvider)
          .saveRole(role, reason: reason);
      if (!mounted) return;
      showAppToast(
        context,
        _saved == null
            ? '${saved.name} created'
            : '${saved.name} saved · applies to ${holders.length} ${holders.length == 1 ? 'person' : 'people'} now',
      );
      setState(() {
        _saved = saved;
        _draft = saved;
      });
      if (widget.roleId == null) context.go(AppRoutes.role(saved.id));
    } on Failure catch (f) {
      if (mounted) {
        setState(
          () => _errors = f is ValidationFailure && f.fieldErrors.isNotEmpty
              ? f.fieldErrors
              : {'form': f.message},
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => RolesSection(
    current: AppRoutes.roles,
    tabs: false,
    body: (context, scope) {
      if (widget.roleId != null && scope.data.role(widget.roleId!) == null) {
        return const ErrorState(
          headline: '404',
          title: 'Role not found',
          message: 'It may have been removed.',
        );
      }
      _start(scope);
      final role = _draft!;
      final readOnly = role.isSystem || !scope.canEdit;
      final changes = _changeCount;
      final holders = scope.rows.where((r) => r.role.id == role.id).toList();
      final isNew = _saved == null;

      final header = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextButton.icon(
            onPressed: () => context.go(AppRoutes.roles),
            icon: const Icon(Icons.chevron_left),
            label: const Text('Roles & Permissions'),
          ),
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
                      isNew ? 'New role' : role.name,
                      style: AppTypography.pageTitle,
                    ),
                  ),
                  Text(
                    isNew
                        ? 'Works like ${role.base.label} · set what it can do below'
                        : [
                            role.isSystem ? 'System role' : 'Custom role',
                            'assigned to ${holders.length} ${holders.length == 1 ? 'person' : 'people'}',
                            if (role.updatedAt != null)
                              'last changed ${DateFormat('d MMM').format(role.updatedAt!)} by ${role.updatedBy}',
                          ].join(' · '),
                    style: AppTypography.small,
                  ),
                ],
              ),
              if (readOnly)
                Wrap(
                  spacing: AppSpacing.sm,
                  children: [
                    if (scope.canCreate && !role.isOwner)
                      AppButton(
                        label: 'Duplicate',
                        variant: AppButtonVariant.secondary,
                        onPressed: () =>
                            context.go('${AppRoutes.newRole}?from=${role.id}'),
                      ),
                  ],
                )
              else
                Wrap(
                  spacing: AppSpacing.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (changes > 0)
                      Text(
                        '$changes unsaved ${changes == 1 ? 'change' : 'changes'}',
                        style: AppTypography.small.copyWith(
                          color: AppColors.warningText,
                        ),
                      ),
                    AppButton(
                      label: 'Discard',
                      variant: AppButtonVariant.secondary,
                      onPressed: changes == 0 && !isNew
                          ? null
                          : () => isNew
                                ? context.go(AppRoutes.roles)
                                : setState(() {
                                    _draft = _saved;
                                    _name.text = _saved!.name;
                                    _description.text = _saved!.description;
                                    _errors = const {};
                                  }),
                    ),
                    AppButton(
                      label: isNew ? 'Review & create' : 'Review & save',
                      busy: _busy,
                      busyLabel: 'Saving…',
                      onPressed: changes == 0 && !isNew
                          ? null
                          : () => _review(scope),
                    ),
                  ],
                ),
            ],
          ),
        ],
      );

      final basics = AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (readOnly)
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                margin: const EdgeInsets.only(bottom: AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.neutralSoft,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Text(
                  role.isSystem
                      ? 'System roles can be viewed and duplicated but not edited.'
                      : 'Only the owner can change roles.',
                  style: AppTypography.small,
                ),
              ),
            if (_errors['form'] != null)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: Text(
                  _errors['form']!,
                  style: AppTypography.small.copyWith(color: AppColors.danger),
                ),
              ),
            if (!readOnly) ...[
              AppTextField(
                label: 'Role name',
                isRequired: true,
                controller: _name,
                maxLength: 40,
                errorText: _errors['name'],
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                label: 'Description',
                isOptional: true,
                controller: _description,
                maxLength: 120,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: AppSpacing.md),
              if (isNew)
                AppDropdownField<SystemRole>(
                  label: 'Works like',
                  helperText:
                      'Sets the menu and home page. Permissions below decide what it can do.',
                  value: role.base,
                  errorText: _errors['base'],
                  options: [
                    for (final r in SystemRole.values)
                      if (r != SystemRole.owner) AppDropdownOption(r, r.label),
                  ],
                  onChanged: (v) => setState(
                    () => _draft = role.copyWith(base: v ?? role.base),
                  ),
                )
              else
                Text(
                  'Works like ${role.base.label}',
                  style: AppTypography.small,
                ),
              const SizedBox(height: AppSpacing.md),
              SwitchRow(
                label: 'Active',
                description:
                    'Inactive roles can’t be given to anyone. People must be moved off it first.',
                value: role.active,
                onChanged: (v) =>
                    setState(() => _draft = role.copyWith(active: v)),
              ),
              const Divider(height: AppSpacing.xl),
            ],
            Semantics(
              header: true,
              child: const Text('Data scope', style: AppTypography.cardTitle),
            ),
            const Text(
              'Which records this role can reach',
              style: AppTypography.helper,
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final (s, hint) in const [
              (DataScope.organization, 'Every branch and employee'),
              (
                DataScope.assignedBranches,
                'Set per person when assigning the role',
              ),
              (DataScope.ownTeam, 'People who report to them'),
              (DataScope.ownRecords, 'Self-service access'),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: OptionCard(
                  title: scopeLabelOf(s),
                  description: hint,
                  selected: role.scope == s,
                  onTap: () {
                    if (!readOnly) {
                      setState(() => _draft = role.copyWith(scope: s));
                    }
                  },
                ),
              ),
          ],
        ),
      );

      final matrix = LayoutBuilder(
        builder: (context, c) => c.maxWidth >= 720
            ? _Matrix(
                role: role,
                saved: _saved,
                readOnly: readOnly,
                onToggle: _toggle,
                error: _errors['grants'],
              )
            : _Sections(
                role: role,
                saved: _saved,
                readOnly: readOnly,
                onToggle: _toggle,
              ),
      );

      final side = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!readOnly && !isNew && changes > 0) ...[
            AppCard(
              header: const CardHeader(title: 'Pending changes'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final p in _diff.added)
                    Text(
                      '+ ${permissionLabel(p)}',
                      style: AppTypography.small.copyWith(
                        color: AppColors.successText,
                      ),
                    ),
                  for (final p in _diff.removed)
                    Text(
                      '− ${permissionLabel(p)}',
                      style: AppTypography.small.copyWith(
                        color: AppColors.danger,
                      ),
                    ),
                  if (_saved!.scope != role.scope)
                    Text(
                      'Scope: ${scopeLabelOf(role.scope)}',
                      style: AppTypography.small,
                    ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    holders.isEmpty
                        ? 'Nobody has this role yet.'
                        : 'Applies immediately to ${holders.map((h) => h.name).take(5).join(', ')}${holders.length > 5 ? ' and ${holders.length - 5} more' : ''}. They’ll see the change on their next page.',
                    style: AppTypography.helper.copyWith(
                      color: AppColors.warningText,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          if (!isNew)
            AppCard(
              header: CardHeader(
                title: 'Assigned people',
                trailing: TextButton(
                  onPressed: () =>
                      context.go('${AppRoutes.people}?role=${role.id}'),
                  child: const Text('Manage'),
                ),
              ),
              child: holders.isEmpty
                  ? const Text('Nobody yet.', style: AppTypography.small)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final h in holders.take(8))
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Text(
                              '${h.name} · ${scope.scopeOf(h)}',
                              style: AppTypography.small.copyWith(
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                        if (holders.length > 8)
                          Text(
                            '+${holders.length - 8} more',
                            style: AppTypography.helper,
                          ),
                      ],
                    ),
            ),
        ],
      );

      return LayoutBuilder(
        builder: (context, c) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            const SizedBox(height: AppSpacing.lg),
            if (c.maxWidth >= 1100)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        basics,
                        const SizedBox(height: AppSpacing.lg),
                        matrix,
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  SizedBox(width: 320, child: side),
                ],
              )
            else ...[
              basics,
              const SizedBox(height: AppSpacing.lg),
              matrix,
              const SizedBox(height: AppSpacing.lg),
              side,
            ],
          ],
        ),
      );
    },
  );
}

String _action(PermissionAction a) =>
    '${a.name[0].toUpperCase()}${a.name.substring(1)}';

/// The desktop permission matrix (board S68).
class _Matrix extends StatelessWidget {
  const _Matrix({
    required this.role,
    required this.saved,
    required this.readOnly,
    required this.onToggle,
    this.error,
  });

  final RoleDefinition role;
  final RoleDefinition? saved;
  final bool readOnly;
  final void Function(PermissionModule, PermissionAction, bool) onToggle;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      header: const CardHeader(title: 'Permissions'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ExcludeSemantics(
            child: Wrap(
              spacing: AppSpacing.md,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Icon(Icons.check_box, size: 16, color: AppColors.primary),
                Text('Granted', style: AppTypography.helper),
                Icon(Icons.lock_outline, size: 16, color: AppColors.textMuted),
                Text(
                  'Owner only — can’t be delegated',
                  style: AppTypography.helper,
                ),
                Text('—  Not applicable', style: AppTypography.helper),
              ],
            ),
          ),
          if (error != null)
            Text(
              error!,
              style: AppTypography.small.copyWith(color: AppColors.danger),
            ),
          const SizedBox(height: AppSpacing.sm),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Table(
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              columnWidths: {
                0: const FixedColumnWidth(220),
                for (var i = 1; i <= PermissionAction.values.length; i++)
                  i: const FixedColumnWidth(78),
              },
              border: const TableBorder(
                horizontalInside: BorderSide(color: AppColors.divider),
              ),
              children: [
                TableRow(
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('Module', style: AppTypography.tableHeader),
                    ),
                    for (final a in PermissionAction.values)
                      Text(
                        _action(a),
                        textAlign: TextAlign.center,
                        style: AppTypography.tableHeader,
                      ),
                  ],
                ),
                for (final m in PermissionModule.values)
                  TableRow(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(m.label, style: AppTypography.bodyStrong),
                            Text(
                              moduleHints[m] ?? '',
                              style: AppTypography.helper,
                            ),
                          ],
                        ),
                      ),
                      for (final a in PermissionAction.values)
                        _Cell(
                          role: role,
                          saved: saved,
                          module: m,
                          action: a,
                          readOnly: readOnly,
                          onToggle: onToggle,
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.role,
    required this.saved,
    required this.module,
    required this.action,
    required this.readOnly,
    required this.onToggle,
  });

  final RoleDefinition role;
  final RoleDefinition? saved;
  final PermissionModule module;
  final PermissionAction action;
  final bool readOnly;
  final void Function(PermissionModule, PermissionAction, bool) onToggle;

  @override
  Widget build(BuildContext context) {
    final label = '${module.label}: ${_action(action)}';
    if (!isApplicable(module, action)) {
      return Semantics(
        label: '$label, not applicable',
        child: const ExcludeSemantics(
          child: Text(
            '—',
            textAlign: TextAlign.center,
            style: AppTypography.helper,
          ),
        ),
      );
    }
    final on = role.grants.can(module, action);
    if (isOwnerOnly(module, action) && !role.isOwner) {
      return Semantics(
        label: '$label, owner only',
        child: const ExcludeSemantics(
          child: Icon(Icons.lock_outline, size: 16, color: AppColors.textMuted),
        ),
      );
    }
    final changed = saved != null && saved!.grants.can(module, action) != on;
    return Container(
      color: changed ? const Color(0xFFFFF8EA) : null,
      child: Center(
        child: Checkbox(
          value: on,
          semanticLabel: label,
          onChanged: readOnly ? null : (v) => onToggle(module, action, v!),
        ),
      ),
    );
  }
}

/// Phone layout (board S69): one card per module with switches.
class _Sections extends StatelessWidget {
  const _Sections({
    required this.role,
    required this.saved,
    required this.readOnly,
    required this.onToggle,
  });

  final RoleDefinition role;
  final RoleDefinition? saved;
  final bool readOnly;
  final void Function(PermissionModule, PermissionAction, bool) onToggle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final m in PermissionModule.values)
          () {
            final actions = [
              for (final a in PermissionAction.values)
                if (isApplicable(m, a)) a,
            ];
            final allowed = actions.where((a) => role.grants.can(m, a)).length;
            final edited =
                saved != null &&
                actions.any(
                  (a) => saved!.grants.can(m, a) != role.grants.can(m, a),
                );
            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: AppCard(
                padding: EdgeInsets.zero,
                // Its own Material so the tile's ink shows on the card.
                child: Material(
                  type: MaterialType.transparency,
                  child: ExpansionTile(
                    title: Text(m.label, style: AppTypography.bodyStrong),
                    subtitle: Text(
                      '$allowed of ${actions.length} allowed',
                      style: AppTypography.helper,
                    ),
                    trailing: edited
                        ? const StatusBadge(
                            label: 'Edited',
                            tone: StatusTone.warning,
                          )
                        : null,
                    childrenPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                    ),
                    children: [
                      for (final a in actions)
                        isOwnerOnly(m, a) && !role.isOwner
                            ? SwitchRow(
                                label: _action(a),
                                value: false,
                                onChanged: null,
                                lockedNote: ' · owner only',
                              )
                            : SwitchRow(
                                label: _action(a),
                                value: role.grants.can(m, a),
                                onChanged: readOnly
                                    ? null
                                    : (v) => onToggle(m, a, v),
                              ),
                    ],
                  ),
                ),
              ),
            );
          }(),
      ],
    );
  }
}

class _ReviewDialog extends StatefulWidget {
  const _ReviewDialog({
    required this.diff,
    required this.scopeChange,
    required this.holders,
    required this.isNew,
  });

  final ({List<Permission> added, List<Permission> removed}) diff;
  final String? scopeChange;
  final List<String> holders;
  final bool isNew;

  @override
  State<_ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends State<_ReviewDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.diff;
    return AlertDialog(
      title: Text(widget.isNew ? 'Create this role?' : 'Review changes'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final p in d.added)
                Text('+ ${permissionLabel(p)}', style: AppTypography.small),
              for (final p in d.removed)
                Text('− ${permissionLabel(p)}', style: AppTypography.small),
              if (widget.scopeChange != null)
                Text(
                  'Scope: ${widget.scopeChange}',
                  style: AppTypography.small,
                ),
              const SizedBox(height: AppSpacing.md),
              if (widget.holders.isNotEmpty)
                Text(
                  'Applies immediately to ${widget.holders.length} ${widget.holders.length == 1 ? 'person' : 'people'}. Pages they have open re-check their access.',
                  style: AppTypography.small.copyWith(
                    color: AppColors.warningText,
                  ),
                ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                label: 'Reason',
                isOptional: true,
                controller: _reason,
                helperText: 'Kept in the audit log.',
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Back'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_reason.text.trim()),
          child: Text(widget.isNew ? 'Create role' : 'Save changes'),
        ),
      ],
    );
  }
}
