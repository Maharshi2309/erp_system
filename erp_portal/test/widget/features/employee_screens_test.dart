import 'package:erp_portal/app/router/app_router.dart';
import 'package:erp_portal/app/router/route_names.dart';
import 'package:erp_portal/features/employees/domain/employee.dart';
import 'package:erp_portal/features/employees/presentation/providers/employee_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_helpers/pump_app.dart';

Employee byCode(ProviderContainer c, String code) =>
    c.read(employeesProvider).value!.firstWhere((e) => e.code == code);

Future<void> go(WidgetTester tester, ProviderContainer c, String to) async {
  c.read(appRouterProvider).go(to);
  await tester.pumpAndSettle();
}

/// Opens the first dropdown showing [current] and picks [option].
Future<void> pick(WidgetTester tester, String current, String option) async {
  await tester.ensureVisible(find.text(current).first);
  await tester.tap(find.text(current).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

/// "Name — Designation" of the first manager option at [branchId].
String firstManagerAt(
  ProviderContainer c,
  String branchId, {
  Set<String> except = const {},
}) {
  final people =
      c
          .read(employeesProvider)
          .value!
          .where(
            (e) =>
                e.branchId == branchId &&
                e.status.isEmployed &&
                !except.contains(e.code),
          )
          .toList()
        ..sort((a, b) => a.fullName.compareTo(b.fullName));
  return '${people.first.fullName} — ${people.first.designation}';
}

void main() {
  group('S39 directory', () {
    testWidgets('lists 248 people, searches and opens a profile', (
      tester,
    ) async {
      final c = await pumpStafflineApp(tester, location: AppRoutes.employees);
      expect(find.text('248 people across 3 branches'), findsOneWidget);
      expect(find.text('Showing 1–10 of 248'), findsOneWidget);
      await enter(tester, 'Search employees', 'isha r');
      await tester.pumpAndSettle();
      expect(find.text('Showing 1–1 of 1'), findsOneWidget);
      await tapText(tester, 'Isha Rathod');
      expect(currentPath(c), AppRoutes.employee(byCode(c, 'EMP-0229').id));
    });

    testWidgets('pages, page size and filters', (tester) async {
      await pumpStafflineApp(tester, location: AppRoutes.employees);
      await tapText(tester, 'Next');
      expect(find.text('Showing 11–20 of 248'), findsOneWidget);
      await pick(tester, 'Any status', 'Inactive');
      expect(find.text('Showing 1–3 of 3'), findsOneWidget);
      await tapText(tester, 'Clear');
      await pick(tester, 'All branches', 'Vadodara');
      expect(find.text('Showing 1–10 of 44 in Vadodara'), findsOneWidget);
      await enter(tester, 'Search employees', 'zzzz');
      await tester.pumpAndSettle();
      expect(find.text('No one matches'), findsOneWidget);
      await tapText(tester, 'Clear filters');
      expect(find.text('Showing 1–10 of 248'), findsOneWidget);
    });

    testWidgets('sorting by name flips the order', (tester) async {
      await pumpStafflineApp(tester, location: AppRoutes.employees);
      expect(find.text('EMP-0201 · Floor Supervisor'), findsOneWidget);
      await tester.tap(find.text('EMPLOYEE'));
      await tester.pumpAndSettle();
      expect(find.text('EMP-0201 · Floor Supervisor'), findsNothing);
    });

    testWidgets('bulk deactivate asks for a reason and reports the result', (
      tester,
    ) async {
      final c = await pumpStafflineApp(tester, location: AppRoutes.employees);
      await enter(tester, 'Search employees', 'EMP-0236');
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Select Komal Desai'));
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);
      await tapText(tester, 'Deactivate');
      await tapText(tester, 'Deactivate');
      expect(
        find.text('Enter a reason. It is kept in the history.'),
        findsOneWidget,
      );
      await enter(tester, 'Reason', 'Contract ended');
      await tester.tap(find.text('Deactivate').last);
      await tester.pumpAndSettle();
      expect(find.text('Komal Desai deactivated'), findsOneWidget);
      expect(byCode(c, 'EMP-0236').status, EmploymentStatus.inactive);
    });

    testWidgets('resend invite and change branch from the bulk bar', (
      tester,
    ) async {
      final c = await pumpStafflineApp(tester, location: AppRoutes.employees);
      await enter(tester, 'Search employees', 'EMP-0240');
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Select Faisal Shaikh'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Resend invite');
      expect(find.text('Invitation sent to 1 person'), findsOneWidget);
      expect(byCode(c, 'EMP-0240').accountStatus, AccountStatus.invited);

      await tester.tap(find.bySemanticsLabel('Select Faisal Shaikh'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Change branch');
      await tapText(tester, 'Move');
      expect(find.text('Choose a branch.'), findsOneWidget);
      await pick(tester, 'Choose a branch', 'Vadodara');
      await pick(tester, 'Choose a manager', firstManagerAt(c, 'b-vad'));
      await tapText(tester, 'Move');
      expect(find.text('1 person moved'), findsOneWidget);
      expect(byCode(c, 'EMP-0240').branchId, 'b-vad');
    });

    testWidgets('template and export download spreadsheets', (tester) async {
      await pumpStafflineApp(tester, location: AppRoutes.employees);
      await tapText(tester, 'Template');
      await tapText(tester, 'Export');
      expect(downloads.saved.map((s) => s.$1), [
        'staffline_employee_template.xlsx',
        'employees.xlsx',
      ]);
    });

    testWidgets('a branch manager is locked to their branch', (tester) async {
      await pumpStafflineApp(
        tester,
        signInAs: branchManager,
        location: AppRoutes.employees,
      );
      expect(find.text('Branch: Surat'), findsOneWidget);
      expect(find.text('Showing 1–10 of 78 in Surat'), findsOneWidget);
      expect(find.text('Import'), findsNothing);
      expect(find.text('Add employee'), findsOneWidget);
    });

    testWidgets('phones get cards and “Load more”', (tester) async {
      await pumpStafflineApp(
        tester,
        size: const Size(390, 844),
        location: AppRoutes.employees,
      );
      expect(find.byType(DataTable), findsNothing);
      await tester.scrollUntilVisible(
        find.text('Load 25 more'),
        400,
        scrollable: find.byType(Scrollable).last,
      );
      await tapText(tester, 'Load 25 more');
      expect(find.text('Load 25 more'), findsOneWidget);
    });

    testWidgets('tablets use the filter panel and removable chips', (
      tester,
    ) async {
      await pumpStafflineApp(
        tester,
        size: const Size(800, 1024),
        location: AppRoutes.employees,
      );
      await tapText(tester, 'Filters');
      await pick(tester, 'All departments', 'Quality');
      await tester.tap(find.textContaining('Show ').last);
      await tester.pumpAndSettle();
      expect(find.text('Department: Quality'), findsOneWidget);
      await tester.tap(find.byTooltip('Remove filter Department: Quality'));
      await tester.pumpAndSettle();
      expect(find.text('Department: Quality'), findsNothing);
    });
  });

  group('S42 profile', () {
    testWidgets('tabs show the record and branch-derived data', (tester) async {
      final c = await pumpStafflineApp(tester);
      await go(tester, c, AppRoutes.employee(byCode(c, 'EMP-0229').id));
      expect(
        find.text('EMP-0229 · Dyeing Technician · Production'),
        findsOneWidget,
      );
      expect(find.text('Signed in · 4h ago'), findsOneWidget);
      final mobile = byCode(c, 'EMP-0229').mobile;
      expect(find.text(maskPhone(mobile)), findsOneWidget);
      expect(find.text(mobile), findsNothing);
      await tapText(tester, 'Show');
      expect(find.text(byCode(c, 'EMP-0229').mobile), findsOneWidget);
      await tapText(tester, 'Attendance');
      expect(find.text('October 2026'), findsOneWidget);
      await tapText(tester, 'Leave & balances');
      expect(find.text('Balances · 2026'), findsOneWidget);
      await tapText(tester, 'Schedule');
      expect(find.text('Inherited from Surat branch'), findsOneWidget);
      await tapText(tester, 'Account & access');
      expect(find.text('Never displayed'), findsOneWidget);
      await tapText(tester, 'Custom fields');
      expect(find.text('B-112'), findsOneWidget);
      await tapText(tester, 'Activity');
      expect(find.text('Probation completed'), findsOneWidget);
    });

    testWidgets('a branch manager sees contact details masked', (tester) async {
      final c = await pumpStafflineApp(tester, signInAs: branchManager);
      await go(tester, c, AppRoutes.employee(byCode(c, 'EMP-0229').id));
      expect(find.text('Show'), findsNothing);
      await tapText(tester, 'Personal & employment');
      expect(find.text('Restricted'), findsOneWidget);
    });

    testWidgets('someone outside your branches is not found', (tester) async {
      final c = await pumpStafflineApp(tester, signInAs: branchManager);
      await go(tester, c, AppRoutes.employee(byCode(c, 'EMP-0105').id));
      expect(find.text('This person isn’t here'), findsOneWidget);
    });

    testWidgets('deactivate, reactivate and terminate', (tester) async {
      final c = await pumpStafflineApp(tester);
      final komal = byCode(c, 'EMP-0236');
      await go(tester, c, AppRoutes.employee(komal.id));
      await tapText(tester, 'Deactivate…');
      await enter(tester, 'Reason', 'Moved away');
      await tester.tap(find.text('Deactivate').last);
      await tester.pumpAndSettle();
      expect(byCode(c, 'EMP-0236').status, EmploymentStatus.inactive);
      await tapText(tester, 'Reactivate…');
      await tester.tap(find.text('Reactivate').last);
      await tester.pumpAndSettle();
      expect(byCode(c, 'EMP-0236').status, EmploymentStatus.active);
      await tester.tap(find.byTooltip('More actions for Komal Desai'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Terminate and archive…');
      await enter(tester, 'Reason', 'Resigned');
      await tester.tap(find.text('Terminate').last);
      await tester.pumpAndSettle();
      expect(byCode(c, 'EMP-0236').status, EmploymentStatus.terminated);
      expect(find.text('Edit'), findsNothing);
    });

    testWidgets('a manager with reports cannot be deactivated', (tester) async {
      final c = await pumpStafflineApp(tester);
      await go(tester, c, AppRoutes.employee(byCode(c, 'EMP-0201').id));
      await tapText(tester, 'Deactivate…');
      await enter(tester, 'Reason', 'Leaving');
      await tester.tap(find.text('Deactivate').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('report to Aarav Bhatt'), findsOneWidget);
    });

    testWidgets('reset password link is sent, never shown', (tester) async {
      final c = await pumpStafflineApp(tester);
      await go(tester, c, AppRoutes.employee(byCode(c, 'EMP-0229').id));
      await tapText(tester, 'Reset password link');
      expect(
        find.text('Reset link sent to isha.r@meridiantex.in'),
        findsOneWidget,
      );
    });
  });

  group('S43 add employee', () {
    testWidgets('empty form lists what to fix with jump links', (tester) async {
      await pumpStafflineApp(tester, location: AppRoutes.newEmployee);
      expect(
        find.text('EMP-0349'),
        findsOneWidget,
        reason: 'suggested next ID',
      );
      await tapText(tester, 'Save & send invite');
      expect(
        find.textContaining('fields need attention before saving'),
        findsOneWidget,
      );
      expect(
        find.textContaining('First name — Enter a first name.'),
        findsOneWidget,
      );
    });

    testWidgets('a taken email names its owner', (tester) async {
      await pumpStafflineApp(tester, location: AppRoutes.newEmployee);
      await enter(tester, 'Work email', 'deepa.n@meridiantex.in');
      await tapText(tester, 'Save & send invite');
      expect(
        find.text(
          'This email belongs to Deepa Nair (EMP-0198). Use a different address.',
        ),
        findsWidgets,
      );
    });

    testWidgets('a complete form creates and invites', (tester) async {
      final c = await pumpStafflineApp(tester, location: AppRoutes.newEmployee);
      await enter(tester, 'First name', 'Pooja');
      await enter(tester, 'Last name', 'Chauhan');
      await enter(tester, 'Work email', 'pooja.c@meridiantex.in');
      await enter(tester, 'Designation', 'Quality Inspector');
      await pick(tester, 'Choose a department', 'Quality');
      await tapText(tester, 'Choose a date');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await pick(tester, 'Choose a branch', 'Surat');
      await pick(
        tester,
        'Choose a manager at Surat',
        'Bhavna Solanki — QA Analyst',
      );
      await pick(tester, 'Select a shift', 'General (09:30–18:30)');
      await pick(tester, 'Select an option', 'M');
      await tapText(tester, 'Save & send invite');
      final created = byCode(c, 'EMP-0349');
      expect(currentPath(c), AppRoutes.employee(created.id));
      expect(created.accountStatus, AccountStatus.invited);
      expect(created.status, EmploymentStatus.probation);
      expect(
        find.text(
          'Pooja Chauhan added · invitation sent to pooja.c@meridiantex.in',
        ),
        findsOneWidget,
      );
    });
  });

  group('S44 edit employee', () {
    testWidgets('changes are tracked and saved to the history', (tester) async {
      final c = await pumpStafflineApp(tester);
      final isha = byCode(c, 'EMP-0229');
      await go(tester, c, AppRoutes.employeeEdit(isha.id));
      expect(
        find.text('IDs never change once attendance exists.'),
        findsOneWidget,
      );
      await enter(tester, 'Designation', 'Senior Dyeing Technician');
      expect(find.text('Changed · was: Dyeing Technician'), findsOneWidget);
      expect(find.text('1 change'), findsOneWidget);
      await tapText(tester, 'Review & save');
      expect(find.text('Save 1 change?'), findsOneWidget);
      await tester.tap(find.text('Save changes').last);
      await tester.pumpAndSettle();
      expect(currentPath(c), AppRoutes.employee(isha.id));
      final saved = byCode(c, 'EMP-0229');
      expect(saved.designation, 'Senior Dyeing Technician');
      expect(
        saved.activity.first.text,
        'Designation: Dyeing Technician → Senior Dyeing Technician',
      );
    });

    testWidgets(
      'moving branches explains consequences and needs a new manager',
      (tester) async {
        final c = await pumpStafflineApp(tester);
        await go(tester, c, AppRoutes.employeeEdit(byCode(c, 'EMP-0229').id));
        await pick(tester, 'Surat', 'Ahmedabad HQ');
        expect(find.text('Moving branches changes these too'), findsOneWidget);
        expect(
          find.textContaining('Effective from', findRichText: true),
          findsWidgets,
        );
        await tapText(tester, 'Review & save');
        expect(
          find.textContaining(
            'Reports to — Choose who this person reports to.',
          ),
          findsOneWidget,
        );
      },
    );
  });

  group('S45 field builder', () {
    testWidgets('locked type, options in use and the required warning', (
      tester,
    ) async {
      await pumpStafflineApp(tester, location: AppRoutes.employeeFields);
      await tapText(tester, 'Uniform size');
      expect(find.textContaining('Used on '), findsOneWidget);
      expect(
        find.text(
          'Locked because values exist. Can switch to Multi-select only.',
        ),
        findsOneWidget,
      );
      expect(find.byTooltip('In use — can’t be removed'), findsWidgets);
      expect(find.byTooltip('Remove option XXL'), findsOneWidget);
      expect(
        find.textContaining(
          '12 employees in Production, Quality, Logistics have no value',
        ),
        findsOneWidget,
      );
    });

    testWidgets('renaming an option updates saved values', (tester) async {
      final c = await pumpStafflineApp(
        tester,
        location: AppRoutes.employeeFields,
      );
      await tapText(tester, 'Uniform size');
      await tester.enterText(
        find.descendant(
          of: find.bySemanticsLabel('Option 3'),
          matching: find.byType(EditableText),
        ),
        'Medium',
      );
      await tester.pump();
      await tapText(tester, 'Save field');
      expect(find.text('Uniform size saved'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(byCode(c, 'EMP-0229').customValues['uniform_size'], 'Medium');
    });

    testWidgets('a new field is created with a key from its label', (
      tester,
    ) async {
      await pumpStafflineApp(tester, location: AppRoutes.employeeFields);
      await tapText(tester, 'New field');
      await tapText(tester, 'Save field');
      expect(find.text('Enter a label.'), findsOneWidget);
      await enter(tester, 'Label', 'Bus pass');
      expect(find.text('bus_pass'), findsOneWidget);
      await tapText(tester, 'Save field');
      expect(find.text('Bus pass saved'), findsOneWidget);
    });

    testWidgets('archiving stops collecting a field', (tester) async {
      await pumpStafflineApp(tester, location: AppRoutes.employeeFields);
      await tapText(tester, 'Locker number');
      await tapText(tester, 'Archive');
      expect(
        find.text('Locker number archived · no longer collected'),
        findsOneWidget,
      );
      expect(find.text('Restore'), findsOneWidget);
    });
  });
}
