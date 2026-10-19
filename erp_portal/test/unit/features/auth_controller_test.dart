import 'package:erp_portal/app/app.dart';
import 'package:erp_portal/core/errors/failure.dart';
import 'package:erp_portal/core/permissions/system_roles.dart';
import 'package:erp_portal/features/auth/data/demo_auth_repository.dart';
import 'package:erp_portal/features/auth/domain/auth_state.dart';
import 'package:erp_portal/features/auth/presentation/providers/auth_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> makeContainer([
  Map<String, Object> prefs = const {},
]) async {
  SharedPreferences.setMockInitialValues(prefs);
  final container = ProviderContainer.test(
    retry: providerRetry,
    overrides: [
      authRepositoryProvider.overrideWithValue(
        DemoAuthRepository(latency: Duration.zero),
      ),
    ],
  );
  // Start the controller and let the restore finish.
  container.read(authControllerProvider);
  await Future<void>.delayed(Duration.zero);
  await container.read(sessionStoreProvider.future);
  for (
    var i = 0;
    i < 10 && container.read(authControllerProvider) is RestoringSession;
    i++
  ) {
    await Future<void>.delayed(Duration.zero);
  }
  return container;
}

void main() {
  const password = DemoAuthRepository.demoPassword;
  const code = DemoAuthRepository.demoAuthenticatorCode;

  test('starts signed out when nothing is saved', () async {
    final c = await makeContainer();
    expect(c.read(authControllerProvider), isA<SignedOut>());
    expect(c.read(sessionProvider), isNull);
  });

  test('employee without two-step goes straight in', () async {
    final c = await makeContainer();
    await c
        .read(authControllerProvider.notifier)
        .signIn(
          identifier: 'EMP-0229',
          password: password,
          keepSignedIn: false,
        );
    final session = c.read(sessionProvider)!;
    expect(session.displayName, 'Isha Rathod');
    expect(session.role, SystemRole.employee);
    expect(session.canSwitchOrganization, isFalse);
  });

  test('admin: password → two-step → signed in', () async {
    final c = await makeContainer();
    final auth = c.read(authControllerProvider.notifier);
    await auth.signIn(
      identifier: 'hetal.s@meridiantex.in',
      password: password,
      keepSignedIn: false,
    );
    expect(c.read(authControllerProvider), isA<AwaitingTwoStep>());
    await auth.verifyTwoStep(
      code: code,
      isBackupCode: false,
      trustDevice: false,
    );
    expect(c.read(sessionProvider)!.role, SystemRole.hrAdmin);
  });

  test('owner of several organizations chooses one, and can switch', () async {
    final c = await makeContainer();
    final auth = c.read(authControllerProvider.notifier);
    await auth.signIn(
      identifier: 'ankit@meridiantex.in',
      password: password,
      keepSignedIn: false,
    );
    await auth.verifyTwoStep(
      code: code,
      isBackupCode: false,
      trustDevice: false,
    );
    final choice = c.read(authControllerProvider) as AwaitingOrganizationChoice;
    expect(choice.memberships, hasLength(3));

    await auth.chooseOrganization('org_pateldyes');
    var session = c.read(sessionProvider)!;
    expect(session.organizationName, 'Patel Dyes & Chemicals');
    expect(session.role, SystemRole.hrAdmin);
    expect(session.canSwitchOrganization, isTrue);

    await auth.chooseOrganization('org_meridian-tex');
    session = c.read(sessionProvider)!;
    expect(session.role, SystemRole.owner);
  });

  test('deactivated membership cannot be opened', () async {
    final c = await makeContainer();
    final auth = c.read(authControllerProvider.notifier);
    await auth.signIn(
      identifier: 'ankit@meridiantex.in',
      password: password,
      keepSignedIn: false,
    );
    await auth.verifyTwoStep(
      code: code,
      isBackupCode: false,
      trustDevice: false,
    );
    await expectLater(
      auth.chooseOrganization('org_sabarmati'),
      throwsA(isA<PermissionFailure>()),
    );
  });

  test('"keep me signed in" survives a restart; sign-out forgets it', () async {
    final first = await makeContainer();
    await first
        .read(authControllerProvider.notifier)
        .signIn(identifier: 'EMP-0229', password: password, keepSignedIn: true);
    final prefs = await SharedPreferences.getInstance();
    final saved = {for (final key in prefs.getKeys()) key: prefs.get(key)!};
    expect(saved, isNotEmpty);

    final second = await makeContainer(saved);
    expect(second.read(sessionProvider)?.displayName, 'Isha Rathod');

    await second.read(authControllerProvider.notifier).signOut();
    expect(second.read(authControllerProvider), isA<SignedOut>());
    final after = await SharedPreferences.getInstance();
    expect(after.getString('session.accountId'), isNull);
  });

  test('without "keep me signed in" nothing is saved', () async {
    final c = await makeContainer();
    await c
        .read(authControllerProvider.notifier)
        .signIn(
          identifier: 'EMP-0229',
          password: password,
          keepSignedIn: false,
        );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('session.accountId'), isNull);
  });

  test('a saved session for an unknown account is discarded', () async {
    final c = await makeContainer({
      'session.accountId': 'u-ghost',
      'session.organizationId': 'org_meridian-tex',
    });
    expect(c.read(authControllerProvider), isA<SignedOut>());
  });

  test('trusted device skips two-step next time', () async {
    final c = await makeContainer();
    final auth = c.read(authControllerProvider.notifier);
    await auth.signIn(
      identifier: 'hetal.s@meridiantex.in',
      password: password,
      keepSignedIn: false,
    );
    await auth.verifyTwoStep(
      code: code,
      isBackupCode: false,
      trustDevice: true,
    );
    await auth.signOut();

    await auth.signIn(
      identifier: 'hetal.s@meridiantex.in',
      password: password,
      keepSignedIn: false,
    );
    expect(c.read(authControllerProvider), isA<SignedIn>());
  });

  test('register → verify email → needs an organization', () async {
    final c = await makeContainer();
    final auth = c.read(authControllerProvider.notifier);
    await auth.register(
      fullName: 'Ravi Shah',
      email: 'Ravi@NewCo.in',
      password: 'Factory2026x',
    );
    expect(
      (c.read(authControllerProvider) as AwaitingEmailVerification).email,
      'ravi@newco.in',
    );
    await auth.verifyEmail(DemoAuthRepository.demoEmailCode);
    expect(c.read(authControllerProvider), isA<NeedsOrganization>());
  });

  test('accepting an invitation signs the new employee in', () async {
    final c = await makeContainer();
    await c
        .read(authControllerProvider.notifier)
        .acceptInvitation(
          token: DemoAuthRepository.demoInviteToken,
          password: 'Quality2026Check',
        );
    final session = c.read(sessionProvider)!;
    expect(session.displayName, 'Pooja Chauhan');
    expect(session.role, SystemRole.employee);
  });
}
