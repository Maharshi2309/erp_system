import 'package:erp_portal/core/errors/failure.dart';
import 'package:erp_portal/features/employees/domain/employee.dart';
import 'package:erp_portal/features/holidays/data/demo_calendar_repository.dart';
import 'package:erp_portal/features/holidays/domain/company_holiday.dart';
import 'package:erp_portal/features/holidays/domain/holiday_import.dart';
import 'package:erp_portal/features/holidays/domain/work_calendar.dart';
import 'package:erp_portal/features/organization/domain/branch.dart';
import 'package:flutter_test/flutter_test.dart';

final today = DateTime(2026, 10, 14);
DateTime d(int month, int day, [int year = 2026]) => DateTime(year, month, day);

Branch branch(String id, String name, {List<HolidayItem> list = const []}) =>
    Branch(
      id: id,
      name: name,
      code: '${name.substring(0, 3).toUpperCase()}-01',
      address: 'x',
      city: 'x',
      state: 'Gujarat',
      pin: '380001',
      hours: HoursPresets.monSat930,
      holidays: HolidaySetup(source: HolidaySource.gujarat, items: list),
    );

final surat = branch('b-sur', 'Surat');
final ahm = branch(
  'b-ahm',
  'Ahmedabad HQ',
  list: [
    HolidayItem(name: 'Bhai Bij', date: d(11, 11)),
    HolidayItem(name: 'Christmas', date: d(12, 25), observed: false),
  ],
);

Employee person(String id, {int? weeklyOff, String shift = 'General'}) =>
    Employee(
      id: id,
      organizationId: 'org',
      code: 'EMP-$id',
      firstName: 'P',
      lastName: id,
      workEmail: '$id@x.in',
      designation: 'Operator',
      department: 'Production',
      type: EmploymentType.fullTime,
      joiningDate: DateTime(2024),
      branchId: 'b-sur',
      shift: shift,
      weeklyOff: weeklyOff,
    );

ScheduleAssignment assign(
  ScheduleLevel level,
  DateTime from, {
  String? shift,
  int? weeklyOff,
  List<String> people = const [],
  String? branchId,
}) => ScheduleAssignment(
  id: '${level.name}-${from.day}',
  level: level,
  name: level.label,
  effectiveFrom: from,
  employeeIds: people,
  branchId: branchId,
  shift: shift,
  weeklyOff: weeklyOff,
);

void main() {
  group('schedule precedence', () {
    final isha = person('isha');
    final calendar = WorkCalendar([
      assign(ScheduleLevel.organization, d(1, 1), weeklyOff: 6),
      assign(ScheduleLevel.branch, d(4, 1), branchId: 'b-sur', weeklyOff: 6),
      assign(
        ScheduleLevel.group,
        d(11, 1),
        people: const ['isha', 'raj'],
        shift: 'Night',
        weeklyOff: 5,
      ),
      assign(
        ScheduleLevel.employee,
        d(12, 1),
        people: const ['isha'],
        shift: 'General',
        weeklyOff: 0,
      ),
    ]);

    test('the most specific assignment in effect wins', () {
      expect(
        calendar.scheduleFor(isha, d(3, 1)).source!.level,
        ScheduleLevel.organization,
      );
      expect(
        calendar.scheduleFor(isha, d(10, 14)).source!.level,
        ScheduleLevel.branch,
      );
      final nov = calendar.scheduleFor(isha, d(11, 2));
      expect((nov.shift, nov.weeklyOff), ('Night', 5));
      final dec = calendar.scheduleFor(isha, d(12, 2));
      expect((dec.shift, dec.weeklyOff), ('General', 0));
    });

    test('dated changes don’t rewrite the past', () {
      expect(calendar.scheduleFor(isha, d(10, 31)).shift, 'General');
      expect(calendar.scheduleFor(isha, d(11, 1)).shift, 'Night');
    });

    test('a personal weekly off beats group and branch assignments', () {
      final own = person('raj', weeklyOff: 2);
      final s = calendar.scheduleFor(own, d(11, 2));
      expect(s.weeklyOff, 2);
      expect(s.source, isNull);
    });

    test('without assignments the employee record applies', () {
      final s = const WorkCalendar(
        [],
      ).scheduleFor(person('x', shift: 'Night'), d(1, 1));
      expect((s.shift, s.weeklyOff, s.source), ('Night', null, null));
    });
  });

  group('holiday scope', () {
    final calendar = WorkCalendar(
      const [],
      holidays: [
        CompanyHoliday(id: 'h1', name: 'Dussehra', date: d(10, 20)),
        CompanyHoliday(
          id: 'h2',
          name: 'Diwali break',
          date: d(11, 9),
          endDate: d(11, 10),
        ),
        CompanyHoliday(
          id: 'h3',
          name: 'Raksha Bandhan',
          date: d(8, 28),
          branchIds: const ['b-sur'],
        ),
        CompanyHoliday(
          id: 'h4',
          name: 'Guru Nanak Jayanti',
          date: d(11, 24),
          optional: true,
        ),
      ],
    );

    test('organization-wide holidays reach every branch', () {
      expect(calendar.holidayFor(surat, d(10, 20))!.name, 'Dussehra');
      expect(calendar.holidayFor(ahm, d(10, 20))!.orgWide, isTrue);
      expect(calendar.holidayFor(null, d(10, 20)), isNotNull);
    });

    test('branch-specific holidays reach only their branches', () {
      expect(calendar.holidayFor(surat, d(8, 28))!.name, 'Raksha Bandhan');
      expect(calendar.holidayFor(ahm, d(8, 28)), isNull);
    });

    test('ranges cover every day', () {
      expect(calendar.holidayFor(surat, d(11, 9))!.name, 'Diwali break');
      expect(calendar.holidayFor(surat, d(11, 10))!.name, 'Diwali break');
      expect(calendar.holidayFor(surat, d(11, 11)), isNull);
    });

    test('optional holidays only when asked', () {
      expect(calendar.holidayFor(surat, d(11, 24)), isNull);
      expect(
        calendar.holidayFor(surat, d(11, 24), includeOptional: true)!.optional,
        isTrue,
      );
    });

    test('a branch’s own list from setup still applies', () {
      expect(calendar.holidayFor(ahm, d(11, 11))!.name, 'Bhai Bij');
      expect(calendar.holidayFor(surat, d(11, 11)), isNull);
      // Unticked items in the branch list don't count.
      expect(calendar.holidayFor(ahm, d(12, 25)), isNull);
    });

    test('holidays between two dates, one per day', () {
      expect(
        calendar
            .holidaysBetween(surat, d(11, 1), d(11, 30), includeOptional: true)
            .map((h) => h.name),
        ['Diwali break', 'Diwali break', 'Guru Nanak Jayanti'],
      );
    });

    test('overlap warning on the form', () {
      final all = calendar.holidays;
      final draft = CompanyHoliday(
        id: '',
        name: 'Gujarati New Year',
        date: d(11, 10),
      );
      expect(overlapping(all, draft).single.name, 'Diwali break');
      final elsewhere = CompanyHoliday(
        id: '',
        name: 'Local fair',
        date: d(8, 28),
        branchIds: const ['b-ahm'],
      );
      expect(overlapping(all, elsewhere), isEmpty);
    });
  });

  group('holiday import', () {
    final existing = [
      CompanyHoliday(id: 'h', name: 'Gandhi Jayanti', date: d(10, 2, 2027)),
    ];

    List<HolidayRow> check(List<List<String>> rows) => checkHolidayRows(
      rows,
      existing: existing,
      branches: [surat, ahm],
      today: today,
    );

    test('dates are read in several formats and checked', () {
      expect(parseHolidayDate('14/01/2027').$1, d(1, 14, 2027));
      expect(parseHolidayDate('2027-01-26').$1, d(1, 26, 2027));
      expect(parseHolidayDate('15 Aug 2027').$1, d(8, 15, 2027));
      expect(parseHolidayDate('31/09/2027').$2, 'September has 30 days');
      expect(parseHolidayDate('01/13/2027').$2, 'There is no month 13');
      expect(parseHolidayDate('soon').$2, 'Use DD/MM/YYYY');
    });

    test('rows are ready, duplicate or invalid with a reason', () {
      final rows = check([
        ['14/01/2027', 'Uttarayan', 'All branches', 'Festival'],
        ['26/01/2027', 'Republic Day', '', 'National'],
        ['26/01/2027', 'Republic Day', 'All branches', 'National'],
        ['28/08/2027', 'Raksha Bandhan', 'Surat', ''],
        ['31/09/2027', 'Navratri', 'Surat', ''],
        ['02/10/2027', 'Gandhi Jayanti', 'All branches', 'National'],
        ['05/11/2027', 'Fair', 'Rajkot', ''],
        ['01/10/2026', 'Old', 'All branches', ''],
        ['24/11/2027', 'Guru Nanak Jayanti', 'Optional', ''],
        ['', '', '', ''],
      ]);
      expect(
        [for (final r in rows) r.status.name],
        [
          'ready',
          'ready',
          'duplicate',
          'ready',
          'invalid',
          'duplicate',
          'invalid',
          'invalid',
          'ready',
        ],
      );
      expect(rows[2].note, 'Same as row 3');
      expect(rows[4].note, 'September has 30 days');
      expect(rows[5].note, 'Already exists for 2027');
      expect(rows[6].note, 'No branch called “Rajkot”');
      expect(rows[7].note, 'Date has passed');
      expect(rows[3].holiday!.branchIds, ['b-sur']);
      expect(rows[1].holiday!.category, HolidayCategory.national);
      expect(rows[8].holiday!.optional, isTrue);
      expect(rows.first.row, 2, reason: 'row 1 is the header');
    });
  });

  group('calendar repository', () {
    late DemoCalendarRepository repo;
    setUp(() {
      repo = DemoCalendarRepository(latency: Duration.zero, today: () => today);
      repo.ensureSeeded('o', [person('isha', shift: 'Night'), person('raj')]);
    });

    test('seeds the demo calendar and the night crew', () async {
      expect((await repo.holidays('o')).length, 14);
      final groups = await repo.assignments('o');
      expect(groups.single.employeeIds, ['isha']);
    });

    test('new holidays get an id; names and dates are checked', () async {
      final saved = await repo.saveHoliday(
        'o',
        CompanyHoliday(id: '', name: ' Founders day ', date: d(12, 1)),
      );
      expect(saved.id, isNotEmpty);
      expect(saved.name, 'Founders day');
      for (final bad in [
        CompanyHoliday(id: '', name: 'X', date: d(12, 1)),
        CompanyHoliday(id: '', name: 'Back', date: d(10, 1)),
        CompanyHoliday(
          id: '',
          name: 'Long',
          date: d(12, 1),
          endDate: d(12, 20),
        ),
        CompanyHoliday(id: '', name: 'Odd', date: d(12, 5), endDate: d(12, 1)),
      ]) {
        await expectLater(
          repo.saveHoliday('o', bad),
          throwsA(isA<ValidationFailure>()),
          reason: bad.name,
        );
      }
    });

    test('past holidays can’t be edited or deleted', () async {
      final gandhi = (await repo.holidays(
        'o',
      )).firstWhere((h) => h.name == 'Gandhi Jayanti');
      await expectLater(
        repo.saveHoliday('o', gandhi.copyWith(name: 'Renamed')),
        throwsA(isA<ConflictFailure>()),
      );
      await expectLater(
        repo.deleteHoliday('o', gandhi.id),
        throwsA(isA<ConflictFailure>()),
      );
      final dussehra = (await repo.holidays(
        'o',
      )).firstWhere((h) => h.name == 'Dussehra');
      await repo.deleteHoliday('o', dussehra.id);
      expect(
        (await repo.holidays('o')).any((h) => h.name == 'Dussehra'),
        isFalse,
      );
    });

    test('imports add every checked row', () async {
      final added = await repo.importHolidays('o', [
        CompanyHoliday(id: '', name: 'Uttarayan', date: d(1, 14, 2027)),
        CompanyHoliday(id: '', name: 'Republic Day', date: d(1, 26, 2027)),
      ]);
      expect(added.map((h) => h.id).toSet().length, 2);
      expect((await repo.holidays('o')).length, 16);
    });

    test('schedules can’t start in the past or without people', () async {
      await expectLater(
        repo.addAssignment(
          'o',
          assign(ScheduleLevel.branch, d(10, 1), branchId: 'b-sur'),
        ),
        throwsA(isA<ValidationFailure>()),
      );
      await expectLater(
        repo.addAssignment('o', assign(ScheduleLevel.group, d(11, 1))),
        throwsA(isA<ValidationFailure>()),
      );
      final ok = await repo.addAssignment(
        'o',
        assign(ScheduleLevel.branch, d(11, 1), branchId: 'b-sur', weeklyOff: 5),
      );
      expect(ok.id, startsWith('sa-'));
    });
  });
}
