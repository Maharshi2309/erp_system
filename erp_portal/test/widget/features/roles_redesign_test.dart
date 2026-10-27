// D-79: roles and permissions in plain words — levels per area, a live
// summary, role cards, comparison and templates.
import 'package:erp_portal/app/router/route_names.dart';
import 'package:erp_portal/core/permissions/permissions.dart';
import 'package:erp_portal/core/permissions/system_roles.dart';
import 'package:erp_portal/features/roles/domain/access.dart';
import 'package:erp_portal/features/roles/domain/access_levels.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_helpers/pump_app.dart';
import 'phase7_screens_test.dart' show tapSemantics;

RoleDefinition _role(SystemRole r) => RoleDefinition(
  id: r.name,
  name: r.label,
  description: '',
  kind: RoleKind.system,
  base: r,
  scope: r.scope,
  grants: r.permissions,
);

void main() {
  group('levels', () {
    test('built-in roles read as plain levels', () {
      final hr = SystemRole.hrAdmin.permissions;
      expect(levelOf(hr, PermissionModule.employees), AccessLevel.full);
      expect(levelOf(hr, PermissionModule.organization), AccessLevel.view);
      expect(levelOf(hr, PermissionModule.roles), AccessLevel.none);

      final la = SystemRole.leaveApprover.permissions;
      expect(levelOf(la, PermissionModule.leave), AccessLevel.view);
      expect(isPlainLevel(la, PermissionModule.leave), isTrue);

      // Branch manager leave: view, apply, approve, export — no rule edits.
      final bm = SystemRole.branchManager.permissions;
      expect(levelOf(bm, PermissionModule.leave), AccessLevel.edit);
      expect(isPlainLevel(bm, PermissionModule.leave), isFalse);
    });

    test('changing a level keeps the switches and clears with No access', () {
      var g = SystemRole.leaveApprover.permissions;
      g = withLevel(g, PermissionModule.leave, AccessLevel.edit);
      expect(g.can(PermissionModule.leave, PermissionAction.approve), isTrue);
      expect(g.can(PermissionModule.leave, PermissionAction.edit), isTrue);
      g = withLevel(g, PermissionModule.leave, AccessLevel.none);
      expect(
        g.grants.where((p) => p.module == PermissionModule.leave),
        isEmpty,
      );
      g = withLevel(g, PermissionModule.reports, AccessLevel.full);
      expect(g.can(PermissionModule.reports, PermissionAction.export), isTrue);
    });

    test('owner-only abilities are never given by a level', () {
      final g = withLevel(
        const PermissionSet.none(),
        PermissionModule.roles,
        AccessLevel.full,
      );
      expect(g.can(PermissionModule.roles, PermissionAction.edit), isFalse);
      expect(levelsFor(PermissionModule.roles), [
        AccessLevel.none,
        AccessLevel.view,
      ]);
    });

    test('the summary speaks plainly', () {
      final s = plainSummary(_role(SystemRole.leaveApprover));
      expect(s.sees, 'They see the people who report to them.');
      expect(s.can, contains('Approve or reject leave'));
      expect(s.cannot, contains('Company settings'));
    });
  });

  testWidgets('roles show as cards, and can be compared', (tester) async {
    await pumpStafflineApp(
      tester,
      size: const Size(1440, 1600),
      location: AppRoutes.roles,
    );
    expect(find.text('Sees: Chosen branches'), findsWidgets);
    expect(find.text('Leave · Can view'), findsWidgets);
    await tapText(tester, 'Compare roles');
    expect(find.text('Whose information'), findsOneWidget);
    expect(find.text('Company settings'), findsOneWidget);
  });

  testWidgets('create a role from a template', (tester) async {
    final c = await pumpStafflineApp(
      tester,
      size: const Size(1440, 1600),
      location: AppRoutes.roles,
    );
    await tapText(tester, 'Create role');
    expect(find.text('Start a new role'), findsOneWidget);
    await tapText(tester, 'Like Branch Manager');
    expect(currentUri(c).toString(), '${AppRoutes.newRole}?from=branchManager');
    expect(find.text('Branch Manager (copy)'), findsOneWidget);
  });

  testWidgets('a level change updates the plain summary', (tester) async {
    await pumpStafflineApp(
      tester,
      size: const Size(1440, 2400),
      location: AppRoutes.role('branchManager'),
    );
    expect(find.text('In plain words'), findsOneWidget);
    expect(
      find.text('Change attendance, notification and branding settings'),
      findsNothing,
    );
    await tapSemantics(tester, 'Company settings: Can edit');
    expect(
      find.text('Change attendance, notification and branding settings'),
      findsWidgets,
    );
    expect(
      find.text('+ Change attendance, notification and branding settings'),
      findsOneWidget,
    );
    await tapText(tester, 'Show detailed table');
    expect(find.text('Detailed table'), findsOneWidget);
  });

  testWidgets('changing someone’s role shows what they’ll be able to do', (
    tester,
  ) async {
    await pumpStafflineApp(
      tester,
      size: const Size(1440, 1600),
      location: AppRoutes.people,
    );
    await tapSemantics(tester, 'Change role of Jignesh Parmar');
    expect(find.text('With Branch Manager, Jignesh:'), findsOneWidget);
    expect(
      find.text('They see people in the branches chosen for them.'),
      findsOneWidget,
    );
  });
}
