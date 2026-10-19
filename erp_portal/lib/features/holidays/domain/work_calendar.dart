import 'package:flutter/foundation.dart';

import '../../employees/domain/employee.dart';
import '../../organization/domain/branch.dart';
import 'company_holiday.dart';

/// Schedule precedence, most specific first (board S66).
enum ScheduleLevel {
  employee('Employee override'),
  group('Shift group'),
  branch('Branch'),
  organization('Organization');

  const ScheduleLevel(this.label);

  final String label;
}

/// A dated schedule change for a set of people (board S66).
@immutable
class ScheduleAssignment {
  const ScheduleAssignment({
    required this.id,
    required this.level,
    required this.name,
    required this.effectiveFrom,
    this.branchId,
    this.employeeIds = const [],
    this.shift,
    this.weeklyOff,
    this.createdBy = '',
  });

  final String id;
  final ScheduleLevel level;

  /// "Surat dyeing night crew", a branch or a person's name.
  final String name;

  /// Floating date; earlier attendance keeps the old schedule.
  final DateTime effectiveFrom;

  /// For branch-level assignments.
  final String? branchId;

  /// For employee and shift-group assignments.
  final List<String> employeeIds;

  /// Shift name offered by the branch; null keeps the person's shift.
  final String? shift;

  /// 0 = Monday … 6 = Sunday; null = the branch's closed days.
  final int? weeklyOff;
  final String createdBy;

  bool appliesTo(Employee e) => switch (level) {
    ScheduleLevel.employee || ScheduleLevel.group => employeeIds.contains(e.id),
    ScheduleLevel.branch => branchId == e.branchId,
    ScheduleLevel.organization => true,
  };
}

/// The schedule that applies to [e] on [date].
typedef ResolvedSchedule = ({
  String shift,
  int? weeklyOff,
  ScheduleAssignment? source,
});

/// Resolves schedules and holidays.
///
/// Schedules come from dated assignments: an employee assignment wins,
/// then the person's own weekly off, then shift group, branch and
/// organization assignments; otherwise the employee record.
///
/// Holidays come from the organization calendar first, then the branch's
/// own list from setup (board S21).
class WorkCalendar {
  const WorkCalendar(this.assignments, {this.holidays = const []});

  final List<ScheduleAssignment> assignments;
  final List<CompanyHoliday> holidays;

  /// The holiday [branch] observes on [d]; optional ones only when asked.
  HolidayItem? holidayFor(
    Branch? branch,
    DateTime d, {
    bool includeOptional = false,
  }) {
    for (final h in holidays) {
      if (h.covers(d) &&
          h.appliesTo(branch?.id) &&
          (includeOptional || !h.optional)) {
        return h.itemOn(d);
      }
    }
    for (final h in branch?.holidays?.items ?? const <HolidayItem>[]) {
      if (h.observed &&
          h.date.year == d.year &&
          h.date.month == d.month &&
          h.date.day == d.day &&
          (includeOptional || !h.optional)) {
        return h;
      }
    }
    return null;
  }

  /// Holidays of [branch] from [from] to [to], one per day, in date order.
  List<HolidayItem> holidaysBetween(
    Branch? branch,
    DateTime from,
    DateTime to, {
    bool includeOptional = false,
  }) => [
    for (
      var d = DateTime(from.year, from.month, from.day);
      !d.isAfter(to);
      d = DateTime(d.year, d.month, d.day + 1)
    )
      ?holidayFor(branch, d, includeOptional: includeOptional),
  ];

  ResolvedSchedule scheduleFor(Employee e, DateTime date) {
    ScheduleAssignment? latest(ScheduleLevel level) {
      final list = [
        for (final a in assignments)
          if (a.level == level &&
              a.appliesTo(e) &&
              !a.effectiveFrom.isAfter(date))
            a,
      ]..sort((a, b) => a.effectiveFrom.compareTo(b.effectiveFrom));
      return list.lastOrNull;
    }

    final own = latest(ScheduleLevel.employee);
    if (own != null) {
      return (
        shift: own.shift ?? e.shift,
        weeklyOff: own.weeklyOff,
        source: own,
      );
    }
    if (e.weeklyOff != null) {
      return (shift: e.shift, weeklyOff: e.weeklyOff, source: null);
    }
    for (final level in const [
      ScheduleLevel.group,
      ScheduleLevel.branch,
      ScheduleLevel.organization,
    ]) {
      final a = latest(level);
      if (a != null) {
        return (shift: a.shift ?? e.shift, weeklyOff: a.weeklyOff, source: a);
      }
    }
    return (shift: e.shift, weeklyOff: null, source: null);
  }
}
