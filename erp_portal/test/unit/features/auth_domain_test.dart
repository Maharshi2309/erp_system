import 'package:erp_portal/core/errors/failure.dart';
import 'package:erp_portal/core/permissions/permissions.dart';
import 'package:erp_portal/core/permissions/system_roles.dart';
import 'package:erp_portal/core/utils/validators.dart';
import 'package:erp_portal/features/auth/data/demo_auth_repository.dart';
import 'package:erp_portal/features/auth/domain/password_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('password rules (board S04)', () {
    Map<String, bool> check(String pw) => {
      for (final r in passwordRules(
        pw,
        name: 'Ankit Patel',
        email: 'ankit@meridiantex.in',
      ))
        r.label: r.isMet,
    };

    test('strong password meets all four', () {
      expect(check('Meridian2026').values, everyElement(isTrue));
    });

    test('each rule fails on its own', () {
      expect(check('Mer1dian')['At least 10 characters'], isFalse);
      expect(check('MeridianTex')['Contains a number'], isFalse);
      expect(check('meridian2026')['Upper and lower case letters'], isFalse);
      expect(check('AnkitIs2026x')['Not your name or email'], isFalse);
    });

    test('empty password meets nothing', () {
      expect(check('').values, everyElement(isFalse));
    });
  });

  group('validators', () {
    test('email', () {
      expect(Validators.isEmail('pooja.c@meridiantex.in'), isTrue);
      expect(Validators.isEmail(' a@b.in '), isTrue);
      expect(Validators.isEmail('ravi.p@meridiantex'), isFalse);
      expect(Validators.isEmail('no-at-sign'), isFalse);
    });

    test('maskEmail matches the design', () {
      expect(maskEmail('ankit@meridiantex.in'), 'an•••@meridiantex.in');
      expect(maskEmail('is@x.in'), 'i•••@x.in');
    });
  });

  group('system roles', () {
    test('two-step is required for admin roles only (board S83 default)', () {
      expect(SystemRole.owner.requiresTwoStep, isTrue);
      expect(SystemRole.attendanceManager.requiresTwoStep, isTrue);
      expect(SystemRole.leaveApprover.requiresTwoStep, isFalse);
      expect(SystemRole.employee.requiresTwoStep, isFalse);
    });

    test('branch manager matrix from board S68', () {
      final p = SystemRole.branchManager.permissions;
      expect(
        p.can(PermissionModule.attendance, PermissionAction.correct),
        isTrue,
      );
      expect(
        p.can(PermissionModule.employees, PermissionAction.deactivate),
        isFalse,
      );
      expect(p.canView(PermissionModule.roles), isFalse);
      expect(p.canView(PermissionModule.settings), isFalse);
    });

    test('employee has no admin modules', () {
      for (final module in PermissionModule.values) {
        expect(SystemRole.employee.permissions.canView(module), isFalse);
      }
    });
  });

  group('DemoAuthRepository', () {
    late DateTime now;
    late DemoAuthRepository repo;

    setUp(() {
      now = DateTime(2026, 10, 16, 10);
      repo = DemoAuthRepository(latency: Duration.zero, clock: () => now);
    });

    test('signs in by email or employee ID, case-insensitively', () async {
      final byEmail = await repo.signIn(
        identifier: 'ANKIT@meridiantex.in',
        password: DemoAuthRepository.demoPassword,
      );
      expect(byEmail.account.fullName, 'Ankit Patel');
      expect(byEmail.requiresTwoStep, isTrue);

      final byId = await repo.signIn(
        identifier: 'emp-0229',
        password: DemoAuthRepository.demoPassword,
      );
      expect(byId.account.fullName, 'Isha Rathod');
      expect(byId.requiresTwoStep, isFalse);
    });

    test('wrong password and unknown account give the same message', () async {
      Future<String> messageFor(String id, String pw) async {
        try {
          await repo.signIn(identifier: id, password: pw);
        } on ValidationFailure catch (f) {
          return f.message;
        }
        fail('expected a failure');
      }

      final wrongPassword = await messageFor('ankit@meridiantex.in', 'nope');
      final noAccount = await messageFor('ghost@meridiantex.in', 'nope');
      expect(wrongPassword, noAccount);
    });

    test('two-step: three wrong codes lock for 15 minutes', () async {
      Future<void> wrong() => repo.verifyTwoStep(
        accountId: 'u-ankit',
        code: '000000',
        isBackupCode: false,
      );
      await expectLater(wrong(), throwsA(isA<ValidationFailure>()));
      await expectLater(wrong(), throwsA(isA<ValidationFailure>()));
      await expectLater(wrong(), throwsA(isA<LockedFailure>()));

      // Even the right code is refused while locked.
      await expectLater(
        repo.verifyTwoStep(
          accountId: 'u-ankit',
          code: DemoAuthRepository.demoAuthenticatorCode,
          isBackupCode: false,
        ),
        throwsA(isA<LockedFailure>()),
      );

      now = now.add(const Duration(minutes: 16));
      expect(
        await repo.verifyTwoStep(
          accountId: 'u-ankit',
          code: DemoAuthRepository.demoAuthenticatorCode,
          isBackupCode: false,
        ),
        isNull,
      );
    });

    test('wrong-code message counts down tries', () async {
      try {
        await repo.verifyTwoStep(
          accountId: 'u-ankit',
          code: '111111',
          isBackupCode: false,
        );
      } on ValidationFailure catch (f) {
        expect(f.message, contains('2 tries left'));
      }
    });

    test('backup codes work once and report how many are left', () async {
      final left = await repo.verifyTwoStep(
        accountId: 'u-ankit',
        code: '7kq2-m9xd'.toUpperCase(),
        isBackupCode: true,
      );
      expect(left, 7);
      await expectLater(
        repo.verifyTwoStep(
          accountId: 'u-ankit',
          code: '7KQ2M9XD',
          isBackupCode: true,
        ),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('register → wrong code → right code', () async {
      await repo.register(
        fullName: 'Ravi Shah',
        email: 'ravi@newco.in',
        password: 'Factory2026x',
      );
      await expectLater(
        repo.verifyEmail(email: 'ravi@newco.in', code: '000000'),
        throwsA(isA<ValidationFailure>()),
      );
      final account = await repo.verifyEmail(
        email: 'ravi@newco.in',
        code: DemoAuthRepository.demoEmailCode,
      );
      expect(await repo.membershipsOf(account.id), isEmpty);
    });

    test('register rejects a used email and weak passwords', () async {
      await expectLater(
        repo.register(
          fullName: 'X',
          email: 'ankit@meridiantex.in',
          password: 'Factory2026x',
        ),
        throwsA(
          isA<ValidationFailure>().having(
            (f) => f.fieldErrors,
            'fieldErrors',
            contains('email'),
          ),
        ),
      );
      await expectLater(
        repo.register(fullName: 'X', email: 'x@newco.in', password: 'weak'),
        throwsA(
          isA<ValidationFailure>().having(
            (f) => f.fieldErrors,
            'fieldErrors',
            contains('password'),
          ),
        ),
      );
    });

    test('reset link works once; expired links are refused', () async {
      final link = await repo.openResetLink(DemoAuthRepository.demoResetToken);
      expect(link.maskedEmail, 'is•••@meridiantex.in');
      await repo.resetPassword(
        token: DemoAuthRepository.demoResetToken,
        newPassword: 'Dyeing2026Tech',
      );
      await expectLater(
        repo.openResetLink(DemoAuthRepository.demoResetToken),
        throwsA(isA<ExpiredFailure>()),
      );
      await expectLater(
        repo.openResetLink(DemoAuthRepository.demoExpiredResetToken),
        throwsA(isA<ExpiredFailure>()),
      );
      final signedIn = await repo.signIn(
        identifier: 'EMP-0229',
        password: 'Dyeing2026Tech',
      );
      expect(signedIn.account.fullName, 'Isha Rathod');
    });

    test(
      'requesting a reset never reveals whether the account exists',
      () async {
        await repo.requestPasswordReset('ghost@nowhere.in');
        await repo.requestPasswordReset('EMP-0229');
      },
    );

    test('invitation: valid, accepted once, expired refused', () async {
      final invitation = await repo.openInvitation(
        DemoAuthRepository.demoInviteToken,
      );
      expect(invitation.fullName, 'Pooja Chauhan');
      final account = await repo.acceptInvitation(
        token: DemoAuthRepository.demoInviteToken,
        password: 'Quality2026Check',
      );
      final memberships = await repo.membershipsOf(account.id);
      expect(memberships.single.role, SystemRole.employee);
      await expectLater(
        repo.openInvitation(DemoAuthRepository.demoInviteToken),
        throwsA(isA<ExpiredFailure>()),
      );
      await expectLater(
        repo.openInvitation(DemoAuthRepository.demoExpiredInviteToken),
        throwsA(isA<ExpiredFailure>()),
      );
    });

    test('owner belongs to three organizations, one deactivated', () async {
      final memberships = await repo.membershipsOf('u-ankit');
      expect(memberships, hasLength(3));
      expect(memberships.where((m) => m.isActive), hasLength(2));
      expect(
        memberships.where((m) => m.lastUsed).single.organizationName,
        'Meridian Textiles',
      );
    });
  });
}
