import 'package:erp_portal/app/router/app_router.dart';
import 'package:erp_portal/app/router/route_names.dart';
import 'package:erp_portal/features/employees/presentation/providers/employee_providers.dart';
import 'package:erp_portal/features/leave/domain/leave.dart';
import 'package:erp_portal/features/leave/presentation/leave_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_helpers/pump_app.dart';

final adminPages = <String>[
  AppRoutes.leave,
  '${AppRoutes.leave}?request=L-2505',
  AppRoutes.leaveRequests,
  AppRoutes.leaveBalances,
  AppRoutes.leaveTypes,
  AppRoutes.leavePolicy,
  AppRoutes.holidays,
  AppRoutes.holidayList,
  AppRoutes.holidayImport,
  AppRoutes.schedules,
  AppRoutes.newHoliday,
  // Dussehra (upcoming) and Gandhi Jayanti (past) from the demo calendar.
  AppRoutes.holidayEdit('hol-9'),
  AppRoutes.holidayEdit('hol-8'),
  AppRoutes.overview,
  '/employees/e-13',
];

/// Isha's own pages, including her pending request.
Future<List<String>> employeePages(ProviderContainer c) async {
  await c.read(leaveDataProvider.future);
  final self = c.read(selfEmployeeProvider)!;
  final mine = c
      .read(leaveDataProvider)
      .value!
      .requests
      .where((r) => r.employeeId == self.id)
      .toList();
  return [
    AppRoutes.home,
    AppRoutes.myLeave,
    '${AppRoutes.applyLeave}?type=casual&from=2026-10-19&to=2026-10-21',
    AppRoutes.leaveHistory,
    AppRoutes.myHolidays,
    for (final r in mine.take(3)) AppRoutes.myLeaveRequest(r.id),
    '${AppRoutes.applyLeave}?amend=${mine.firstWhere((r) => r.status == LeaveStatus.pending).id}',
  ];
}

const widths = <Size>[
  Size(320, 568),
  Size(390, 844),
  Size(768, 1024),
  Size(1024, 768),
  Size(1440, 900),
];

Future<void> visit(
  WidgetTester tester,
  ProviderContainer c,
  List<String> pages,
) async {
  for (final page in pages) {
    c.read(appRouterProvider).go(page);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: page);
  }
}

void main() {
  for (final size in widths) {
    testWidgets('leave and holiday pages lay out at ${size.width.toInt()} px', (
      tester,
    ) async {
      var c = await pumpStafflineApp(tester, size: size);
      await visit(tester, c, adminPages);
      c = await pumpStafflineApp(tester, size: size, signInAs: branchManager);
      await visit(tester, c, [
        AppRoutes.leave,
        AppRoutes.branchDashboard,
        AppRoutes.holidays,
      ]);
      c = await pumpStafflineApp(tester, size: size, signInAs: leaveApprover);
      await visit(tester, c, [AppRoutes.teamApprovals, AppRoutes.myLeave]);
      c = await pumpStafflineApp(tester, size: size, signInAs: employee);
      await visit(tester, c, await employeePages(c));
    });
  }

  testWidgets('leave and holiday pages at 200% text on a 390 px phone', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    const size = Size(390, 844);
    var c = await pumpStafflineApp(tester, size: size);
    await visit(tester, c, adminPages);
    c = await pumpStafflineApp(tester, size: size, signInAs: leaveApprover);
    await visit(tester, c, [AppRoutes.teamApprovals]);
    c = await pumpStafflineApp(tester, size: size, signInAs: employee);
    await visit(tester, c, await employeePages(c));
  });
}
