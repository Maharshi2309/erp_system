// End-to-end journeys from the Phase 8 brief, driven through the real
// screens with the demo backend. Run on a device:
//
//   flutter test integration_test -d macos
//
// They also run headless with `flutter test integration_test`.
import 'dart:io';

import 'package:erp_portal/app/router/app_router.dart';
import 'package:erp_portal/app/router/route_names.dart';
import 'package:erp_portal/core/widgets/app_button.dart';
import 'package:erp_portal/features/attendance/domain/attendance.dart';
import 'package:erp_portal/features/attendance/presentation/attendance_providers.dart';
import 'package:erp_portal/features/auth/data/demo_auth_repository.dart';
import 'package:erp_portal/features/auth/presentation/providers/auth_providers.dart';
import 'package:erp_portal/features/employees/domain/employee.dart';
import 'package:erp_portal/features/employees/presentation/providers/employee_providers.dart';
import 'package:erp_portal/features/leave/domain/leave.dart';
import 'package:erp_portal/features/leave/presentation/leave_providers.dart';
import 'package:erp_portal/features/organization/presentation/providers/organization_providers.dart';
import 'package:erp_portal/features/reports/presentation/report_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/test_helpers/pump_app.dart';

Future<void> pick(WidgetTester tester, String current, String option) async {
  await tester.ensureVisible(find.text(current).first);
  await tester.tap(find.text(current).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

/// Scrolls [f] into the real window, then taps it.
Future<void> tapFound(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<void> go(WidgetTester tester, ProviderContainer c, String to) async {
  c.read(appRouterProvider).go(to);
  await tester.pumpAndSettle();
}

/// Signs in through the welcome page like a person would.
Future<void> signInViaForm(
  WidgetTester tester,
  ProviderContainer c,
  String identifier,
) async {
  await c.read(authControllerProvider.notifier).signOut();
  await tester.pumpAndSettle();
  expect(currentPath(c), AppRoutes.welcome);
  await enter(tester, 'Work email or employee ID', identifier);
  await enter(tester, 'Password', DemoAuthRepository.demoPassword);
  await tapText(tester, 'Sign in');
  // Admin demo accounts use two-step sign-in.
  if (currentPath(c) == AppRoutes.twoStep) {
    await tester.enterText(
      find.byType(TextField).first,
      DemoAuthRepository.demoAuthenticatorCode,
    );
    await tester.pump();
    await tapText(tester, 'Verify and sign in');
  }
}

/// On a device the real window is used; headless runs use a fixed size.
final onDevice = !Platform.environment.containsKey('FLUTTER_TEST');

Size? sized(Size s) => onDevice ? null : s;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('1–2 owner registers, sets up the organization and a branch', (
    tester,
  ) async {
    final c = await pumpStafflineApp(
      tester,
      signInAs: null,
      location: AppRoutes.register,
    );
    await enter(tester, 'Full name', 'Ravi Shah');
    await enter(tester, 'Work email', 'ravi@newco.in');
    await enter(tester, 'Password', 'Factory2026x');
    await tapText(
      tester,
      'I agree to the Terms of Service and Privacy Policy. *',
    );
    await tapText(tester, 'Create account');
    expect(currentPath(c), AppRoutes.verifyEmail);
    await tester.enterText(
      find.byType(TextField),
      DemoAuthRepository.demoEmailCode,
    );
    await tester.pump();
    await tapText(tester, 'Verify email');
    await tapText(tester, 'Set up organization');
    expect(currentPath(c), AppRoutes.onboarding);

    await tapText(tester, 'Set Up Your Organisation');
    await enter(tester, 'Organisation name', 'Newco Fabrics');
    await tapText(tester, '11–50');
    await tapText(tester, 'Create Organisation');
    expect(currentPath(c), AppRoutes.overview);
    expect(c.read(sessionProvider)!.organizationName, 'Newco Fabrics');

    await dismissToasts(tester);
    await go(tester, c, AppRoutes.newBranch);
    await enter(tester, 'Branch name', 'Bhiwandi');
    await enter(tester, 'Address', 'Kalyan Road');
    await enter(tester, 'City', 'Bhiwandi');
    await enter(tester, 'PIN code', '421302');
    await tapText(tester, 'Create Branch');
    expect(find.text('Bhiwandi created · 25% set up'), findsOneWidget);
    expect(
      c.read(branchesProvider).value!.map((b) => b.name),
      contains('Bhiwandi'),
    );
  });

  testWidgets('3 HR adds an employee who is invited', (tester) async {
    final c = await pumpStafflineApp(
      tester,
      signInAs: hrAdmin,
      location: AppRoutes.newEmployee,
      size: sized(const Size(1440, 1600)),
    );
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
    final created = c
        .read(employeesProvider)
        .value!
        .firstWhere((e) => e.workEmail == 'pooja.c@meridiantex.in');
    expect(created.accountStatus, AccountStatus.invited);
    expect(currentPath(c), AppRoutes.employee(created.id));
  });

  testWidgets(
    '4–8 employee signs in, punches, requests leave; approver decides',
    (tester) async {
      final c = await pumpStafflineApp(
        tester,
        signInAs: null,
        size: sized(const Size(1440, 900)),
      );
      // 4. Sign in with the employee ID.
      await enter(tester, 'Work email or employee ID', employee);
      await enter(tester, 'Password', DemoAuthRepository.demoPassword);
      await tapText(tester, 'Sign in');
      expect(currentPath(c), AppRoutes.home);

      // 5. Punch out, then in again.
      await tapText(tester, 'Punch out');
      expect(find.text('Punched out'), findsOneWidget);
      await tapText(tester, 'Punch in');
      expect(find.text('Punched in'), findsOneWidget);
      final self = c.read(selfEmployeeProvider)!;
      final punches = c
          .read(attendanceDataProvider)
          .value!
          .punches
          .where((p) => p.employeeId == self.id && p.source == PunchSource.web);
      expect(punches.length, 2);

      // 6. Request leave.
      final before = c
          .read(leaveBookProvider)
          .value!
          .balance(self, 'casual', 2026);
      await go(
        tester,
        c,
        '${AppRoutes.applyLeave}?type=casual&from=2026-10-27&to=2026-10-28',
      );
      await enter(tester, 'Reason', 'Family function');
      await tapText(tester, 'Submit request');
      expect(find.text('Waiting for Aarav Bhatt'), findsOneWidget);

      // 7. The approver decides.
      await signInViaForm(tester, c, leaveApprover);
      expect(currentPath(c), AppRoutes.teamApprovals);
      const what = 'Casual leave · 27–28 Oct · 2 days';
      final card = find.ancestor(
        of: find.text(what),
        matching: find.byType(Card),
      );
      final approve = card.evaluate().isEmpty
          ? find.widgetWithText(AppButton, 'Approve').last
          : find.descendant(
              of: card.first,
              matching: find.widgetWithText(AppButton, 'Approve'),
            );
      await tapFound(tester, approve);
      expect(
        find.textContaining('Isha Rathod has been notified'),
        findsOneWidget,
      );

      // 8. The employee sees the decision and the new balance.
      await signInViaForm(tester, c, employee);
      await go(tester, c, AppRoutes.myLeave);
      expect(find.text('Next approved leave'), findsOneWidget);
      final after = c
          .read(leaveBookProvider)
          .value!
          .balance(c.read(selfEmployeeProvider)!, 'casual', 2026);
      expect(after.available, before.available - 2);
      final request = c
          .read(leaveDataProvider)
          .value!
          .requests
          .firstWhere((r) => r.employeeId == self.id && r.from.day == 27);
      expect(request.status, LeaveStatus.approved);
      await go(tester, c, AppRoutes.myNotifications);
      expect(find.text('Leave approved'), findsOneWidget);
    },
  );

  testWidgets('9 role restrictions hold across roles', (tester) async {
    final c = await pumpStafflineApp(
      tester,
      signInAs: employee,
      size: sized(const Size(1440, 900)),
    );
    for (final path in [
      AppRoutes.employees,
      AppRoutes.reports,
      AppRoutes.roles,
      AppRoutes.leave,
    ]) {
      await go(tester, c, path);
      expect(currentPath(c), AppRoutes.accessDenied, reason: path);
    }
    await signInViaForm(tester, c, branchManager);
    for (final path in [AppRoutes.roles, AppRoutes.settings]) {
      await go(tester, c, path);
      expect(currentPath(c), AppRoutes.accessDenied, reason: path);
    }
    await go(tester, c, AppRoutes.employees);
    expect(
      c
          .read(visibleEmployeesProvider)
          .value!
          .every((e) => e.branchId == 'b-sur'),
      isTrue,
    );
  });

  testWidgets('10 reports and authorized exports', (tester) async {
    final c = await pumpStafflineApp(
      tester,
      signInAs: hrAdmin,
      location: AppRoutes.reports,
      size: sized(const Size(1440, 1400)),
    );
    await tapFound(tester, find.text('Leave requests & decisions').first);
    await tapFound(tester, find.widgetWithText(AppButton, 'Export'));
    expect(downloads.saved.single.$1, endsWith('.xlsx'));
    expect(
      (await c.read(exportHistoryProvider.future)).first.kind.label,
      'Leave requests & decisions',
    );

    await signInViaForm(tester, c, branchManager);
    await go(
      tester,
      c,
      '${AppRoutes.reportResults}?report=audit&from=2026-10-01&to=2026-10-14',
    );
    expect(find.text('You can’t run this report'), findsOneWidget);
    await go(
      tester,
      c,
      '${AppRoutes.reportResults}?report=roster&from=2026-10-01&to=2026-10-14',
    );
    expect(
      c.read(reportSourcesProvider)!.people.every((e) => e.branchId == 'b-sur'),
      isTrue,
    );
  });
}
