import 'package:erp_portal/core/errors/failure.dart';
import 'package:erp_portal/core/permissions/system_roles.dart';
import 'package:erp_portal/features/employees/domain/employee.dart';
import 'package:erp_portal/features/holidays/domain/company_holiday.dart';
import 'package:erp_portal/features/holidays/domain/work_calendar.dart';
import 'package:erp_portal/features/leave/data/demo_leave_repository.dart';
import 'package:erp_portal/features/leave/domain/leave.dart';
import 'package:erp_portal/features/leave/domain/leave_book.dart';
import 'package:erp_portal/features/organization/domain/branch.dart';
import 'package:flutter_test/flutter_test.dart';

// Wednesday. Sundays are closed; 20 Oct (Tue) is Dussehra.
final today = DateTime(2026, 10, 14);
DateTime d(int month, int day) => DateTime(2026, month, day);

Branch branch(String id, {LeaveSetup? leave}) => Branch(
  id: id,
  name: id == 'b-sur' ? 'Surat' : 'Ahmedabad HQ',
  address: 'x',
  city: 'x',
  state: 'Gujarat',
  pin: '394230',
  hours: HoursPresets.monSat930,
  leave: leave,
);

Employee person(
  String id, {
  String branch = 'b-sur',
  String? manager,
  DateTime? joined,
  SystemRole role = SystemRole.employee,
  String department = 'Production',
  EmploymentType type = EmploymentType.fullTime,
}) => Employee(
  id: id,
  organizationId: 'org',
  code: 'EMP-$id',
  firstName: 'P',
  lastName: id,
  workEmail: '$id@x.in',
  designation: 'Operator',
  department: department,
  type: type,
  joiningDate: joined ?? DateTime(2024),
  branchId: branch,
  shift: 'General',
  managerId: manager,
  role: role,
);

final hr = person('hr', branch: 'b-ahm', role: SystemRole.hrAdmin);
final bm = person('bm', role: SystemRole.branchManager, manager: 'owner');
final aarav = person('aarav', manager: 'bm', role: SystemRole.leaveApprover);
final isha = person('isha', manager: 'aarav');
final chirag = person('chirag', manager: 'aarav');
final kiran = person('kiran', branch: 'b-ahm', manager: 'hr');
final staff = [hr, bm, aarav, isha, chirag, kiran];

final calendar = WorkCalendar(
  const [],
  holidays: [
    CompanyHoliday(id: 'h1', name: 'Dussehra', date: d(10, 20)),
    CompanyHoliday(
      id: 'h2',
      name: 'Guru Nanak Jayanti',
      date: d(11, 24),
      optional: true,
    ),
    CompanyHoliday(
      id: 'h3',
      name: 'Raksha Bandhan',
      date: d(10, 22),
      branchIds: const ['b-ahm'],
    ),
  ],
);

const policy = LeavePolicy(
  routes: [
    ApprovalRoute(id: 'r1', second: SecondStep.hrIfDays, minDays: 5),
    ApprovalRoute(
      id: 'r2',
      branchId: 'b-sur',
      second: SecondStep.branchManagerIfDays,
      minDays: 3,
    ),
    ApprovalRoute(id: 'r3', typeKey: 'earned', second: SecondStep.hrAlways),
  ],
);

var _n = 0;
LeaveRequest req(
  Employee e,
  String type,
  DateTime from,
  DateTime to, {
  LeaveStatus status = LeaveStatus.pending,
  HalfDay half = HalfDay.full,
  List<ApprovalStep>? steps,
}) => LeaveRequest(
  id: 'L-${_n++}',
  employeeId: e.id,
  typeKey: type,
  from: from,
  to: to,
  half: half,
  reason: '',
  createdAt: d(10, 10),
  status: status,
  steps:
      steps ??
      [ApprovalStep(kind: ApproverKind.manager, approverId: e.managerId)],
);

LeaveBook book({
  List<LeaveRequest> requests = const [],
  List<LeaveAdjustment> adjustments = const [],
  LeavePolicy p = policy,
  List<Branch>? branches,
  List<Employee>? employees,
  List<LeaveType> types = DemoLeaveRepository.defaultTypes,
}) => LeaveBook(
  data: LeaveData(
    types: types,
    policy: p,
    requests: requests,
    adjustments: adjustments,
  ),
  employees: employees ?? staff,
  branches: branches ?? [branch('b-sur'), branch('b-ahm')],
  today: today,
  calendar: calendar,
);

LeaveType type(String key) =>
    DemoLeaveRepository.defaultTypes.firstWhere((t) => t.key == key);

void main() {
  group('counting days', () {
    test('weekly offs and holidays are not counted', () {
      final days = book().countDays(
        isha,
        type('casual'),
        d(10, 17),
        d(10, 21),
        HalfDay.full,
      );
      expect([for (final x in days) x.counted], [1, 0, 1, 0, 1]);
      expect(days[1].note, 'Weekly off, not counted');
      expect(days[3].note, 'Dussehra — holiday, not counted');
    });

    test('a half day counts 0.5', () {
      final b = book();
      final r = req(isha, 'casual', d(10, 19), d(10, 19), half: HalfDay.first);
      expect(b.daysOf(r), 0.5);
    });

    test('branch-specific holidays only apply to that branch', () {
      final b = book();
      final t = type('casual');
      expect(
        b
            .countDays(kiran, t, d(10, 22), d(10, 22), HalfDay.full)
            .single
            .counted,
        0,
      );
      expect(
        b.countDays(isha, t, d(10, 22), d(10, 22), HalfDay.full).single.counted,
        1,
      );
    });

    test('a type can count holidays and weekly offs', () {
      final t = type(
        'casual',
      ).copyWith(countHolidays: true, countWeeklyOffs: true);
      final days = book().countDays(
        isha,
        t,
        d(10, 17),
        d(10, 21),
        HalfDay.full,
      );
      expect(days.fold(0.0, (s, x) => s + x.counted), 5);
    });

    test('optional holiday leave counts only optional holidays', () {
      final b = book();
      final t = type('optional');
      expect(
        b.countDays(isha, t, d(11, 24), d(11, 24), HalfDay.full).single.counted,
        1,
      );
      expect(
        b.countDays(isha, t, d(11, 23), d(11, 23), HalfDay.full).single.counted,
        0,
      );
    });

    test('a holiday added later gives the day back', () {
      final r = req(isha, 'casual', d(10, 26), d(10, 27));
      expect(book(requests: [r]).daysOf(r), 2);
      final withHoliday = LeaveBook(
        data: LeaveData(
          types: DemoLeaveRepository.defaultTypes,
          policy: policy,
          requests: [r],
        ),
        employees: staff,
        branches: [branch('b-sur'), branch('b-ahm')],
        today: today,
        calendar: WorkCalendar(
          const [],
          holidays: [CompanyHoliday(id: 'x', name: 'New', date: d(10, 27))],
        ),
      );
      expect(withHoliday.daysOf(r), 1);
    });
  });

  group('entitlement and balance', () {
    test('upfront types are granted on 1 Jan, prorated for joiners', () {
      final b = book();
      expect(b.entitlement(isha, type('casual'), 2026), 8);
      final joiner = person('new', joined: d(7, 1));
      expect(b.entitlement(joiner, type('casual'), 2026), 4);
      final future = person('later', joined: DateTime(2027, 2));
      expect(b.entitlement(future, type('casual'), 2026), 0);
    });

    test('monthly accrual starts after the waiting months', () {
      final b = book();
      // Jan–Oct for an old hand.
      expect(b.entitlement(isha, type('earned'), 2026), 12.5);
      // Joined 1 Mar, eligible 1 Sep: Sep and Oct.
      final joiner = person('new', joined: d(3, 1));
      expect(b.entitlement(joiner, type('earned'), 2026), 2.5);
    });

    test('a branch setup overrides the allowance or switches a type off', () {
      const setup = LeaveSetup.defaults;
      final b = book(
        branches: [
          branch('b-sur', leave: setup),
          branch('b-ahm'),
        ],
      );
      expect(b.entitlement(isha, type('casual'), 2026), 12);
      final off = LeaveSetup(
        types: [
          for (final t in setup.types)
            t.key == 'sick' ? t.copyWith(enabled: false) : t,
        ],
        approval: setup.approval,
      );
      final b2 = book(
        branches: [
          branch('b-sur', leave: off),
          branch('b-ahm'),
        ],
      );
      expect(b2.offers(isha, type('sick')), isFalse);
      expect(
        b2.balances(isha, 2026).map((x) => x.type.key),
        isNot(contains('sick')),
      );
    });

    test('used, pending, adjustments and carry make the balance', () {
      final b = book(
        requests: [
          req(isha, 'casual', d(9, 8), d(9, 9), status: LeaveStatus.approved),
          req(isha, 'casual', d(10, 19), d(10, 19)),
          req(isha, 'casual', d(9, 24), d(9, 24), status: LeaveStatus.rejected),
          req(
            isha,
            'casual',
            d(9, 15),
            d(9, 15),
            status: LeaveStatus.withdrawn,
          ),
        ],
        adjustments: [
          LeaveAdjustment(
            id: 'a1',
            employeeId: 'isha',
            typeKey: 'casual',
            days: 1.5,
            effective: d(6, 1),
            reason: 'Comp-off',
            by: 'HR',
          ),
          LeaveAdjustment(
            id: 'a2',
            employeeId: 'isha',
            typeKey: 'casual',
            days: 2,
            effective: d(1, 1),
            reason: 'Carried',
            by: 'System',
            carry: true,
          ),
        ],
      );
      final bal = b.balance(isha, 'casual', 2026);
      expect(bal.granted, 8);
      expect(bal.carried, 2);
      expect(bal.adjusted, 1.5);
      expect(bal.used, 2);
      expect(bal.pending, 1);
      expect(bal.available, 8.5);
    });

    test('the ledger runs newest first with a running balance', () {
      final b = book(
        requests: [
          req(isha, 'casual', d(9, 8), d(9, 9), status: LeaveStatus.approved),
          req(isha, 'casual', d(10, 19), d(10, 19)),
        ],
      );
      final lines = b.ledger(isha, 'casual', 2026);
      expect(lines.first.what, startsWith('Pending'));
      expect(lines.first.balance, 5);
      expect(lines.last.what, 'Granted · 1 Jan 2026');
      expect(lines.last.balance, 8);
    });

    test('taken by type counts approved days in the range only', () {
      final b = book(
        requests: [
          req(isha, 'casual', d(9, 30), d(10, 2), status: LeaveStatus.approved),
          req(chirag, 'sick', d(10, 5), d(10, 5), status: LeaveStatus.approved),
          req(chirag, 'sick', d(10, 6), d(10, 6)),
        ],
      );
      expect(b.takenByType([isha, chirag], d(10, 1), d(10, 14)), {
        'casual': 2,
        'sick': 1,
      });
    });
  });

  group('validation', () {
    Map<String, String> check(
      LeaveBook b, {
      Employee? e,
      String? t = 'casual',
      DateTime? from,
      DateTime? to,
      HalfDay half = HalfDay.full,
      String? amending,
    }) => b.validate(
      e: e ?? isha,
      typeKey: t,
      from: from,
      to: to ?? from,
      half: half,
      amending: amending,
    );

    test('type and dates are required and ordered', () {
      final b = book();
      expect(check(b, t: null)['type'], 'Choose a leave type.');
      expect(check(b)['dates'], 'Choose the start and end dates.');
      expect(
        check(b, from: d(10, 20), to: d(10, 19))['dates'],
        'The end date can’t be before the start date.',
      );
    });

    test('inactive or ineligible types are refused', () {
      expect(
        check(book(), t: 'parental', from: d(10, 19))['type'],
        'You’re not eligible for maternity / paternity.',
      );
      final contractOnly = type(
        'casual',
      ).copyWith(eligibleTypes: [EmploymentType.contract]);
      expect(
        check(book(types: [contractOnly]), from: d(10, 19))['type'],
        'You’re not eligible for casual leave.',
      );
    });

    test('half days are for one day and only where allowed', () {
      final b = book();
      expect(
        check(b, from: d(10, 19), to: d(10, 21), half: HalfDay.first)['half'],
        'Half days are for a single day. Choose full days or one date.',
      );
      expect(
        check(b, t: 'earned', from: d(10, 26), half: HalfDay.first)['half'],
        'Earned leave can’t be taken as a half day.',
      );
      expect(check(b, from: d(10, 19), half: HalfDay.second), isEmpty);
    });

    test('dates with nothing to count are refused', () {
      expect(
        check(book(), from: d(10, 18), to: d(10, 18))['dates'],
        'Those dates are holidays or weekly offs — nothing to request.',
      );
    });

    test('casual can’t be backdated; sick up to the policy limit', () {
      final b = book();
      expect(
        check(b, from: d(10, 12))['dates'],
        'Casual leave can’t start in the past.',
      );
      expect(check(b, t: 'sick', from: d(10, 12)), isEmpty);
      expect(
        check(b, t: 'sick', from: d(10, 5))['dates'],
        'Sick leave can be backdated by up to 7 days.',
      );
    });

    test('earned leave needs notice', () {
      expect(
        check(book(), t: 'earned', from: d(10, 19))['dates'],
        'Earned leave needs 7 days’ notice — start on Wed 21 Oct or later.',
      );
    });

    test('the longest request is capped', () {
      expect(
        check(book(), t: 'unpaid', from: d(10, 15), to: d(11, 20))['dates'],
        'Unpaid leave allows at most 15 days in one request.',
      );
    });

    test('blackouts block the listed types for the listed people', () {
      final p = policy.copyWith(
        blackouts: [
          Blackout(
            name: 'Dispatch peak',
            from: d(11, 2),
            to: d(11, 6),
            branchIds: const ['b-sur'],
            blockedTypes: const ['earned'],
          ),
        ],
      );
      final b = book(p: p);
      expect(
        check(b, t: 'earned', from: d(11, 2))['dates'],
        'Earned leave can’t be taken during Dispatch peak (2–6 Nov).',
      );
      expect(check(b, from: d(11, 2)), isEmpty);
      expect(check(b, e: kiran, t: 'earned', from: d(11, 2)), isEmpty);
    });

    test('overlap names the request and the next day that counts', () {
      final pending = req(isha, 'casual', d(10, 19), d(10, 19));
      final b = book(requests: [pending]);
      expect(
        check(b, from: d(10, 19), to: d(10, 21))['overlap'],
        'This overlaps your pending request for Mon 19 Oct. Withdraw it '
        'first, or change the start date to Wed 21 Oct.',
      );
      // Amending the same request doesn't overlap itself.
      expect(
        check(b, from: d(10, 19), to: d(10, 21), amending: pending.id),
        isEmpty,
      );
    });

    test('rejected and withdrawn requests don’t block new ones', () {
      final b = book(
        requests: [
          req(
            isha,
            'casual',
            d(10, 19),
            d(10, 19),
            status: LeaveStatus.rejected,
          ),
          req(
            isha,
            'casual',
            d(10, 19),
            d(10, 19),
            status: LeaveStatus.withdrawn,
          ),
        ],
      );
      expect(check(b, from: d(10, 19)), isEmpty);
    });

    test('a request can’t exceed the balance unless negative is allowed', () {
      final used = req(
        isha,
        'casual',
        d(9, 1),
        d(9, 8),
        status: LeaveStatus.approved,
      );
      final b = book(requests: [used]);
      expect(b.balance(isha, 'casual', 2026).available, 1);
      // Mon 19 + Dussehra: one day, exactly what's left.
      expect(check(b, from: d(10, 19), to: d(10, 20)), isEmpty);
      expect(
        check(b, from: d(10, 19), to: d(10, 21))['balance'],
        'Not enough casual leave: 1 available, 2 requested.',
      );
      final lenient = book(
        requests: [used],
        p: policy.copyWith(allowNegative: true),
      );
      expect(check(lenient, from: d(10, 19), to: d(10, 22)), isEmpty);
      expect(
        check(lenient, from: d(10, 19), to: d(10, 24))['balance'],
        isNotNull,
      );
    });

    test('optional holidays are limited per year', () {
      final b = book(requests: [req(isha, 'optional', d(11, 24), d(11, 24))]);
      final other = DateTime(2026, 12, 25);
      final withXmas = LeaveBook(
        data: b.data,
        employees: staff,
        branches: [branch('b-sur'), branch('b-ahm')],
        today: today,
        calendar: WorkCalendar(
          const [],
          holidays: [
            ...calendar.holidays,
            CompanyHoliday(
              id: 'x',
              name: 'Christmas',
              date: other,
              optional: true,
            ),
          ],
        ),
      );
      expect(
        check(withXmas, t: 'optional', from: other)['balance'],
        'You can take 1 optional holiday a year.',
      );
      expect(
        check(book(), t: 'optional', from: d(11, 23))['dates'],
        'Choose an optional holiday.',
      );
    });
  });

  group('routing and decisions', () {
    test('step 1 is the reporting manager', () {
      final steps = book().route(isha, type('casual'), 1);
      expect(steps.single.kind, ApproverKind.manager);
      expect(steps.single.approverId, 'aarav');
    });

    test('long leave adds a second step from the most specific route', () {
      final b = book();
      // Surat: branch manager from 3 days.
      expect(b.route(isha, type('casual'), 3).map((s) => s.kind), [
        ApproverKind.manager,
        ApproverKind.branchManager,
      ]);
      // Ahmedabad: default route, HR from 5 days.
      expect(b.route(kiran, type('casual'), 5).map((s) => s.kind), [
        ApproverKind.manager,
      ]);
      // Kiran's manager is HR, so the HR step isn't repeated.
      final ravi = person('ravi', branch: 'b-ahm', manager: 'kiran');
      expect(
        book(
          employees: [...staff, ravi],
        ).route(ravi, type('casual'), 5).map((s) => s.kind),
        [ApproverKind.manager, ApproverKind.hr],
      );
      // Earned leave always goes to HR.
      expect(b.route(isha, type('earned'), 1).last.kind, ApproverKind.hr);
    });

    test('no manager, or central approval, goes to HR', () {
      final loner = person('loner');
      expect(
        book(
          employees: [...staff, loner],
        ).route(loner, type('casual'), 1).single.note,
        'No reporting manager',
      );
      final central = LeaveSetup(
        types: LeaveSetup.defaults.types,
        approval: LeaveApproval.owner,
      );
      expect(
        book(
          branches: [
            branch('b-sur', leave: central),
            branch('b-ahm'),
          ],
        ).route(isha, type('casual'), 1).single.kind,
        ApproverKind.hr,
      );
    });

    test('nobody is routed to approve their own request', () {
      // Aarav's 3-day Surat leave: manager (bm) then branch manager (bm
      // again) — the duplicate step is dropped.
      expect(book().route(aarav, type('casual'), 3).map((s) => s.approverId), [
        'bm',
      ]);
      // The branch manager's own long leave can't go to themselves.
      final steps = book().route(bm, type('casual'), 3);
      expect(steps.any((s) => s.approverId == 'bm'), isFalse);
      final self = person('self', manager: 'self');
      final own = book(
        employees: [...staff, self],
      ).route(self, type('casual'), 1);
      expect(own.single.kind, ApproverKind.hr);
      expect(
        own.single.note,
        'Routed to HR — approver cannot approve own request',
      );
    });

    test('who may decide', () {
      final b = book();
      final r = req(isha, 'casual', d(10, 19), d(10, 19));
      bool can(
        SystemRole role,
        Employee? self, [
        List<String> ids = const [],
      ]) => b.canDecide(r, role: role, self: self, branchIds: ids);
      expect(can(SystemRole.leaveApprover, aarav), isTrue);
      expect(can(SystemRole.leaveApprover, chirag), isFalse);
      expect(can(SystemRole.employee, isha), isFalse, reason: 'own request');
      expect(can(SystemRole.hrAdmin, hr), isTrue);
      expect(can(SystemRole.owner, null), isTrue);
      expect(can(SystemRole.branchManager, bm, ['b-sur']), isTrue);
      expect(can(SystemRole.branchManager, bm, ['b-ahm']), isFalse);
      // HR can't decide their own request either.
      final mine = req(hr, 'casual', d(10, 19), d(10, 19));
      expect(b.canDecide(mine, role: SystemRole.hrAdmin, self: hr), isFalse);
      // Decided and sent-back requests can't be decided.
      for (final s in [LeaveStatus.approved, LeaveStatus.changesRequested]) {
        final x = req(isha, 'casual', d(10, 19), d(10, 19), status: s);
        expect(b.canDecide(x, role: SystemRole.hrAdmin, self: hr), isFalse);
      }
    });

    test('who sees which requests', () {
      final rs = [
        req(isha, 'casual', d(10, 19), d(10, 19)),
        req(kiran, 'casual', d(10, 19), d(10, 19)),
        req(bm, 'casual', d(10, 19), d(10, 19)),
      ];
      final b = book(requests: rs);
      List<String> seen(
        SystemRole role,
        Employee? self, [
        List<String> ids = const [],
      ]) => [
        for (final r in b.visibleTo(role: role, self: self, branchIds: ids))
          r.employeeId,
      ];
      expect(seen(SystemRole.hrAdmin, hr), ['isha', 'kiran', 'bm']);
      expect(seen(SystemRole.branchManager, bm, ['b-sur']), ['isha', 'bm']);
      expect(seen(SystemRole.leaveApprover, aarav), ['isha']);
      expect(seen(SystemRole.employee, isha), isEmpty);
    });

    test('approved leave shows for the days it covers', () {
      final r = req(
        isha,
        'casual',
        d(10, 15),
        d(10, 16),
        status: LeaveStatus.approved,
      );
      final b = book(requests: [r]);
      expect(b.leaveOn(isha, d(10, 16)), r);
      expect(b.leaveOn(isha, d(10, 17)), isNull);
      expect(b.leaveOn(chirag, d(10, 16)), isNull);
    });
  });

  group('rules for types and policy', () {
    test('leave type fields are checked', () {
      const others = DemoLeaveRepository.defaultTypes;
      expect(validateLeaveType(type('casual'), others), isEmpty);
      final bad = type('casual').copyWith(
        name: 'Sick leave',
        allowance: 0,
        minDays: 5,
        maxDays: 2,
        backdateDays: 40,
      );
      expect(validateLeaveType(bad, others).keys, [
        'name',
        'allowance',
        'minDays',
        'backdate',
      ]);
    });

    test('policy needs a default route and sane limits', () {
      expect(validateLeavePolicy(policy), isEmpty);
      final bad = policy.copyWith(
        backdatedSickDays: 31,
        longestRequestDays: 0,
        routes: [policy.routes[1]],
        blackouts: [Blackout(name: 'X', from: d(12, 2), to: d(12, 1))],
      );
      expect(validateLeavePolicy(bad), {
        'backdated':
            'Must be 30 days or less, so attendance for a closed month isn’t changed.',
        'longest': 'Enter 1 to 90 working days.',
        'routes': 'Keep a default route for all branches.',
        'blackouts': '“X” ends before it starts.',
      });
    });

    test('the accrual example follows the type', () {
      expect(
        accrualExample(type('earned').copyWith(startsAfterMonths: 3), 2026),
        'Eligible from 1 Jun (after 3 months) → accrues 1.25 days on the 1st '
        'of each month → 8.75 days by 31 Dec → up to 30 carried into 2027.',
      );
      expect(
        accrualExample(type('casual'), 2026),
        'Eligible from 1 Mar → 6.5 of 8 days granted for the rest of 2026 → '
        'unused days lapse on 31 Dec.',
      );
    });
  });

  group('repository transitions', () {
    late DemoLeaveRepository repo;
    setUp(() {
      repo = DemoLeaveRepository(
        latency: Duration.zero,
        today: () => today,
        now: () => DateTime(2026, 10, 14, 14, 10),
      );
    });

    Future<LeaveRequest> submit({DateTime? from, List<ApprovalStep>? steps}) =>
        repo.submit(
          'o',
          req(
            isha,
            'casual',
            from ?? d(10, 19),
            from ?? d(10, 19),
            steps: steps,
          ),
        );

    test('approve finishes the last step', () async {
      final r = await submit();
      final done = await repo.decide(
        'o',
        r.id,
        approve: true,
        by: 'Aarav Bhatt',
        byEmployeeId: 'aarav',
      );
      expect(done.status, LeaveStatus.approved);
      expect(done.steps.single.decidedBy, 'Aarav Bhatt');
      expect(done.history.last.text, 'Approved');
    });

    test('two steps stay pending after the first approval', () async {
      final r = await submit(
        steps: const [
          ApprovalStep(kind: ApproverKind.manager, approverId: 'aarav'),
          ApprovalStep(kind: ApproverKind.hr),
        ],
      );
      final first = await repo.decide(
        'o',
        r.id,
        approve: true,
        by: 'Aarav',
        byEmployeeId: 'aarav',
      );
      expect(first.status, LeaveStatus.pending);
      expect(first.currentStep!.kind, ApproverKind.hr);
      final second = await repo.decide(
        'o',
        r.id,
        approve: true,
        by: 'Hetal',
        byEmployeeId: 'hr',
      );
      expect(second.status, LeaveStatus.approved);
    });

    test('a rejection needs a reason and ends the request', () async {
      final r = await submit();
      await expectLater(
        repo.decide('o', r.id, approve: false, by: 'A', byEmployeeId: 'aarav'),
        throwsA(isA<ValidationFailure>()),
      );
      final no = await repo.decide(
        'o',
        r.id,
        approve: false,
        by: 'A',
        byEmployeeId: 'aarav',
        note: 'Audit week, please move',
      );
      expect(no.status, LeaveStatus.rejected);
      expect(no.decisionNote, 'Audit week, please move');
      await expectLater(
        repo.decide('o', r.id, approve: true, by: 'A', byEmployeeId: 'aarav'),
        throwsA(isA<ConflictFailure>()),
      );
    });

    test('nobody decides their own request', () async {
      final r = await submit();
      await expectLater(
        repo.decide('o', r.id, approve: true, by: 'Isha', byEmployeeId: 'isha'),
        throwsA(isA<PermissionFailure>()),
      );
    });

    test('request changes, then amend sends it back for approval', () async {
      final r = await submit();
      final back = await repo.requestChanges(
        'o',
        r.id,
        by: 'Aarav',
        note: 'Take Tuesday instead',
      );
      expect(back.status, LeaveStatus.changesRequested);
      final amended = await repo.amend(
        'o',
        back.copyWith(from: d(10, 21), to: d(10, 21)),
        by: 'Isha',
      );
      expect(amended.status, LeaveStatus.pending);
      expect(amended.amendedFrom, (d(10, 19), d(10, 19)));
      expect(amended.decisionNote, isEmpty);
    });

    test('withdraw only while open; cancel only before it starts', () async {
      final r = await submit();
      final w = await repo.withdraw('o', r.id, by: 'Isha');
      expect(w.status, LeaveStatus.withdrawn);
      await expectLater(
        repo.withdraw('o', r.id, by: 'Isha'),
        throwsA(isA<ConflictFailure>()),
      );

      final later = await submit(from: d(10, 26));
      await expectLater(
        repo.cancel('o', later.id, by: 'Isha'),
        throwsA(isA<ConflictFailure>()),
        reason: 'not approved yet',
      );
      await repo.decide(
        'o',
        later.id,
        approve: true,
        by: 'A',
        byEmployeeId: 'aarav',
      );
      final c = await repo.cancel('o', later.id, by: 'Isha');
      expect(c.status, LeaveStatus.cancelled);

      final started = await submit(from: d(10, 14));
      await repo.decide(
        'o',
        started.id,
        approve: true,
        by: 'A',
        byEmployeeId: 'aarav',
      );
      await expectLater(
        repo.cancel('o', started.id, by: 'Isha'),
        throwsA(isA<ConflictFailure>()),
      );
    });

    test('adjustments need a size and a reason', () async {
      LeaveAdjustment adj(double days, String reason) => LeaveAdjustment(
        id: '',
        employeeId: 'isha',
        typeKey: 'earned',
        days: days,
        effective: today,
        reason: reason,
        by: 'Hetal',
      );
      await expectLater(
        repo.adjust('o', adj(0, 'Correction')),
        throwsA(isA<ValidationFailure>()),
      );
      await expectLater(
        repo.adjust('o', adj(31, 'Correction')),
        throwsA(isA<ValidationFailure>()),
      );
      await expectLater(
        repo.adjust('o', adj(1, 'abc')),
        throwsA(isA<ValidationFailure>()),
      );
      final ok = await repo.adjust('o', adj(-1.5, 'Recovered over-use'));
      expect(ok.id, startsWith('evt_'));
      expect((await repo.load('o')).adjustments.single.days, -1.5);
    });

    test('types and policy are validated on save', () async {
      await expectLater(
        repo.saveType('o', type('casual').copyWith(name: ' ')),
        throwsA(isA<ValidationFailure>()),
      );
      await expectLater(
        repo.savePolicy('o', policy.copyWith(backdatedSickDays: 45)),
        throwsA(isA<ValidationFailure>()),
      );
      final saved = await repo.savePolicy('o', policy);
      expect(saved.updatedAt, isNotNull);
    });
  });
}
