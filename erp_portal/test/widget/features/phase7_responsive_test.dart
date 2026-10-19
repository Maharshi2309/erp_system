import 'package:erp_portal/app/router/app_router.dart';
import 'package:erp_portal/app/router/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_helpers/pump_app.dart';

final ownerPages = <String>[
  AppRoutes.roles,
  AppRoutes.role('branchManager'),
  AppRoutes.role('hrAdmin'),
  '${AppRoutes.newRole}?from=attendanceManager',
  AppRoutes.people,
  AppRoutes.invitations,
  AppRoutes.notifications,
  AppRoutes.auditLog,
  AppRoutes.auditEvent('evt_8f2206'),
  AppRoutes.settings,
  AppRoutes.settingsAttendance,
  AppRoutes.settingsSchedules,
  AppRoutes.settingsNotifications,
  AppRoutes.settingsSecurity,
  AppRoutes.settingsData,
  AppRoutes.settingsBranding,
  AppRoutes.reports,
  '${AppRoutes.reportResults}?report=monthly&from=2026-10-01&to=2026-10-14',
  '${AppRoutes.reportResults}?report=audit&from=2026-10-01&to=2026-10-14',
  AppRoutes.exportHistory,
];

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
    testWidgets('Phase 7 pages lay out at ${size.width.toInt()} px', (
      tester,
    ) async {
      var c = await pumpStafflineApp(tester, size: size);
      await visit(tester, c, ownerPages);
      c = await pumpStafflineApp(tester, size: size, signInAs: branchManager);
      await visit(tester, c, [AppRoutes.reports, AppRoutes.invitations]);
      c = await pumpStafflineApp(tester, size: size, signInAs: employee);
      await visit(tester, c, [AppRoutes.myNotifications, AppRoutes.myProfile]);
    });
  }

  testWidgets('Phase 7 pages at 200% text on a 390 px phone', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    const size = Size(390, 844);
    var c = await pumpStafflineApp(tester, size: size);
    await visit(tester, c, ownerPages);
    c = await pumpStafflineApp(tester, size: size, signInAs: employee);
    await visit(tester, c, [AppRoutes.myNotifications, AppRoutes.myProfile]);
  });
}
