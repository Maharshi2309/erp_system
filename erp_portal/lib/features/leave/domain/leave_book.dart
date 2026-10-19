import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../../../core/permissions/system_roles.dart';
import '../../employees/domain/employee.dart';
import '../../holidays/domain/work_calendar.dart';
import '../../organization/domain/branch.dart';
import 'leave.dart';

/// One day inside a request (board S89 "You'll use N days").
typedef LeaveDay = ({DateTime date, double counted, String note});

/// A type's balance for one year (boards S60, S90, S92).
@immutable
class LeaveBalance {
  const LeaveBalance({
    required this.type,
    required this.granted,
    required this.carried,
    required this.adjusted,
    required this.used,
    required this.pending,
    required this.available,
    required this.offered,
  });

  final LeaveType type;

  /// Granted upfront, or accrued so far for monthly types.
  final double granted;
  final double carried;
  final double adjusted;

  /// Approved requests (including future approved leave).
  final double used;

  /// Held for open requests.
  final double pending;
  final double available;

  /// False when the employee's branch doesn't offer the type.
  final bool offered;

  double get total => granted + carried + adjusted;
}

/// A ledger line (board S92), newest first with a running balance.
typedef LedgerLine = ({
  DateTime date,
  String what,
  String note,
  double amount,
  double balance,
  bool held,
});

/// Leave computed from records. Pure: give it data and "today".
class LeaveBook {
  LeaveBook({
    required this.data,
    required this.employees,
    required this.branches,
    required this.today,
    this.calendar = const WorkCalendar([]),
  }) {
    for (final b in branches) {
      _branches[b.id] = b;
    }
    for (final e in employees) {
      _people[e.id] = e;
    }
  }

  final LeaveData data;
  final List<Employee> employees;
  final List<Branch> branches;

  /// Floating date in the organization's zone.
  final DateTime today;
  final WorkCalendar calendar;
  final _branches = <String, Branch>{};
  final _people = <String, Employee>{};

  Employee? person(String id) => _people[id];
  Branch? branchOf(Employee e) => _branches[e.branchId];
  LeavePolicy get policy => data.policy;

  /// Holidays observed at [e]'s branch on [d] (optional ones excluded).
  HolidayItem? holidayOn(
    Employee e,
    DateTime d, {
    bool includeOptional = false,
  }) => calendar.holidayFor(branchOf(e), d, includeOptional: includeOptional);

  bool isWeeklyOff(Employee e, DateTime d) {
    final off = calendar.scheduleFor(e, d).weeklyOff;
    if (off != null) return off == d.weekday - 1;
    final b = branchOf(e);
    return b != null && !b.hours[d.weekday - 1].open;
  }

  // ---------- Counting ----------

  /// Each day of a request and whether it counts (boards S89, S58 rules).
  List<LeaveDay> countDays(
    Employee e,
    LeaveType type,
    DateTime from,
    DateTime to,
    HalfDay half,
  ) {
    final days = <LeaveDay>[];
    if (to.isBefore(from)) return days;
    for (
      var d = from;
      !d.isAfter(to);
      d = DateTime(d.year, d.month, d.day + 1)
    ) {
      if (type.optionalHolidaysOnly) {
        final h = holidayOn(e, d, includeOptional: true);
        days.add(
          h != null && h.optional
              ? (date: d, counted: 1.0, note: '${h.name} — optional holiday')
              : (date: d, counted: 0.0, note: 'Not an optional holiday'),
        );
        continue;
      }
      final holiday = holidayOn(e, d);
      if (holiday != null && !type.countHolidays) {
        days.add((
          date: d,
          counted: 0,
          note: '${holiday.name} — holiday, not counted',
        ));
      } else if (isWeeklyOff(e, d) && !type.countWeeklyOffs) {
        days.add((date: d, counted: 0, note: 'Weekly off, not counted'));
      } else {
        days.add((
          date: d,
          counted: half == HalfDay.full ? 1 : 0.5,
          note: 'Counted',
        ));
      }
    }
    return days;
  }

  double daysOf(LeaveRequest r) {
    final e = person(r.employeeId);
    final type = data.type(r.typeKey);
    if (e == null || type == null) return 0;
    return countDays(
      e,
      type,
      r.from,
      r.to,
      r.half,
    ).fold(0.0, (s, d) => s + d.counted);
  }

  // ---------- Entitlement and balance ----------

  /// The branch's setting for a type (Phase 3 leave setup), if any.
  LeaveTypeSetup? _setupOf(Employee e, LeaveType type) =>
      branchOf(e)?.leave?.types.where((t) => t.key == type.key).firstOrNull;

  /// Does [e]'s branch offer [type]? Types the branch setup doesn't list
  /// follow the organization type (e.g. optional holidays).
  bool offers(Employee e, LeaveType type) {
    if (!type.eligible(e)) return false;
    final setup = _setupOf(e, type);
    return setup == null || setup.enabled;
  }

  /// Days a year for [e]: the branch override, else the type default.
  double yearlyFor(Employee e, LeaveType type) {
    final setup = _setupOf(e, type);
    return setup != null && setup.tracksBalance
        ? setup.daysPerYear.toDouble()
        : type.yearly;
  }

  /// Granted (upfront) or accrued (monthly) for [year] as of today.
  double entitlement(Employee e, LeaveType type, int year) {
    if (!type.tracksBalance || !offers(e, type)) return 0;
    final eligibleFrom = DateTime(
      e.joiningDate.year,
      e.joiningDate.month + type.startsAfterMonths,
      e.joiningDate.day,
    );
    final yearEnd = DateTime(year, 12, 31);
    if (eligibleFrom.isAfter(yearEnd)) return 0;
    final yearly = yearlyFor(e, type);
    final start = eligibleFrom.isAfter(DateTime(year))
        ? eligibleFrom
        : DateTime(year);
    if (type.method == AccrualMethod.upfront) {
      if (start == DateTime(year)) return yearly;
      final months = 12 - start.month + 1;
      return _half(yearly * months / 12);
    }
    // Monthly: credited on the 1st of each month from the start month.
    final last = year < today.year ? 12 : (year > today.year ? 0 : today.month);
    final firstMonth = start.year < year
        ? 1
        : start.month + (start.day > 1 ? 1 : 0);
    final months = (last - firstMonth + 1).clamp(0, 12);
    return double.parse((yearly / 12 * months).toStringAsFixed(2));
  }

  static double _half(double v) => (v * 2).round() / 2;

  List<LeaveRequest> requestsOf(Employee e) => [
    for (final r in data.requests)
      if (r.employeeId == e.id) r,
  ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  LeaveBalance balance(
    Employee e,
    String typeKey,
    int year, {
    String? exceptRequest,
  }) {
    final type = data.type(typeKey)!;
    final adj = data.adjustments.where(
      (a) =>
          a.employeeId == e.id &&
          a.typeKey == typeKey &&
          a.effective.year == year,
    );
    final carried = adj.where((a) => a.carry).fold(0.0, (s, a) => s + a.days);
    final adjusted = adj.where((a) => !a.carry).fold(0.0, (s, a) => s + a.days);
    var used = 0.0, pending = 0.0;
    for (final r in data.requests) {
      if (r.employeeId != e.id ||
          r.typeKey != typeKey ||
          r.from.year != year ||
          r.id == exceptRequest) {
        continue;
      }
      if (r.status == LeaveStatus.approved) used += daysOf(r);
      if (r.status.isOpen) pending += daysOf(r);
    }
    final granted = entitlement(e, type, year);
    return LeaveBalance(
      type: type,
      granted: granted,
      carried: carried,
      adjusted: adjusted,
      used: used,
      pending: pending,
      available: granted + carried + adjusted - used - pending,
      offered: offers(e, type),
    );
  }

  /// Balances for every balance-tracked type the employee is offered.
  List<LeaveBalance> balances(Employee e, int year) => [
    for (final t in data.types)
      if (t.tracksBalance && offers(e, t)) balance(e, t.key, year),
  ];

  /// Transactions newest first with the running balance (board S92).
  List<LedgerLine> ledger(Employee e, String typeKey, int year) {
    final type = data.type(typeKey)!;
    final lines =
        <
          ({DateTime date, String what, String note, double amount, bool held})
        >[];
    final granted = entitlement(e, type, year);
    if (granted > 0) {
      lines.add((
        date: DateTime(year),
        what: type.method == AccrualMethod.monthly
            ? 'Accrued · Jan–${DateFormat('MMM').format(DateTime(year, year == today.year ? today.month : 12))} $year'
            : 'Granted · 1 Jan $year',
        note: type.method == AccrualMethod.monthly
            ? '${formatDays(yearlyFor(e, type) / 12)} days on the 1st of each month'
            : 'Annual ${type.name.toLowerCase()} allowance',
        amount: granted,
        held: false,
      ));
    }
    for (final a in data.adjustments.where(
      (a) =>
          a.employeeId == e.id &&
          a.typeKey == typeKey &&
          a.effective.year == year,
    )) {
      lines.add((
        date: a.effective,
        what: a.carry
            ? 'Carried forward · ${a.effective.year - 1}'
            : 'Adjusted by ${a.by}',
        note: a.reason,
        amount: a.days,
        held: false,
      ));
    }
    for (final r in data.requests.where(
      (r) =>
          r.employeeId == e.id && r.typeKey == typeKey && r.from.year == year,
    )) {
      final days = daysOf(r);
      final when = _range(r.from, r.to);
      switch (r.status) {
        case LeaveStatus.approved:
          final approver = r.steps
              .where((s) => s.approved == true)
              .lastOrNull
              ?.decidedBy;
          lines.add((
            date: r.from,
            what: 'Used · $when',
            note: approver == null ? 'Approved' : 'Approved by $approver',
            amount: -days,
            held: false,
          ));
        case LeaveStatus.pending || LeaveStatus.changesRequested:
          lines.add((
            date: r.createdAt,
            what: 'Pending · $when',
            note: 'Held until it is decided',
            amount: -days,
            held: true,
          ));
        case LeaveStatus.rejected:
          lines.add((
            date: r.createdAt,
            what: 'Rejected · $when',
            note:
                'Nothing deducted${r.decisionNote.isEmpty ? '' : ' — “${r.decisionNote}”'}',
            amount: 0,
            held: false,
          ));
        case LeaveStatus.withdrawn || LeaveStatus.cancelled:
          lines.add((
            date: r.createdAt,
            what: '${r.status.label} · $when',
            note: 'Days returned',
            amount: 0,
            held: false,
          ));
      }
    }
    lines.sort((a, b) => a.date.compareTo(b.date));
    var running = 0.0;
    final out = <LedgerLine>[];
    for (final l in lines) {
      running += l.amount;
      out.add((
        date: l.date,
        what: l.what,
        note: l.note,
        amount: l.amount,
        balance: running,
        held: l.held,
      ));
    }
    return out.reversed.toList();
  }

  // ---------- Validation ----------

  /// Errors keyed by field ("type", "dates", "half", "balance", "overlap");
  /// empty when the request can be sent (board S89).
  Map<String, String> validate({
    required Employee e,
    required String? typeKey,
    required DateTime? from,
    required DateTime? to,
    required HalfDay half,
    String? amending,
  }) {
    final errors = <String, String>{};
    final type = typeKey == null ? null : data.type(typeKey);
    if (type == null) {
      errors['type'] = 'Choose a leave type.';
      return errors;
    }
    if (!type.eligible(e)) {
      errors['type'] = 'You’re not eligible for ${type.name.toLowerCase()}.';
      return errors;
    }
    if (!offers(e, type)) {
      errors['type'] = '${type.name} isn’t offered at your branch.';
      return errors;
    }
    if (from == null || to == null) {
      errors['dates'] = 'Choose the start and end dates.';
      return errors;
    }
    if (to.isBefore(from)) {
      errors['dates'] = 'The end date can’t be before the start date.';
      return errors;
    }
    if (half != HalfDay.full && from != to) {
      errors['half'] =
          'Half days are for a single day. Choose full days or one date.';
    } else if (half != HalfDay.full && !type.allowHalfDays) {
      errors['half'] = '${type.name} can’t be taken as a half day.';
    }
    final days = countDays(e, type, from, to, half);
    final total = days.fold(0.0, (s, d) => s + d.counted);
    if (total == 0) {
      errors['dates'] = type.optionalHolidaysOnly
          ? 'Choose an optional holiday.'
          : 'Those dates are holidays or weekly offs — nothing to request.';
      return errors;
    }
    if (type.optionalHolidaysOnly && days.any((d) => d.counted == 0)) {
      errors['dates'] =
          'Optional holiday leave can only be taken on optional holidays.';
    }
    final longest = type.maxDays < policy.longestRequestDays
        ? type.maxDays
        : policy.longestRequestDays.toDouble();
    if (total > longest) {
      errors['dates'] =
          '${type.name} allows at most ${formatDays(longest)} days in one request.';
    }
    if (from.isBefore(today)) {
      final allowed = type.backdateDays == 0
          ? 0
          : (type.backdateDays < policy.backdatedSickDays
                ? type.backdateDays
                : policy.backdatedSickDays);
      if (allowed == 0) {
        errors['dates'] = '${type.name} can’t start in the past.';
      } else if (today.difference(from).inDays > allowed) {
        errors['dates'] =
            '${type.name} can be backdated by up to $allowed days.';
      }
    }
    if (type.noticeDays > 0) {
      final earliest = DateTime(
        today.year,
        today.month,
        today.day + type.noticeDays,
      );
      if (from.isBefore(earliest)) {
        errors['dates'] =
            '${type.name} needs ${type.noticeDays} days’ notice — start on ${DateFormat('EEE d MMM').format(earliest)} or later.';
      }
    }
    for (final b in policy.blackouts) {
      final hit = days
          .where((d) => d.counted > 0 && b.covers(e, d.date, type.key))
          .firstOrNull;
      if (hit != null) {
        errors['dates'] =
            '${type.name} can’t be taken during ${b.name} (${_range(b.from, b.to)}).';
        break;
      }
    }
    for (final r in requestsOf(e)) {
      if (r.id == amending || !r.status.holdsDays) continue;
      if (!r.to.isBefore(from) && !r.from.isAfter(to)) {
        // The first day after it that would count (skips holidays/offs).
        var next = DateTime(r.to.year, r.to.month, r.to.day + 1);
        for (var i = 0; i < 14; i++) {
          if (countDays(e, type, next, next, HalfDay.full).first.counted > 0) {
            break;
          }
          next = DateTime(next.year, next.month, next.day + 1);
        }
        errors['overlap'] =
            'This overlaps your ${r.status == LeaveStatus.approved ? 'approved' : 'pending'} request for '
            '${_range(r.from, r.to)}. ${r.status.isOpen ? 'Withdraw it first' : 'Cancel it first'}, or change the start date to '
            '${DateFormat('EEE d MMM').format(next)}.';
        break;
      }
    }
    if (type.optionalHolidaysOnly) {
      final taken = requestsOf(e)
          .where(
            (r) =>
                r.id != amending &&
                r.typeKey == type.key &&
                r.status.holdsDays &&
                r.from.year == from.year,
          )
          .length;
      if (taken >= policy.optionalHolidaysPerYear) {
        errors['balance'] =
            'You can take ${policy.optionalHolidaysPerYear} optional holiday a year.';
      }
    }
    if (type.tracksBalance) {
      final bal = balance(e, type.key, from.year, exceptRequest: amending);
      final floor = policy.allowNegative ? -policy.negativeLimit : 0.0;
      if (bal.available - total < floor) {
        errors['balance'] =
            'Not enough ${type.name.toLowerCase()}: ${formatDays(bal.available)} available, ${formatDays(total)} requested.';
      }
    }
    return errors;
  }

  // ---------- Routing and decisions ----------

  /// Approval steps for a request (board S59). Nobody approves their own
  /// request: such a step goes to HR instead.
  List<ApprovalStep> route(Employee e, LeaveType type, double days) {
    final manager = e.managerId == null ? null : person(e.managerId!);
    final branch = branchOf(e);
    final steps = <ApprovalStep>[];
    if (branch?.leave?.approval == LeaveApproval.owner) {
      steps.add(
        const ApprovalStep(
          kind: ApproverKind.hr,
          note: 'Branch leave is approved centrally',
        ),
      );
    } else if (manager != null && manager.status.isEmployed) {
      steps.add(
        ApprovalStep(kind: ApproverKind.manager, approverId: manager.id),
      );
    } else {
      steps.add(
        const ApprovalStep(kind: ApproverKind.hr, note: 'No reporting manager'),
      );
    }

    final routes = [
      for (final r in policy.routes)
        if ((r.branchId == null || r.branchId == e.branchId) &&
            (r.typeKey == null || r.typeKey == type.key))
          r,
    ]..sort((a, b) => b.specificity.compareTo(a.specificity));
    final rule = routes.firstOrNull;
    final wantsHr =
        branch?.leave?.approval == LeaveApproval.managerThenHr ||
        (rule != null &&
            (rule.second == SecondStep.hrAlways ||
                (rule.second == SecondStep.hrIfDays && days >= rule.minDays)));
    if (rule != null &&
        rule.second == SecondStep.branchManagerIfDays &&
        days >= rule.minDays) {
      final bm = employees
          .where(
            (x) =>
                x.branchId == e.branchId &&
                x.role == SystemRole.branchManager &&
                x.status.isEmployed,
          )
          .firstOrNull;
      if (bm != null && bm.id != steps.first.approverId) {
        steps.add(
          ApprovalStep(kind: ApproverKind.branchManager, approverId: bm.id),
        );
      }
    }
    // HR decides once: no second HR step when the manager is HR.
    final managerIsHr = manager?.role == SystemRole.hrAdmin;
    if (wantsHr &&
        !managerIsHr &&
        steps.every((s) => s.kind != ApproverKind.hr)) {
      steps.add(const ApprovalStep(kind: ApproverKind.hr));
    }

    return [
      for (final s in steps)
        if (s.approverId == e.id)
          const ApprovalStep(
            kind: ApproverKind.hr,
            note: 'Routed to HR — approver cannot approve own request',
          )
        else
          s,
    ];
  }

  /// "Aarav Bhatt" / "HR Admin" for a step.
  String approverName(ApprovalStep s) => switch (s.kind) {
    ApproverKind.hr =>
      employees
              .where((x) => x.role == SystemRole.hrAdmin && x.status.isEmployed)
              .map((x) => '${x.fullName} (HR Admin)')
              .firstOrNull ??
          'HR',
    _ =>
      s.approverId == null
          ? 'their manager'
          : (person(s.approverId!)?.fullName ?? 'their manager'),
  };

  /// May the member ([role], own record [self], scope [branchIds]) decide
  /// [r] now? Nobody decides their own request. The owner and HR decide any
  /// open step; a branch manager any request from their branches (board
  /// S57); others only the step assigned to them.
  bool canDecide(
    LeaveRequest r, {
    required SystemRole role,
    required Employee? self,
    List<String> branchIds = const [],
  }) {
    if (r.status != LeaveStatus.pending) return false;
    if (self != null && self.id == r.employeeId) return false;
    final step = r.currentStep;
    if (step == null) return false;
    if (role == SystemRole.owner || role == SystemRole.hrAdmin) return true;
    if (role == SystemRole.branchManager && self != null) {
      final branch = person(r.employeeId)?.branchId;
      if (branchIds.isEmpty
          ? branch == self.branchId
          : branchIds.contains(branch)) {
        return true;
      }
    }
    return self != null && step.approverId == self.id;
  }

  /// Requests a member may see (PRD §3.1 data scope): everything for the
  /// owner and HR, their branches for a branch manager, and their reports
  /// (or steps assigned to them) for a leave approver.
  List<LeaveRequest> visibleTo({
    required SystemRole role,
    required Employee? self,
    List<String> branchIds = const [],
  }) => [
    for (final r in data.requests)
      if (_sees(r, role: role, self: self, branchIds: branchIds)) r,
  ];

  bool _sees(
    LeaveRequest r, {
    required SystemRole role,
    required Employee? self,
    required List<String> branchIds,
  }) {
    if (role == SystemRole.owner || role == SystemRole.hrAdmin) return true;
    if (self != null && r.employeeId == self.id) {
      return role == SystemRole.branchManager;
    }
    final e = person(r.employeeId);
    if (e == null) return false;
    return switch (role) {
      SystemRole.branchManager =>
        branchIds.isEmpty || branchIds.contains(e.branchId),
      SystemRole.leaveApprover =>
        self != null &&
            (e.managerId == self.id ||
                r.steps.any((s) => s.approverId == self.id)),
      _ => false,
    };
  }

  /// Teammates (same branch and department) off on any counted day.
  ({int off, int team}) teamOff(LeaveRequest r) {
    final e = person(r.employeeId);
    if (e == null) return (off: 0, team: 0);
    final team = employees
        .where(
          (x) =>
              x.id != e.id &&
              x.branchId == e.branchId &&
              x.department == e.department &&
              x.status.isEmployed,
        )
        .toList();
    final type = data.type(r.typeKey);
    final days = type == null
        ? const <LeaveDay>[]
        : countDays(
            e,
            type,
            r.from,
            r.to,
            r.half,
          ).where((d) => d.counted > 0).toList();
    var off = 0;
    for (final t in team) {
      final overlaps = data.requests.any(
        (o) =>
            o.employeeId == t.id &&
            (o.status == LeaveStatus.approved || o.status.isOpen) &&
            days.any((d) => !d.date.isBefore(o.from) && !d.date.isAfter(o.to)),
      );
      if (overlaps) off++;
    }
    return (off: off, team: team.length + 1);
  }

  /// Approved leave days of [people] between [from] and [to] by type key
  /// (dashboards "Leave taken by type"); only days that count.
  Map<String, double> takenByType(
    Iterable<Employee> people,
    DateTime from,
    DateTime to,
  ) {
    final ids = {for (final e in people) e.id};
    final out = <String, double>{};
    for (final r in data.requests) {
      if (r.status != LeaveStatus.approved ||
          !ids.contains(r.employeeId) ||
          r.to.isBefore(from) ||
          r.from.isAfter(to)) {
        continue;
      }
      final e = person(r.employeeId);
      final type = data.type(r.typeKey);
      if (e == null || type == null) continue;
      final days = countDays(e, type, r.from, r.to, r.half)
          .where((d) => !d.date.isBefore(from) && !d.date.isAfter(to))
          .fold(0.0, (s, d) => s + d.counted);
      if (days > 0) out[type.key] = (out[type.key] ?? 0) + days;
    }
    return out;
  }

  /// Approved leave of [e] covering [d] (attendance shows "On leave").
  LeaveRequest? leaveOn(Employee e, DateTime d) => data.requests
      .where(
        (r) =>
            r.employeeId == e.id &&
            r.status == LeaveStatus.approved &&
            !d.isBefore(r.from) &&
            !d.isAfter(r.to),
      )
      .firstOrNull;
}

bool _same(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// "Mon 19 Oct" or "2–6 Nov" or "30 Oct – 2 Nov".
String leaveRange(DateTime from, DateTime to) => _range(from, to);

String _range(DateTime from, DateTime to) {
  if (_same(from, to)) return DateFormat('EEE d MMM').format(from);
  if (from.month == to.month && from.year == to.year) {
    return '${from.day}–${DateFormat('d MMM').format(to)}';
  }
  return '${DateFormat('d MMM').format(from)} – ${DateFormat('d MMM').format(to)}';
}
