import 'package:flutter/foundation.dart';

import '../../../core/permissions/permissions.dart';
import '../../../core/permissions/system_roles.dart';
import '../../../shared/models/app_session.dart';

/// Which cells of the permission matrix exist (board S68). Cells missing
/// here are "not applicable".
const applicableActions = <PermissionModule, Set<PermissionAction>>{
  PermissionModule.organization: {
    PermissionAction.view,
    PermissionAction.create,
    PermissionAction.edit,
    PermissionAction.deactivate,
    PermissionAction.export,
  },
  PermissionModule.employees: {
    PermissionAction.view,
    PermissionAction.create,
    PermissionAction.edit,
    PermissionAction.deactivate,
    PermissionAction.export,
  },
  PermissionModule.attendance: {
    PermissionAction.view,
    PermissionAction.approve,
    PermissionAction.correct,
    PermissionAction.export,
  },
  PermissionModule.leave: {
    PermissionAction.view,
    PermissionAction.create,
    PermissionAction.edit,
    PermissionAction.approve,
    PermissionAction.export,
  },
  PermissionModule.holidays: {
    PermissionAction.view,
    PermissionAction.create,
    PermissionAction.edit,
    PermissionAction.deactivate,
    PermissionAction.export,
  },
  PermissionModule.settings: {PermissionAction.view, PermissionAction.edit},
  PermissionModule.roles: {
    PermissionAction.view,
    PermissionAction.create,
    PermissionAction.edit,
    PermissionAction.deactivate,
  },
  PermissionModule.reports: {PermissionAction.view, PermissionAction.export},
  PermissionModule.importExport: {
    PermissionAction.view,
    PermissionAction.create,
    PermissionAction.export,
  },
  PermissionModule.auditLog: {PermissionAction.view, PermissionAction.export},
};

/// Cells only the owner holds; they can't be delegated (board S68 🔒).
final ownerOnly = {
  const Permission(PermissionModule.organization, PermissionAction.create),
  const Permission(PermissionModule.organization, PermissionAction.deactivate),
  const Permission(PermissionModule.roles, PermissionAction.create),
  const Permission(PermissionModule.roles, PermissionAction.edit),
  const Permission(PermissionModule.roles, PermissionAction.deactivate),
};

bool isApplicable(PermissionModule m, PermissionAction a) =>
    applicableActions[m]?.contains(a) ?? false;

bool isOwnerOnly(PermissionModule m, PermissionAction a) =>
    ownerOnly.contains(Permission(m, a));

/// One-line description of each module (board S68).
const moduleHints = <PermissionModule, String>{
  PermissionModule.organization: 'Profile, branch details',
  PermissionModule.employees: 'Directory, profiles, custom fields',
  PermissionModule.attendance: 'Records, missing punches',
  PermissionModule.leave: 'Requests, balances, adjustments',
  PermissionModule.holidays: 'Calendars and branch holidays',
  PermissionModule.settings: 'Policies, schedules, security',
  PermissionModule.roles: 'Role definitions and assignment',
  PermissionModule.reports: 'Analytics, report center',
  PermissionModule.importExport: 'Bulk employee and holiday files',
  PermissionModule.auditLog: 'Who changed what, and when',
};

String scopeLabelOf(DataScope s) => switch (s) {
  DataScope.organization => 'Organization-wide',
  DataScope.assignedBranches => 'Assigned branches',
  DataScope.ownTeam => 'Own team',
  DataScope.ownRecords => 'Own records',
};

enum RoleKind { system, custom }

/// A role (boards S67–S69). System roles can be viewed and duplicated, not
/// edited. A custom role "works like" one system role, which sets its menu,
/// home page and record-level behaviour; its matrix sets what it may do.
@immutable
class RoleDefinition {
  const RoleDefinition({
    required this.id,
    required this.name,
    required this.description,
    required this.kind,
    required this.base,
    required this.scope,
    required this.grants,
    this.active = true,
    this.updatedAt,
    this.updatedBy = '',
  });

  /// System and seeded roles use the [SystemRole] name as id.
  final String id;
  final String name;
  final String description;
  final RoleKind kind;
  final SystemRole base;
  final DataScope scope;
  final PermissionSet grants;
  final bool active;
  final DateTime? updatedAt;
  final String updatedBy;

  bool get isSystem => kind == RoleKind.system;
  bool get isOwner => id == SystemRole.owner.name;

  RoleDefinition copyWith({
    String? id,
    String? name,
    String? description,
    RoleKind? kind,
    SystemRole? base,
    DataScope? scope,
    PermissionSet? grants,
    bool? active,
    DateTime? updatedAt,
    String? updatedBy,
  }) => RoleDefinition(
    id: id ?? this.id,
    name: name ?? this.name,
    description: description ?? this.description,
    kind: kind ?? this.kind,
    base: base ?? this.base,
    scope: scope ?? this.scope,
    grants: grants ?? this.grants,
    active: active ?? this.active,
    updatedAt: updatedAt ?? this.updatedAt,
    updatedBy: updatedBy ?? this.updatedBy,
  );
}

/// The differences between two grant sets, for "Pending changes" and the
/// audit entry (boards S68, S78).
({List<Permission> added, List<Permission> removed}) grantDiff(
  PermissionSet before,
  PermissionSet after,
) => (
  added: [
    for (final p in after.grants)
      if (!before.grants.contains(p)) p,
  ]..sort(_byMatrix),
  removed: [
    for (final p in before.grants)
      if (!after.grants.contains(p)) p,
  ]..sort(_byMatrix),
);

int _byMatrix(Permission a, Permission b) => a.module.index != b.module.index
    ? a.module.index - b.module.index
    : a.action.index - b.action.index;

/// "Attendance · Correct".
String permissionLabel(Permission p) =>
    '${p.module.label.split(' &').first} · ${p.action.name[0].toUpperCase()}${p.action.name.substring(1)}';

/// Field errors for a custom role; empty when it can be saved.
Map<String, String> validateRole(RoleDefinition r, List<RoleDefinition> all) {
  final errors = <String, String>{};
  final name = r.name.trim();
  if (name.length < 2) {
    errors['name'] = 'Name the role.';
  } else if (all.any(
    (o) => o.id != r.id && o.name.toLowerCase() == name.toLowerCase(),
  )) {
    errors['name'] = 'Another role has this name.';
  }
  if (r.grants.grants.any((p) => isOwnerOnly(p.module, p.action))) {
    errors['grants'] = 'Owner-only permissions can’t be given to a role.';
  } else if (r.grants.grants.any((p) => !isApplicable(p.module, p.action))) {
    errors['grants'] = 'Some permissions don’t apply to their module.';
  }
  if (r.base == SystemRole.owner) {
    errors['base'] = 'Only the owner role works like the owner.';
  }
  return errors;
}

/// A member's role and, for branch-scoped roles, their branches.
@immutable
class RoleAssignment {
  const RoleAssignment({
    required this.key,
    required this.roleId,
    this.branchIds = const [],
    this.teamSize = 0,
    this.changedAt,
    this.changedBy = '',
  });

  /// Employee code, or account id for members without an employee record.
  final String key;
  final String roleId;
  final List<String> branchIds;

  /// For "Own team (6)".
  final int teamSize;
  final DateTime? changedAt;
  final String changedBy;
}

/// A member without an employee record (the owner).
typedef AccessMember = ({String key, String name, String email});

/// Why an invitation didn't arrive (board S71 "Not delivered").
typedef Bounce = ({String reason, DateTime at});

/// Roles, assignments and invitation delivery state (boards S67–S71).
@immutable
class AccessData {
  const AccessData({
    required this.roles,
    this.assignments = const {},
    this.members = const [],
    this.bounces = const {},
  });

  final List<RoleDefinition> roles;
  final Map<String, RoleAssignment> assignments;
  final List<AccessMember> members;

  /// Employee code → bounce.
  final Map<String, Bounce> bounces;

  RoleDefinition? role(String id) => roles.where((r) => r.id == id).firstOrNull;
}

/// The signed-in member's effective access: their assigned role's current
/// definition. Inactive roles fall back to Employee. This is how a
/// permission change reaches open sessions (D-53).
AppSession applyAccess(AppSession session, AccessData data) {
  final key = session.employeeId ?? session.userId;
  final assignment = data.assignments[key];
  final roleId = assignment?.roleId ?? session.role.name;
  var def = data.role(roleId);
  if (def == null) return session;
  if (!def.active) def = data.role(SystemRole.employee.name) ?? def;
  final branchIds = switch (def.scope) {
    DataScope.organization => const <String>[],
    DataScope.assignedBranches => assignment?.branchIds ?? session.branchIds,
    _ => session.branchIds,
  };
  return session.withAccess(
    role: def.base,
    roleId: def.id,
    roleTitle: def.name,
    grants: def.grants,
    scope: def.scope,
    branchIds: branchIds,
  );
}
