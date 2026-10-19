import 'package:erp_portal/core/errors/failure.dart';
import 'package:erp_portal/core/permissions/permissions.dart';
import 'package:erp_portal/core/permissions/system_roles.dart';
import 'package:erp_portal/features/audit/data/demo_audit_repository.dart';
import 'package:erp_portal/features/audit/domain/audit.dart';
import 'package:erp_portal/features/employees/domain/employee.dart';
import 'package:erp_portal/features/notifications/domain/notifications.dart';
import 'package:erp_portal/features/organization/domain/branch.dart';
import 'package:erp_portal/features/reports/domain/reports.dart';
import 'package:erp_portal/features/roles/data/demo_access_repository.dart';
import 'package:erp_portal/features/roles/domain/access.dart';
import 'package:erp_portal/features/settings/domain/settings.dart';
import 'package:erp_portal/shared/models/app_session.dart';
import 'package:flutter_test/flutter_test.dart';

final now = DateTime(2026, 10, 14, 14, 10);

AppSession session(
  SystemRole role, {
  String? employeeId,
  List<String> branchIds = const [],
}) => AppSession(
  userId: 'u-${role.name}',
  displayName: role.label,
  email: '${role.name}@x.in',
  organizationId: 'org',
  organizationName: 'Org',
  role: role,
  employeeId: employeeId,
  branchIds: branchIds,
);

Employee person(
  String code, {
  SystemRole role = SystemRole.employee,
  String branch = 'b-sur',
  AccountStatus account = AccountStatus.signedIn,
}) => Employee(
  id: 'e-$code',
  organizationId: 'org',
  code: code,
  firstName: 'P',
  lastName: code,
  workEmail: '$code@x.in',
  personalEmail: '$code@gmail.com',
  mobile: '+91 98250 14417',
  designation: 'Operator',
  department: 'Production',
  type: EmploymentType.fullTime,
  joiningDate: DateTime(2024),
  branchId: branch,
  shift: 'General',
  role: role,
  accountStatus: account,
);

Branch branch(String id, String name) => Branch(
  id: id,
  name: name,
  address: 'x',
  city: 'x',
  state: 'Gujarat',
  pin: '380001',
  hours: HoursPresets.monSat930,
);

void main() {
  group('roles and effective access', () {
    final roles = DemoAccessRepository.defaultRoles(now);
    RoleDefinition role(String id) => roles.firstWhere((r) => r.id == id);

    test('system roles keep the built-in grants', () {
      // Every applicable cell of the matrix.
      expect(role('owner').grants.grants.length, 37);
      expect(
        role(
          'hrAdmin',
        ).grants.can(PermissionModule.roles, PermissionAction.view),
        isFalse,
      );
      expect(role('branchManager').isSystem, isFalse);
      expect(role('payroll_viewer').active, isFalse);
    });

    test('the session takes the assigned role’s current definition', () {
      final edited = role('branchManager').copyWith(
        grants: PermissionSet.of(const {
          PermissionModule.leave: [PermissionAction.view],
        }),
      );
      final data = AccessData(
        roles: [for (final r in roles) r.id == edited.id ? edited : r],
        assignments: const {
          'EMP-0102': RoleAssignment(
            key: 'EMP-0102',
            roleId: 'branchManager',
            branchIds: ['b-sur'],
          ),
        },
      );
      final s = applyAccess(
        session(SystemRole.branchManager, employeeId: 'EMP-0102'),
        data,
      );
      expect(
        s.permissions.can(PermissionModule.leave, PermissionAction.approve),
        isFalse,
      );
      expect(s.permissions.canView(PermissionModule.leave), isTrue);
      expect(s.branchIds, ['b-sur']);
      expect(s.roleName, 'Branch Manager');
    });

    test('a reassigned role changes menus, scope and permissions', () {
      final data = AccessData(
        roles: roles,
        assignments: const {
          'EMP-0201': RoleAssignment(key: 'EMP-0201', roleId: 'employee'),
        },
      );
      final s = applyAccess(
        session(SystemRole.leaveApprover, employeeId: 'EMP-0201'),
        data,
      );
      expect(s.role, SystemRole.employee);
      expect(s.scope, DataScope.ownRecords);
      expect(s.permissions.canView(PermissionModule.leave), isFalse);
    });

    test('an inactive role falls back to Employee', () {
      final data = AccessData(
        roles: roles,
        assignments: const {
          'EMP-1': RoleAssignment(key: 'EMP-1', roleId: 'payroll_viewer'),
        },
      );
      final s = applyAccess(
        session(SystemRole.employee, employeeId: 'EMP-1'),
        data,
      );
      expect(s.roleName, 'Employee');
    });

    test('organization-wide roles clear branch limits', () {
      final data = AccessData(
        roles: roles,
        assignments: const {
          'EMP-1': RoleAssignment(key: 'EMP-1', roleId: 'hrAdmin'),
        },
      );
      final s = applyAccess(
        session(
          SystemRole.branchManager,
          employeeId: 'EMP-1',
          branchIds: ['b-sur'],
        ),
        data,
      );
      expect(s.branchIds, isEmpty);
      expect(s.permissions.canView(PermissionModule.auditLog), isTrue);
    });

    test('custom roles can’t hold owner-only permissions', () {
      final bad = role('branchManager').copyWith(
        grants: PermissionSet({
          ...role('branchManager').grants.grants,
          const Permission(PermissionModule.roles, PermissionAction.edit),
        }),
      );
      expect(validateRole(bad, roles)['grants'], isNotNull);
      final dup = bad.copyWith(
        id: 'x',
        name: 'hr admin',
        grants: const PermissionSet.none(),
      );
      expect(validateRole(dup, roles)['name'], 'Another role has this name.');
      expect(
        validateRole(
          dup.copyWith(name: 'New', base: SystemRole.owner),
          roles,
        )['base'],
        isNotNull,
      );
    });

    test('pending changes are listed by module and action', () {
      final d = grantDiff(
        PermissionSet.of(const {
          PermissionModule.employees: [PermissionAction.deactivate],
        }),
        PermissionSet.of(const {
          PermissionModule.attendance: [PermissionAction.correct],
        }),
      );
      expect(d.added.map(permissionLabel), ['Attendance · Correct']);
      expect(d.removed.map(permissionLabel), ['Employees · Deactivate']);
    });
  });

  group('access repository', () {
    late DemoAccessRepository repo;
    setUp(() {
      repo = DemoAccessRepository(latency: Duration.zero, now: () => now)
        ..ensureSeeded('org_meridian-tex', [
          person('EMP-0102', role: SystemRole.branchManager),
          person('EMP-0105', role: SystemRole.hrAdmin),
          person('EMP-0300', account: AccountStatus.invited),
          person('EMP-0301', account: AccountStatus.invited),
        ]);
    });
    const org = 'org_meridian-tex';

    test('seeds the owner and everyone above Employee', () async {
      final d = await repo.load(org);
      expect(d.assignments['u-ankit']!.roleId, 'owner');
      expect(d.assignments['EMP-0102']!.branchIds, ['b-sur']);
      expect(d.bounces.keys, ['EMP-0301']);
    });

    test('system roles are read-only', () async {
      final hr = (await repo.load(org)).role('hrAdmin')!;
      await expectLater(
        repo.saveRole(org, hr.copyWith(name: 'People team'), by: 'A'),
        throwsA(isA<PermissionFailure>()),
      );
    });

    test('custom roles save; roles in use can’t be switched off', () async {
      final bm = (await repo.load(org)).role('branchManager')!;
      final saved = await repo.saveRole(
        org,
        bm.copyWith(description: 'x'),
        by: 'Ankit',
      );
      expect(saved.updatedBy, 'Ankit');
      await expectLater(
        repo.saveRole(org, bm.copyWith(active: false), by: 'Ankit'),
        throwsA(isA<ConflictFailure>()),
      );
      final created = await repo.saveRole(
        org,
        bm.copyWith(id: '', name: 'Night supervisor'),
        by: 'Ankit',
      );
      expect(created.id, startsWith('role_'));
      expect(created.kind, RoleKind.custom);
    });

    test('the last owner keeps the role', () async {
      await expectLater(
        repo.assign(
          org,
          const RoleAssignment(key: 'u-ankit', roleId: 'hrAdmin'),
          by: 'A',
        ),
        throwsA(isA<ConflictFailure>()),
      );
      await repo.assign(
        org,
        const RoleAssignment(key: 'EMP-0105', roleId: 'owner'),
        by: 'A',
      );
      final ok = await repo.assign(
        org,
        const RoleAssignment(key: 'u-ankit', roleId: 'hrAdmin'),
        by: 'A',
      );
      expect(ok.roleId, 'hrAdmin');
    });

    test('branch roles need branches; inactive roles can’t be given', () async {
      await expectLater(
        repo.assign(
          org,
          const RoleAssignment(key: 'EMP-0300', roleId: 'branchManager'),
          by: 'A',
        ),
        throwsA(isA<ValidationFailure>()),
      );
      await expectLater(
        repo.assign(
          org,
          const RoleAssignment(key: 'EMP-0300', roleId: 'payroll_viewer'),
          by: 'A',
        ),
        throwsA(isA<ConflictFailure>()),
      );
    });

    test('other organizations don’t get the demo owner', () async {
      repo.ensureSeeded('org_other', const []);
      expect((await repo.load('org_other')).assignments, isEmpty);
    });
  });

  group('audit trail', () {
    test('entries are sealed in a checksum chain', () async {
      final repo = DemoAuditRepository(latency: Duration.zero, now: () => now);
      await repo.record(
        'o',
        AuditEvent(
          id: '',
          at: now,
          actorName: 'Hetal',
          actorRole: 'HR Admin',
          action: 'leave.approve',
          entityType: 'Leave request',
          entityLabel: 'Leave #L-1',
          summary: 'Approved',
        ),
      );
      final chain = repo.chain('o');
      expect(verifyAuditChain(chain), isTrue);
      expect(chain.last.previousHash, chain[chain.length - 2].hash);
      // Any edit is detectable.
      final tampered = [
        ...chain.take(chain.length - 1),
        AuditEvent(
          id: chain.last.id,
          at: chain.last.at,
          actorName: chain.last.actorName,
          actorRole: chain.last.actorRole,
          action: chain.last.action,
          entityType: chain.last.entityType,
          entityLabel: chain.last.entityLabel,
          summary: 'Rejected',
          previousHash: chain.last.previousHash,
          hash: chain.last.hash,
        ),
      ];
      expect(verifyAuditChain(tampered), isFalse);
    });

    test('sensitive values are masked', () {
      expect(
        maskValue('Personal email', 'isha.rathod@gmail.com'),
        'is••••@gmail.com',
      );
      expect(maskValue('Mobile', '+91 98250 14417'), '+91 98•• ••4417');
      expect(maskValue('IP address', '103.21.58.14'), '103.21.••.••');
      expect(maskValue('Date of birth', '1998-02-01'), 'Restricted');
      expect(maskValue('Password', 'secret'), '••••••••');
      expect(shownValue('Branch', 'Surat'), 'Surat');
      expect(shownValue('Mobile', '9825014417'), '98•• ••4417');
    });

    test('filters by period, actor, area, entity, branch and text', () {
      final e = AuditEvent(
        id: 'evt_1',
        at: now.subtract(const Duration(days: 3)),
        actorName: 'Hetal Shah',
        actorRole: 'HR Admin',
        action: 'employee.update',
        entityType: 'Employee',
        entityLabel: 'Isha Rathod',
        branchId: 'b-sur',
        summary: 'Mobile updated',
      );
      expect(const AuditQuery().matches(e, now), isTrue);
      expect(const AuditQuery(days: 1).matches(e, now), isFalse);
      expect(const AuditQuery(actor: 'Ankit Patel').matches(e, now), isFalse);
      expect(const AuditQuery(areas: {'employee'}).matches(e, now), isTrue);
      expect(const AuditQuery(areas: {'leave'}).matches(e, now), isFalse);
      expect(const AuditQuery(branchId: 'b-ahm').matches(e, now), isFalse);
      expect(const AuditQuery(search: 'mobile').matches(e, now), isTrue);
      expect(const AuditQuery(entityType: 'Role').matches(e, now), isFalse);
    });
  });

  group('notification preferences', () {
    test('defaults follow the design matrix', () {
      const p = NotificationPrefs();
      expect(
        p.isOn(NotifyEvent.leaveSubmitted, Recipient.manager, Channel.inApp),
        isTrue,
      );
      expect(
        p.isOn(NotifyEvent.leaveSubmitted, Recipient.employee, Channel.inApp),
        isFalse,
      );
      expect(
        NotifyEvent.leaveSubmitted.applies(Recipient.employee, Channel.inApp),
        isFalse,
      );
      expect(
        p.isOn(NotifyEvent.invitation, Recipient.employee, Channel.email),
        isTrue,
      );
    });

    test('locked and not-applicable switches can’t change', () {
      const p = NotificationPrefs();
      final locked = p.toggled(
        NotifyEvent.invitation,
        Recipient.employee,
        Channel.email,
      );
      expect(
        locked.isOn(NotifyEvent.invitation, Recipient.employee, Channel.email),
        isTrue,
      );
      final off = p.toggled(
        NotifyEvent.leaveDecided,
        Recipient.employee,
        Channel.inApp,
      );
      expect(
        off.isOn(NotifyEvent.leaveDecided, Recipient.employee, Channel.inApp),
        isFalse,
      );
      expect(off.onCount, p.onCount - 1);
    });
  });

  group('settings', () {
    test('two-step policy', () {
      expect(TwoStepPolicy.optional.requires(SystemRole.owner), isFalse);
      expect(TwoStepPolicy.admins.requires(SystemRole.branchManager), isTrue);
      expect(TwoStepPolicy.admins.requires(SystemRole.employee), isFalse);
      expect(TwoStepPolicy.everyone.requires(SystemRole.employee), isTrue);
      expect(
        validateSecurity(const SecuritySettings(minPasswordLength: 6)),
        isNotEmpty,
      );
    });

    test('export rights and formats', () {
      const d = DataSettings();
      expect(d.canExport(SystemRole.owner, ExportArea.restricted), isTrue);
      expect(
        d.canExport(SystemRole.branchManager, ExportArea.restricted),
        isFalse,
      );
      expect(
        d.canExport(SystemRole.attendanceManager, ExportArea.leave),
        isFalse,
      );
      expect(DurationStyle.decimal.format(484), '8.07');
      expect(DurationStyle.hoursMinutes.format(484), '8:04');
    });

    test('brand color contrast', () {
      expect(contrastWithWhite(0xFF2B4ACB), greaterThan(4.5));
      expect(contrastWithWhite(0xFFF2B84B), lessThan(3));
    });
  });

  group('reports', () {
    final people = [person('EMP-1'), person('EMP-2', branch: 'b-ahm')];
    final branches = [
      branch('b-sur', 'Surat'),
      branch('b-ahm', 'Ahmedabad HQ'),
    ];
    ReportSources sources([DataSettings format = const DataSettings()]) => (
      people: people,
      branches: branches,
      attendance: null,
      leave: null,
      audit: [
        AuditEvent(
          id: 'evt_1',
          at: now,
          actorName: 'Hetal',
          actorRole: 'HR Admin',
          action: 'employee.update',
          entityType: 'Employee',
          entityId: 'e-EMP-1',
          entityLabel: 'P EMP-1',
          summary: 'Mobile updated',
          changes: const [
            (
              field: 'Mobile',
              before: '+91 98250 14417',
              after: '+91 98790 24417',
            ),
          ],
        ),
      ],
      holidays: const [],
      format: format,
    );
    ReportFilter f(ReportKind k, {String? branchId, Set<String>? cols}) =>
        ReportFilter(
          kind: k,
          from: DateTime(2026, 10, 1),
          to: DateTime(2026, 10, 14),
          branchId: branchId,
          columns: cols ?? {for (final c in k.columns) c.key},
        );

    test('who may run and export', () {
      const data = DataSettings();
      expect(
        reportBlock(ReportKind.roster, session(SystemRole.employee), data),
        isNotNull,
      );
      expect(
        reportBlock(ReportKind.audit, session(SystemRole.branchManager), data),
        'Owner and HR Admin only',
      );
      expect(
        reportBlock(
          ReportKind.monthly,
          session(SystemRole.branchManager),
          data,
          export: true,
        ),
        isNull,
      );
      final off = data.copyWith(
        exportRights: {
          ...data.exportRights,
          SystemRole.branchManager: {ExportArea.people},
        },
      );
      expect(
        reportBlock(
          ReportKind.monthly,
          session(SystemRole.branchManager),
          off,
          export: true,
        ),
        'Exports of attendance are turned off for your role',
      );
      expect(
        reportBlock(
          ReportKind.roster,
          session(SystemRole.attendanceManager),
          data,
        ),
        isNotNull,
      );
    });

    test('restricted columns need the right and organization scope', () {
      final s = buildReport(
        f(ReportKind.roster),
        sources(),
        session(SystemRole.hrAdmin),
      );
      expect(s.headers, contains('Personal email'));
      final bm = buildReport(
        f(ReportKind.roster),
        sources(),
        session(SystemRole.branchManager, branchIds: ['b-sur']),
      );
      expect(bm.headers, isNot(contains('Personal email')));
      expect(bm.headers, isNot(contains('Mobile')));
    });

    test('branch filter and always-included columns', () {
      final t = buildReport(
        f(ReportKind.roster, branchId: 'b-ahm', cols: {}),
        sources(),
        session(SystemRole.hrAdmin),
      );
      expect(t.headers, ['Employee ID', 'Name']);
      expect(t.rows.single.first, 'EMP-2');
    });

    test('the audit report masks sensitive values', () {
      final t = buildReport(
        f(ReportKind.audit),
        sources(),
        session(SystemRole.owner),
      );
      expect(t.rows.single.last, 'Mobile: +91 98•• ••4417 → +91 98•• ••4417');
    });

    test('file dates follow the data settings', () {
      final iso = buildReport(
        f(ReportKind.changes),
        sources(const DataSettings(dateFormat: FileDateFormat.iso)),
        session(SystemRole.hrAdmin),
      );
      expect(iso.rows.single.first, '2026-10-14');
    });

    test('filters describe themselves and round-trip', () {
      final x = f(ReportKind.monthly, branchId: 'b-sur');
      expect(x.describe(branches), '1 Oct 2026 – 14 Oct 2026 · Surat');
      expect(x.toQuery()['report'], 'monthly');
    });
  });
}
