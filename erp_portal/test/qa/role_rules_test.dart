// The portal rule book (docs/qa/rule_book.md) as tests: which pages each
// role opens, and the data-scope and permission rules found in role QA.
import 'package:erp_portal/app/router/app_router.dart';
import 'package:erp_portal/app/router/route_names.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers/pump_app.dart';

const roles = [
  owner,
  hrAdmin,
  branchManager,
  attendanceManager,
  leaveApprover,
  employee,
];

/// Page → which of [roles] may open it (1) or are refused (0).
const access = <String, String>{
  AppRoutes.overview: '111000',
  AppRoutes.organization: '111000',
  AppRoutes.ownerProfile: '100000',
  AppRoutes.branches: '111000',
  AppRoutes.newBranch: '100000',
  '/branches/b-sur/edit': '100000',
  AppRoutes.employees: '111000',
  AppRoutes.newEmployee: '111000',
  AppRoutes.employeeImport: '110000',
  AppRoutes.employeeFields: '110000',
  AppRoutes.branchDashboard: '111000',
  AppRoutes.attendance: '111100',
  AppRoutes.attendanceRecords: '111100',
  AppRoutes.attendanceExports: '111100',
  AppRoutes.faceCheck: '111100',
  AppRoutes.leave: '111010',
  AppRoutes.leaveBalances: '111010',
  AppRoutes.leaveTypes: '110000',
  AppRoutes.leavePolicy: '110000',
  AppRoutes.holidays: '111000',
  AppRoutes.newHoliday: '110000',
  AppRoutes.holidayImport: '110000',
  AppRoutes.roles: '100000',
  AppRoutes.people: '100000',
  AppRoutes.newRole: '100000',
  AppRoutes.invitations: '111000',
  AppRoutes.reports: '111000',
  AppRoutes.exportHistory: '111000',
  AppRoutes.settings: '110000',
  AppRoutes.settingsAttendance: '110000',
  AppRoutes.settingsSecurity: '100000',
  AppRoutes.settingsData: '100000',
  AppRoutes.auditLog: '110000',
  AppRoutes.teamApprovals: '111010',
  AppRoutes.home: '111111',
  AppRoutes.myAttendance: '111111',
  AppRoutes.myLeave: '111111',
  AppRoutes.myHolidays: '111111',
  AppRoutes.myProfile: '111111',
  AppRoutes.myFace: '111111',
  AppRoutes.myNotifications: '111111',
};

const landing = {
  owner: AppRoutes.overview,
  hrAdmin: AppRoutes.overview,
  branchManager: AppRoutes.branchDashboard,
  attendanceManager: AppRoutes.attendance,
  leaveApprover: AppRoutes.teamApprovals,
  employee: AppRoutes.home,
};

void main() {
  for (final (i, role) in roles.indexed) {
    testWidgets('$role lands on their home and opens only allowed pages', (
      tester,
    ) async {
      final c = await pumpStafflineApp(tester, signInAs: role);
      expect(currentPath(c), landing[role]);
      for (final MapEntry(key: page, value: allowed) in access.entries) {
        c.read(appRouterProvider).go(page);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$role $page');
        expect(
          currentPath(c),
          allowed[i] == '1' ? page : AppRoutes.accessDenied,
          reason: '$role $page',
        );
      }
    });
  }

  group('branch manager (Surat)', () {
    testWidgets('sees only their branch in Branches', (tester) async {
      await pumpStafflineApp(
        tester,
        signInAs: branchManager,
        location: AppRoutes.branches,
      );
      expect(find.text('Surat'), findsWidgets);
      expect(find.text('Ahmedabad HQ'), findsNothing);
      expect(find.text('Vadodara'), findsNothing);
    });

    testWidgets('another branch’s page is not found', (tester) async {
      await pumpStafflineApp(
        tester,
        signInAs: branchManager,
        location: AppRoutes.branch('b-vad'),
      );
      expect(find.text('This branch doesn’t exist'), findsOneWidget);
    });

    testWidgets('sees only Surat invitations', (tester) async {
      await pumpStafflineApp(
        tester,
        signInAs: branchManager,
        location: AppRoutes.invitations,
      );
      expect(find.text('Chirag Vaghela'), findsWidgets);
      expect(find.text('Bhavesh Parmar'), findsNothing);
    });

    testWidgets('has no holiday export', (tester) async {
      await pumpStafflineApp(
        tester,
        signInAs: branchManager,
        location: AppRoutes.holidayList,
      );
      expect(find.text('Export'), findsNothing);
    });

    testWidgets('Overview by URL says it covers only their branch', (
      tester,
    ) async {
      await pumpStafflineApp(
        tester,
        signInAs: branchManager,
        location: AppRoutes.overview,
      );
      expect(find.textContaining('All my branches · 1 branch'), findsOneWidget);
    });
  });

  testWidgets('a leave approver can’t export leave', (tester) async {
    final c = await pumpStafflineApp(
      tester,
      signInAs: leaveApprover,
      location: AppRoutes.leaveRequests,
    );
    expect(find.text('Export'), findsNothing);
    c.read(appRouterProvider).go(AppRoutes.leaveBalances);
    await tester.pumpAndSettle();
    expect(find.text('Export balances'), findsNothing);
  });

  testWidgets('HR still exports leave and holidays', (tester) async {
    final c = await pumpStafflineApp(
      tester,
      signInAs: hrAdmin,
      location: AppRoutes.leaveRequests,
    );
    expect(find.text('Export'), findsOneWidget);
    c.read(appRouterProvider).go(AppRoutes.holidayList);
    await tester.pumpAndSettle();
    expect(find.text('Export'), findsOneWidget);
  });

  testWidgets('HR’s approvals page describes an organization-wide scope', (
    tester,
  ) async {
    await pumpStafflineApp(
      tester,
      signInAs: hrAdmin,
      location: AppRoutes.teamApprovals,
    );
    expect(
      find.text('You approve leave for everyone in the organization.'),
      findsOneWidget,
    );
  });
}
