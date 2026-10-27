import 'package:erp_portal/app/router/app_router.dart';
import 'package:erp_portal/app/router/route_names.dart';
import 'package:erp_portal/core/permissions/permissions.dart';
import 'package:erp_portal/core/permissions/system_roles.dart';
import 'package:erp_portal/core/utils/validators.dart';
import 'package:erp_portal/core/widgets/app_button.dart';
import 'package:erp_portal/features/audit/presentation/audit_providers.dart';
import 'package:erp_portal/features/auth/data/demo_auth_repository.dart';
import 'package:erp_portal/features/auth/domain/auth_state.dart';
import 'package:erp_portal/features/auth/presentation/providers/auth_providers.dart';
import 'package:erp_portal/features/employees/presentation/providers/employee_providers.dart';
import 'package:erp_portal/features/leave/presentation/leave_providers.dart';
import 'package:erp_portal/features/notifications/presentation/notification_providers.dart';
import 'package:erp_portal/features/organization/presentation/providers/organization_providers.dart';
import 'package:erp_portal/features/reports/domain/reports.dart';
import 'package:erp_portal/features/reports/presentation/report_providers.dart';
import 'package:erp_portal/features/roles/presentation/access_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_helpers/pump_app.dart';

/// Scrolls to and taps a control by its accessible label.
Future<void> tapSemantics(WidgetTester tester, String label) async {
  final f = find.bySemanticsLabel(label);
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

/// Confirms the "Confirm it’s you" password dialog.
Future<void> confirmPassword(WidgetTester tester) async {
  expect(find.text('Confirm it’s you'), findsOneWidget);
  await enter(tester, 'Password', DemoAuthRepository.demoPassword);
  await tester.tap(find.widgetWithText(AppButton, 'Confirm'));
  await tester.pumpAndSettle();
}

void main() {
  group('roles: change, revoke and see it take effect (Phase 7 gate)', () {
    testWidgets('removing leave approval from Branch Manager reaches Jignesh', (
      tester,
    ) async {
      final c = await pumpStafflineApp(
        tester,
        location: AppRoutes.role('branchManager'),
        size: const Size(1440, 1600),
      );
      expect(find.text('Branch Manager'), findsWidgets);
      await tapSemantics(tester, 'Leave: Approve or reject leave');
      expect(find.text('1 unsaved change'), findsOneWidget);
      expect(find.text('− Approve or reject leave'), findsOneWidget);
      await tapText(tester, 'Review & save');
      await enter(tester, 'Reason', 'Approvals move to HR this quarter');
      await tapText(tester, 'Save changes');
      await confirmPassword(tester);
      expect(find.textContaining('Branch Manager saved'), findsOneWidget);

      final events = await c.read(auditEventsProvider.future);
      final e = events.firstWhere((x) => x.action == 'role.update');
      expect(e.reason, 'Approvals move to HR this quarter');
      expect(e.changes.single.field, 'Leave · Approve');
      expect(events.any((x) => x.action == 'auth.reauth'), isTrue);

      await switchTo(tester, c, branchManager, location: AppRoutes.leave);
      expect(
        c
            .read(sessionProvider)!
            .permissions
            .can(PermissionModule.leave, PermissionAction.approve),
        isFalse,
      );
      await tapText(tester, 'Chirag Vaghela');
      expect(find.widgetWithText(AppButton, 'Approve'), findsNothing);
    });

    testWidgets('removing a view permission locks the page', (tester) async {
      final c = await pumpStafflineApp(
        tester,
        location: AppRoutes.role('branchManager'),
        size: const Size(1440, 1600),
      );
      await tapSemantics(tester, 'Holidays & schedules: No access');
      await tapText(tester, 'Review & save');
      await tapText(tester, 'Save changes');
      await confirmPassword(tester);
      await switchTo(tester, c, branchManager, location: AppRoutes.holidays);
      expect(currentPath(c), AppRoutes.accessDenied);
      expect(find.text('Holidays'), findsNothing);
    });

    testWidgets('a wrong password doesn’t save', (tester) async {
      final c = await pumpStafflineApp(
        tester,
        location: AppRoutes.role('branchManager'),
        size: const Size(1440, 1600),
      );
      await tapSemantics(tester, 'Leave: Approve or reject leave');
      await tapText(tester, 'Review & save');
      await tapText(tester, 'Save changes');
      await enter(tester, 'Password', 'wrong-password');
      await tester.tap(find.widgetWithText(AppButton, 'Confirm'));
      await tester.pumpAndSettle();
      expect(
        find.text('That password isn’t right. Try again.'),
        findsOneWidget,
      );
      await tapText(tester, 'Cancel');
      expect(
        c
            .read(accessDataProvider)
            .value!
            .role('branchManager')!
            .grants
            .can(PermissionModule.leave, PermissionAction.approve),
        isTrue,
      );
    });

    testWidgets('system roles are read-only and can be duplicated', (
      tester,
    ) async {
      final c = await pumpStafflineApp(
        tester,
        location: AppRoutes.role('hrAdmin'),
        size: const Size(1440, 1600),
      );
      expect(
        find.text('System roles can be viewed and duplicated but not edited.'),
        findsOneWidget,
      );
      expect(find.text('Review & save'), findsNothing);
      await tapText(tester, 'Duplicate');
      expect(currentUri(c).queryParameters['from'], 'hrAdmin');
      await enter(tester, 'Role name', 'People partner');
      await tapText(tester, 'Review & create');
      await tapText(tester, 'Create role');
      await confirmPassword(tester);
      expect(find.text('People partner created'), findsOneWidget);
      final role = c
          .read(accessDataProvider)
          .value!
          .roles
          .firstWhere((r) => r.name == 'People partner');
      expect(role.isSystem, isFalse);
      expect(currentPath(c), AppRoutes.role(role.id));
    });

    testWidgets('changing someone’s role, and the last-owner rule', (
      tester,
    ) async {
      final c = await pumpStafflineApp(tester, location: AppRoutes.people);
      await tester.tap(find.bySemanticsLabel('Change role of Ankit Patel'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Ankit Patel is the only owner.'),
        findsOneWidget,
      );
      await tapText(tester, 'Cancel');

      await tester.tap(find.bySemanticsLabel('Change role of Aarav Bhatt'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Leave Approver').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Employee').last);
      await tester.pumpAndSettle();
      await tapText(tester, 'Save');
      expect(
        find.text(
          'Aarav Bhatt is now Employee. They’ll see the change at next page load.',
        ),
        findsOneWidget,
      );
      final aarav = c
          .read(employeesProvider)
          .value!
          .firstWhere((e) => e.code == 'EMP-0201');
      expect(aarav.role, SystemRole.employee);

      await switchTo(
        tester,
        c,
        leaveApprover,
        location: AppRoutes.teamApprovals,
      );
      expect(c.read(sessionProvider)!.role, SystemRole.employee);
      expect(currentPath(c), AppRoutes.accessDenied);
    });

    testWidgets('promoting to HR Admin is a high-impact change', (
      tester,
    ) async {
      await pumpStafflineApp(tester, location: AppRoutes.people);
      await tester.tap(find.bySemanticsLabel('Change role of Jignesh Parmar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Branch Manager').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('HR Admin').last);
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Jignesh Parmar will see every employee record in all branches.',
        ),
        findsOneWidget,
      );
      expect(find.text('Confirm high-impact change'), findsOneWidget);
    });
  });

  group('restricted access', () {
    testWidgets('HR admins can’t reach roles, security or data settings', (
      tester,
    ) async {
      final c = await pumpStafflineApp(tester, signInAs: hrAdmin);
      for (final path in [
        AppRoutes.roles,
        AppRoutes.settingsSecurity,
        AppRoutes.settingsData,
      ]) {
        c.read(appRouterProvider).go(path);
        await tester.pumpAndSettle();
        expect(currentPath(c), AppRoutes.accessDenied, reason: path);
      }
      c.read(appRouterProvider).go(AppRoutes.settings);
      await tester.pumpAndSettle();
      expect(find.text('Security'), findsNothing);
      expect(find.text('Notifications'), findsWidgets);
    });

    testWidgets('employees can’t reach reports or the audit log', (
      tester,
    ) async {
      final c = await pumpStafflineApp(tester, signInAs: employee);
      for (final path in [
        AppRoutes.reports,
        AppRoutes.auditLog,
        AppRoutes.settings,
      ]) {
        c.read(appRouterProvider).go(path);
        await tester.pumpAndSettle();
        expect(currentPath(c), AppRoutes.accessDenied, reason: path);
      }
    });
  });

  group('invitations', () {
    testWidgets('resend expired and revoke', (tester) async {
      final c = await pumpStafflineApp(
        tester,
        location: AppRoutes.invitations,
        size: const Size(1440, 1600),
      );
      expect(find.text('Not delivered'), findsWidgets);
      final resendAll = find.textContaining('Resend all expired (');
      await tester.tap(resendAll);
      await tester.pumpAndSettle();
      expect(find.textContaining('invitation'), findsWidgets);
      await dismissToasts(tester);
      final revoke = find.bySemanticsLabel(RegExp('^Revoke ')).first;
      await tester.ensureVisible(revoke);
      await tester.tap(revoke);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Revoke').last);
      await tester.pumpAndSettle();
      expect(find.text('Invitation revoked'), findsOneWidget);
      final events = await c.read(auditEventsProvider.future);
      expect(events.any((e) => e.action == 'invite.revoke'), isTrue);
      expect(events.any((e) => e.action == 'invite.send'), isTrue);
    });
  });

  group('notifications', () {
    testWidgets('a leave request reaches the approver’s inbox', (tester) async {
      final c = await pumpStafflineApp(
        tester,
        signInAs: employee,
        location:
            '${AppRoutes.applyLeave}?type=casual&from=2026-10-27&to=2026-10-28',
      );
      await tapText(tester, 'Submit request');
      await switchTo(
        tester,
        c,
        leaveApprover,
        location: AppRoutes.myNotifications,
      );
      expect(find.text('Leave request to approve'), findsOneWidget);
      expect(c.read(unreadCountProvider), 1);
      expect(find.byTooltip('Notifications, 1 unread'), findsOneWidget);
      await tapText(tester, 'Leave request to approve');
      expect(currentPath(c), AppRoutes.teamApprovals);
      expect(c.read(unreadCountProvider), 0);

      // Approving tells Isha.
      await tester.tap(find.widgetWithText(AppButton, 'Approve').last);
      await tester.pumpAndSettle();
      await switchTo(tester, c, employee, location: AppRoutes.myNotifications);
      expect(find.text('Leave approved'), findsOneWidget);
      await tapText(tester, 'Mark all read');
      expect(c.read(unreadCountProvider), 0);
    });

    testWidgets('admin inbox filters and opens the record', (tester) async {
      final c = await pumpStafflineApp(
        tester,
        signInAs: hrAdmin,
        location: AppRoutes.notifications,
      );
      await tapText(tester, 'People 1');
      expect(find.text('Invitation not delivered'), findsWidgets);
      await tapText(tester, 'Fix email');
      expect(currentPath(c), AppRoutes.invitations);
    });

    testWidgets('turning a switch off stops the notification', (tester) async {
      final c = await pumpStafflineApp(
        tester,
        signInAs: hrAdmin,
        location: AppRoutes.settingsNotifications,
        size: const Size(1440, 1600),
      );
      await tester.tap(
        find.bySemanticsLabel('New request needs approval: Manager In-app'),
      );
      await tester.pumpAndSettle();
      await tapText(tester, 'Save changes');
      expect(find.text('✓ All changes saved'), findsOneWidget);
      await switchTo(
        tester,
        c,
        employee,
        location:
            '${AppRoutes.applyLeave}?type=casual&from=2026-10-27&to=2026-10-27',
      );
      await tapText(tester, 'Submit request');
      await switchTo(tester, c, leaveApprover);
      await c.read(inboxProvider.future);
      expect(
        c
            .read(inboxProvider)
            .value!
            .any((n) => n.title == 'Leave request to approve'),
        isFalse,
      );
    });
  });

  group('audit log', () {
    testWidgets('owner reveals a masked value with a reason', (tester) async {
      final c = await pumpStafflineApp(
        tester,
        location: AppRoutes.auditLog,
        size: const Size(1440, 1200),
      );
      await tapText(tester, 'Mobile number and personal email updated');
      // Before and after both end in 4417, so both mask the same way.
      expect(find.text('+91 98•• ••4417'), findsNWidgets(2));
      expect(find.text('+91 98250 14417'), findsNothing);
      await tester.tap(find.bySemanticsLabel('Reveal Mobile'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Reveal');
      expect(
        find.text('Give a reason (at least 5 characters).'),
        findsOneWidget,
      );
      await enter(tester, 'Reason', 'Employee disputes the change');
      await tapText(tester, 'Reveal');
      expect(find.text('+91 98250 14417'), findsOneWidget);
      final events = await c.read(auditEventsProvider.future);
      expect(events.first.action, 'audit.reveal');
      expect(events.first.reason, 'Employee disputes the change');
    });

    testWidgets('HR sees masked values without a reveal button', (
      tester,
    ) async {
      await pumpStafflineApp(
        tester,
        signInAs: hrAdmin,
        location: AppRoutes.auditLog,
        size: const Size(1440, 1200),
      );
      await tapText(tester, 'Mobile number and personal email updated');
      expect(find.text('is••••@gmail.com'), findsNWidgets(2));
      expect(find.textContaining('Reveal'), findsNothing);
      expect(find.text('✓ Chain verified', findRichText: true), findsNothing);
      expect(find.textContaining('Chain verified'), findsOneWidget);
    });

    testWidgets('a leave decision is recorded with its actor', (tester) async {
      final c = await pumpStafflineApp(
        tester,
        signInAs: leaveApprover,
        location: AppRoutes.teamApprovals,
      );
      await tester.tap(find.widgetWithText(AppButton, 'Approve').first);
      await tester.pumpAndSettle();
      await switchTo(tester, c, hrAdmin, location: AppRoutes.auditLog);
      final e = (await c.read(auditEventsProvider.future)).firstWhere(
        (x) => x.action == 'leave.approve' && x.actorName == 'Aarav Bhatt',
      );
      expect(e.actorRole, 'Leave Approver');
      expect(find.text('leave.approve'), findsWidgets);
      // Filter to leave actions.
      await tapText(tester, 'Any action');
      await tapText(tester, 'Action: leave');
      expect(find.text('employee.update'), findsNothing);
    });

    testWidgets('export is logged', (tester) async {
      final c = await pumpStafflineApp(tester, location: AppRoutes.auditLog);
      await tapText(tester, 'Export');
      expect(downloads.saved.single.$1, startsWith('audit_log_'));
      final events = await c.read(auditEventsProvider.future);
      expect(events.first.action, 'audit.export');
    });
  });

  group('reports', () {
    testWidgets('HR exports a report; it appears in the history', (
      tester,
    ) async {
      final c = await pumpStafflineApp(
        tester,
        signInAs: hrAdmin,
        location: AppRoutes.reports,
        size: const Size(1440, 1400),
      );
      // The catalogue card (a recent export has the same name).
      await tester.tap(find.text('Monthly attendance summary').first);
      await tester.pumpAndSettle();
      await tapText(tester, 'CSV');
      await tester.tap(find.widgetWithText(AppButton, 'Export'));
      await tester.pumpAndSettle();
      expect(
        find.text('Monthly attendance summary exported as CSV'),
        findsOneWidget,
      );
      expect(downloads.saved.single.$1, endsWith('.csv'));
      final history = await c.read(exportHistoryProvider.future);
      expect(history.first.kind.label, 'Monthly attendance summary');
      expect(
        (await c.read(auditEventsProvider.future)).first.action,
        'report.export',
      );
      await tapText(tester, 'Export history');
      await tester.tap(
        find.bySemanticsLabel('Download Monthly attendance summary').first,
      );
      await tester.pumpAndSettle();
      expect(downloads.saved.length, 2);
      expect(
        (await c.read(auditEventsProvider.future)).first.action,
        'report.download',
      );
    });

    testWidgets('results page sorts and pages', (tester) async {
      await pumpStafflineApp(
        tester,
        signInAs: hrAdmin,
        location:
            '${AppRoutes.reportResults}?report=roster&from=2026-10-01&to=2026-10-14',
        size: const Size(1440, 1200),
      );
      expect(find.textContaining('1–10 of'), findsOneWidget);
      await tapText(tester, 'Next');
      expect(find.textContaining('11–20 of'), findsOneWidget);
      await tapText(tester, 'Name');
      expect(find.textContaining('1–10 of'), findsOneWidget);
    });

    testWidgets('a branch manager’s reports stay inside Surat', (tester) async {
      final c = await pumpStafflineApp(
        tester,
        signInAs: branchManager,
        location:
            '${AppRoutes.reportResults}?report=roster&from=2026-10-01&to=2026-10-14&cols=org',
        size: const Size(1440, 1200),
      );
      final sources = c.read(reportSourcesProvider)!;
      expect(sources.people.every((e) => e.branchId == 'b-sur'), isTrue);
      expect(find.text('Ahmedabad HQ'), findsNothing);
      expect(find.text('Personal email'), findsNothing);
      c
          .read(appRouterProvider)
          .go(
            '${AppRoutes.reportResults}?report=audit&from=2026-10-01&to=2026-10-14',
          );
      await tester.pumpAndSettle();
      expect(find.text('You can’t run this report'), findsOneWidget);
    });

    testWidgets('turning off an export right disables Export', (tester) async {
      final c = await pumpStafflineApp(
        tester,
        location: AppRoutes.settingsData,
        size: const Size(1440, 1600),
      );
      await tester.tap(
        find.bySemanticsLabel('Branch Manager can export Attendance'),
      );
      await tester.pumpAndSettle();
      await tapText(tester, 'Save changes');
      await switchTo(
        tester,
        c,
        branchManager,
        location:
            '${AppRoutes.reportResults}?report=monthly&from=2026-10-01&to=2026-10-14',
      );
      expect(find.text('Export XLSX'), findsNothing);
      expect(
        find.text('Exports of attendance are turned off for your role'),
        findsOneWidget,
      );
    });
  });

  group('settings', () {
    testWidgets('two-step for everyone applies at the next sign-in', (
      tester,
    ) async {
      final c = await pumpStafflineApp(
        tester,
        location: AppRoutes.settingsSecurity,
        size: const Size(1440, 1400),
      );
      await tapText(tester, 'Required for everyone');
      await tapText(tester, 'Save changes');
      await confirmPassword(tester);
      expect(find.text('✓ Saved · logged in the audit trail'), findsOneWidget);
      await c.read(authControllerProvider.notifier).signOut();
      await tester.pumpAndSettle();
      await c
          .read(authControllerProvider.notifier)
          .signIn(
            identifier: employee,
            password: DemoAuthRepository.demoPassword,
            keepSignedIn: false,
          );
      expect(c.read(authControllerProvider), isA<AwaitingTwoStep>());
    });

    testWidgets('attendance policy changes the branch rules', (tester) async {
      final c = await pumpStafflineApp(
        tester,
        location: AppRoutes.settingsAttendance,
        size: const Size(1440, 1200),
      );
      await enter(tester, r'Grace period \(minutes\)', '15');
      expect(find.text('Changed from 10 min'), findsOneWidget);
      await tapText(tester, 'Save changes');
      expect(find.text('✓ Saved · logged in the audit trail'), findsOneWidget);
      final b = c.read(branchesProvider).value!.firstWhere((b) => b.isActive);
      expect(b.attendance!.graceMinutes, 15);
      final e = (await c.read(
        auditEventsProvider.future,
      )).firstWhere((x) => x.action == 'policy.update');
      expect(e.changes.single.after, '15 min');
    });

    testWidgets('settings search', (tester) async {
      await pumpStafflineApp(tester, location: AppRoutes.settings);
      await tester.enterText(find.byType(TextField).first, 'zzz');
      await tester.pump();
      expect(find.textContaining('No settings match'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'leave');
      await tester.pump();
      expect(find.text('Leave policy'), findsOneWidget);
    });
  });

  group('my profile', () {
    testWidgets('an employee updates their own contact details', (
      tester,
    ) async {
      final c = await pumpStafflineApp(
        tester,
        signInAs: employee,
        location: AppRoutes.myProfile,
      );
      expect(find.text('My profile'), findsOneWidget);
      await tapText(tester, 'Edit');
      await enter(tester, 'Mobile', '12');
      await tapText(tester, 'Save');
      expect(find.text(Validators.mobileMessage), findsOneWidget);
      await enter(tester, 'Mobile', '+91 98790 11111');
      await tapText(tester, 'Save');
      expect(find.text('Contact details saved'), findsOneWidget);
      expect(c.read(selfEmployeeProvider)!.mobile, '+91 98790 11111');
      // Isha can't open the audit log; read the trail directly.
      final e =
          (await c
                  .read(auditRepositoryProvider)
                  .events(c.read(sessionProvider)!.organizationId))
              .firstWhere((x) => x.action == 'employee.update');
      expect(e.changes.first.field, 'Mobile');
      await tapText(tester, 'Reset by email');
      expect(
        find.textContaining('We sent a password reset link'),
        findsOneWidget,
      );
      // Leave data still loads (nothing else touched the record).
      expect(c.read(leaveDataProvider).hasError, isFalse);
    });
  });

  testWidgets('every report runs on the demo data', (tester) async {
    final c = await pumpStafflineApp(
      tester,
      size: const Size(1440, 1200),
      signInAs: owner,
    );
    for (final k in ReportKind.values) {
      c
          .read(appRouterProvider)
          .go(
            '${AppRoutes.reportResults}?report=${k.name}&from=2026-10-01&to=2026-10-14',
          );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: k.name);
      expect(find.text(k.label), findsWidgets, reason: k.name);
      final rows = c.read(reportSourcesProvider)!;
      expect(rows.people, isNotEmpty);
    }
    // Exports in both formats.
    await tapText(tester, 'Export CSV');
    await tapText(tester, 'Export XLSX');
    expect(downloads.saved.map((d) => d.$1.split('.').last), ['csv', 'xlsx']);
  });

  testWidgets('branding and data settings save and are logged', (tester) async {
    final c = await pumpStafflineApp(
      tester,
      location: AppRoutes.settingsBranding,
      size: const Size(1440, 1600),
    );
    await tester.tap(find.bySemanticsLabel('Teal'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.bySemanticsLabel('Custom color, hex'),
        matching: find.byType(EditableText),
      ),
      '#F2B84B',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('White text on this color is hard to read'),
      findsOneWidget,
    );
    await tapText(tester, 'Save');
    expect(find.text('✓ Saved'), findsOneWidget);

    c.read(appRouterProvider).go(AppRoutes.settingsData);
    await tester.pumpAndSettle();
    await tapText(tester, 'Hours and minutes (8:04)');
    await tapText(tester, 'Decimal hours (8.07)');
    await tapText(tester, 'Save changes');
    expect(find.text('✓ All changes saved'), findsOneWidget);
    final events = await c.read(auditEventsProvider.future);
    expect(
      events
          .where((e) => e.action == 'settings.update')
          .map((e) => e.entityLabel),
      containsAll(['Branding & localization', 'Data & export']),
    );
  });
}
