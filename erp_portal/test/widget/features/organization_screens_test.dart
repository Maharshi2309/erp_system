import 'package:erp_portal/app/router/app_router.dart';
import 'package:erp_portal/app/router/route_names.dart';
import 'package:erp_portal/features/employees/data/demo_employee_repository.dart';
import 'package:erp_portal/features/employees/presentation/providers/employee_providers.dart';
import 'package:erp_portal/features/organization/domain/branch.dart';
import 'package:erp_portal/features/organization/domain/setup_progress.dart';
import 'package:erp_portal/features/organization/presentation/providers/organization_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_helpers/pump_app.dart';

Future<void> go(WidgetTester tester, ProviderContainer c, String to) async {
  c.read(appRouterProvider).go(to);
  await tester.pumpAndSettle();
}

Finder inTable(String text) =>
    find.descendant(of: find.byType(DataTable), matching: find.text(text));

Branch branchOf(ProviderContainer c, String id) =>
    c.read(branchProvider(id)).value!;

void main() {
  group('S15–S25 setup home and S30 dashboard', () {
    testWidgets('owner with employees sees the dashboard and setup strip', (
      tester,
    ) async {
      final c = await pumpStafflineApp(tester, location: AppRoutes.overview);
      expect(find.text('Total employees'), findsOneWidget);
      expect(find.text('248'), findsOneWidget);
      expect(find.text('Branch setup'), findsOneWidget);
      // Sidebar: a BRANCHES section with percentages while setup is open.
      expect(find.text('BRANCHES'), findsOneWidget);
      expect(find.text('65%'), findsWidgets);
      await tapText(tester, 'Continue setup');
      expect(currentUri(c).path, startsWith('/branches/'));
    });

    testWidgets(
      'setup home and returning banner while there are no employees',
      (tester) async {
        final c = await pumpStafflineApp(
          tester,
          location: AppRoutes.overview,
          overrides: [
            employeeRepositoryProvider.overrideWithValue(
              DemoEmployeeRepository(latency: Duration.zero, seed: false),
            ),
          ],
        );
        expect(find.text('Ahmedabad HQ'), findsWidgets);
        expect(find.text('Manage Branch'), findsWidgets);
        await tapText(tester, 'Continue setup');
        expect(currentUri(c).path, AppRoutes.branchSetup('b-sur'));
        expect(find.text(SetupStep.holidays.title), findsWidgets);
        expect(find.text('Save'), findsOneWidget);
      },
    );

    testWidgets('“Open full dashboard” switches the setup home to S30', (
      tester,
    ) async {
      await pumpStafflineApp(
        tester,
        location: AppRoutes.overview,
        overrides: [
          employeeRepositoryProvider.overrideWithValue(
            DemoEmployeeRepository(latency: Duration.zero, seed: false),
          ),
        ],
      );
      await tapText(tester, 'Open full dashboard');
      expect(find.text('Total employees'), findsOneWidget);
      expect(find.text('No one joined in the last 14 days'), findsOneWidget);
    });

    testWidgets('HR admin gets the dashboard without owner setup tasks', (
      tester,
    ) async {
      await pumpStafflineApp(
        tester,
        signInAs: hrAdmin,
        location: AppRoutes.overview,
      );
      expect(find.text('Total employees'), findsOneWidget);
      expect(find.text('BRANCHES'), findsNothing);
      expect(find.text('Branch setup'), findsNothing);
      expect(find.text('Setup checklist'), findsNothing);
    });
  });

  group('S20–S22 branch setup', () {
    testWidgets('saving a step raises the percentage and shows a toast', (
      tester,
    ) async {
      final c = await pumpStafflineApp(
        tester,
        location: '${AppRoutes.branchSetup('b-sur')}?step=roles',
      );
      await tapText(tester, 'Save');
      expect(SetupProgress(branchOf(c, 'b-sur')).percent, 80);
      expect(
        find.text('Roles & permissions saved · Surat is 80% set up'),
        findsOneWidget,
      );
    });

    testWidgets('an invalid manager email blocks saving', (tester) async {
      final c = await pumpStafflineApp(
        tester,
        location: '${AppRoutes.branchSetup('b-sur')}?step=roles',
      );
      await tapText(tester, 'Invite a branch manager');
      await tapText(tester, 'Save');
      expect(
        find.text('Add the manager’s email to send the invitation.'),
        findsOneWidget,
      );
      expect(branchOf(c, 'b-sur').roles, isNull);
    });

    testWidgets('closing a panel keeps its draft for later', (tester) async {
      await pumpStafflineApp(
        tester,
        location: '${AppRoutes.branchSetup('b-sur')}?step=roles',
      );
      await tapText(tester, 'Invite a branch manager');
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Save'), findsNothing);

      final c = ProviderScope.containerOf(
        tester.element(find.byType(Scaffold).first),
      );
      await go(tester, c, AppRoutes.overview);
      await go(tester, c, '${AppRoutes.branchSetup('b-sur')}?step=roles');
      expect(
        find.text('You have unsaved changes from earlier.'),
        findsOneWidget,
      );
      await tapText(tester, 'Discard');
      expect(find.text('You have unsaved changes from earlier.'), findsNothing);
    });

    testWidgets('copy from another branch fills the step', (tester) async {
      final c = await pumpStafflineApp(
        tester,
        location: '${AppRoutes.branchSetup('b-vad')}?step=attendance',
      );
      await tapText(tester, 'Copy from Surat');
      await tapText(tester, 'Save');
      expect(branchOf(c, 'b-vad').attendance?.method, PunchMethod.both);
      expect(SetupProgress(branchOf(c, 'b-vad')).percent, 60);
    });

    testWidgets('final review is locked until the five steps are done', (
      tester,
    ) async {
      await pumpStafflineApp(tester, location: AppRoutes.branchSetup('b-vad'));
      expect(find.text('Review'), findsOneWidget);
      final review = tester.widget<Semantics>(
        find
            .ancestor(of: find.text('Review'), matching: find.byType(Semantics))
            .first,
      );
      expect(review.properties.enabled, isNot(true));
    });

    testWidgets('unknown branch shows not found', (tester) async {
      await pumpStafflineApp(tester, location: AppRoutes.branchSetup('b-nope'));
      expect(find.text('This branch doesn’t exist'), findsOneWidget);
    });
  });

  group('S35 organization profile', () {
    testWidgets('a time zone change needs confirmation', (tester) async {
      final c = await pumpStafflineApp(
        tester,
        location: AppRoutes.organization,
      );
      await tapText(tester, 'Edit profile');
      await tapText(tester, 'Asia/Kolkata (India, UTC+05:30)');
      await tapText(tester, 'Asia/Dubai (UTC+04:00)');
      await tapText(tester, 'Save changes');
      expect(find.text('Confirm sensitive changes'), findsOneWidget);
      expect(find.textContaining('Asia/Kolkata → Asia/Dubai'), findsOneWidget);
      await tapText(tester, 'Cancel');
      expect(c.read(organizationProvider).value?.timeZone, 'Asia/Kolkata');

      await tapText(tester, 'Save changes');
      await tester.tap(find.text('Save changes').last);
      await tester.pumpAndSettle();
      expect(c.read(organizationProvider).value?.timeZone, 'Asia/Dubai');
      expect(find.text('Organization profile saved.'), findsOneWidget);
    });

    testWidgets('an attendance manager cannot open it', (tester) async {
      final c = await pumpStafflineApp(
        tester,
        signInAs: attendanceManager,
        location: AppRoutes.organization,
      );
      expect(currentPath(c), AppRoutes.accessDenied);
    });
  });

  group('S36 branches', () {
    testWidgets('search, status filter and clear', (tester) async {
      await pumpStafflineApp(tester, location: AppRoutes.branches);
      expect(
        find.text('3 active · 1 inactive · 248 employees'),
        findsOneWidget,
      );
      await enter(tester, 'Search branches', 'vad');
      await tester.pumpAndSettle();
      expect(inTable('Vadodara'), findsOneWidget);
      expect(inTable('Surat'), findsNothing);
      await enter(tester, 'Search branches', 'zzz');
      await tester.pumpAndSettle();
      expect(find.text('No branches match'), findsOneWidget);
      await tapText(tester, 'Clear filters');
      expect(inTable('Surat'), findsOneWidget);
    });

    testWidgets('a branch row opens its detail page', (tester) async {
      final c = await pumpStafflineApp(tester, location: AppRoutes.branches);
      await tapText(tester, 'Vadodara');
      expect(currentPath(c), AppRoutes.branch('b-vad'));
    });
  });

  group('S37 edit branch', () {
    testWidgets('saves changes and returns to the branch', (tester) async {
      final c = await pumpStafflineApp(
        tester,
        location: AppRoutes.branchEdit('b-vad'),
      );
      await enter(tester, 'Phone', '+91 265 2350000');
      await tapText(tester, 'Save branch');
      expect(currentPath(c), AppRoutes.branch('b-vad'));
      expect(branchOf(c, 'b-vad').phone, '+91 265 2350000');
    });

    testWidgets('a staffed branch cannot be made inactive', (tester) async {
      await pumpStafflineApp(tester, location: AppRoutes.branchEdit('b-sur'));
      expect(find.textContaining('must be moved'), findsWidgets);
    });

    testWidgets('a branch manager is refused', (tester) async {
      final c = await pumpStafflineApp(
        tester,
        signInAs: branchManager,
        location: AppRoutes.branchEdit('b-sur'),
      );
      expect(currentPath(c), AppRoutes.accessDenied);
    });
  });

  group('S38 branch detail', () {
    testWidgets('tabs show the saved setup', (tester) async {
      await pumpStafflineApp(tester, location: AppRoutes.branch('b-sur'));
      expect(find.text('SUR-01'), findsWidgets);
      expect(find.textContaining('65% set up'), findsOneWidget);
      await tapText(tester, 'Schedule & policies');
      expect(find.text('Attendance rules'), findsOneWidget);
      expect(find.text('Casual leave'), findsWidgets);
      await tapText(tester, 'Holidays');
      expect(find.text('No holiday calendar yet'), findsOneWidget);
      await tapText(tester, 'Employees');
      expect(find.text('Not built yet'), findsOneWidget);
    });

    testWidgets('deactivating a staffed branch explains why not', (
      tester,
    ) async {
      final c = await pumpStafflineApp(
        tester,
        location: AppRoutes.branch('b-sur'),
      );
      await tapText(tester, 'Deactivate…');
      await tester.tap(find.text('Deactivate').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('must be moved'), findsOneWidget);
      expect(branchOf(c, 'b-sur').isActive, isTrue);
    });

    testWidgets('an inactive branch can be reactivated', (tester) async {
      final c = await pumpStafflineApp(
        tester,
        location: AppRoutes.branch('b-raj'),
      );
      await tapText(tester, 'Reactivate…');
      await tester.tap(find.text('Reactivate').last);
      await tester.pumpAndSettle();
      expect(branchOf(c, 'b-raj').isActive, isTrue);
    });
  });
}
