// D-75: the platform super admin sees statistics about organizations and
// their use of Staffline — never personal data.
import 'package:erp_portal/app/router/app_router.dart';
import 'package:erp_portal/app/router/route_names.dart';
import 'package:erp_portal/features/auth/data/demo_auth_repository.dart';
import 'package:erp_portal/features/auth/domain/auth_state.dart';
import 'package:erp_portal/features/auth/presentation/providers/auth_providers.dart';
import 'package:erp_portal/features/employees/presentation/providers/employee_providers.dart';
import 'package:erp_portal/features/organization/presentation/providers/organization_providers.dart';
import 'package:erp_portal/features/platform/domain/platform_stats.dart';
import 'package:erp_portal/features/platform/presentation/platform_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_helpers/pump_app.dart';

const platformAdmin = DemoAuthRepository.platformAdminEmail;

/// Every text painted on screen.
List<String> shownTexts(WidgetTester tester) => [
  for (final e in find.byType(Text).evaluate())
    (e.widget as Text).data ?? (e.widget as Text).textSpan?.toPlainText() ?? '',
  for (final e in find.byType(RichText).evaluate())
    (e.widget as RichText).text.toPlainText(),
];

/// Names, emails and phone numbers of every person in every organization.
Future<Set<String>> personalData(ProviderContainer c) async {
  final orgs = c.read(organizationRepositoryProvider);
  final people = c.read(employeeRepositoryProvider);
  final snap = await c.read(platformSnapshotProvider.future);
  final out = <String>{};
  for (final o in snap.orgs) {
    for (final e in await people.employees(o.id)) {
      out
        ..add(e.fullName)
        ..add(e.workEmail)
        ..add(e.mobile);
    }
    final owner = await orgs.ownerProfile(o.id);
    if (owner != null) {
      out
        ..add(owner.fullName)
        ..add(owner.email);
    }
  }
  return out..removeWhere((x) => x.trim().isEmpty);
}

void main() {
  testWidgets('the super admin signs in with two-step and lands on the '
      'platform overview', (tester) async {
    final c = await pumpStafflineApp(tester, signInAs: platformAdmin);
    expect(c.read(authControllerProvider), isA<PlatformSignedIn>());
    expect(c.read(sessionProvider), isNull, reason: 'no organization session');
    expect(currentPath(c), AppRoutes.platform);
    expect(find.text('Platform overview'), findsOneWidget);
    expect(
      find.text('Signed in as platform admin · 2-step verified'),
      findsOneWidget,
    );
    final snap = await c.read(platformSnapshotProvider.future);
    expect(snap.orgs, hasLength(8));
    expect(find.text('8'), findsWidgets);
    expect(find.text('Meridian Textiles'), findsWidgets);
    expect(find.text('Coastal Craft Exports'), findsWidgets);
  });

  testWidgets('no personal data appears on the overview or a detail page', (
    tester,
  ) async {
    final c = await pumpStafflineApp(
      tester,
      signInAs: platformAdmin,
      size: const Size(1440, 4000),
    );
    final personal = await personalData(c);
    expect(personal, contains('Isha Rathod'));
    expect(personal, contains('Ankit Patel'));

    void check(String page) {
      final texts = shownTexts(tester);
      for (final t in texts) {
        expect(t.contains('@'), isFalse, reason: '$page shows "$t"');
        for (final p in personal) {
          expect(t.contains(p), isFalse, reason: '$page shows "$p" in "$t"');
        }
      }
    }

    check('overview');
    c.read(appRouterProvider).go(AppRoutes.platformOrg('org_meridian-tex'));
    await tester.pumpAndSettle();
    expect(find.text('Counts only — no people are listed'), findsOneWidget);
    expect(find.text('Surat'), findsWidgets);
    check('Meridian detail');
  });

  testWidgets('the statistics add up', (tester) async {
    final c = await pumpStafflineApp(tester, signInAs: platformAdmin);
    final s = await c.read(platformSnapshotProvider.future);
    OrgStats org(String id) => s.orgs.firstWhere((o) => o.id == id);

    final meridian = org('org_meridian-tex');
    final people = await c
        .read(employeeRepositoryProvider)
        .employees('org_meridian-tex');
    expect(meridian.employees, people.where((e) => e.status.isEmployed).length);
    expect(meridian.activeBranches, 3);
    expect(meridian.activeToday, greaterThan(0));
    expect(s.employees, s.orgs.fold<int>(0, (n, o) => n + o.employees));
    expect(s.dailyActive, hasLength(30));
    expect(s.dailyActive.last, s.activeToday);

    expect(
      org('org_coastal-craft').statusAt(s.generatedAt),
      OrgStatus.settingUp,
    );
    expect(org('org_meridian-tex').statusAt(s.generatedAt), OrgStatus.active);
    expect(org('org_kaveri-foods').selfieBranches, 1);
    expect(
      s.featureUse.firstWhere((f) => f.$1 == 'Selfie punches').$2,
      (2 * 100 / 8).round(),
    );
    expect(s.registrations().last.$2, 1, reason: 'Coastal Craft, Oct 2026');
  });

  testWidgets('a detail page lists branch counts and opens from the list', (
    tester,
  ) async {
    final c = await pumpStafflineApp(
      tester,
      signInAs: platformAdmin,
      size: const Size(1440, 3000),
    );
    await tester.tap(find.text('Kaveri Foods').last);
    await tester.pumpAndSettle();
    expect(currentPath(c), AppRoutes.platformOrg('org_kaveri-foods'));
    expect(find.text('Peenya'), findsWidgets);
    expect(find.textContaining('On at 1 branch'), findsOneWidget);

    c.read(appRouterProvider).go(AppRoutes.platformOrg('org_nope'));
    await tester.pumpAndSettle();
    expect(find.text('This organization isn’t registered'), findsOneWidget);
  });

  testWidgets('the super admin can’t open organization pages', (tester) async {
    final c = await pumpStafflineApp(tester, signInAs: platformAdmin);
    for (final page in [
      AppRoutes.overview,
      AppRoutes.employees,
      '/employees/e-1',
      AppRoutes.home,
      AppRoutes.auditLog,
    ]) {
      c.read(appRouterProvider).go(page);
      await tester.pumpAndSettle();
      expect(currentPath(c), AppRoutes.platform, reason: page);
    }
  });

  testWidgets('organization members can’t open platform pages', (tester) async {
    for (final who in [owner, hrAdmin, employee]) {
      final c = await pumpStafflineApp(tester, signInAs: who);
      c.read(appRouterProvider).go(AppRoutes.platform);
      await tester.pumpAndSettle();
      expect(currentPath(c), AppRoutes.accessDenied, reason: who);
      expect(
        () => c.read(platformSnapshotProvider.future),
        throwsA(anything),
        reason: who,
      );
    }
  });

  testWidgets('signed out, the platform page asks to sign in', (tester) async {
    final c = await pumpStafflineApp(tester, signInAs: null);
    c.read(appRouterProvider).go(AppRoutes.platform);
    await tester.pumpAndSettle();
    expect(currentPath(c), AppRoutes.welcome);
  });

  testWidgets('works on a phone and at 200% text', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final c = await pumpStafflineApp(
      tester,
      signInAs: platformAdmin,
      size: const Size(320, 640),
    );
    expect(tester.takeException(), isNull);
    expect(find.byTooltip('Sign out'), findsOneWidget);
    c.read(appRouterProvider).go(AppRoutes.platformOrg('org_meridian-tex'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Sign out'));
    await tester.pumpAndSettle();
    expect(currentPath(c), AppRoutes.welcome);
  });
}
