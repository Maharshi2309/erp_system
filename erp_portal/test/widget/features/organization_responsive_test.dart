import 'package:erp_portal/app/router/app_router.dart';
import 'package:erp_portal/app/router/route_names.dart';
import 'package:erp_portal/features/auth/data/demo_auth_repository.dart';
import 'package:erp_portal/features/auth/presentation/providers/auth_providers.dart';
import 'package:erp_portal/features/organization/domain/setup_progress.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_helpers/pump_app.dart';

/// Every Phase 3 page; layout errors fail the test on their own.
final pages = <String>[
  AppRoutes.overview,
  AppRoutes.organization,
  AppRoutes.ownerProfile,
  AppRoutes.branches,
  AppRoutes.newBranch,
  AppRoutes.branchBasics('b-sur'),
  AppRoutes.branchSetup('b-sur'),
  AppRoutes.branchSetup('b-ahm'),
  AppRoutes.branchEdit('b-sur'),
  AppRoutes.branch('b-sur'),
  for (final step in SetupStep.values)
    if (step != SetupStep.basics)
      '${AppRoutes.branchSetup('b-vad')}?step=${step.name}',
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
    testWidgets('Phase 3 pages lay out at ${size.width.toInt()} px', (
      tester,
    ) async {
      for (final page in pages) {
        await pumpStafflineApp(tester, size: size, location: page);
        expect(tester.takeException(), isNull, reason: page);
      }
    });
  }

  testWidgets('Phase 3 pages at 200% text on a 390 px phone', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    for (final page in pages) {
      await pumpStafflineApp(
        tester,
        size: const Size(390, 844),
        location: page,
      );
      expect(tester.takeException(), isNull, reason: page);
    }
  });

  testWidgets('onboarding pages lay out at 320 px', (tester) async {
    final c = await pumpStafflineApp(
      tester,
      size: const Size(320, 568),
      signInAs: null,
    );
    final auth = c.read(authControllerProvider.notifier);
    await auth.register(
      fullName: 'Riya Shah',
      email: 'riya@shreeweaves.in',
      password: DemoAuthRepository.demoPassword,
    );
    await auth.verifyEmail(DemoAuthRepository.demoEmailCode);
    for (final page in [AppRoutes.onboarding, AppRoutes.createOrganization]) {
      c.read(appRouterProvider).go(page);
      await tester.pumpAndSettle();
      expect(currentPath(c), page);
      expect(tester.takeException(), isNull, reason: page);
    }
  });
}
