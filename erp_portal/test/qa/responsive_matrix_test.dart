// Phase 8 responsive QA: every major screen for each role at the brief's
// nine sizes, intermediate widths, live resizing and text scaling.
import 'package:erp_portal/app/router/app_router.dart';
import 'package:erp_portal/app/router/route_names.dart';
import 'package:erp_portal/features/auth/data/demo_auth_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers/pump_app.dart';

const matrix = <Size>[
  Size(320, 568),
  Size(375, 667),
  Size(390, 844),
  Size(430, 932),
  Size(768, 1024),
  Size(1024, 768),
  Size(1280, 800),
  Size(1440, 900),
  Size(1920, 1080),
];

/// Widths between the breakpoints, where layouts switch.
const intermediate = <Size>[
  Size(600, 900),
  Size(720, 900),
  Size(900, 900),
  Size(1100, 900),
  Size(1600, 900),
];

final pagesByRole = <String, List<String>>{
  owner: [
    AppRoutes.overview,
    AppRoutes.organization,
    AppRoutes.branches,
    AppRoutes.branch('b-sur'),
    AppRoutes.employees,
    '/employees/e-13',
    AppRoutes.newEmployee,
    AppRoutes.employeeImport,
    AppRoutes.attendance,
    AppRoutes.attendanceRecords,
    AppRoutes.missingPunches,
    AppRoutes.monthlySummary,
    AppRoutes.faceCheck,
    AppRoutes.leave,
    AppRoutes.leaveRequests,
    AppRoutes.leaveBalances,
    AppRoutes.leaveTypes,
    AppRoutes.leavePolicy,
    AppRoutes.holidays,
    AppRoutes.holidayList,
    AppRoutes.newHoliday,
    AppRoutes.schedules,
    AppRoutes.roles,
    AppRoutes.role('branchManager'),
    AppRoutes.people,
    AppRoutes.invitations,
    AppRoutes.reports,
    '${AppRoutes.reportResults}?report=monthly&from=2026-10-01&to=2026-10-14',
    AppRoutes.exportHistory,
    AppRoutes.notifications,
    AppRoutes.settings,
    AppRoutes.settingsNotifications,
    AppRoutes.settingsData,
    AppRoutes.auditLog,
    AppRoutes.auditEvent('evt_8f2206'),
  ],
  branchManager: [
    AppRoutes.branchDashboard,
    AppRoutes.employees,
    AppRoutes.attendance,
    AppRoutes.leave,
    AppRoutes.holidays,
    AppRoutes.reports,
  ],
  leaveApprover: [AppRoutes.teamApprovals, AppRoutes.myLeave],
  employee: [
    AppRoutes.home,
    AppRoutes.myAttendance,
    AppRoutes.myLeave,
    '${AppRoutes.applyLeave}?type=casual&from=2026-10-19&to=2026-10-21',
    AppRoutes.leaveHistory,
    AppRoutes.myHolidays,
    AppRoutes.myNotifications,
    AppRoutes.myProfile,
    AppRoutes.myFace,
  ],
  DemoAuthRepository.platformAdminEmail: [
    AppRoutes.platform,
    AppRoutes.platformOrg('org_meridian-tex'),
  ],
};

Future<void> visitAll(
  WidgetTester tester,
  ProviderContainer c,
  List<String> pages,
  String label,
) async {
  for (final page in pages) {
    c.read(appRouterProvider).go(page);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: '$label $page');
    // No page-level horizontal overflow: nothing paints past the screen.
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    for (final box in find.byType(Scaffold).evaluate()) {
      final r = box.renderObject! as RenderBox;
      expect(
        r.size.width,
        lessThanOrEqualTo(size.width + 0.5),
        reason: '$label $page scaffold wider than the screen',
      );
    }
  }
}

void main() {
  for (final size in [...matrix, ...intermediate]) {
    for (final role in pagesByRole.keys) {
      testWidgets('${size.width.toInt()}×${size.height.toInt()} · $role', (
        tester,
      ) async {
        final c = await pumpStafflineApp(tester, size: size, signInAs: role);
        await visitAll(tester, c, pagesByRole[role]!, '$size');
      });
    }
  }

  for (final scale in [1.3, 2.0]) {
    for (final size in const [Size(390, 844), Size(1440, 900)]) {
      testWidgets('text ×$scale at ${size.width.toInt()} px', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        for (final role in pagesByRole.keys) {
          final c = await pumpStafflineApp(tester, size: size, signInAs: role);
          await visitAll(tester, c, pagesByRole[role]!, 'x$scale $role');
        }
      });
    }
  }

  testWidgets('resizing the window keeps each page usable', (tester) async {
    final c = await pumpStafflineApp(tester, size: const Size(1920, 1080));
    for (final page in const [
      AppRoutes.overview,
      AppRoutes.employees,
      AppRoutes.leave,
      AppRoutes.reports,
    ]) {
      c.read(appRouterProvider).go(page);
      await tester.pumpAndSettle();
      for (final w in const [
        1920.0,
        1280.0,
        1024.0,
        768.0,
        600.0,
        390.0,
        320.0,
        1440.0,
      ]) {
        tester.view.physicalSize = Size(w, 900);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$page at $w');
      }
      expect(currentPath(c), page);
    }
  });

  testWidgets('dialogs and side panels stay inside a 320 px screen', (
    tester,
  ) async {
    const screen = Size(320, 568);
    void inside(Finder f, String what) {
      final r = tester.getRect(f.first);
      expect(r.left, greaterThanOrEqualTo(-0.5), reason: what);
      expect(r.right, lessThanOrEqualTo(screen.width + 0.5), reason: what);
      expect(r.top, greaterThanOrEqualTo(-0.5), reason: what);
      expect(r.bottom, lessThanOrEqualTo(screen.height + 0.5), reason: what);
    }

    final c = await pumpStafflineApp(
      tester,
      size: screen,
      location: AppRoutes.people,
    );
    final change = find.bySemanticsLabel('Change role of Aarav Bhatt');
    await tester.ensureVisible(change);
    await tester.pumpAndSettle();
    await tester.tap(change);
    await tester.pumpAndSettle();
    inside(find.byType(Dialog), 'change role dialog');
    await tapText(tester, 'Cancel');

    c.read(appRouterProvider).go(AppRoutes.leaveBalances);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Adjust').first);
    await tester.tap(find.text('Adjust').first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    inside(find.text('Adjust balance'), 'adjust side panel title');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Adjust balance'), findsNothing, reason: 'Escape closes');

    c.read(appRouterProvider).go(AppRoutes.role('branchManager'));
    await tester.pumpAndSettle();
    // Area cards: switch one ability off.
    final approve = find.bySemanticsLabel('Leave: Approve or reject leave');
    await tester.ensureVisible(approve);
    await tester.pumpAndSettle();
    await tester.tap(approve);
    await tester.pumpAndSettle();
    await tapText(tester, 'Review & save');
    inside(find.byType(AlertDialog), 'review dialog');
    expect(tester.takeException(), isNull);
  });
}
