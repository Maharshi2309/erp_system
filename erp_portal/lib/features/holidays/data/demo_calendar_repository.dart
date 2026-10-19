import '../../../core/errors/failure.dart';
import '../../employees/domain/employee.dart';
import '../domain/calendar_repository.dart';
import '../domain/company_holiday.dart';
import '../domain/work_calendar.dart';
import 'holiday_seed.dart';

/// DEMO ONLY — holidays and schedule assignments in memory.
class DemoCalendarRepository implements CalendarRepository {
  DemoCalendarRepository({
    this.latency = const Duration(milliseconds: 500),
    required this.today,
  });

  final Duration latency;
  final DateTime Function() today;
  final _data = <String, List<ScheduleAssignment>>{};
  final _holidays = <String, List<CompanyHoliday>>{};
  int _next = 1;
  int _nextHoliday = 100;

  Future<void> _delay() =>
      latency == Duration.zero ? Future.value() : Future.delayed(latency);

  bool isSeeded(String id) => _data.containsKey(id);

  /// The Surat night crew as a shift group (board S66).
  void ensureSeeded(String organizationId, List<Employee> employees) {
    if (_data.containsKey(organizationId)) return;
    _holidays[organizationId] = demoCompanyHolidays();
    final night = [
      for (final e in employees)
        if (e.shift == 'Night') e.id,
    ];
    _data[organizationId] = [
      if (night.isNotEmpty)
        ScheduleAssignment(
          id: 'sa-${_next++}',
          level: ScheduleLevel.group,
          name: 'Surat dyeing night crew',
          branchId: 'b-sur',
          employeeIds: night,
          shift: 'Night',
          effectiveFrom: DateTime(2026, 4, 1),
          createdBy: 'Hetal Shah',
        ),
    ];
  }

  DateTime get _today {
    final t = today();
    return DateTime(t.year, t.month, t.day);
  }

  void _check(CompanyHoliday h) {
    if (h.name.trim().length < 2) {
      throw const ValidationFailure(
        'Name the holiday.',
        fieldErrors: {'name': 'Enter the holiday name.'},
      );
    }
    if (h.endDate.isBefore(h.date)) {
      throw const ValidationFailure(
        'Check the dates.',
        fieldErrors: {'date': 'The last day can’t be before the first.'},
      );
    }
    if (h.endDate.difference(h.date).inDays > 13) {
      throw const ValidationFailure(
        'Check the dates.',
        fieldErrors: {'date': 'A holiday can cover at most 14 days.'},
      );
    }
    if (h.date.isBefore(_today)) {
      throw const ValidationFailure(
        'Choose today or a later date.',
        fieldErrors: {
          'date':
              'Past days can’t become holidays — attendance already used them.',
        },
      );
    }
  }

  @override
  Future<List<CompanyHoliday>> holidays(String organizationId) async {
    await _delay();
    final list = <CompanyHoliday>[...?_holidays[organizationId]]
      ..sort((a, b) => a.date.compareTo(b.date));
    return List.unmodifiable(list);
  }

  @override
  Future<CompanyHoliday> saveHoliday(
    String organizationId,
    CompanyHoliday holiday,
  ) async {
    await _delay();
    final list = _holidays[organizationId] ??= [];
    final i = list.indexWhere((h) => h.id == holiday.id);
    if (i >= 0 && list[i].date.isBefore(_today)) {
      throw const ConflictFailure(
        'Past holidays can’t be edited because attendance already used them.',
      );
    }
    _check(holiday);
    final saved = holiday.copyWith(
      id: holiday.id.isEmpty ? 'hol-${_nextHoliday++}' : holiday.id,
      name: holiday.name.trim(),
    );
    if (i >= 0) {
      list[i] = saved;
    } else {
      list.add(saved);
    }
    return saved;
  }

  @override
  Future<void> deleteHoliday(String organizationId, String id) async {
    await _delay();
    final list = _holidays[organizationId] ?? [];
    final h = list.where((h) => h.id == id).firstOrNull;
    if (h == null) {
      throw const NotFoundFailure('That holiday no longer exists.');
    }
    if (h.date.isBefore(_today)) {
      throw const ConflictFailure(
        'Past holidays can’t be removed because attendance already used them.',
      );
    }
    list.remove(h);
  }

  @override
  Future<List<CompanyHoliday>> importHolidays(
    String organizationId,
    List<CompanyHoliday> rows,
  ) async {
    await _delay();
    rows.forEach(_check);
    final list = _holidays[organizationId] ??= [];
    final saved = [
      for (final r in rows) r.copyWith(id: 'hol-${_nextHoliday++}'),
    ];
    list.addAll(saved);
    return saved;
  }

  @override
  Future<List<ScheduleAssignment>> assignments(String organizationId) async {
    await _delay();
    return List.unmodifiable(_data[organizationId] ?? const []);
  }

  @override
  Future<ScheduleAssignment> addAssignment(
    String organizationId,
    ScheduleAssignment a,
  ) async {
    await _delay();
    final t = today();
    if (a.effectiveFrom.isBefore(DateTime(t.year, t.month, t.day))) {
      throw const ValidationFailure(
        'Choose today or a later date.',
        fieldErrors: {
          'effective':
              'Schedules can’t change in the past — attendance already used them.',
        },
      );
    }
    if ((a.level == ScheduleLevel.employee || a.level == ScheduleLevel.group) &&
        a.employeeIds.isEmpty) {
      throw const ValidationFailure(
        'Choose who it applies to.',
        fieldErrors: {'target': 'Choose at least one person.'},
      );
    }
    final saved = ScheduleAssignment(
      id: 'sa-${_next++}',
      level: a.level,
      name: a.name,
      effectiveFrom: a.effectiveFrom,
      branchId: a.branchId,
      employeeIds: a.employeeIds,
      shift: a.shift,
      weeklyOff: a.weeklyOff,
      createdBy: a.createdBy,
    );
    (_data[organizationId] ??= []).add(saved);
    return saved;
  }
}
