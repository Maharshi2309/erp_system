import 'package:erp_portal/core/errors/failure.dart';
import 'package:erp_portal/core/permissions/system_roles.dart';
import 'package:erp_portal/core/utils/zoned_time.dart';
import 'package:erp_portal/features/attendance/data/demo_attendance_repository.dart';
import 'package:erp_portal/features/attendance/domain/attendance.dart';
import 'package:erp_portal/features/attendance/domain/attendance_book.dart';
import 'package:erp_portal/features/attendance/presentation/attendance_providers.dart';
import 'package:erp_portal/features/employees/data/demo_employee_repository.dart';
import 'package:erp_portal/features/employees/domain/employee.dart';
import 'package:erp_portal/features/organization/data/demo_organization_repository.dart';
import 'package:erp_portal/features/organization/domain/branch.dart';
import 'package:erp_portal/shared/models/app_session.dart';
import 'package:flutter_test/flutter_test.dart';

const kolkata = 'Asia/Kolkata';
final day = DateTime(2026, 10, 13); // Tuesday
final now = instantOf(DateTime(2026, 10, 14, 14, 10), kolkata);

Branch branch({
  String id = 'b',
  String? zone,
  ShiftMode shifts = ShiftMode.branchHours,
  List<HolidayItem> holidays = const [],
}) => Branch(
  id: id,
  name: 'Surat',
  address: 'x',
  city: 'Surat',
  state: 'Gujarat',
  pin: '394230',
  timeZone: zone,
  hours: HoursPresets.monSat930,
  attendance: AttendanceRules(shiftMode: shifts),
  holidays: HolidaySetup(source: HolidaySource.gujarat, items: holidays),
);

Employee person({
  String id = 'e',
  String shift = 'General',
  String? manager,
  DateTime? joined,
}) => Employee(
  id: id,
  organizationId: 'org',
  code: 'EMP-$id',
  firstName: 'Test',
  lastName: id,
  workEmail: '$id@x.in',
  designation: 'Operator',
  department: 'Production',
  type: EmploymentType.fullTime,
  joiningDate: joined ?? DateTime(2025),
  branchId: 'b',
  shift: shift,
  managerId: manager,
);

var _n = 0;
Punch p(
  String zone,
  DateTime date,
  int h,
  int m,
  PunchKind kind, {
  String employee = 'e',
  int dayOffset = 0,
}) => Punch(
  id: 'p${_n++}',
  employeeId: employee,
  at: instantOf(
    DateTime(date.year, date.month, date.day + dayOffset, h, m),
    zone,
  ),
  kind: kind,
  source: PunchSource.kiosk,
);

AttendanceBook book(
  List<Punch> punches, {
  List<Correction> corrections = const [],
  Branch? b,
  List<Employee>? people,
  DateTime? at,
}) => AttendanceBook(
  data: AttendanceData(punches: punches, corrections: corrections),
  employees: people ?? [person()],
  branches: [b ?? branch()],
  orgZone: kolkata,
  now: at ?? now,
);

const i = PunchKind.punchIn, o = PunchKind.punchOut;

void main() {
  group('worked time and status', () {
    test('a normal day with a lunch break is present', () {
      final r = book([
        p(kolkata, day, 9, 25, i),
        p(kolkata, day, 13, 0, o),
        p(kolkata, day, 14, 0, i),
        p(kolkata, day, 18, 35, o),
      ]).day(person(), day);
      expect(r.status, DayStatus.present);
      expect(r.workedMinutes, 3 * 60 + 35 + 4 * 60 + 35);
      expect(r.breakMinutes, 60);
      expect(r.expectedMinutes, 8 * 60);
      expect(formatDelta(r.workedMinutes, r.expectedMinutes), '+0h 10m');
    });

    test('explicit unpaid breaks are taken off the session', () {
      final r = book([
        p(kolkata, day, 10, 12, i),
        p(kolkata, day, 13, 35, PunchKind.breakStart),
        p(kolkata, day, 13, 53, PunchKind.breakEnd),
        p(kolkata, day, 18, 34, o),
      ]).day(person(), day);
      expect(r.workedMinutes, 8 * 60 + 4);
      expect(r.breakMinutes, 18);
      expect(r.lateMinutes, 42);
      expect(r.status, DayStatus.late);
    });

    test('arriving within the grace period is not late', () {
      final r = book([
        p(kolkata, day, 9, 39, i),
        p(kolkata, day, 18, 40, o),
      ]).day(person(), day);
      expect(r.lateMinutes, 0);
    });

    test('leaving early, short shifts and half days', () {
      expect(
        book([
          p(kolkata, day, 9, 28, i),
          p(kolkata, day, 16, 5, o),
        ]).day(person(), day).status,
        DayStatus.leftEarly,
      );
      expect(
        book([
          p(kolkata, day, 9, 33, i),
          p(kolkata, day, 12, 30, o),
          p(kolkata, day, 14, 30, i),
          p(kolkata, day, 18, 10, o),
        ]).day(person(), day).status,
        DayStatus.shortShift,
      );
      expect(
        book([
          p(kolkata, day, 9, 30, i),
          p(kolkata, day, 13, 30, o),
        ]).day(person(), day).status,
        DayStatus.halfDay,
      );
      expect(
        book([
          p(kolkata, day, 12, 0, i),
          p(kolkata, day, 18, 30, o),
        ]).day(person(), day).status,
        DayStatus.halfDay,
      );
    });

    test('no punches: absent, weekly off, holiday, not yet, upcoming', () {
      final b = book(
        const [],
        b: branch(
          holidays: [
            HolidayItem(name: 'Dussehra', date: DateTime(2026, 10, 20)),
          ],
        ),
      );
      expect(b.day(person(), day).status, DayStatus.absent);
      expect(
        b.day(person(), DateTime(2026, 10, 11)).status,
        DayStatus.weeklyOff,
      );
      expect(b.day(person(), DateTime(2026, 10, 20)).status, DayStatus.holiday);
      expect(
        b.day(person(), DateTime(2026, 10, 15)).status,
        DayStatus.upcoming,
      );
      final morning = book(
        const [],
        at: instantOf(DateTime(2026, 10, 14, 10, 0), kolkata),
      );
      expect(
        morning.day(person(), DateTime(2026, 10, 14)).status,
        DayStatus.notYet,
      );
      expect(
        b.day(person(), DateTime(2026, 10, 14)).status,
        DayStatus.absent,
        reason: 'two hours past shift start',
      );
      expect(
        book(const []).day(person(joined: DateTime(2026, 10, 14)), day).status,
        DayStatus.none,
      );
    });
  });

  group('missing punches', () {
    test(
      'an open session today is working; on an earlier day it is missing',
      () {
        final b = book([
          p(kolkata, day, 9, 41, i),
          p(kolkata, day, 13, 9, o),
          p(kolkata, day, 14, 2, i),
          p(kolkata, day, 9, 24, i, dayOffset: 1),
        ]);
        final yesterday = b.day(person(), day);
        expect(yesterday.status, DayStatus.missingPunch);
        expect(
          yesterday.workedMinutes,
          3 * 60 + 28,
          reason: 'the open session is excluded',
        );
        expect(yesterday.missingWhat, 'no punch-out');
        expect(
          b.day(person(), DateTime(2026, 10, 14)).status,
          DayStatus.working,
        );
      },
    );

    test('a punch-out without a punch-in is missing a punch-in', () {
      final r = book([p(kolkata, day, 18, 31, o)]).day(person(), day);
      expect(r.status, DayStatus.missingPunch);
      expect(r.missingWhat, 'no punch-in');
    });

    test('the queue lists open days and marks overdue ones', () {
      final b = book([
        p(kolkata, DateTime(2026, 10, 8), 9, 24, i),
        p(kolkata, day, 9, 30, i),
      ]);
      final queue = b.missingPunches([person()]);
      expect(queue.map((r) => r.date), [DateTime(2026, 10, 8), day]);
      expect(b.isOverdue(queue.first), isTrue);
      expect(b.isOverdue(queue.last), isFalse);
    });
  });

  group('overnight shifts and time zones', () {
    test('a night shift stays on the day it started', () {
      final b = book(
        [
          p(kolkata, day, 21, 2, i),
          p(kolkata, day, 1, 0, o, dayOffset: 1),
          p(kolkata, day, 1, 30, i, dayOffset: 1),
          p(kolkata, day, 6, 5, o, dayOffset: 1),
        ],
        b: branch(shifts: ShiftMode.several),
        people: [person(shift: 'Night')],
      );
      final r = b.day(person(shift: 'Night'), day);
      expect(r.sessions.length, 2);
      expect(r.status, DayStatus.present);
      expect(r.workedMinutes, 3 * 60 + 58 + 4 * 60 + 35);
      expect(
        b.day(person(shift: 'Night'), DateTime(2026, 10, 14)).sessions,
        isEmpty,
      );
    });

    test('days are cut at the branch’s midnight, not UTC’s', () {
      // 23:30 in Dubai is 01:30 the next day in Kolkata.
      final dubai = branch(zone: 'Asia/Dubai');
      final late = instantOf(DateTime(2026, 10, 13, 23, 30), 'Asia/Dubai');
      final b = book([
        p('Asia/Dubai', day, 9, 30, i),
        Punch(
          id: 'x',
          employeeId: 'e',
          at: late,
          kind: o,
          source: PunchSource.app,
        ),
      ], b: dubai);
      final r = b.day(person(), day);
      expect(r.zone, 'Asia/Dubai');
      expect(r.workedMinutes, 14 * 60);
      expect(clockTime(late, 'Asia/Dubai'), '23:30');
      expect(clockTime(late, kolkata), '01:00');
      expect(b.day(person(), DateTime(2026, 10, 14)).sessions, isEmpty);
    });

    test('the shift window follows the branch zone', () {
      final b = book(const [], b: branch(zone: 'Asia/Dubai'));
      final shift = b.shiftOn(person(), day)!;
      expect(shift.start, DateTime.utc(2026, 10, 13, 5, 30));
      expect(shift.end.difference(shift.start).inHours, 9);
    });
  });

  group('corrections keep the original', () {
    final punches = [
      p(kolkata, day, 9, 41, i),
      p(kolkata, day, 13, 9, o),
      p(kolkata, day, 14, 2, i),
    ];
    Correction c(
      CorrectionStatus status, {
      String? replaces,
      int h = 18,
      int m = 30,
    }) => Correction(
      id: 'c',
      employeeId: 'e',
      workDate: day,
      changes: [
        CorrectionChange(
          kind: replaces == null ? o : i,
          at: instantOf(DateTime(2026, 10, 13, h, m), kolkata),
          replaces: replaces,
        ),
      ],
      reason: 'Saw on CCTV',
      by: 'Mitesh Rana',
      createdAt: day,
      status: status,
    );

    test('a pending correction does not count yet', () {
      final r = book(
        punches,
        corrections: [c(CorrectionStatus.pending)],
      ).day(person(), day);
      expect(r.status, DayStatus.missingPunch);
      expect(r.pendingCorrection, isNotNull);
    });

    test('an approved correction completes the day and is marked', () {
      final r = book(
        punches,
        corrections: [c(CorrectionStatus.approved)],
      ).day(person(), day);
      expect(r.status, DayStatus.late);
      expect(r.workedMinutes, 3 * 60 + 28 + 4 * 60 + 28);
      expect(r.corrected, isTrue);
      expect(r.correctedBy, 'Mitesh Rana');
      expect(r.timeline.last.corrected, isTrue);
    });

    test('a moved punch replaces the original without deleting it', () {
      final b = book(
        [...punches, p(kolkata, day, 18, 30, o)],
        corrections: [
          c(CorrectionStatus.approved, replaces: punches.first.id, h: 9, m: 30),
        ],
      );
      final r = b.day(person(), day);
      expect(r.lateMinutes, 0);
      expect(
        b.data.punches.first.id,
        punches.first.id,
        reason: 'original kept',
      );
      expect(
        b.effectivePunches('e').map((x) => x.id),
        isNot(contains(punches.first.id)),
      );
    });

    test('a rejected correction changes nothing', () {
      final r = book(
        punches,
        corrections: [c(CorrectionStatus.rejected)],
      ).day(person(), day);
      expect(r.status, DayStatus.missingPunch);
      expect(r.corrected, isFalse);
    });
  });

  group('who approves', () {
    AppSession session(SystemRole role) => AppSession(
      userId: 'u',
      displayName: 'X',
      email: 'x@x.in',
      organizationId: 'org',
      organizationName: 'O',
      role: role,
    );

    test('a manager correcting their own report needs a second person', () {
      final manager = person(id: 'm');
      expect(
        needsSecondApproval(
          session(SystemRole.attendanceManager),
          person(manager: 'm'),
          manager,
        ),
        isTrue,
      );
      expect(
        needsSecondApproval(
          session(SystemRole.hrAdmin),
          person(manager: 'm'),
          person(id: 'hr'),
        ),
        isFalse,
      );
      expect(
        needsSecondApproval(
          session(SystemRole.owner),
          person(manager: 'm'),
          null,
        ),
        isFalse,
      );
      expect(
        needsSecondApproval(session(SystemRole.employee), person(), person()),
        isTrue,
        reason: 'nobody corrects themselves',
      );
    });
  });

  group('DemoAttendanceRepository', () {
    late DemoAttendanceRepository repo;
    setUp(
      () => repo = DemoAttendanceRepository(
        latency: Duration.zero,
        clock: () => now,
      ),
    );

    test('punch in and out change state; repeats are refused', () async {
      final a = await repo.punch(
        'o',
        employeeId: 'e',
        kind: i,
        source: PunchSource.web,
        requestId: 'r1',
      );
      await expectLater(
        repo.punch(
          'o',
          employeeId: 'e',
          kind: i,
          source: PunchSource.web,
          requestId: 'r2',
        ),
        throwsA(isA<ConflictFailure>()),
      );
      await repo.punch(
        'o',
        employeeId: 'e',
        kind: o,
        source: PunchSource.web,
        requestId: 'r3',
      );
      await expectLater(
        repo.punch(
          'o',
          employeeId: 'e',
          kind: o,
          source: PunchSource.web,
          requestId: 'r4',
        ),
        throwsA(isA<ConflictFailure>()),
      );
      expect(a.at, now);
    });

    test('retrying with the same request id records only once', () async {
      final a = await repo.punch(
        'o',
        employeeId: 'e',
        kind: i,
        source: PunchSource.web,
        requestId: 'same',
      );
      final b = await repo.punch(
        'o',
        employeeId: 'e',
        kind: i,
        source: PunchSource.web,
        requestId: 'same',
      );
      expect(b.id, a.id);
      expect((await repo.load('o')).punches.length, 1);
    });

    test('a failed punch saves nothing', () async {
      repo.failNextPunch = true;
      await expectLater(
        repo.punch(
          'o',
          employeeId: 'e',
          kind: i,
          source: PunchSource.web,
          requestId: 'x',
        ),
        throwsA(isA<NetworkFailure>()),
      );
      expect((await repo.load('o')).punches, isEmpty);
    });

    test(
      'corrections need a reason, are routed, and can’t be self-approved',
      () async {
        final draft = Correction(
          id: '',
          employeeId: 'e',
          workDate: day,
          changes: [CorrectionChange(kind: o, at: now)],
          reason: 'no',
          by: 'Mitesh Rana',
          createdAt: day,
        );
        await expectLater(
          repo.correct('o', draft, needsSecondApproval: true),
          throwsA(isA<ValidationFailure>()),
        );
        final saved = await repo.correct(
          'o',
          Correction(
            id: '',
            employeeId: 'e',
            workDate: day,
            changes: draft.changes,
            reason: 'Verified with CCTV',
            by: 'Mitesh Rana',
            createdAt: day,
          ),
          needsSecondApproval: true,
        );
        expect(saved.status, CorrectionStatus.pending);
        await expectLater(
          repo.decide('o', saved.id, approve: true, by: 'Mitesh Rana'),
          throwsA(isA<PermissionFailure>()),
        );
        final approved = await repo.decide(
          'o',
          saved.id,
          approve: true,
          by: 'Hetal Shah',
        );
        expect(approved.status, CorrectionStatus.approved);
        expect(approved.decidedBy, 'Hetal Shah');
        await expectLater(
          repo.decide('o', saved.id, approve: false, by: 'Hetal Shah'),
          throwsA(isA<ConflictFailure>()),
        );
      },
    );

    test('one open request per day; answering it closes it', () async {
      final r = CorrectionRequest(
        id: '',
        employeeId: 'e',
        workDate: day,
        kind: o,
        proposedAt: now,
        message: 'Forgot',
        createdAt: day,
      );
      final saved = await repo.request('o', r);
      await expectLater(repo.request('o', r), throwsA(isA<ConflictFailure>()));
      await repo.correct(
        'o',
        Correction(
          id: '',
          employeeId: 'e',
          workDate: day,
          changes: [CorrectionChange(kind: o, at: now)],
          reason: 'As requested',
          by: 'X',
          createdAt: day,
          requestId: saved.id,
        ),
        needsSecondApproval: false,
      );
      expect(
        (await repo.load('o')).requests.single.status,
        RequestStatus.resolved,
      );
    });

    test('the seed reproduces the design’s day in Surat', () async {
      const org = 'org_meridian-tex';
      final people = await DemoEmployeeRepository(
        latency: Duration.zero,
      ).employees(org);
      final branches = await DemoOrganizationRepository(
        latency: Duration.zero,
      ).branches(org);
      repo.ensureSeeded(
        org,
        employees: people,
        branches: branches,
        orgZone: kolkata,
      );
      final b = AttendanceBook(
        data: await repo.load(org),
        employees: people,
        branches: branches,
        orgZone: kolkata,
        now: now,
      );
      DayRecord of(String code) =>
          b.day(people.firstWhere((e) => e.code == code), day);
      expect(of('EMP-0240').status, DayStatus.missingPunch);
      expect(of('EMP-0236').missingWhat, 'no punch-in');
      expect(of('EMP-0229').status, DayStatus.late);
      expect(of('EMP-0229').workedMinutes, 8 * 60 + 4);
      expect(of('EMP-0229').corrected, isTrue);
      expect(of('EMP-0152').status, DayStatus.leftEarly);
      expect(of('EMP-0233').status, DayStatus.absent);
      expect(of('EMP-0176').status, DayStatus.halfDay);
      expect(of('EMP-0217').status, DayStatus.shortShift);
      final queue = b
          .missingPunches(people)
          .where((r) => r.date.isBefore(b.today))
          .toList();
      expect(queue.length, 7);
      expect(queue.where(b.isOverdue).length, 2);
      expect(
        queue.where((r) => r.employee.branchId == 'b-vad'),
        isEmpty,
        reason: 'Vadodara is all clear',
      );
      expect(
        b
            .day(
              people.firstWhere((e) => e.code == 'EMP-0229'),
              DateTime(2026, 10, 14),
            )
            .status,
        DayStatus.working,
      );
    });
  });
}
