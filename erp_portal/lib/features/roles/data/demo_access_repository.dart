import '../../../core/errors/failure.dart';
import '../../../core/permissions/permissions.dart';
import '../../../core/permissions/system_roles.dart';
import '../../employees/domain/employee.dart';
import '../domain/access.dart';
import '../domain/access_repository.dart';

/// DEMO ONLY — roles and assignments in memory, seeded from the employee
/// records and the demo owner account (boards S67–S71).
class DemoAccessRepository implements AccessRepository {
  DemoAccessRepository({
    this.latency = const Duration(milliseconds: 400),
    required this.now,
  });

  final Duration latency;
  final DateTime Function() now;
  final _orgs = <String, _Org>{};
  int _next = 1;

  Future<void> _delay() =>
      latency == Duration.zero ? Future.value() : Future.delayed(latency);

  bool isSeeded(String id) => _orgs.containsKey(id);

  static RoleDefinition _system(
    SystemRole r,
    String description, {
    RoleKind kind = RoleKind.system,
  }) => RoleDefinition(
    id: r.name,
    name: r.label,
    description: description,
    kind: kind,
    base: r,
    scope: r.scope,
    grants: PermissionSet({
      for (final p in r.permissions.grants)
        if (isApplicable(p.module, p.action) &&
            (r == SystemRole.owner || !isOwnerOnly(p.module, p.action)))
          p,
    }),
  );

  /// The roles every organization starts with.
  static List<RoleDefinition> defaultRoles(DateTime t) => [
    _system(
      SystemRole.owner,
      'Everything, including billing and deleting the organization',
    ),
    _system(
      SystemRole.hrAdmin,
      'People, attendance, leave, holidays and reports',
    ),
    _system(
      SystemRole.branchManager,
      'Runs one or more branches',
      kind: RoleKind.custom,
    ).copyWith(
      updatedAt: DateTime(t.year, t.month, t.day - 12, 10, 3),
      updatedBy: 'Ankit Patel',
    ),
    _system(
      SystemRole.attendanceManager,
      'Corrects attendance and exports it',
      kind: RoleKind.custom,
    ),
    _system(
      SystemRole.leaveApprover,
      'Given automatically to reporting managers',
    ),
    _system(SystemRole.employee, 'Self-service only'),
    RoleDefinition(
      id: 'payroll_viewer',
      name: 'Payroll viewer',
      description: 'Read-only attendance export for the accountant',
      kind: RoleKind.custom,
      base: SystemRole.hrAdmin,
      scope: DataScope.organization,
      grants: PermissionSet.of(const {
        PermissionModule.attendance: [
          PermissionAction.view,
          PermissionAction.export,
        ],
        PermissionModule.reports: [
          PermissionAction.view,
          PermissionAction.export,
        ],
      }),
      active: false,
    ),
  ];

  void ensureSeeded(String organizationId, List<Employee> employees) {
    if (_orgs.containsKey(organizationId)) return;
    final o = _orgs[organizationId] = _Org();
    final t = now();
    o.roles.addAll(defaultRoles(t));
    // The demo owner account owns Meridian only; in other organizations
    // the membership from sign-in applies.
    if (organizationId == 'org_meridian-tex') {
      o.members.add((
        key: 'u-ankit',
        name: 'Ankit Patel',
        email: 'ankit@meridiantex.in',
      ));
      o.assignments['u-ankit'] = const RoleAssignment(
        key: 'u-ankit',
        roleId: 'owner',
      );
    }
    for (final e in employees) {
      if (e.role == SystemRole.employee) continue;
      o.assignments[e.code] = RoleAssignment(
        key: e.code,
        roleId: e.role.name,
        // The demo attendance manager covers two branches.
        branchIds: e.role.scope != DataScope.assignedBranches
            ? const []
            : (e.code == 'EMP-0110' ? const ['b-sur', 'b-vad'] : [e.branchId]),
        teamSize: employees.where((x) => x.managerId == e.id).length,
      );
    }
    final invited = employees
        .where((e) => e.accountStatus == AccountStatus.invited)
        .toList();
    if (invited.length > 1) {
      o.bounces[invited[1].code] = (
        reason: 'Mail server rejected the address',
        at: DateTime(t.year, t.month, t.day - 2, 11, 20),
      );
    }
  }

  _Org _org(String id) => _orgs.putIfAbsent(id, _Org.new);

  @override
  Future<AccessData> load(String organizationId) async {
    await _delay();
    final o = _org(organizationId);
    return AccessData(
      roles: List.unmodifiable(o.roles),
      assignments: Map.unmodifiable(o.assignments),
      members: List.unmodifiable(o.members),
      bounces: Map.unmodifiable(o.bounces),
    );
  }

  @override
  Future<RoleDefinition> saveRole(
    String organizationId,
    RoleDefinition role, {
    required String by,
  }) async {
    await _delay();
    final o = _org(organizationId);
    final i = o.roles.indexWhere((r) => r.id == role.id);
    if (i >= 0 && o.roles[i].isSystem) {
      throw const PermissionFailure(
        'System roles can be viewed and duplicated but not edited.',
      );
    }
    final errors = validateRole(role, o.roles);
    if (errors.isNotEmpty) {
      throw ValidationFailure(errors.values.first, fieldErrors: errors);
    }
    if (i >= 0 &&
        !role.active &&
        o.roles[i].active &&
        o.assignments.values.any((a) => a.roleId == role.id)) {
      throw const ConflictFailure(
        'People still have this role. Give them another role first.',
      );
    }
    final saved = role.copyWith(
      id: role.id.isEmpty ? 'role_${_next++}' : role.id,
      kind: RoleKind.custom,
      name: role.name.trim(),
      updatedAt: now(),
      updatedBy: by,
    );
    if (i >= 0) {
      o.roles[i] = saved;
    } else {
      o.roles.add(saved);
    }
    return saved;
  }

  @override
  Future<RoleAssignment> assign(
    String organizationId,
    RoleAssignment assignment, {
    required String by,
  }) async {
    await _delay();
    final o = _org(organizationId);
    final role = o.roles.where((r) => r.id == assignment.roleId).firstOrNull;
    if (role == null) {
      throw const NotFoundFailure('That role no longer exists.');
    }
    if (!role.active) {
      throw const ConflictFailure('That role is inactive.');
    }
    final current = o.assignments[assignment.key];
    final owners = o.assignments.values.where((a) => a.roleId == 'owner');
    if (current?.roleId == 'owner' &&
        assignment.roleId != 'owner' &&
        owners.length <= 1) {
      throw const ConflictFailure(
        'This is the only owner. Make someone else an owner first.',
      );
    }
    if (role.scope == DataScope.assignedBranches &&
        assignment.branchIds.isEmpty) {
      throw const ValidationFailure(
        'Choose the branches.',
        fieldErrors: {'branches': 'Choose at least one branch.'},
      );
    }
    final saved = RoleAssignment(
      key: assignment.key,
      roleId: assignment.roleId,
      branchIds: role.scope == DataScope.assignedBranches
          ? assignment.branchIds
          : const [],
      teamSize: current?.teamSize ?? assignment.teamSize,
      changedAt: now(),
      changedBy: by,
    );
    o.assignments[assignment.key] = saved;
    return saved;
  }

  @override
  Future<void> clearBounce(String organizationId, String key) async {
    await _delay();
    _org(organizationId).bounces.remove(key);
  }
}

class _Org {
  final roles = <RoleDefinition>[];
  final assignments = <String, RoleAssignment>{};
  final members = <AccessMember>[];
  final bounces = <String, Bounce>{};
}
