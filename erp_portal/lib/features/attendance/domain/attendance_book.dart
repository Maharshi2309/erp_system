import 'package:flutter/foundation.dart';

import '../../../core/utils/zoned_time.dart';
import '../../employees/domain/employee.dart';
import '../../employees/domain/employee_rules.dart';
import '../../holidays/domain/work_calendar.dart';
import '../../organization/domain/branch.dart';
import 'attendance.dart';

/// Unpaid break included in a full shift (board S86 "60m break").
const allowedBreakMinutes = 60;

/// Days after which a missing punch is overdue and blocks payroll (S54).
const overdueAfterDays = 3;

/// Days an employee has to request a correction (S87).
const requestWindowDays = 3;

enum DayStatus {
  present('Present'),
  late('Late'),
  leftEarly('Left early'),
  halfDay('Half day'),
  shortShift('Short shift'),
  missingPunch('Missing punch'),
  absent('Absent'),
  onLeave('On leave'),
  holiday('Holiday'),
  weeklyOff('Weekly off'),
  working('Working'),
  notYet('Not punched yet'),
  upcoming('Upcoming'),
  none('—');

  const DayStatus(this.label);

  final String label;

  /// Shown in "Exceptions only" (board S53).
  bool get isException => const {
    late,
    leftEarly,
    halfDay,
    shortShift,
    missingPunch,
    absent,
  }.contains(this);

  /// Came to work (late or early-leaving still counts as present).
  bool get attended => const {
    present,
    late,
    leftEarly,
    halfDay,
    shortShift,
    working,
    missingPunch,
  }.contains(this);

  /// Monthly grid code (board S56).
  String get code => switch (this) {
    present || shortShift || leftEarly => 'P',
    late => 'L',
    halfDay => '½',
    absent => 'A',
    onLeave => 'LV',
    holiday => 'H',
    weeklyOff => 'W',
    missingPunch => '!',
    working => 'P',
    _ => '',
  };
}

/// One work session: punch in → punch out, with breaks inside.
@immutable
class WorkSession {
  const WorkSession({this.inPunch, this.outPunch, this.breaks = const []});

  final Punch? inPunch;
  final Punch? outPunch;

  /// (start, end) instants; end null while a break is open.
  final List<(DateTime, DateTime?)> breaks;

  bool get isOpen => inPunch != null && outPunch == null;
  bool get isOrphanOut => inPunch == null && outPunch != null;

  int get breakMinutes => breaks
      .where((b) => b.$2 != null)
      .fold(0, (s, b) => s + b.$2!.difference(b.$1).inMinutes);

  /// Worked minutes; 0 until both ends are known.
  int get minutes => inPunch == null || outPunch == null
      ? 0
      : outPunch!.at.difference(inPunch!.at).inMinutes - breakMinutes;
}

/// A shift on a given day, as instants.
typedef ShiftWindow = ({
  DateTime start,
  DateTime end,
  int expected,
  String label,
});

/// A line in the day timeline (boards S53, S88).
typedef TimelineEntry = ({
  DateTime at,
  PunchKind kind,
  String source,
  bool corrected,
  int? lateMinutes,
});

/// One employee's attendance for one day, computed from punches.
@immutable
class DayRecord {
  const DayRecord({
    required this.employee,
    required this.date,
    required this.status,
    required this.sessions,
    required this.shift,
    required this.workedMinutes,
    required this.breakMinutes,
    required this.lateMinutes,
    required this.earlyMinutes,
    required this.scheduled,
    required this.zone,
    this.holidayName,
    this.corrected = false,
    this.pendingCorrection,
    this.correctedBy,
    this.correctionReason,
  });

  final Employee employee;

  /// Floating date of the work day.
  final DateTime date;
  final DayStatus status;
  final List<WorkSession> sessions;
  final ShiftWindow? shift;
  final int workedMinutes;
  final int breakMinutes;
  final int lateMinutes;
  final int earlyMinutes;
  final bool scheduled;

  /// Branch time zone used for display.
  final String zone;
  final String? holidayName;
  final bool corrected;
  final Correction? pendingCorrection;
  final String? correctedBy;
  final String? correctionReason;

  int get expectedMinutes => scheduled ? (shift?.expected ?? 0) : 0;

  DateTime? get firstIn =>
      sessions.map((s) => s.inPunch?.at).whereType<DateTime>().firstOrNull;
  DateTime? get lastOut =>
      sessions.map((s) => s.outPunch?.at).whereType<DateTime>().lastOrNull;

  bool get hasOpenSession => sessions.any((s) => s.isOpen);

  /// "no punch-out" / "no punch-in" for missing-punch rows.
  String get missingWhat {
    if (sessions.any((s) => s.isOrphanOut)) return 'no punch-in';
    final night = (shift?.label ?? '').startsWith('Night');
    return night ? 'no punch-out (night shift)' : 'no punch-out';
  }

  List<TimelineEntry> get timeline => [
    for (final s in sessions) ...[
      if (s.inPunch case final p?)
        (
          at: p.at,
          kind: PunchKind.punchIn,
          source: p.source.label,
          corrected: p.correctionId != null,
          lateMinutes: identical(s, sessions.first) && lateMinutes > 0
              ? lateMinutes
              : null,
        ),
      for (final b in s.breaks) ...[
        (
          at: b.$1,
          kind: PunchKind.breakStart,
          source: '',
          corrected: false,
          lateMinutes: null,
        ),
        if (b.$2 != null)
          (
            at: b.$2!,
            kind: PunchKind.breakEnd,
            source: '',
            corrected: false,
            lateMinutes: null,
          ),
      ],
      if (s.outPunch case final p?)
        (
          at: p.at,
          kind: PunchKind.punchOut,
          source: p.source.label,
          corrected: p.correctionId != null,
          lateMinutes: null,
        ),
    ],
  ];
}

/// Attendance computed from records. Pure: give it data and "now", ask it
/// questions. Results are cached per employee.
class AttendanceBook {
  AttendanceBook({
    required this.data,
    required this.employees,
    required this.branches,
    required this.orgZone,
    required this.now,
    this.calendar = const WorkCalendar([]),
    this.onLeave,
  }) {
    for (final b in branches) {
      _branches[b.id] = b;
    }
    for (final c in data.corrections) {
      if (c.status == CorrectionStatus.approved) {
        for (final ch in c.changes) {
          if (ch.replaces != null) _replaced.add(ch.replaces!);
        }
      }
    }
    for (final p in data.punches) {
      (_punchesOf[p.employeeId] ??= []).add(p);
    }
    for (final c in data.corrections) {
      (_correctionsOf[c.employeeId] ??= []).add(c);
    }
  }

  final AttendanceData data;
  final List<Employee> employees;
  final List<Branch> branches;
  final String orgZone;

  /// UTC instant.
  final DateTime now;

  /// Dated schedule assignments (Phase 6).
  final WorkCalendar calendar;

  /// Approved leave covering a day (Phase 6), if known.
  final bool Function(Employee e, DateTime date)? onLeave;

  final _branches = <String, Branch>{};
  final _replaced = <String>{};
  final _punchesOf = <String, List<Punch>>{};
  final _correctionsOf = <String, List<Correction>>{};
  final _sessionsByDay = <String, Map<DateTime, List<WorkSession>>>{};
  final _dayCache = <(String, DateTime), DayRecord>{};

  Branch? branchOf(Employee e) => _branches[e.branchId];

  String zoneOf(Employee e) => _branches[e.branchId]?.timeZone ?? orgZone;

  /// Today's floating date for [e]'s branch.
  DateTime todayFor(Employee e) => dateOnly(wallTime(now, zoneOf(e)));

  /// Today in the organization's zone.
  DateTime get today => dateOnly(wallTime(now, orgZone));

  ShiftWindow? shiftOn(Employee e, DateTime date) {
    final branch = branchOf(e);
    if (branch == null) return null;
    final name = calendar.scheduleFor(e, date).shift;
    final shift =
        shiftsFor(branch).where((s) => s.name == name).firstOrNull ??
        shiftsFor(branch).first;
    final zone = zoneOf(e);
    final start = instantOf(date.add(Duration(minutes: shift.start)), zone);
    final overnight = shift.end <= shift.start;
    final endDay = overnight ? date.add(const Duration(days: 1)) : date;
    final end = instantOf(endDay.add(Duration(minutes: shift.end)), zone);
    final length = end.difference(start).inMinutes;
    return (
      start: start,
      end: end,
      expected: length > 6 * 60 ? length - allowedBreakMinutes : length,
      label: shiftLabel(shift),
    );
  }

  String? holidayOn(Employee e, DateTime date) =>
      calendar.holidayFor(branchOf(e), date)?.name;

  /// Is [e] expected to work on [date]?
  bool isScheduled(Employee e, DateTime date) {
    final branch = branchOf(e);
    if (branch == null || !e.status.isEmployed) return false;
    if (date.isBefore(dateOnly(e.joiningDate))) return false;
    if (holidayOn(e, date) != null) return false;
    final weekday = date.weekday - 1;
    final off = calendar.scheduleFor(e, date).weeklyOff;
    if (off != null) return off != weekday;
    return branch.hours[weekday].open;
  }

  /// Punches that count: originals not replaced, plus approved corrections.
  List<Punch> effectivePunches(String employeeId) {
    final list = [
      for (final p in _punchesOf[employeeId] ?? const <Punch>[])
        if (!_replaced.contains(p.id)) p,
      for (final c in _correctionsOf[employeeId] ?? const <Correction>[])
        if (c.status == CorrectionStatus.approved)
          for (var i = 0; i < c.changes.length; i++)
            Punch(
              id: '${c.id}-$i',
              employeeId: employeeId,
              at: c.changes[i].at,
              kind: c.changes[i].kind,
              source: PunchSource.correction,
              correctionId: c.id,
              replaces: c.changes[i].replaces,
            ),
    ]..sort((a, b) => a.at.compareTo(b.at));
    return list;
  }

  /// Sessions grouped by work day. A session belongs to the day of its
  /// punch-in, so overnight shifts stay on their start date.
  Map<DateTime, List<WorkSession>> _sessions(Employee e) =>
      _sessionsByDay.putIfAbsent(e.id, () {
        final zone = zoneOf(e);
        final night = (shiftOn(e, today)?.label ?? '').startsWith('Night');
        final byDay = <DateTime, List<WorkSession>>{};
        Punch? openIn;
        var breaks = <(DateTime, DateTime?)>[];

        // On a night shift, morning punches belong to the shift that
        // started the evening before.
        DateTime workDay(DateTime instant) {
          final local = wallTime(instant, zone);
          final day = dateOnly(local);
          return night && local.hour < 12
              ? DateTime(day.year, day.month, day.day - 1)
              : day;
        }

        void add(WorkSession s, DateTime dayOf) {
          (byDay[workDay(dayOf)] ??= []).add(s);
        }

        void closeOpen({Punch? out}) {
          add(
            WorkSession(inPunch: openIn, outPunch: out, breaks: breaks),
            openIn!.at,
          );
          openIn = null;
          breaks = [];
        }

        for (final p in effectivePunches(e.id)) {
          switch (p.kind) {
            case PunchKind.punchIn:
              if (openIn != null) closeOpen();
              openIn = p;
            case PunchKind.punchOut:
              if (openIn != null && p.at.difference(openIn!.at).inHours < 20) {
                closeOpen(out: p);
              } else {
                if (openIn != null) closeOpen();
                add(WorkSession(outPunch: p), p.at);
              }
            case PunchKind.breakStart:
              if (openIn != null) breaks.add((p.at, null));
            case PunchKind.breakEnd:
              if (openIn != null &&
                  breaks.isNotEmpty &&
                  breaks.last.$2 == null) {
                breaks[breaks.length - 1] = (breaks.last.$1, p.at);
              }
          }
        }
        if (openIn != null) closeOpen();
        return byDay;
      });

  DayRecord day(Employee e, DateTime date) => _dayCache.putIfAbsent((
    e.id,
    dateOnly(date),
  ), () => _compute(e, dateOnly(date)));

  DayRecord _compute(Employee e, DateTime date) {
    final branch = branchOf(e);
    final rules = branch?.attendance ?? const AttendanceRules();
    final zone = zoneOf(e);
    final sessions = _sessions(e)[date] ?? const <WorkSession>[];
    final shift = shiftOn(e, date);
    final scheduled = isScheduled(e, date);
    final holiday = holidayOn(e, date);
    final todayHere = todayFor(e);
    final corrections = (_correctionsOf[e.id] ?? const <Correction>[])
        .where((c) => dateOnly(c.workDate) == date)
        .toList();
    final pending = corrections
        .where((c) => c.status == CorrectionStatus.pending)
        .lastOrNull;
    final applied = corrections
        .where((c) => c.status == CorrectionStatus.approved)
        .lastOrNull;

    final worked = sessions.fold(0, (s, x) => s + x.minutes);
    var breakMinutes = sessions.fold(0, (s, x) => s + x.breakMinutes);
    final closed = sessions
        .where((s) => s.inPunch != null && s.outPunch != null)
        .toList();
    for (var i = 1; i < closed.length; i++) {
      breakMinutes += closed[i].inPunch!.at
          .difference(closed[i - 1].outPunch!.at)
          .inMinutes;
    }

    var late = 0;
    var early = 0;
    final firstIn = sessions
        .map((s) => s.inPunch?.at)
        .whereType<DateTime>()
        .firstOrNull;
    final lastOut = sessions.lastOrNull?.outPunch?.at;
    if (shift != null && scheduled) {
      if (firstIn != null &&
          firstIn.isAfter(
            shift.start.add(Duration(minutes: rules.graceMinutes)),
          )) {
        late = firstIn.difference(shift.start).inMinutes;
      }
      if (lastOut != null &&
          lastOut.isBefore(
            shift.end.subtract(Duration(minutes: rules.earlyLeaveMinutes)),
          )) {
        early = shift.end.difference(lastOut).inMinutes;
      }
    }

    DayStatus status;
    if (sessions.isEmpty) {
      if (!e.status.isEmployed || date.isBefore(dateOnly(e.joiningDate))) {
        status = DayStatus.none;
      } else if (holiday != null) {
        status = DayStatus.holiday;
      } else if (!scheduled) {
        status = DayStatus.weeklyOff;
      } else if (onLeave?.call(e, date) ?? false) {
        status = DayStatus.onLeave;
      } else if (date.isAfter(todayHere)) {
        status = DayStatus.upcoming;
      } else if (date == todayHere &&
          (shift == null ||
              now.isBefore(
                shift.start.add(Duration(minutes: rules.halfDayLateMinutes)),
              ))) {
        status = DayStatus.notYet;
      } else {
        status = DayStatus.absent;
      }
    } else if (sessions.any((s) => s.isOrphanOut)) {
      status = DayStatus.missingPunch;
    } else if (sessions.any((s) => s.isOpen)) {
      final stillOn =
          sessions.last.isOpen &&
          shift != null &&
          now.isBefore(shift.end.add(const Duration(hours: 6))) &&
          !now.isBefore(sessions.last.inPunch!.at);
      status = stillOn && sessions.where((s) => s.isOpen).length == 1
          ? DayStatus.working
          : DayStatus.missingPunch;
    } else if (!scheduled) {
      status = DayStatus.present;
    } else if (late > rules.halfDayLateMinutes ||
        (shift != null && worked <= shift.expected / 2)) {
      status = DayStatus.halfDay;
    } else if (early > 0) {
      status = DayStatus.leftEarly;
    } else if (shift != null && worked < shift.expected - 60) {
      status = DayStatus.shortShift;
    } else if (late > 0) {
      status = DayStatus.late;
    } else {
      status = DayStatus.present;
    }

    return DayRecord(
      employee: e,
      date: date,
      status: status,
      sessions: sessions,
      shift: shift,
      workedMinutes: worked,
      breakMinutes: breakMinutes,
      lateMinutes: late,
      earlyMinutes: early,
      scheduled: scheduled,
      zone: zone,
      holidayName: holiday,
      corrected: applied != null,
      pendingCorrection: pending,
      correctedBy: applied?.by,
      correctionReason: applied?.reason,
    );
  }

  /// Records for [people] on [date].
  List<DayRecord> daysOn(DateTime date, Iterable<Employee> people) => [
    for (final e in people)
      if (e.status != EmploymentStatus.terminated) day(e, date),
  ];

  /// Days of [e] from [from] to [to] (inclusive), newest first.
  List<DayRecord> range(Employee e, DateTime from, DateTime to) => [
    for (
      var d = dateOnly(to);
      !d.isBefore(dateOnly(from));
      d = DateTime(d.year, d.month, d.day - 1)
    )
      day(e, d),
  ];

  /// Open requests from employees.
  CorrectionRequest? openRequest(Employee e, DateTime date) => data.requests
      .where(
        (r) =>
            r.employeeId == e.id &&
            dateOnly(r.workDate) == date &&
            r.status == RequestStatus.open,
      )
      .lastOrNull;

  PunchReminder? lastReminder(Employee e, DateTime date) => data.reminders
      .where((r) => r.employeeId == e.id && dateOnly(r.workDate) == date)
      .lastOrNull;

  /// Days with a missing punch in the last [days] days, oldest first
  /// (board S54).
  List<DayRecord> missingPunches(Iterable<Employee> people, {int days = 30}) {
    final list = <DayRecord>[];
    for (final e in people) {
      if (!e.status.isEmployed) continue;
      final today = todayFor(e);
      for (var i = 0; i <= days; i++) {
        final d = DateTime(today.year, today.month, today.day - i);
        final r = day(e, d);
        if (r.status == DayStatus.missingPunch) list.add(r);
      }
    }
    list.sort((a, b) => a.date.compareTo(b.date));
    return list;
  }

  bool isOverdue(DayRecord r) =>
      todayFor(r.employee).difference(r.date).inDays > overdueAfterDays;

  /// All corrections for [people], newest first.
  List<Correction> correctionsFor(Iterable<Employee> people) {
    final ids = {for (final e in people) e.id};
    return data.corrections.where((c) => ids.contains(c.employeeId)).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  /// Summary counts for [records] (boards S52, S53).
  static AttendanceCounts count(Iterable<DayRecord> records) {
    var scheduled = 0,
        present = 0,
        late = 0,
        absent = 0,
        missing = 0,
        working = 0,
        lateSum = 0,
        leave = 0;
    var worked = 0, expected = 0;
    for (final r in records) {
      if (r.scheduled) scheduled++;
      if (r.status.attended) present++;
      if (r.lateMinutes > 0) {
        late++;
        lateSum += r.lateMinutes;
      }
      if (r.status == DayStatus.absent) absent++;
      if (r.status == DayStatus.onLeave) leave++;
      if (r.status == DayStatus.missingPunch) missing++;
      if (r.status == DayStatus.working) working++;
      worked += r.workedMinutes;
      expected += r.expectedMinutes;
    }
    return AttendanceCounts(
      scheduled: scheduled,
      present: present,
      late: late,
      absent: absent,
      missing: missing,
      working: working,
      onLeave: leave,
      averageLate: late == 0 ? 0 : (lateSum / late).round(),
      workedMinutes: worked,
      expectedMinutes: expected,
    );
  }
}

@immutable
class AttendanceCounts {
  const AttendanceCounts({
    required this.scheduled,
    required this.present,
    required this.late,
    required this.absent,
    required this.missing,
    required this.working,
    required this.onLeave,
    required this.averageLate,
    required this.workedMinutes,
    required this.expectedMinutes,
  });

  final int scheduled;
  final int present;
  final int late;
  final int absent;
  final int missing;
  final int working;

  /// Scheduled but on approved leave (Phase 6).
  final int onLeave;
  final int averageLate;
  final int workedMinutes;
  final int expectedMinutes;

  int get onTime => present - late;

  /// Present as a share of scheduled, 0–100.
  int get rate => scheduled == 0 ? 0 : (present / scheduled * 100).round();
}

/// "8h 04m".
String formatMinutes(int minutes) {
  final m = minutes.abs();
  return '${minutes < 0 ? '−' : ''}${m ~/ 60}h ${(m % 60).toString().padLeft(2, '0')}m';
}

/// "+0h 18m" / "−4h 32m" against the expected time.
String formatDelta(int worked, int expected) {
  final d = worked - expected;
  if (expected == 0) return '—';
  return d >= 0 ? '+${formatMinutes(d)}' : formatMinutes(d);
}

/// "09:41" in [zone].
String clockTime(DateTime instant, String zone) {
  final t = wallTime(instant, zone);
  return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}
