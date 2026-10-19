import 'package:flutter/foundation.dart';

import '../../core/permissions/permissions.dart';
import '../../core/permissions/system_roles.dart';

/// The signed-in member of one organization.
@immutable
class AppSession {
  const AppSession({
    required this.userId,
    required this.displayName,
    required this.email,
    required this.organizationId,
    required this.organizationName,
    required this.role,
    this.scopeLabel = '',
    this.canSwitchOrganization = false,
    this.branchIds = const [],
    this.employeeId,
    this.roleId,
    this.roleTitle,
    this.grants,
    this.scopeOverride,
  });

  final String userId;
  final String displayName;
  final String email;
  final String organizationId;
  final String organizationName;
  final SystemRole role;

  /// Where the role applies, e.g. "all branches", "Surat".
  final String scopeLabel;

  /// True when the member belongs to more than one organization.
  final bool canSwitchOrganization;

  /// Branches this member's role covers; empty means every branch.
  final List<String> branchIds;

  /// The member's own employee code (e.g. EMP-0229), when they have one.
  final String? employeeId;

  /// The role definition behind this session (Phase 7); null until roles
  /// load, when the built-in defaults of [role] apply.
  final String? roleId;
  final String? roleTitle;
  final PermissionSet? grants;
  final DataScope? scopeOverride;

  /// Can this member see records of [branchId]?
  bool coversBranch(String branchId) =>
      branchIds.isEmpty || branchIds.contains(branchId);

  String get roleName => roleTitle ?? role.label;
  DataScope get scope => scopeOverride ?? role.scope;
  PermissionSet get permissions => grants ?? role.permissions;

  /// The same session under a (re)assigned role definition.
  AppSession withAccess({
    required SystemRole role,
    required String roleId,
    required String roleTitle,
    required PermissionSet grants,
    required DataScope scope,
    required List<String> branchIds,
  }) => AppSession(
    userId: userId,
    displayName: displayName,
    email: email,
    organizationId: organizationId,
    organizationName: organizationName,
    role: role,
    scopeLabel: scopeLabel,
    canSwitchOrganization: canSwitchOrganization,
    branchIds: branchIds,
    employeeId: employeeId,
    roleId: roleId,
    roleTitle: roleTitle,
    grants: grants,
    scopeOverride: scope,
  );

  @override
  bool operator ==(Object other) =>
      other is AppSession &&
      other.userId == userId &&
      other.organizationId == organizationId &&
      other.role == role &&
      other.roleId == roleId &&
      other.roleTitle == roleTitle &&
      other.grants == grants &&
      other.scopeOverride == scopeOverride &&
      listEquals(other.branchIds, branchIds) &&
      other.scopeLabel == scopeLabel &&
      other.employeeId == employeeId &&
      other.canSwitchOrganization == canSwitchOrganization &&
      other.displayName == displayName;

  @override
  int get hashCode => Object.hash(
    userId,
    organizationId,
    role,
    roleId,
    grants,
    scopeOverride,
    Object.hashAll(branchIds),
  );
}
