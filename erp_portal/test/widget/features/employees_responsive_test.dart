import 'package:erp_portal/app/router/app_router.dart';
import 'package:erp_portal/app/router/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_helpers/pump_app.dart';

/// Every Phase 4 page (Isha is e-13 in the seed). Layout errors fail on
/// their own.
final pages = <String>[
  AppRoutes.overview,
  AppRoutes.employees,
  AppRoutes.employee('e-13'),
  AppRoutes.newEmployee,
  AppRoutes.employeeEdit('e-13'),
  AppRoutes.employeeImport,
  AppRoutes.importResult('imp-3'),
  AppRoutes.employeeFields,
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
    testWidgets('Phase 4 pages lay out at ${size.width.toInt()} px', (
      tester,
    ) async {
      final c = await pumpStafflineApp(tester, size: size);
      for (final page in pages) {
        c.read(appRouterProvider).go(page);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: page);
      }
      // Profile tabs and the field editor have their own layouts.
      c.read(appRouterProvider).go(AppRoutes.employee('e-13'));
      await tester.pumpAndSettle();
      for (final tab in [
        'Attendance',
        'Leave & balances',
        'Custom fields',
        'Activity',
      ]) {
        await tester.ensureVisible(find.text(tab).last);
        await tester.tap(find.text(tab).last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: tab);
      }
      c.read(appRouterProvider).go(AppRoutes.employeeFields);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Uniform size').first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'field editor');
    });
  }

  testWidgets('branch dashboard at 320 and 1440 px', (tester) async {
    for (final size in [const Size(320, 568), const Size(1440, 900)]) {
      await pumpStafflineApp(
        tester,
        size: size,
        signInAs: branchManager,
        location: AppRoutes.branchDashboard,
      );
      expect(tester.takeException(), isNull, reason: '$size');
    }
  });

  testWidgets('Phase 4 pages at 200% text on a 390 px phone', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final c = await pumpStafflineApp(tester, size: const Size(390, 844));
    for (final page in [...pages, AppRoutes.branchDashboard]) {
      c.read(appRouterProvider).go(page);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: page);
    }
  });
}
