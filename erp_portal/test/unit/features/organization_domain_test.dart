import 'dart:typed_data';

import 'package:erp_portal/core/errors/failure.dart';
import 'package:erp_portal/core/utils/image_picking.dart';
import 'package:erp_portal/core/utils/validators.dart';
import 'package:erp_portal/features/organization/data/demo_organization_repository.dart';
import 'package:erp_portal/features/organization/domain/branch.dart';
import 'package:erp_portal/features/organization/domain/branch_validation.dart';
import 'package:erp_portal/features/organization/domain/organization.dart';
import 'package:erp_portal/features/organization/domain/setup_progress.dart';
import 'package:flutter_test/flutter_test.dart';

Branch basics({WeeklyHours? hours, String pin = '395007'}) => Branch(
  id: 'b-1',
  name: 'Surat',
  address: 'Ring Road',
  city: 'Surat',
  state: 'Gujarat',
  pin: pin,
  hours: hours ?? HoursPresets.monSat930,
);

Branch complete() => basics().copyWith(
  attendance: const AttendanceRules(),
  holidays: HolidaySetup.from(HolidaySource.gujarat),
  leave: LeaveSetup.defaults,
  roles: const RolesSetup(),
  reviewed: true,
);

void main() {
  group('SetupProgress', () {
    test('weights add up to 100 without the optional reminders step', () {
      final total = SetupStep.values
          .where((s) => !s.isOptional)
          .fold<int>(0, (sum, s) => sum + s.weight);
      expect(total, 100);
      expect(SetupStep.reminders.weight, 0);
    });

    test(
      'a new branch with valid basics is 25% and the next step is attendance',
      () {
        final p = SetupProgress(basics());
        expect(p.percent, 25);
        expect(p.next, SetupStep.attendance);
        expect(setupStatusOf(basics()), BranchSetupStatus.basicsDone);
        expect(p.canReview, isFalse);
      },
    );

    test('each saved step adds its weight; review needs all five', () {
      var b = basics().copyWith(attendance: const AttendanceRules());
      expect(SetupProgress(b).percent, 45);
      b = b.copyWith(holidays: HolidaySetup.from(HolidaySource.none));
      expect(SetupProgress(b).percent, 60);
      b = b.copyWith(leave: LeaveSetup.defaults);
      expect(SetupProgress(b).percent, 80);
      b = b.copyWith(roles: const RolesSetup());
      expect(SetupProgress(b).percent, 95);
      expect(SetupProgress(b).canReview, isTrue);
      expect(SetupProgress(b).next, SetupStep.review);
      b = b.copyWith(reviewed: true);
      expect(SetupProgress(b).percent, 100);
      expect(SetupProgress(b).isReady, isTrue);
      expect(setupStatusOf(b), BranchSetupStatus.complete);
    });

    test('reminders never change the percentage', () {
      final b = basics().copyWith(reminders: const ReminderSettings());
      expect(SetupProgress(b).percent, 25);
      expect(SetupProgress(b).isComplete(SetupStep.reminders), isTrue);
    });

    test('a saved step that becomes invalid needs attention and lowers %', () {
      final b = complete().copyWith(
        roles: const RolesSetup(
          manager: BranchManagerChoice.invite,
          managerEmail: 'not-an-email',
        ),
      );
      final p = SetupProgress(b);
      expect(p.needsAttention(SetupStep.roles), isTrue);
      expect(p.needsAttention(SetupStep.review), isTrue);
      expect(p.percent, 80);
      expect(p.attention.first, SetupStep.roles);
      expect(setupStatusOf(b), BranchSetupStatus.needsAttention);
    });

    test('leave with every type off or a zero allowance is incomplete', () {
      final allOff = LeaveSetup(
        types: [
          for (final t in LeaveSetup.defaults.types) t.copyWith(enabled: false),
        ],
        approval: LeaveSetup.defaults.approval,
      );
      expect(allOff.isComplete, isFalse);
      final zero = LeaveSetup(
        types: [
          for (final t in LeaveSetup.defaults.types)
            t.tracksBalance && t.enabled ? t.copyWith(daysPerYear: 0) : t,
        ],
        approval: LeaveSetup.defaults.approval,
      );
      expect(zero.isComplete, isFalse);
    });

    test('attendance limits are enforced', () {
      expect(const AttendanceRules(graceMinutes: 121).isComplete, isFalse);
      expect(const AttendanceRules(earlyLeaveMinutes: 241).isComplete, isFalse);
      expect(
        const AttendanceRules(halfDayLateMinutes: 481).isComplete,
        isFalse,
      );
    });

    test('basics need a 6-digit PIN and at least one valid open day', () {
      expect(
        SetupProgress(basics(pin: '3950')).isComplete(SetupStep.basics),
        isFalse,
      );
      final closed = [for (var i = 0; i < 7; i++) const DayHours.closed()];
      expect(SetupProgress(basics(hours: closed)).percent, 0);
      final backwards = [...HoursPresets.monSat930]
        ..[0] = DayHours(open: true, opensAt: hm(18, 0), closesAt: hm(9, 0));
      expect(SetupProgress(basics(hours: backwards)).percent, 0);
    });
  });

  group('validateBranchDetails', () {
    Map<String, String> validate({
      String name = 'Surat',
      String pin = '395007',
      String email = '',
      WeeklyHours? hours,
      String? code,
    }) => validateBranchDetails(
      name: name,
      address: 'Ring Road',
      city: 'Surat',
      pin: pin,
      email: email,
      hours: hours ?? HoursPresets.monSat930,
      otherBranchNames: const ['Ahmedabad HQ'],
      code: code,
      otherBranchCodes: const ['AHM-01'],
    );

    test('valid details pass', () => expect(validate(), isEmpty));

    test('reports each problem with the design wording', () {
      final closed = [for (var i = 0; i < 7; i++) const DayHours.closed()];
      final errors = validate(
        name: ' ahmedabad hq ',
        pin: '12',
        email: 'x@',
        hours: closed,
        code: 'ahm-01',
      );
      expect(errors['name'], 'You already have a branch with this name.');
      expect(errors['pin'], Validators.pinMessage);
      expect(errors['email'], 'Check the email address.');
      expect(errors['code'], contains('AHM-01 is already used'));
      expect(errors['hours'], 'Open the branch on at least one day.');
    });

    test('flags the day whose closing time is before opening', () {
      final hours = [...HoursPresets.monSat930]
        ..[2] = DayHours(open: true, opensAt: hm(18, 0), closesAt: hm(9, 0));
      expect(validate(hours: hours).keys, ['hours.2']);
    });
  });

  test('hoursSummary', () {
    expect(hoursSummary(HoursPresets.monSat930), '6 days · 54 h a week');
    expect(
      hoursSummary([for (var i = 0; i < 7; i++) const DayHours.closed()]),
      'Closed all week',
    );
  });

  group('DemoOrganizationRepository', () {
    late DemoOrganizationRepository repo;
    final created = <(String, String)>[];

    setUp(() {
      created.clear();
      repo = DemoOrganizationRepository(
        latency: Duration.zero,
        onOrganizationCreated: (account, org) => created.add((account, org.id)),
      );
    });

    test('creating an organization makes the creator its owner', () async {
      final org = await repo.createOrganization(
        ownerAccountId: 'u-new',
        ownerName: 'Riya',
        ownerEmail: 'riya@example.in',
        name: 'Shree Weaves',
        employeeRange: employeeRanges.first,
      );
      expect(org.id, 'org_shree-weaves');
      expect(org.timeZone, defaultTimeZone);
      expect(created, [('u-new', 'org_shree-weaves')]);
      expect(await repo.branches(org.id), isEmpty);
    });

    test('rejects a one-letter organization name', () async {
      await expectLater(
        repo.createOrganization(
          ownerAccountId: 'u',
          ownerName: 'R',
          ownerEmail: 'r@x.in',
          name: 'A',
          employeeRange: employeeRanges.first,
        ),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('suggests a free code and refuses duplicate names', () async {
      const org = 'org_meridian-tex';
      final b = await repo.createBranch(
        org,
        basics().copyWith(name: 'Surya Mills'),
      );
      expect(b.code, startsWith('SUR-'));
      expect(b.code, isNot('SUR-01'));
      await expectLater(
        repo.createBranch(org, basics().copyWith(name: 'surya mills')),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('a branch with employees cannot be deactivated', () async {
      const org = 'org_meridian-tex';
      final branches = await repo.branches(org);
      final staffed = branches.firstWhere((b) => b.employeeCount > 0);
      await expectLater(
        repo.setBranchStatus(org, staffed.id, BranchStatus.inactive),
        throwsA(
          isA<ValidationFailure>().having(
            (f) => f.message,
            'message',
            contains('must be moved to another branch'),
          ),
        ),
      );
      final empty = branches.firstWhere((b) => b.employeeCount == 0);
      final reactivated = await repo.setBranchStatus(
        org,
        empty.id,
        BranchStatus.active,
      );
      expect(reactivated.isActive, isTrue);
    });

    test('seed data matches the design percentages', () async {
      final branches = await repo.branches('org_meridian-tex');
      final percents = {
        for (final b in branches) b.name: SetupProgress(b).percent,
      };
      expect(percents.values, containsAll([100, 65, 40]));
      expect(await repo.setupBookmark('org_meridian-tex'), isNotNull);
    });
  });

  group('validateImage', () {
    PickedImage file(List<int> head, [int size = 64]) =>
        PickedImage(name: 'logo', bytes: Uint8List(size)..setAll(0, head));

    test('accepts PNG and JPG by their first bytes', () {
      expect(validateImage(file([0x89, 0x50, 0x4E, 0x47])), isNull);
      expect(validateImage(file([0xFF, 0xD8, 0xFF])), isNull);
    });

    test('rejects other files and images over 2 MB', () {
      expect(
        validateImage(file([0x3C, 0x73, 0x76, 0x67])),
        contains('isn’t an image'),
      );
      expect(
        validateImage(file([0x89, 0x50, 0x4E, 0x47], maxImageBytes + 1)),
        contains('over 2 MB'),
      );
    });
  });
}
