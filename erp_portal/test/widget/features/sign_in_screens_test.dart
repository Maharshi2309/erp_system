import 'package:erp_portal/app/router/app_router.dart';
import 'package:erp_portal/app/router/route_names.dart';
import 'package:erp_portal/features/auth/data/demo_auth_repository.dart';
import 'package:erp_portal/features/auth/presentation/providers/auth_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_helpers/pump_app.dart';

void main() {
  group('S03 Welcome', () {
    testWidgets('empty form shows inline errors', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpStafflineApp(tester, signInAs: null);
      await tapText(tester, 'Sign in');
      expect(
        find.text('Enter your work email or employee ID.'),
        findsOneWidget,
      );
      expect(find.text('Enter your password.'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('wrong password shows the generic message', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpStafflineApp(tester, signInAs: null);
      await enter(tester, 'Work email or employee ID', 'EMP-0229');
      await enter(tester, 'Password', 'wrong-password');
      await tapText(tester, 'Sign in');
      expect(
        find.textContaining(
          'That email or employee ID and password don’t match',
        ),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('employee signs in with employee ID and lands on Home', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final c = await pumpStafflineApp(tester, signInAs: null);
      await enter(tester, 'Work email or employee ID', 'EMP-0229');
      await enter(tester, 'Password', DemoAuthRepository.demoPassword);
      await tapText(tester, 'Sign in');
      expect(currentPath(c), AppRoutes.home);
      semantics.dispose();
    });

    testWidgets('demo account rows fill the form', (tester) async {
      final semantics = tester.ensureSemantics();
      final c = await pumpStafflineApp(tester, signInAs: null);
      await tapText(tester, 'EMP-0229');
      await tapText(tester, 'Sign in');
      expect(currentPath(c), AppRoutes.home);
      semantics.dispose();
    });

    testWidgets('links go to register, forgot password and invitation', (
      tester,
    ) async {
      final c = await pumpStafflineApp(tester, signInAs: null);
      await tapText(tester, 'Set up an organization');
      expect(currentPath(c), AppRoutes.register);
      c.read(appRouterProvider).go(AppRoutes.welcome);
      await tester.pumpAndSettle();
      await tapText(tester, 'Forgot password?');
      expect(currentPath(c), AppRoutes.forgotPassword);
      c.read(appRouterProvider).go(AppRoutes.welcome);
      await tester.pumpAndSettle();
      await tapText(tester, 'Accept invitation');
      expect(currentPath(c), AppRoutes.acceptInvite);
    });

    testWidgets('lays out without overflow from 320 px to 1920 px', (
      tester,
    ) async {
      for (final size in const [
        Size(320, 568),
        Size(390, 844),
        Size(768, 1024),
        Size(1440, 900),
        Size(1920, 1080),
      ]) {
        await pumpStafflineApp(tester, signInAs: null, size: size);
        expect(tester.takeException(), isNull, reason: '$size');
      }
    });
  });

  group('S06 Two-step', () {
    Future<void> toTwoStep(WidgetTester tester) async {
      final c = await pumpStafflineApp(tester, signInAs: null);
      await c
          .read(authControllerProvider.notifier)
          .signIn(
            identifier: hrAdmin,
            password: DemoAuthRepository.demoPassword,
            keepSignedIn: false,
          );
      await tester.pumpAndSettle();
      expect(currentPath(c), AppRoutes.twoStep);
    }

    testWidgets('verify is disabled until 6 digits, then signs in', (
      tester,
    ) async {
      await toTwoStep(tester);
      expect(find.text('Signing in as'), findsOneWidget);
      expect(find.text(hrAdmin), findsOneWidget);
      await tester.enterText(find.byType(TextField), '4829');
      await tester.pump();
      final verify = find.ancestor(
        of: find.text('Verify and sign in'),
        matching: find.byType(TextButton),
      );
      expect(tester.widget<TextButton>(verify).onPressed, isNull);
      await tester.enterText(find.byType(TextField), '482913');
      await tester.pump();
      await tapText(tester, 'Verify and sign in');
      expect(find.text('Overview'), findsWidgets);
    });

    testWidgets('three wrong codes lock sign-in', (tester) async {
      await toTwoStep(tester);
      for (var i = 0; i < 3; i++) {
        await tester.enterText(find.byType(TextField), '000000');
        await tester.pump();
        await tapText(tester, 'Verify and sign in');
      }
      expect(
        find.textContaining('Sign-in is paused for 15 minutes'),
        findsOneWidget,
      );
    });

    testWidgets('backup code mode, used code shows how many are left', (
      tester,
    ) async {
      await toTwoStep(tester);
      await tapText(tester, 'Use a backup code instead');
      expect(find.text('Use a backup code'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '7kq2-m9xd');
      await tester.pump();
      await tapText(tester, 'Verify and sign in');
      expect(find.textContaining('Backup code used — 7 left'), findsOneWidget);
    });

    testWidgets('“Sign in as someone else” goes back to welcome', (
      tester,
    ) async {
      await toTwoStep(tester);
      await tapText(tester, 'Sign in as someone else');
      expect(find.text('Welcome'), findsOneWidget);
    });
  });

  group('S10 Organization selection', () {
    testWidgets('lists memberships; deactivated one cannot be opened', (
      tester,
    ) async {
      final c = await pumpStafflineApp(tester, signInAs: null);
      final auth = c.read(authControllerProvider.notifier);
      await auth.signIn(
        identifier: owner,
        password: DemoAuthRepository.demoPassword,
        keepSignedIn: false,
      );
      await auth.verifyTwoStep(
        code: '482913',
        isBackupCode: false,
        trustDevice: false,
      );
      await tester.pumpAndSettle();
      expect(currentPath(c), AppRoutes.chooseOrganization);
      expect(find.text('Last used'), findsOneWidget);
      expect(
        find.text('Membership deactivated · history kept'),
        findsOneWidget,
      );

      await tapText(tester, 'Sabarmati Retail');
      expect(currentPath(c), AppRoutes.chooseOrganization);

      await tapText(tester, 'Meridian Textiles');
      expect(currentPath(c), AppRoutes.overview);
    });
  });

  group('S04–S05 Register and verify', () {
    testWidgets('validation, then account, then code, then onboarding', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final c = await pumpStafflineApp(
        tester,
        signInAs: null,
        location: AppRoutes.register,
      );
      await tapText(tester, 'Create account');
      // Listed in the summary and under the field.
      expect(find.text('Enter your full name.'), findsNWidgets(2));
      expect(find.text('Accept the terms to continue.'), findsNWidgets(2));
      expect(find.textContaining('Please fix 4 things'), findsOneWidget);

      await enter(tester, 'Full name', 'Ravi Shah');
      await enter(tester, 'Work email', 'ravi@newco.in');
      await enter(tester, 'Password', 'Factory2026x');
      expect(
        find.bySemanticsLabel('At least 10 characters, met'),
        findsOneWidget,
      );
      await tapText(
        tester,
        'I agree to the Terms of Service and Privacy Policy. *',
      );
      await tapText(tester, 'Create account');
      expect(currentPath(c), AppRoutes.verifyEmail);
      expect(find.textContaining('ra•••@newco.in'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '111111');
      await tester.pump();
      await tapText(tester, 'Verify email');
      expect(find.textContaining('That code isn’t right'), findsOneWidget);

      await tester.enterText(
        find.byType(TextField),
        DemoAuthRepository.demoEmailCode,
      );
      await tester.pump();
      await tapText(tester, 'Verify email');
      expect(find.text('Email verified'), findsOneWidget);
      await tapText(tester, 'Set up organization');
      expect(currentPath(c), AppRoutes.onboarding);
      expect(find.text('Sign out'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('existing email is reported on the field', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpStafflineApp(
        tester,
        signInAs: null,
        location: AppRoutes.register,
      );
      await enter(tester, 'Full name', 'Someone');
      await enter(tester, 'Work email', owner);
      await enter(tester, 'Password', 'Factory2026x');
      await tapText(
        tester,
        'I agree to the Terms of Service and Privacy Policy. *',
      );
      await tapText(tester, 'Create account');
      expect(
        find.textContaining('An account already uses this email'),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('resend countdown turns into a link', (tester) async {
      final c = await pumpStafflineApp(tester, signInAs: null);
      await c
          .read(authControllerProvider.notifier)
          .register(
            fullName: 'Ravi Shah',
            email: 'ravi@newco.in',
            password: 'Factory2026x',
          );
      c.read(appRouterProvider).go(AppRoutes.verifyEmail);
      await tester.pumpAndSettle();
      expect(find.text('Resend in 0:45'), findsOneWidget);
      await tester.pump(const Duration(seconds: 45));
      await tester.pumpAndSettle();
      await tapText(tester, 'Resend code');
      expect(
        find.text('New code sent. Earlier codes no longer work.'),
        findsOneWidget,
      );
    });
  });

  group('S07–S08 Password recovery', () {
    testWidgets('request shows the same confirmation for any input', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpStafflineApp(
        tester,
        signInAs: null,
        location: AppRoutes.forgotPassword,
      );
      await enter(tester, 'Work email or employee ID', 'ghost@nowhere.in');
      await tapText(tester, 'Send reset link');
      expect(find.textContaining('If an account matches'), findsOneWidget);
      expect(find.text('Send again'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('reset: mismatch error, then success back to sign-in', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final c = await pumpStafflineApp(
        tester,
        signInAs: null,
        location:
            '${AppRoutes.resetPassword}?token=${DemoAuthRepository.demoResetToken}',
      );
      expect(find.textContaining('is•••@meridiantex.in'), findsOneWidget);
      await enter(tester, 'New password', 'Dyeing2026Tech');
      await enter(tester, 'Confirm new password', 'Dyeing2026Tecx');
      await tapText(tester, 'Update password');
      expect(
        find.text('Passwords don’t match. Re-type the new password.'),
        findsOneWidget,
      );

      await enter(tester, 'Confirm new password', 'Dyeing2026Tech');
      await tapText(tester, 'Update password');
      expect(currentPath(c), AppRoutes.welcome);
      expect(find.textContaining('Password updated'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('expired link offers a new one', (tester) async {
      final c = await pumpStafflineApp(
        tester,
        signInAs: null,
        location:
            '${AppRoutes.resetPassword}?token=${DemoAuthRepository.demoExpiredResetToken}',
      );
      expect(find.text('This reset link has expired'), findsOneWidget);
      await tapText(tester, 'Request a new link');
      expect(currentPath(c), AppRoutes.forgotPassword);
    });
  });

  group('S09 Invitation', () {
    testWidgets('shows who invited, then joins as the employee', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final c = await pumpStafflineApp(
        tester,
        signInAs: null,
        location:
            '${AppRoutes.acceptInvite}?token=${DemoAuthRepository.demoInviteToken}',
      );
      expect(find.text('Hetal Shah invited you to join'), findsOneWidget);
      expect(find.text('as Employee · Surat branch'), findsOneWidget);
      expect(find.text('EMP-0244'), findsOneWidget);

      await enter(tester, 'Create a password', 'Quality2026Check');
      await enter(tester, 'Confirm password', 'Quality2026Check');
      await tapText(tester, 'Accept and join');
      expect(find.text('Agree to continue.'), findsOneWidget);

      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tapText(tester, 'Accept and join');
      expect(currentPath(c), AppRoutes.home);
      expect(c.read(sessionProvider)!.displayName, 'Pooja Chauhan');
      semantics.dispose();
    });

    testWidgets('missing or expired token explains what to do', (tester) async {
      await pumpStafflineApp(
        tester,
        signInAs: null,
        location: AppRoutes.acceptInvite,
      );
      expect(find.text('This invitation can’t be used'), findsOneWidget);
      expect(find.textContaining('Open your invitation email'), findsOneWidget);
    });
  });

  group('Responsive', () {
    final pages = {
      'welcome': AppRoutes.welcome,
      'register': AppRoutes.register,
      'forgot': AppRoutes.forgotPassword,
      'reset':
          '${AppRoutes.resetPassword}?token=${DemoAuthRepository.demoResetToken}',
      'invite':
          '${AppRoutes.acceptInvite}?token=${DemoAuthRepository.demoInviteToken}',
    };
    for (final size in const [
      Size(320, 568),
      Size(390, 844),
      Size(1440, 900),
    ]) {
      pages.forEach((name, location) {
        testWidgets('$name at ${size.width.toInt()} px has no overflow', (
          tester,
        ) async {
          await pumpStafflineApp(
            tester,
            signInAs: null,
            size: size,
            location: location,
          );
          expect(tester.takeException(), isNull);
        });
      });
    }

    testWidgets('sign-in pages at 200% text on a phone', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      for (final location in pages.values) {
        await pumpStafflineApp(
          tester,
          signInAs: null,
          size: const Size(390, 844),
          location: location,
        );
        expect(tester.takeException(), isNull, reason: location);
      }
    });

    testWidgets('two-step and organization pages at 320 px', (tester) async {
      final c = await pumpStafflineApp(
        tester,
        signInAs: null,
        size: const Size(320, 568),
      );
      final auth = c.read(authControllerProvider.notifier);
      await auth.signIn(
        identifier: owner,
        password: DemoAuthRepository.demoPassword,
        keepSignedIn: false,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await auth.verifyTwoStep(
        code: '482913',
        isBackupCode: false,
        trustDevice: false,
      );
      await tester.pumpAndSettle();
      expect(currentPath(c), AppRoutes.chooseOrganization);
      expect(tester.takeException(), isNull);
    });
  });

  group('Session restore', () {
    testWidgets('a kept session opens straight into the app', (tester) async {
      final c = await pumpStafflineApp(
        tester,
        signInAs: null,
        storedPrefs: {
          'session.accountId': 'u-isha',
          'session.organizationId': 'org_meridian-tex',
        },
      );
      expect(currentPath(c), AppRoutes.home);
      expect(c.read(sessionProvider)!.displayName, 'Isha Rathod');
    });
  });
}
