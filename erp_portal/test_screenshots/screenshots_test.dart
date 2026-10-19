// Generates review screenshots with the real fonts. Not part of the
// regression suite (`flutter test` only runs test/). Regenerate with:
//
//   flutter test test_screenshots --update-goldens
//
// Images are written to test_screenshots/output/.
import 'dart:convert';
import 'dart:io';

import 'package:erp_portal/app/router/app_router.dart';
import 'package:erp_portal/app/router/route_names.dart';
import 'package:erp_portal/features/auth/data/demo_auth_repository.dart';
import 'package:erp_portal/features/auth/presentation/providers/auth_providers.dart';
import 'package:erp_portal/features/employees/domain/employee_import.dart';
import 'package:erp_portal/features/employees/presentation/providers/import_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/test_helpers/pump_app.dart';
import '../test/unit/features/employee_import_test.dart' show sampleCsv;

Future<void> _loadFonts() async {
  Future<ByteData> asset(String name) => rootBundle.load('assets/fonts/$name');
  await (FontLoader('IBMPlexSans')
        ..addFont(asset('IBMPlexSans-Regular.ttf'))
        ..addFont(asset('IBMPlexSans-Medium.ttf'))
        ..addFont(asset('IBMPlexSans-SemiBold.ttf')))
      .load();
  await (FontLoader('IBMPlexMono')
        ..addFont(asset('IBMPlexMono-Regular.ttf'))
        ..addFont(asset('IBMPlexMono-Medium.ttf')))
      .load();
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  final icons = File(
    '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  if (icons.existsSync()) {
    final bytes = icons.readAsBytesSync();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
  }
}

void main() {
  setUpAll(_loadFonts);
  onboardingShots();
  importShots();
  employeeShots();
  leaveShots();
  phase7Shots();
  phase8Shots();

  final shots = <(String, Size, String)>[
    ('overview_1440', const Size(1440, 900), AppRoutes.overview),
    ('gallery_1440', const Size(1440, 3200), AppRoutes.designSystem),
    ('gallery_tablet_768', const Size(768, 3600), AppRoutes.designSystem),
    ('gallery_phone_390', const Size(390, 5200), AppRoutes.designSystem),
    ('overview_phone_390', const Size(390, 844), AppRoutes.overview),
    // Phase 3.
    ('s23_setup_home_1440', const Size(1440, 1400), AppRoutes.overview),
    ('s23_setup_home_phone_390', const Size(390, 2400), AppRoutes.overview),
    ('s16_owner_profile_1440', const Size(1440, 1100), AppRoutes.ownerProfile),
    ('s18_new_branch_1440', const Size(1440, 1700), AppRoutes.newBranch),
    ('s18_new_branch_phone_390', const Size(390, 2600), AppRoutes.newBranch),
    (
      's20_setup_checklist_1440',
      const Size(1440, 1300),
      '/branches/b-sur/setup',
    ),
    (
      's21_panel_attendance_1440',
      const Size(1440, 1000),
      '/branches/b-vad/setup?step=attendance',
    ),
    (
      's21_panel_holidays_1440',
      const Size(1440, 1000),
      '/branches/b-sur/setup?step=holidays',
    ),
    (
      's21_panel_roles_phone_390',
      const Size(390, 1200),
      '/branches/b-sur/setup?step=roles',
    ),
    (
      's22_setup_complete_1440',
      const Size(1440, 1300),
      '/branches/b-ahm/setup',
    ),
    ('s35_org_profile_1440', const Size(1440, 1200), AppRoutes.organization),
    ('s36_branches_1440', const Size(1440, 900), AppRoutes.branches),
    ('s36_branches_phone_390', const Size(390, 1200), AppRoutes.branches),
    ('s37_branch_edit_1440', const Size(1440, 2000), '/branches/b-sur/edit'),
    ('s38_branch_detail_1440', const Size(1440, 1000), '/branches/b-sur'),
    // Phase 4.
    ('s39_directory_1440', const Size(1440, 1000), AppRoutes.employees),
    ('s40_directory_tablet_768', const Size(768, 1100), AppRoutes.employees),
    ('s41_directory_phone_390', const Size(390, 1400), AppRoutes.employees),
    ('s42_profile_1440', const Size(1440, 1000), '/employees/e-13'),
    ('s43_add_employee_1440', const Size(1440, 2600), AppRoutes.newEmployee),
    ('s44_edit_employee_1440', const Size(1440, 2400), '/employees/e-13/edit'),
    ('s30_dashboard_1440', const Size(1440, 1900), AppRoutes.overview),
    ('s31_dashboard_tablet_768', const Size(768, 2200), AppRoutes.overview),
    ('s32_dashboard_phone_390', const Size(390, 2600), AppRoutes.overview),
    (
      's45_field_builder_1440',
      const Size(1440, 1300),
      AppRoutes.employeeFields,
    ),
    (
      's46_import_upload_1440',
      const Size(1440, 1000),
      AppRoutes.employeeImport,
    ),
    (
      's51_import_past_results_1440',
      const Size(1440, 1000),
      '/employees/import/results/imp-3',
    ),
    // Phase 5.
    (
      's52_attendance_overview_1440',
      const Size(1440, 1300),
      AppRoutes.attendance,
    ),
    (
      's53_records_1440',
      const Size(1440, 1200),
      '/attendance/records?date=2026-10-13&branch=b-sur',
    ),
    (
      's54_missing_punches_1440',
      const Size(1440, 1300),
      AppRoutes.missingPunches,
    ),
    (
      's55_correction_1440',
      const Size(1440, 1200),
      '/attendance/correct/e-10/2026-10-13',
    ),
    (
      's55_corrections_list_1440',
      const Size(1440, 1100),
      AppRoutes.corrections,
    ),
    ('s56_monthly_1440', const Size(1440, 1500), AppRoutes.monthlySummary),
    ('s52_attendance_phone_390', const Size(390, 2400), AppRoutes.attendance),
  ];

  for (final (name, size, route) in shots) {
    testWidgets(name, (tester) async {
      await pumpStafflineApp(tester, size: size, location: route);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('output/$name.png'),
      );
    });
  }

  final signedOutShots = <(String, Size, String)>[
    ('s03_welcome_1440', const Size(1440, 900), AppRoutes.welcome),
    ('s03_welcome_phone_390', const Size(390, 1500), AppRoutes.welcome),
    ('s04_register_1440', const Size(1440, 1300), AppRoutes.register),
    ('s07_forgot_1440', const Size(1440, 900), AppRoutes.forgotPassword),
    (
      's09_invite_phone_390',
      const Size(390, 1400),
      '${AppRoutes.acceptInvite}?token=${DemoAuthRepository.demoInviteToken}',
    ),
  ];
  for (final (name, size, route) in signedOutShots) {
    testWidgets(name, (tester) async {
      await pumpStafflineApp(
        tester,
        signInAs: null,
        size: size,
        location: route,
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('output/$name.png'),
      );
    });
  }

  testWidgets('s06_two_step_1440', (tester) async {
    final c = await pumpStafflineApp(
      tester,
      signInAs: null,
      size: const Size(1440, 1000),
    );
    await c
        .read(authControllerProvider.notifier)
        .signIn(
          identifier: owner,
          password: DemoAuthRepository.demoPassword,
          keepSignedIn: false,
        );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('output/s06_two_step_1440.png'),
    );
    await c
        .read(authControllerProvider.notifier)
        .verifyTwoStep(
          code: DemoAuthRepository.demoAuthenticatorCode,
          isBackupCode: false,
          trustDevice: false,
        );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('output/s10_choose_org_1440.png'),
    );
  });

  testWidgets('s72_access_denied_1440', (tester) async {
    await pumpStafflineApp(
      tester,
      signInAs: hrAdmin,
      location: AppRoutes.roles,
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('output/s72_access_denied_1440.png'),
    );
  });

  testWidgets('employee_tabs_phone_390', (tester) async {
    await pumpStafflineApp(
      tester,
      signInAs: employee,
      size: const Size(390, 844),
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('output/employee_tabs_phone_390.png'),
    );
  });

  testWidgets('drawer_phone_390', (tester) async {
    await pumpStafflineApp(tester, size: const Size(390, 844));
    await tester.tap(find.byTooltip('Open navigation'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('output/drawer_phone_390.png'),
    );
  });

  testWidgets('side_panel_1440', (tester) async {
    await pumpStafflineApp(
      tester,
      // Tall enough that the button is on screen without scrolling.
      size: const Size(1440, 3200),
      location: AppRoutes.designSystem,
    );
    await tester.tap(find.text('Side panel'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('output/side_panel_1440.png'),
    );
  });
}

/// Brand-new accounts: S12 and S13 before any organization exists.
void onboardingShots() {
  for (final (name, route) in [
    ('s12_onboarding_start_1440', AppRoutes.onboarding),
    ('s13_create_org_1440', AppRoutes.createOrganization),
  ]) {
    testWidgets(name, (tester) async {
      final c = await pumpStafflineApp(
        tester,
        signInAs: null,
        size: const Size(1440, 1000),
      );
      final auth = c.read(authControllerProvider.notifier);
      await auth.register(
        fullName: 'Riya Shah',
        email: 'riya@shreeweaves.in',
        password: DemoAuthRepository.demoPassword,
      );
      await auth.verifyEmail(DemoAuthRepository.demoEmailCode);
      c.read(appRouterProvider).go(route);
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('output/$name.png'),
      );
    });
  }
}

/// Import wizard steps (boards S47–S51), driven through the controller.
void employeeShots() {
  for (final (name, size, route) in [
    ('s86_employee_home_390', const Size(390, 1500), AppRoutes.home),
    ('s86_employee_home_1440', const Size(1440, 1000), AppRoutes.home),
    ('s87_my_attendance_390', const Size(390, 1500), AppRoutes.myAttendance),
    ('s88_day_detail_390', const Size(390, 1300), '/my/attendance/2026-10-13'),
  ]) {
    testWidgets(name, (tester) async {
      await pumpStafflineApp(
        tester,
        size: size,
        signInAs: employee,
        location: route,
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('output/$name.png'),
      );
    });
  }
}

void importShots() {
  testWidgets('s47_s51_import_steps_1440', (tester) async {
    final c = await pumpStafflineApp(
      tester,
      size: const Size(1440, 1300),
      location: AppRoutes.employeeImport,
    );
    final controller = c.read(importControllerProvider.notifier);
    Future<void> shot(String name) async {
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('output/$name.png'),
      );
    }

    // The load yields once so its "Reading file…" state can paint; pump
    // to let it finish.
    final loading = controller.loadFile(
      'surat_staff_oct.csv',
      Uint8List.fromList(utf8.encode(sampleCsv)),
    );
    await tester.pumpAndSettle();
    await loading;
    await shot('s46_import_ready_1440');
    controller.goTo(ImportStep.mapping);
    await shot('s47_import_mapping_1440');
    controller.setDateOrder(DateOrder.dayFirst);
    final validating = controller.validate();
    await tester.pumpAndSettle();
    await validating;
    await shot('s48_import_validate_1440');
    controller
      ..goTo(ImportStep.duplicates)
      ..setPolicy(DuplicatePolicy.update);
    await shot('s49_import_duplicates_1440');
    controller
      ..setAcknowledged(true)
      ..goTo(ImportStep.confirm);
    await shot('s50_import_confirm_1440');
    final committing = controller.commit();
    await tester.pump();
    await committing;
    await shot('s51_import_results_1440');
  });

  testWidgets('s33_branch_dashboard_1440', (tester) async {
    await pumpStafflineApp(
      tester,
      size: const Size(1440, 1100),
      signInAs: branchManager,
      location: AppRoutes.branchDashboard,
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('output/s33_branch_dashboard_1440.png'),
    );
  });
}

void leaveShots() {
  for (final (name, size, account, route) in [
    ('s62_calendar_1440', const Size(1440, 1500), hrAdmin, '/holidays'),
    ('s62_calendar_390', const Size(390, 2000), hrAdmin, '/holidays'),
    ('s63_list_1440', const Size(1440, 1200), hrAdmin, '/holidays/list'),
    ('s64_new_holiday_1440', const Size(1440, 1300), hrAdmin, '/holidays/new'),
    ('s65_import_1440', const Size(1440, 900), hrAdmin, '/holidays/import'),
    (
      's66_schedules_1440',
      const Size(1440, 1000),
      hrAdmin,
      '/holidays/schedules',
    ),
    (
      's62_calendar_bm_1440',
      const Size(1440, 1300),
      branchManager,
      '/holidays',
    ),
    (
      's57_approvals_bm_1440',
      const Size(1440, 1100),
      branchManager,
      AppRoutes.leave,
    ),
    ('s57_approvals_hr_1440', const Size(1440, 1100), hrAdmin, AppRoutes.leave),
    (
      's57_approvals_390',
      const Size(390, 1400),
      branchManager,
      AppRoutes.leave,
    ),
    (
      's61_requests_1440',
      const Size(1440, 1300),
      hrAdmin,
      AppRoutes.leaveRequests,
    ),
    (
      's60_balances_1440',
      const Size(1440, 1300),
      hrAdmin,
      AppRoutes.leaveBalances,
    ),
    ('s58_types_1440', const Size(1440, 2000), hrAdmin, AppRoutes.leaveTypes),
    ('s59_policy_1440', const Size(1440, 1500), hrAdmin, AppRoutes.leavePolicy),
    ('s58_types_390', const Size(390, 3600), hrAdmin, AppRoutes.leaveTypes),
    (
      's34_team_approvals_1440',
      const Size(1440, 1200),
      leaveApprover,
      AppRoutes.teamApprovals,
    ),
    (
      's34_team_approvals_390',
      const Size(390, 1800),
      leaveApprover,
      AppRoutes.teamApprovals,
    ),
  ]) {
    testWidgets(name, (tester) async {
      await pumpStafflineApp(
        tester,
        size: size,
        signInAs: account,
        location: route,
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('output/$name.png'),
      );
    });
  }
  testWidgets('s91_request_390', (tester) async {
    await pumpStafflineApp(
      tester,
      size: const Size(390, 1300),
      signInAs: employee,
      location: AppRoutes.myLeave,
    );
    await tapText(tester, 'Casual · Mon 19 Oct');
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('output/s91_request_390.png'),
    );
    await tapText(tester, 'Withdraw request');
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('output/s91_withdraw_sheet_390.png'),
    );
  });
  for (final (name, size, route) in [
    ('s90_my_leave_390', const Size(390, 1300), AppRoutes.myLeave),
    ('s90_my_leave_1440', const Size(1440, 1100), AppRoutes.myLeave),
    (
      's89_apply_overlap_390',
      const Size(390, 1500),
      '${AppRoutes.applyLeave}?type=casual&from=2026-10-19&to=2026-10-21',
    ),
    (
      's89_apply_1440',
      const Size(1440, 1300),
      '${AppRoutes.applyLeave}?type=casual&from=2026-10-27&to=2026-10-28',
    ),
    ('s92_history_390', const Size(390, 1500), AppRoutes.leaveHistory),
    ('s93_my_holidays_390', const Size(390, 1300), AppRoutes.myHolidays),
    ('s86_employee_home_leave_390', const Size(390, 1600), AppRoutes.home),
  ]) {
    testWidgets(name, (tester) async {
      await pumpStafflineApp(
        tester,
        size: size,
        signInAs: employee,
        location: route,
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('output/$name.png'),
      );
    });
  }
}

void phase7Shots() {
  for (final (name, size, account, route) in [
    ('s67_roles_1440', const Size(1440, 900), owner, '/roles'),
    (
      'p8_hr_organization_1440',
      const Size(1440, 1100),
      hrAdmin,
      '/organization',
    ),
    ('p8_hr_branches_1440', const Size(1440, 900), hrAdmin, '/branches'),
    (
      'p8_hr_branch_detail_1440',
      const Size(1440, 1100),
      hrAdmin,
      '/branches/b-sur',
    ),
    ('s73_reports_1440', const Size(1440, 1300), hrAdmin, '/reports'),
    (
      's74_results_1440',
      const Size(1440, 1100),
      hrAdmin,
      '/reports/results?report=monthly&from=2026-10-01&to=2026-10-14',
    ),
    ('s75_exports_1440', const Size(1440, 900), hrAdmin, '/reports/exports'),
    ('s73_reports_bm_390', const Size(390, 2600), branchManager, '/reports'),
    ('s80_settings_1440', const Size(1440, 1000), owner, '/settings'),
    (
      's79_attendance_policy_1440',
      const Size(1440, 1100),
      owner,
      '/settings/attendance',
    ),
    (
      's81_schedules_1440',
      const Size(1440, 1300),
      owner,
      '/settings/schedules',
    ),
    (
      's82_notification_settings_1440',
      const Size(1440, 1500),
      owner,
      '/settings/notifications',
    ),
    ('s83_security_1440', const Size(1440, 1200), owner, '/settings/security'),
    ('s84_data_1440', const Size(1440, 1500), owner, '/settings/data'),
    ('s85_branding_1440', const Size(1440, 1400), owner, '/settings/branding'),
    (
      's82_notification_settings_390',
      const Size(390, 2400),
      owner,
      '/settings/notifications',
    ),
    (
      's76_notifications_1440',
      const Size(1440, 900),
      hrAdmin,
      '/notifications',
    ),
    (
      's95_my_notifications_390',
      const Size(390, 1000),
      employee,
      '/my/notifications',
    ),
    ('s77_audit_log_1440', const Size(1440, 1100), owner, '/audit-log'),
    (
      's78_audit_event_1440',
      const Size(1440, 1000),
      owner,
      '/audit-log/evt_8f2206',
    ),
    (
      's68_role_editor_1440',
      const Size(1440, 1500),
      owner,
      '/roles/branchManager',
    ),
    (
      's69_role_editor_390',
      const Size(390, 2400),
      owner,
      '/roles/branchManager',
    ),
    ('s70_people_1440', const Size(1440, 1000), owner, '/roles/people'),
    (
      's71_invitations_1440',
      const Size(1440, 1100),
      owner,
      '/roles/invitations',
    ),
  ]) {
    testWidgets(name, (tester) async {
      await pumpStafflineApp(
        tester,
        size: size,
        signInAs: account,
        location: route,
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('output/$name.png'),
      );
    });
  }
}

/// Phase 8: the responsive matrix. Each image is exactly one viewport.
void phase8Shots() {
  const sizes = [
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
  const pages = [
    ('overview', owner, AppRoutes.overview),
    ('employees', owner, AppRoutes.employees),
    ('my_attendance', employee, AppRoutes.myAttendance),
  ];
  for (final size in sizes) {
    final tag = '${size.width.toInt()}x${size.height.toInt()}';
    for (final (page, account, route) in pages) {
      final name = 'p8_${page}_$tag';
      testWidgets(name, (tester) async {
        await pumpStafflineApp(
          tester,
          size: size,
          signInAs: account,
          location: route,
        );
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('output/p8/$name.png'),
        );
      });
    }
  }
  for (final (name, size, account, route) in [
    ('p8_text200_overview_390', const Size(390, 844), owner, '/overview'),
    ('p8_text200_employees_1440', const Size(1440, 900), owner, '/employees'),
    ('p8_text200_my_leave_390', const Size(390, 844), employee, '/my/leave'),
  ]) {
    testWidgets(name, (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpStafflineApp(
        tester,
        size: size,
        signInAs: account,
        location: route,
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('output/p8/$name.png'),
      );
    });
  }
}
