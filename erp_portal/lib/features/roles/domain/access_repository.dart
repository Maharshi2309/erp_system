import 'access.dart';

/// Roles and who holds them (boards S67–S71). The backend must apply the
/// same rules: system roles are read-only, owner-only permissions can't be
/// granted, and the last owner can't lose the role.
abstract interface class AccessRepository {
  Future<AccessData> load(String organizationId);

  /// Creates (empty id) or updates a custom role.
  Future<RoleDefinition> saveRole(
    String organizationId,
    RoleDefinition role, {
    required String by,
  });

  Future<RoleAssignment> assign(
    String organizationId,
    RoleAssignment assignment, {
    required String by,
  });

  /// After an address is fixed or the invitation is resent.
  Future<void> clearBounce(String organizationId, String key);
}
