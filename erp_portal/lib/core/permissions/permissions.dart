import 'package:flutter/foundation.dart';

/// Permission modules, as grouped in the role editor (board S68) and PRD §11.
enum PermissionModule {
  organization('Organization & branches'),
  employees('Employees'),
  attendance('Attendance'),
  leave('Leave'),
  holidays('Holidays'),
  settings('Settings'),
  roles('Roles & permissions'),
  reports('Dashboard & reports'),
  importExport('Import & export'),
  auditLog('Audit log');

  const PermissionModule(this.label);

  final String label;
}

enum PermissionAction {
  view,
  create,
  edit,
  deactivate,
  approve,
  correct,
  export,
}

/// Which records a role reaches (PRD §3.1, board S68 "Data scope").
enum DataScope { organization, assignedBranches, ownTeam, ownRecords }

@immutable
class Permission {
  const Permission(this.module, this.action);

  final PermissionModule module;
  final PermissionAction action;

  @override
  bool operator ==(Object other) =>
      other is Permission && other.module == module && other.action == action;

  @override
  int get hashCode => Object.hash(module, action);

  /// PRD-style key, e.g. `employees.view`.
  @override
  String toString() => '${module.name}.${action.name}';
}

/// The permissions granted to the signed-in member.
///
/// The client uses this only to decide what to show. Every protected
/// operation must also be authorised by the backend (PRD §11); hiding a
/// button is never the security boundary.
@immutable
class PermissionSet {
  const PermissionSet(this.grants);

  const PermissionSet.none() : grants = const {};

  factory PermissionSet.all() => PermissionSet({
    for (final module in PermissionModule.values)
      for (final action in PermissionAction.values) Permission(module, action),
  });

  /// Grants every listed action on each listed module.
  factory PermissionSet.of(
    Map<PermissionModule, Iterable<PermissionAction>> modules,
  ) => PermissionSet({
    for (final entry in modules.entries)
      for (final action in entry.value) Permission(entry.key, action),
  });

  final Set<Permission> grants;

  bool can(PermissionModule module, PermissionAction action) =>
      grants.contains(Permission(module, action));

  bool canView(PermissionModule module) => can(module, PermissionAction.view);

  @override
  bool operator ==(Object other) =>
      other is PermissionSet && setEquals(other.grants, grants);

  @override
  int get hashCode => Object.hashAllUnordered(grants);
}
