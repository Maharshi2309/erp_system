import 'package:erp_portal/core/errors/failure.dart';
import 'package:erp_portal/core/permissions/permissions.dart';
import 'package:erp_portal/core/utils/initials.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PermissionSet', () {
    test('none grants nothing', () {
      const set = PermissionSet.none();
      expect(set.canView(PermissionModule.employees), isFalse);
    });

    test('all grants every module and action', () {
      final set = PermissionSet.all();
      for (final module in PermissionModule.values) {
        for (final action in PermissionAction.values) {
          expect(set.can(module, action), isTrue, reason: '$module.$action');
        }
      }
    });

    test('of grants exactly the listed actions', () {
      final set = PermissionSet.of(const {
        PermissionModule.reports: [PermissionAction.view],
      });
      expect(set.canView(PermissionModule.reports), isTrue);
      expect(
        set.can(PermissionModule.reports, PermissionAction.export),
        isFalse,
      );
      expect(set.canView(PermissionModule.roles), isFalse);
    });

    test('value equality ignores order', () {
      final a = PermissionSet.of(const {
        PermissionModule.leave: [
          PermissionAction.view,
          PermissionAction.approve,
        ],
      });
      final b = PermissionSet.of(const {
        PermissionModule.leave: [
          PermissionAction.approve,
          PermissionAction.view,
        ],
      });
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('Permission prints as a PRD key', () {
      expect(
        const Permission(
          PermissionModule.employees,
          PermissionAction.view,
        ).toString(),
        'employees.view',
      );
    });
  });

  group('Failure messages', () {
    test('typed failures show their own message', () {
      expect(
        userMessageFor(const NetworkFailure()),
        contains('Nothing was changed'),
      );
      expect(
        userMessageFor(const ValidationFailure('Check the PIN code.')),
        'Check the PIN code.',
      );
    });

    test('unknown errors never leak internals', () {
      final message = userMessageFor(StateError('db password=secret'));
      expect(message, 'Something went wrong. Try again.');
      expect(message, isNot(contains('secret')));
    });

    test('validation failures carry field errors', () {
      const failure = ValidationFailure(
        'Please fix 1 thing.',
        fieldErrors: {'pin': 'PIN codes have 6 digits.'},
      );
      expect(failure.fieldErrors['pin'], 'PIN codes have 6 digits.');
    });
  });

  group('initialsOf', () {
    test('two words', () => expect(initialsOf('Ankit Patel'), 'AP'));
    test(
      'extra spaces and case',
      () => expect(initialsOf('  meridian   textiles '), 'MT'),
    );
    test('more than two words uses the first two', () {
      expect(initialsOf('Patel Dyes & Chemicals'), 'PD');
    });
    test('empty name', () => expect(initialsOf('  '), '··'));
  });
}
