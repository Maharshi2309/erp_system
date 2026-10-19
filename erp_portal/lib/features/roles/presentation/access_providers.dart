import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/config/app_config.dart';
import '../../../app/router/route_names.dart';
import '../../../core/errors/failure.dart';
import '../../../core/permissions/permissions.dart';
import '../../../core/permissions/system_roles.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/zoned_time.dart';
import '../../audit/presentation/audit_providers.dart';
import '../../auth/domain/auth_state.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../../employees/domain/employee.dart';
import '../../employees/presentation/providers/employee_providers.dart';
import '../../organization/domain/organization.dart';
import '../data/demo_access_repository.dart';
import '../domain/access.dart';
import '../domain/access_repository.dart';

final accessRepositoryProvider = Provider<AccessRepository>(
  (ref) => DemoAccessRepository(
    latency: ref.watch(demoLatencyProvider),
    // The organization clock depends on the session, which depends on
    // access: use the app clock in the default zone (dates only).
    now: () => wallTime(ref.read(clockProvider)(), defaultTimeZone),
  ),
);

/// Roles and assignments of the signed-in organization. Reads the auth
/// state directly: [sessionProvider] depends on this provider.
final accessDataProvider = AsyncNotifierProvider<AccessNotifier, AccessData>(
  AccessNotifier.new,
);

class AccessNotifier extends AsyncNotifier<AccessData> {
  AccessRepository get _repo => ref.read(accessRepositoryProvider);
  String get _org =>
      (ref.read(authControllerProvider) as SignedIn).session.organizationId;

  @override
  Future<AccessData> build() async {
    final auth = ref.watch(authControllerProvider);
    if (auth is! SignedIn) throw const PermissionFailure();
    final org = auth.session.organizationId;
    final repo = ref.watch(accessRepositoryProvider);
    if (repo is DemoAccessRepository && !repo.isSeeded(org)) {
      repo.ensureSeeded(
        org,
        await ref.read(employeeRepositoryProvider).employees(org),
      );
    }
    return repo.load(org);
  }

  /// Re-reads roles and assignments after a change.
  Future<void> reload() async => state = AsyncData(await _repo.load(_org));
}

/// Changes to roles and assignments. Kept out of [AccessNotifier]: the
/// session depends on access data, so the notifier can't read anything
/// that depends on the session (employees, the session itself).
final accessServiceProvider = Provider<AccessService>(AccessService.new);

class AccessService {
  AccessService(this.ref);

  final Ref ref;

  AccessRepository get _repo => ref.read(accessRepositoryProvider);
  String get _org => ref.read(sessionProvider)!.organizationId;
  AccessData? get _data => ref.read(accessDataProvider).value;
  Future<void> _reload() => ref.read(accessDataProvider.notifier).reload();

  void _require(PermissionAction action) {
    final s = ref.read(sessionProvider);
    if (s == null || !s.permissions.can(PermissionModule.roles, action)) {
      throw const PermissionFailure('Only the owner can change roles.');
    }
  }

  /// People holding [roleId], by name.
  List<String> holders(String roleId) {
    final data = _data;
    if (data == null) return const [];
    final people = ref.read(employeesProvider).value ?? const <Employee>[];
    return [
      for (final a in data.assignments.values)
        if (a.roleId == roleId)
          people.where((e) => e.code == a.key).firstOrNull?.fullName ??
              data.members.where((m) => m.key == a.key).firstOrNull?.name ??
              a.key,
    ];
  }

  /// Saves a custom role (owner only, board S68). Applies at once to the
  /// people who hold it (D-53).
  Future<RoleDefinition> saveRole(
    RoleDefinition role, {
    String reason = '',
  }) async {
    _require(role.id.isEmpty ? PermissionAction.create : PermissionAction.edit);
    final before = role.id.isEmpty ? null : _data?.role(role.id);
    final saved = await _repo.saveRole(
      _org,
      role,
      by: ref.read(sessionProvider)!.displayName,
    );
    await _reload();
    final diff = grantDiff(
      before?.grants ?? const PermissionSet.none(),
      saved.grants,
    );
    await ref
        .read(auditRecorderProvider)
        .record(
          action: before == null ? 'role.create' : 'role.update',
          entityType: 'Role',
          entityId: saved.id,
          entityLabel: 'Role: ${saved.name}',
          entityRoute: AppRoutes.role(saved.id),
          summary: [
            if (before == null) 'Created ${saved.name}',
            if (diff.added.isNotEmpty)
              'Added ${diff.added.map(permissionLabel).join(', ')}',
            if (diff.removed.isNotEmpty)
              'removed ${diff.removed.map(permissionLabel).join(', ')}',
            if (before != null && before.scope != saved.scope)
              'scope ${scopeLabelOf(saved.scope)}',
            if (before != null && before.active != saved.active)
              saved.active ? 'reactivated' : 'deactivated',
          ].join('; '),
          reason: reason,
          changes: [
            for (final p in diff.added)
              (
                field: permissionLabel(p),
                before: 'Not allowed',
                after: 'Allowed',
              ),
            for (final p in diff.removed)
              (
                field: permissionLabel(p),
                before: 'Allowed',
                after: 'Not allowed',
              ),
            if (before != null && before.scope != saved.scope)
              (
                field: 'Data scope',
                before: scopeLabelOf(before.scope),
                after: scopeLabelOf(saved.scope),
              ),
          ],
          affected: [
            for (final name in holders(saved.id))
              '$name · sees the change on their next page',
          ],
        );
    return saved;
  }

  /// Gives [e] (or a member without an employee record, [key]) a role.
  /// The employee record follows so leave routing stays right (D-54).
  Future<RoleAssignment> assign({
    required String key,
    required String roleId,
    List<String> branchIds = const [],
    Employee? employee,
  }) async {
    _require(PermissionAction.edit);
    final saved = await _repo.assign(
      _org,
      RoleAssignment(key: key, roleId: roleId, branchIds: branchIds),
      by: ref.read(sessionProvider)!.displayName,
    );
    final role = _data?.role(roleId);
    final previous = _data?.role(
      _data?.assignments[key]?.roleId ?? employee?.role.name ?? '',
    );
    final name =
        employee?.fullName ??
        _data?.members.where((m) => m.key == key).firstOrNull?.name ??
        key;
    await ref
        .read(auditRecorderProvider)
        .record(
          action: 'role.assign',
          entityType: 'Member',
          entityId: key,
          entityLabel: name,
          entityRoute: employee == null
              ? null
              : AppRoutes.employee(employee.id),
          branchId: employee?.branchId,
          summary: '$name is now ${role?.name ?? roleId}',
          changes: [
            (
              field: 'Role',
              before: previous?.name ?? '—',
              after: role?.name ?? roleId,
            ),
            if (branchIds.isNotEmpty)
              (field: 'Branches', before: '—', after: branchIds.join(', ')),
          ],
        );
    if (employee != null && role != null) {
      final semantic =
          role.kind == RoleKind.custom &&
              (role.base == SystemRole.hrAdmin || role.base == SystemRole.owner)
          ? SystemRole.employee
          : role.base;
      if (employee.role != semantic) {
        await ref
            .read(employeesProvider.notifier)
            .save(
              employee.copyWith(role: semantic),
              notes: ['Role changed to ${role.name}'],
            );
      }
    }
    await _reload();
    return saved;
  }

  Future<void> clearBounce(String key) async {
    await _repo.clearBounce(_org, key);
    await _reload();
  }
}
