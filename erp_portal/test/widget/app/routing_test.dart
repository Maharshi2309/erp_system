import 'package:erp_portal/app/router/app_router.dart';
import 'package:erp_portal/app/router/route_names.dart';
import 'package:erp_portal/features/auth/presentation/providers/auth_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_helpers/pump_app.dart';

void main() {
  testWidgets('signed-out start lands on welcome', (tester) async {
    final c = await pumpStafflineApp(tester, signInAs: null);
    expect(currentPath(c), AppRoutes.welcome);
    expect(find.text('Welcome'), findsOneWidget);
  });

  testWidgets('each role lands on its own home with its own menu', (
    tester,
  ) async {
    final expectations = {
      owner: (AppRoutes.overview, 'Roles & Permissions'),
      hrAdmin: (AppRoutes.overview, 'Audit Log'),
      branchManager: (AppRoutes.branchDashboard, 'Branch reports'),
      attendanceManager: (AppRoutes.attendance, 'Missing punches'),
      leaveApprover: (AppRoutes.teamApprovals, 'Approvals'),
      employee: (AppRoutes.home, 'Holidays'),
    };
    for (final MapEntry(key: account, value: (home, menuItem))
        in expectations.entries) {
      final c = await pumpStafflineApp(tester, signInAs: account);
      expect(currentPath(c), home, reason: account);
      expect(find.text(menuItem), findsWidgets, reason: account);
    }
  });

  testWidgets(
    'HR admin opening an owner page sees access denied in their shell',
    (tester) async {
      final c = await pumpStafflineApp(
        tester,
        signInAs: hrAdmin,
        location: AppRoutes.roles,
      );
      expect(currentPath(c), AppRoutes.accessDenied);
      expect(find.text('You don’t have access to this page'), findsOneWidget);
      expect(
        find.textContaining(
          'Roles & Permissions is managed by the organization owner',
        ),
        findsOneWidget,
      );
      // Still inside the HR admin's own menu.
      expect(find.text('Audit Log'), findsOneWidget);

      await tester.tap(find.text('Ask the owner for access'));
      await tester.pumpAndSettle();
      expect(find.text('Request sent to Ankit Patel.'), findsOneWidget);
      expect(find.text('Request sent'), findsOneWidget);

      await tester.tap(find.text('Go to your dashboard'));
      await tester.pumpAndSettle();
      expect(currentPath(c), AppRoutes.overview);
    },
  );

  testWidgets('unknown URL shows the 404 page with a way back', (tester) async {
    final c = await pumpStafflineApp(tester, location: '/no-such-page');
    expect(find.text('404'), findsOneWidget);
    await tester.tap(find.text('Go to your dashboard'));
    await tester.pumpAndSettle();
    expect(currentPath(c), AppRoutes.overview);
  });

  testWidgets('a deep link survives signing in', (tester) async {
    final c = await pumpStafflineApp(tester, signInAs: null);
    c.read(appRouterProvider).go('/holidays');
    await tester.pumpAndSettle();
    expect(currentUri(c).queryParameters['from'], '/holidays');

    await signInDemo(c, hrAdmin);
    await tester.pumpAndSettle();
    expect(currentPath(c), AppRoutes.holidays);
  });

  testWidgets('account menu: switch organization, then sign out', (
    tester,
  ) async {
    final c = await pumpStafflineApp(tester);
    await tester.tap(find.byTooltip('Ankit Patel, account menu'));
    await tester.pumpAndSettle();
    expect(find.text('Owner · Meridian Textiles'), findsOneWidget);
    await tester.tap(find.text('Switch organization…'));
    await tester.pumpAndSettle();
    expect(currentPath(c), AppRoutes.chooseOrganization);

    await tester.tap(find.text('Patel Dyes & Chemicals'));
    await tester.pumpAndSettle();
    expect(c.read(sessionProvider)!.organizationName, 'Patel Dyes & Chemicals');
    expect(currentPath(c), AppRoutes.overview);
    // HR admin there: no Roles & Permissions.
    expect(find.text('Roles & Permissions'), findsNothing);

    await tester.tap(find.byTooltip('Ankit Patel, account menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(currentPath(c), AppRoutes.welcome);
  });

  testWidgets('employee on a phone gets bottom tabs, not a drawer', (
    tester,
  ) async {
    final c = await pumpStafflineApp(
      tester,
      signInAs: employee,
      size: const Size(390, 844),
    );
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byTooltip('Open navigation'), findsNothing);
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Leave'),
      ),
    );
    await tester.pumpAndSettle();
    expect(currentPath(c), AppRoutes.myLeave);
  });

  testWidgets(
    'leave approver phone tabs end with Approvals; profile via menu',
    (tester) async {
      final c = await pumpStafflineApp(
        tester,
        signInAs: leaveApprover,
        size: const Size(390, 844),
      );
      final bar = find.byType(NavigationBar);
      expect(
        find.descendant(of: bar, matching: find.text('Approvals')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: bar, matching: find.text('Profile')),
        findsNothing,
      );
      await tester.tap(find.byTooltip('Aarav Bhatt, account menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('My profile'));
      await tester.pumpAndSettle();
      expect(currentPath(c), AppRoutes.myProfile);
    },
  );

  testWidgets('employee sees ME heading in the sidebar on desktop', (
    tester,
  ) async {
    await pumpStafflineApp(tester, signInAs: leaveApprover);
    expect(find.text('ME'), findsOneWidget);
    expect(find.text('MY TEAM'), findsOneWidget);
  });
}
