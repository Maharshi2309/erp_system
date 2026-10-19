import 'package:erp_portal/app/router/app_router.dart';
import 'package:erp_portal/app/router/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_helpers/pump_app.dart';

final adminPages = <String>[
  AppRoutes.attendance,
  '${AppRoutes.attendanceRecords}?date=2026-10-13&branch=b-sur',
  AppRoutes.missingPunches,
  '/attendance/correct/e-10/2026-10-13',
  AppRoutes.corrections,
  AppRoutes.monthlySummary,
  AppRoutes.attendanceExports,
  AppRoutes.overview,
];

final employeePages = <String>[
  AppRoutes.home,
  AppRoutes.myAttendance,
  '/my/attendance/2026-10-13',
  '/my/attendance/2026-10-14',
];

const widths = <Size>[
  Size(320, 568),
  Size(390, 844),
  Size(768, 1024),
  Size(1024, 768),
  Size(1440, 900),
];

void main() {
  for (final size in widths) {
    testWidgets('attendance pages lay out at ${size.width.toInt()} px', (
      tester,
    ) async {
      var c = await pumpStafflineApp(tester, size: size);
      for (final page in adminPages) {
        c.read(appRouterProvider).go(page);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: page);
      }
      for (final view in ['Weekly', 'Monthly']) {
        c.read(appRouterProvider).go(AppRoutes.attendance);
        await tester.pumpAndSettle();
        await tester.tap(find.text(view).first);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: view);
      }
      c = await pumpStafflineApp(tester, size: size, signInAs: employee);
      for (final page in employeePages) {
        c.read(appRouterProvider).go(page);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: page);
      }
    });
  }

  testWidgets('attendance pages at 200% text on a 390 px phone', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    var c = await pumpStafflineApp(tester, size: const Size(390, 844));
    for (final page in adminPages) {
      c.read(appRouterProvider).go(page);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: page);
    }
    c = await pumpStafflineApp(
      tester,
      size: const Size(390, 844),
      signInAs: employee,
    );
    for (final page in employeePages) {
      c.read(appRouterProvider).go(page);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: page);
    }
  });
}
