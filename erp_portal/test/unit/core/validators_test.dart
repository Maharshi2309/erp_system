// D-78: shared field validation (contact details, names, dates).
import 'package:erp_portal/core/permissions/system_roles.dart';
import 'package:erp_portal/core/utils/validators.dart';
import 'package:erp_portal/features/employees/domain/employee.dart';
import 'package:erp_portal/features/employees/domain/employee_rules.dart';
import 'package:erp_portal/features/organization/domain/branch.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('phone numbers (India)', () {
    test('mobile numbers: 10 digits from 6–9, +91 / 91 / 0 allowed', () {
      for (final ok in [
        '9825012345',
        '98250 12345',
        '+91 98250 12345',
        '+91-98250-12345',
        '919825012345',
        '09825012345',
        '(+91) 6000000001',
      ]) {
        expect(Validators.isMobile(ok), isTrue, reason: ok);
      }
      for (final bad in [
        '12',
        '5825012345',
        '98250 1234',
        '982501234567',
        '+1 202 555 0101',
        'abc9825012345',
        '98250x12345',
        '',
      ]) {
        expect(Validators.isMobile(bad), isFalse, reason: bad);
      }
    });

    test('phones also accept landlines with the area code', () {
      expect(Validators.isPhone('079 4000 2210'), isTrue);
      expect(Validators.isPhone('+91 79 4000 2210'), isTrue);
      expect(Validators.isPhone('4000 2210'), isFalse);
      expect(Validators.isPhone('0000000000'), isFalse);
    });

    test('finds the number inside an emergency contact', () {
      expect(Validators.phoneIn('Ravi Shah, +91 98250 12345'), '9825012345');
      expect(
        Validators.phoneIn('Ravi Shah (father) 079-4000-2210'),
        '7940002210',
      );
      expect(Validators.phoneIn('Ravi Shah'), isNull);
      expect(Validators.phoneIn('Ravi 12345'), isNull);
    });
  });

  test('names, labels, PIN codes and emails', () {
    for (final ok in ["D'Souza", 'Anne-Marie', 'Ravi K. Shah', 'राहुल']) {
      expect(Validators.isPersonName(ok), isTrue, reason: ok);
    }
    for (final bad in ['Ravi2', '123', '', '  ', '-Ravi', 'A' * 51]) {
      expect(Validators.isPersonName(bad), isFalse, reason: bad);
    }
    expect(Validators.isLabel('QA Analyst'), isTrue);
    expect(Validators.isLabel('12345'), isFalse);
    expect(Validators.isLabel('A'), isFalse);
    expect(Validators.isPin('380015'), isTrue);
    expect(Validators.isPin('080015'), isFalse);
    expect(Validators.isPin('38001'), isFalse);
    for (final ok in ['a@b.in', 'pooja.c+hr@meridian-tex.co.in']) {
      expect(Validators.isEmail(ok), isTrue, reason: ok);
    }
    for (final bad in [
      'a@b',
      'a..b@c.in',
      'a b@c.in',
      '.a@b.in',
      'a.@b.in',
      'a@-b.in',
    ]) {
      expect(Validators.isEmail(bad), isFalse, reason: bad);
    }
  });

  group('employee record', () {
    final today = DateTime(2026, 10, 26);
    final branch = Branch(
      id: 'b-1',
      name: 'Surat',
      address: 'Plot 22',
      city: 'Surat',
      state: 'Gujarat',
      pin: '394230',
      hours: HoursPresets.monSat930,
    );
    final ok = Employee(
      id: 'e-x',
      organizationId: 'org',
      code: 'EMP-9000',
      firstName: 'Pooja',
      lastName: 'Chauhan',
      workEmail: 'pooja.c@meridiantex.in',
      mobile: '+91 98250 61233',
      designation: 'Quality Inspector',
      department: 'Quality',
      type: EmploymentType.fullTime,
      joiningDate: DateTime(2026, 10, 19),
      branchId: 'b-1',
      shift: 'General',
      role: SystemRole.branchManager,
      dateOfBirth: DateTime(1995, 4, 2),
      emergencyContact: 'Ravi Chauhan, 98250 11111',
    );
    Map<String, String> check(Employee e) => validateEmployee(
      e,
      others: const [],
      fields: const [],
      branch: branch,
      sendInvite: false,
      today: today,
    );

    test('a complete record passes', () {
      expect(check(ok), isEmpty);
    });

    test('each contact and identity problem is named', () {
      expect(
        check(ok.copyWith(mobile: '12345'))['mobile'],
        Validators.mobileMessage,
      );
      expect(
        check(ok.copyWith(firstName: 'P00ja'))['firstName'],
        Validators.nameMessage,
      );
      expect(
        check(
          ok.copyWith(personalEmail: 'pooja.c@meridiantex.in'),
        )['personalEmail'],
        'Use a personal address, not the work email.',
      );
      expect(
        check(ok.copyWith(personalEmail: 'pooja@'))['personalEmail'],
        Validators.emailMessage,
      );
      expect(
        check(ok.copyWith(emergencyContact: 'Ravi'))['emergencyContact'],
        contains('a name and a 10-digit'),
      );
      expect(
        check(ok.copyWith(emergencyContact: '98250 11111'))['emergencyContact'],
        contains('a name and a 10-digit'),
      );
      expect(
        check(
          ok.copyWith(emergencyContact: 'Self, +91 98250 61233'),
        )['emergencyContact'],
        'Use someone else’s number, not the employee’s own mobile.',
      );
      expect(check(ok.copyWith(designation: '1234'))['designation'], isNotNull);
    });

    test('dates of birth and joining', () {
      expect(
        check(ok.copyWith(dateOfBirth: DateTime(2027, 1, 1)))['dateOfBirth'],
        'The date of birth can’t be in the future.',
      );
      expect(
        check(ok.copyWith(dateOfBirth: DateTime(2010, 1, 1)))['dateOfBirth'],
        'The employee must be at least 18 on the joining date.',
      );
      expect(
        check(ok.copyWith(dateOfBirth: DateTime(1940, 1, 1)))['dateOfBirth'],
        isNotNull,
      );
      expect(
        check(ok.copyWith(joiningDate: DateTime(2027, 6, 1)))['joiningDate'],
        'Joining dates can be up to 6 months ahead.',
      );
    });
  });
}
