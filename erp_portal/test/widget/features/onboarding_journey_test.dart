import 'package:erp_portal/app/router/app_router.dart';
import 'package:erp_portal/app/router/route_names.dart';
import 'package:erp_portal/features/auth/data/demo_auth_repository.dart';
import 'package:erp_portal/features/auth/presentation/providers/auth_providers.dart';
import 'package:erp_portal/features/organization/domain/setup_progress.dart';
import 'package:erp_portal/features/organization/presentation/providers/organization_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_helpers/pump_app.dart';

/// Registers and verifies a brand-new account, which lands on /onboarding.
Future<ProviderContainer> newAccount(WidgetTester tester, {Size? size}) async {
  final container = await pumpStafflineApp(
    tester,
    signInAs: null,
    size: size ?? const Size(1440, 900),
  );
  final auth = container.read(authControllerProvider.notifier);
  await auth.register(
    fullName: 'Riya Shah',
    email: 'riya@shreeweaves.in',
    password: DemoAuthRepository.demoPassword,
  );
  await auth.verifyEmail(DemoAuthRepository.demoEmailCode);
  container.read(appRouterProvider).go(AppRoutes.onboarding);
  await tester.pumpAndSettle();
  return container;
}

Future<void> saveStep(WidgetTester tester, SetupStep step, String id) async {
  final container = ProviderScope.containerOf(
    tester.element(find.byType(Scaffold).first),
  );
  container
      .read(appRouterProvider)
      .go('${AppRoutes.branchSetup(id)}?step=${step.name}');
  await tester.pumpAndSettle();
  await tapText(
    tester,
    step == SetupStep.review ? 'Mark branch ready' : 'Save',
  );
}

void main() {
  testWidgets('new owner: organisation → owner profile → first branch → 100%', (
    tester,
  ) async {
    final container = await newAccount(tester);
    expect(currentPath(container), AppRoutes.onboarding);

    // S12 → S13: create the organisation.
    await tapText(tester, 'Set Up Your Organisation');
    expect(currentPath(container), AppRoutes.createOrganization);
    await tapText(tester, 'Create Organisation');
    expect(find.textContaining('Please fix 2 things'), findsOneWidget);
    await enter(tester, 'Organisation name', 'Shree Weaves');
    await tapText(tester, '11–50');
    await tapText(tester, 'Create Organisation');
    expect(currentPath(container), AppRoutes.overview);
    expect(container.read(sessionProvider)?.organizationName, 'Shree Weaves');
    expect(
      find.text('Shree Weaves is created. Next: your owner profile.'),
      findsOneWidget,
    );
    expect(find.text('1 of 3'), findsOneWidget);

    // S16: owner profile.
    await dismissToasts(tester);
    container.read(appRouterProvider).go(AppRoutes.ownerProfile);
    await tester.pumpAndSettle();
    await enter(tester, 'Mobile number', '+91 98250 41736');
    await enter(tester, 'Designation', 'Proprietor');
    await tapText(tester, 'Save Owner Profile');
    expect(currentPath(container), AppRoutes.overview);
    expect(find.text('2 of 3'), findsOneWidget);

    // S18: first branch.
    await dismissToasts(tester);
    await tapText(tester, 'Set Up Your First Branch');
    expect(currentPath(container), AppRoutes.newBranch);
    expect(find.text('Set up your first branch'), findsWidgets);
    await enter(tester, 'Branch name', 'Surat');
    await enter(tester, 'Address', 'Ring Road');
    await enter(tester, 'City', 'Surat');
    await enter(tester, 'PIN code', '395002');
    await tapText(tester, 'Create Branch');
    final branchId = currentPath(container).split('/')[2];
    expect(currentPath(container), AppRoutes.branchSetup(branchId));
    expect(find.text('Surat created · 25% set up'), findsOneWidget);

    // S20–S22: every step in its side panel.
    await dismissToasts(tester);
    for (final step in [
      SetupStep.attendance,
      SetupStep.holidays,
      SetupStep.leave,
      SetupStep.roles,
    ]) {
      await saveStep(tester, step, branchId);
    }
    var branch = container.read(branchProvider(branchId)).value!;
    expect(SetupProgress(branch).percent, 95);
    expect(find.textContaining('95% set up'), findsWidgets);

    await saveStep(tester, SetupStep.review, branchId);
    branch = container.read(branchProvider(branchId)).value!;
    expect(SetupProgress(branch).isReady, isTrue);
    expect(
      find.text('Surat is ready · Branch Setup Completed'),
      findsOneWidget,
    );
    expect(find.text('Add Another Branch'), findsOneWidget);
  });

  testWidgets('organisation name problems show inline', (tester) async {
    await newAccount(tester);
    await tapText(tester, 'Set Up Your Organisation');
    await enter(tester, 'Organisation name', 'A');
    await tapText(tester, '11–50');
    await tapText(tester, 'Create Organisation');
    expect(find.text('Use at least 2 characters.'), findsWidgets);
  });

  testWidgets('a new account cannot open the dashboard before creating one', (
    tester,
  ) async {
    final container = await newAccount(tester);
    container.read(appRouterProvider).go(AppRoutes.branches);
    await tester.pumpAndSettle();
    expect(currentPath(container), AppRoutes.onboarding);
  });
}
