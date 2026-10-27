// D-73: admins choose which built-in employee fields are required,
// optional or hidden; the "Employee fields" permission controls who may.
import 'package:erp_portal/app/router/app_router.dart';
import 'package:erp_portal/app/router/route_names.dart';
import 'package:erp_portal/core/permissions/permissions.dart';
import 'package:erp_portal/core/widgets/app_button.dart';
import 'package:erp_portal/features/audit/presentation/audit_providers.dart';
import 'package:erp_portal/features/auth/presentation/providers/auth_providers.dart';
import 'package:erp_portal/features/employees/data/employee_files.dart';
import 'package:erp_portal/features/employees/domain/employee.dart';
import 'package:erp_portal/features/employees/domain/employee_import.dart';
import 'package:erp_portal/features/employees/domain/employee_rules.dart';
import 'package:erp_portal/features/employees/domain/field_settings.dart';
import 'package:erp_portal/features/employees/presentation/providers/employee_providers.dart';
import 'package:erp_portal/features/organization/presentation/providers/organization_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_helpers/pump_app.dart';
import 'attendance_screens_test.dart' show byCode;
import 'phase7_screens_test.dart' show confirmPassword, tapSemantics;

void main() {
  group('rules', () {
    const defaults = EmployeeFieldSettings();

    test('core fields are locked as required', () {
      for (final f in [
        StandardField.code,
        StandardField.firstName,
        StandardField.lastName,
        StandardField.branch,
        StandardField.joiningDate,
        StandardField.type,
        StandardField.shift,
        StandardField.manager,
      ]) {
        expect(f.locked, isTrue, reason: f.label);
        expect(
          defaults.withRule(f, FieldRule.hidden).ruleOf(f),
          FieldRule.required,
        );
      }
      expect(
        StandardField.workEmail.allowed,
        isNot(contains(FieldRule.hidden)),
      );
    });

    test('defaults match the earlier form', () {
      expect(defaults.requires(StandardField.designation), isTrue);
      expect(defaults.requires(StandardField.department), isTrue);
      expect(defaults.ruleOf(StandardField.mobile), FieldRule.optional);
      expect(
        defaults.withRule(StandardField.mobile, FieldRule.optional),
        defaults,
      );
    });

    testWidgets('the validator follows the rules', (tester) async {
      final c = await pumpStafflineApp(tester);
      final isha = byCode(c, employee);
      final surat = c
          .read(branchesProvider)
          .value!
          .firstWhere((b) => b.id == 'b-sur');
      final others = c
          .read(employeesProvider)
          .value!
          .where((e) => e.id != isha.id);
      Map<String, String> check(
        Employee e,
        EmployeeFieldSettings s, {
        bool restricted = true,
      }) => validateEmployee(
        e,
        others: others,
        fields: const [],
        branch: surat,
        sendInvite: false,
        settings: s,
        seesRestricted: restricted,
      );
      final blank = isha.copyWith(
        designation: '',
        department: '',
        mobile: '',
        personalEmail: '',
      );
      expect(
        check(blank, defaults).keys,
        containsAll(['designation', 'department']),
      );

      final custom = defaults
          .withRule(StandardField.designation, FieldRule.hidden)
          .withRule(StandardField.department, FieldRule.optional)
          .withRule(StandardField.mobile, FieldRule.required)
          .withRule(StandardField.personalEmail, FieldRule.required);
      final errors = check(blank, custom);
      expect(errors.keys, isNot(contains('designation')));
      expect(errors.keys, isNot(contains('department')));
      expect(errors['mobile'], 'Enter a mobile number.');
      expect(errors['personalEmail'], 'Enter a personal email.');
      // People who can't see restricted fields aren't asked for them.
      expect(
        check(blank, custom, restricted: false).keys,
        isNot(contains('personalEmail')),
      );
    });

    test('import follows the rules', () {
      final s = const EmployeeFieldSettings()
          .withRule(StandardField.designation, FieldRule.hidden)
          .withRule(StandardField.mobile, FieldRule.required);
      final header = templateRows(const [], s).first;
      expect(header, isNot(contains('Designation')));
      expect(header, contains('Mobile number'));
      final mapping = [
        for (final f in ImportField.values)
          if (f.isShown(s)) ImportTarget.field(f),
      ];
      expect(
        mapping,
        isNot(contains(const ImportTarget.field(ImportField.designation))),
      );
      expect(unmappedRequired(mapping, s), isEmpty);
      expect(
        unmappedRequired([
          for (final t in mapping)
            if (t.field != ImportField.mobile) t,
        ], s),
        [ImportField.mobile],
      );
      // A Designation column in the file is not imported while hidden.
      expect(
        autoMatchColumns(['Designation'], const [], s).single.isIgnored,
        isTrue,
      );
    });
  });

  testWidgets('HR makes mobile required and hides designation; the add form '
      'follows and the change is audited', (tester) async {
    final c = await pumpStafflineApp(
      tester,
      signInAs: hrAdmin,
      size: const Size(1440, 2400),
      location: AppRoutes.employeeFields,
    );
    expect(find.text('Built-in fields'), findsOneWidget);
    expect(
      find.textContaining('Always required', findRichText: true),
      findsNWidgets(8),
    );

    Future<void> setRule(String field, String rule) async {
      final chips = find.bySemanticsLabel('$field rule');
      final option = find.descendant(of: chips, matching: find.text(rule));
      await tester.ensureVisible(option);
      await tester.tap(option);
      await tester.pumpAndSettle();
    }

    await setRule('Mobile number', 'Required');
    await setRule('Designation', 'Hidden');
    expect(find.text('Mobile number · changed'), findsOneWidget);
    await tapText(tester, 'Save field settings');
    final saved = c.read(fieldSettingsProvider).value!;
    expect(saved.requires(StandardField.mobile), isTrue);
    expect(saved.shows(StandardField.designation), isFalse);
    final event = (await c.read(
      auditEventsProvider.future,
    )).firstWhere((e) => e.action == 'settings.employeeFields');
    expect(event.changes.map((x) => '${x.field}: ${x.before} → ${x.after}'), [
      'Mobile number: Optional → Required',
      'Designation: Required → Hidden',
    ]);

    c.read(appRouterProvider).go(AppRoutes.newEmployee);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp('^Designation')), findsNothing);
    await tapText(tester, 'Save & send invite');
    expect(
      find.textContaining('Mobile number — Enter a mobile number.'),
      findsOneWidget,
    );
    expect(find.textContaining('Designation —'), findsNothing);
  });

  testWidgets('who may change field settings', (tester) async {
    final c = await pumpStafflineApp(tester, signInAs: branchManager);
    c.read(appRouterProvider).go(AppRoutes.employeeFields);
    await tester.pumpAndSettle();
    expect(currentPath(c), AppRoutes.accessDenied);

    // The owner gives Branch Manager "Employee fields: View" only.
    await switchTo(tester, c, owner, location: AppRoutes.role('branchManager'));
    await tapSemantics(tester, 'Employee form: Can view');
    await tapText(tester, 'Review & save');
    await enter(tester, 'Reason', 'Managers check what new joiners need');
    await tapText(tester, 'Save changes');
    await confirmPassword(tester);

    await switchTo(
      tester,
      c,
      branchManager,
      location: AppRoutes.employeeFields,
    );
    expect(currentPath(c), AppRoutes.employeeFields);
    expect(find.text('View only'), findsOneWidget);
    expect(find.text('Save field settings'), findsNothing);
    expect(find.widgetWithText(AppButton, 'New field'), findsNothing);
    expect(
      c
          .read(sessionProvider)!
          .permissions
          .can(PermissionModule.employeeFields, PermissionAction.edit),
      isFalse,
    );
  });
}
