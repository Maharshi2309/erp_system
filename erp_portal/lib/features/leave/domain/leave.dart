import 'package:flutter/foundation.dart';

import '../../employees/domain/employee.dart';

enum AccrualMethod {
  upfront('Yearly, upfront'),
  monthly('Monthly accrual'),
  none('No balance');

  const AccrualMethod(this.label);

  final String label;
}

/// An organization-wide leave type (board S58). A branch's leave setup
/// (Phase 3) can switch a type off or override its yearly allowance.
@immutable
class LeaveType {
  const LeaveType({
    required this.key,
    required this.name,
    required this.color,
    this.paid = true,
    this.method = AccrualMethod.upfront,
    this.allowance = 0,
    this.startsAfterMonths = 0,
    this.carryForwardMax = 0,
    this.minDays = 0.5,
    this.maxDays = 15,
    this.allowHalfDays = true,
    this.countWeeklyOffs = false,
    this.countHolidays = false,
    this.noticeDays = 0,
    this.backdateDays = 0,
    this.eligibleTypes = const [],
    this.branchIds = const [],
    this.departments = const [],
    this.active = true,
    this.optionalHolidaysOnly = false,
  });

  final String key;
  final String name;

  /// ARGB colour of the type's dot.
  final int color;
  final bool paid;
  final AccrualMethod method;

  /// Days a year (upfront) or a month (monthly accrual).
  final double allowance;

  /// Accrual starts this many months after joining.
  final int startsAfterMonths;
  final double carryForwardMax;
  final double minDays;
  final double maxDays;
  final bool allowHalfDays;
  final bool countWeeklyOffs;
  final bool countHolidays;

  /// Days of notice needed (planned leave).
  final int noticeDays;

  /// How far back a request may start (sick leave).
  final int backdateDays;

  /// Empty = everyone.
  final List<EmploymentType> eligibleTypes;
  final List<String> branchIds;
  final List<String> departments;
  final bool active;

  /// May only be taken on optional holidays (board S93).
  final bool optionalHolidaysOnly;

  bool get tracksBalance => method != AccrualMethod.none;

  /// Days a year at the default allowance.
  double get yearly =>
      method == AccrualMethod.monthly ? allowance * 12 : allowance;

  bool eligible(Employee e) =>
      active &&
      (eligibleTypes.isEmpty || eligibleTypes.contains(e.type)) &&
      (branchIds.isEmpty || branchIds.contains(e.branchId)) &&
      (departments.isEmpty || departments.contains(e.department));

  /// "Paid · 8/yr upfront" (board S58 list).
  String get summary => [
    paid ? 'Paid' : 'Unpaid',
    switch (method) {
      AccrualMethod.upfront => '${_n(allowance)}/yr upfront',
      AccrualMethod.monthly => '${_n(allowance)}/mo accrual',
      AccrualMethod.none =>
        optionalHolidaysOnly ? 'optional holidays' : 'no balance',
    },
  ].join(' · ');

  LeaveType copyWith({
    String? key,
    String? name,
    int? color,
    bool? paid,
    AccrualMethod? method,
    double? allowance,
    int? startsAfterMonths,
    double? carryForwardMax,
    double? minDays,
    double? maxDays,
    bool? allowHalfDays,
    bool? countWeeklyOffs,
    bool? countHolidays,
    int? noticeDays,
    int? backdateDays,
    List<EmploymentType>? eligibleTypes,
    List<String>? branchIds,
    List<String>? departments,
    bool? active,
  }) => LeaveType(
    key: key ?? this.key,
    name: name ?? this.name,
    color: color ?? this.color,
    paid: paid ?? this.paid,
    method: method ?? this.method,
    allowance: allowance ?? this.allowance,
    startsAfterMonths: startsAfterMonths ?? this.startsAfterMonths,
    carryForwardMax: carryForwardMax ?? this.carryForwardMax,
    minDays: minDays ?? this.minDays,
    maxDays: maxDays ?? this.maxDays,
    allowHalfDays: allowHalfDays ?? this.allowHalfDays,
    countWeeklyOffs: countWeeklyOffs ?? this.countWeeklyOffs,
    countHolidays: countHolidays ?? this.countHolidays,
    noticeDays: noticeDays ?? this.noticeDays,
    backdateDays: backdateDays ?? this.backdateDays,
    eligibleTypes: eligibleTypes ?? this.eligibleTypes,
    branchIds: branchIds ?? this.branchIds,
    departments: departments ?? this.departments,
    active: active ?? this.active,
    optionalHolidaysOnly: optionalHolidaysOnly,
  );
}

String _n(double v) => v == v.roundToDouble() ? '${v.toInt()}' : '$v';

/// "1", "0.5", "1.25".
String formatDays(double v) => _n(double.parse(v.toStringAsFixed(2)));

/// When step 2 applies (board S59 "Step 2").
enum SecondStep {
  none('None'),
  hrIfDays('HR Admin if N+ days'),
  branchManagerIfDays('Branch Manager if N+ days'),
  hrAlways('HR Admin always');

  const SecondStep(this.label);

  final String label;
}

/// One approval route (board S59). Step 1 is always the reporting manager.
@immutable
class ApprovalRoute {
  const ApprovalRoute({
    required this.id,
    this.branchId,
    this.typeKey,
    this.second = SecondStep.none,
    this.minDays = 0,
  });

  final String id;

  /// Null = all branches / all types.
  final String? branchId;
  final String? typeKey;
  final SecondStep second;
  final double minDays;

  /// More specific routes win: type, then branch, then the default.
  int get specificity => (typeKey != null ? 2 : 0) + (branchId != null ? 1 : 0);
}

/// A period when leave is restricted (board S59).
@immutable
class Blackout {
  const Blackout({
    required this.name,
    required this.from,
    required this.to,
    this.departments = const [],
    this.branchIds = const [],
    this.blockedTypes = const [],
  });

  final String name;
  final DateTime from;
  final DateTime to;
  final List<String> departments;
  final List<String> branchIds;

  /// Leave types that can't be requested inside the period; empty = all.
  final List<String> blockedTypes;

  bool covers(Employee e, DateTime d, String typeKey) =>
      !d.isBefore(from) &&
      !d.isAfter(to) &&
      (departments.isEmpty || departments.contains(e.department)) &&
      (branchIds.isEmpty || branchIds.contains(e.branchId)) &&
      (blockedTypes.isEmpty || blockedTypes.contains(typeKey));
}

/// Organization leave rules (board S59).
@immutable
class LeavePolicy {
  const LeavePolicy({
    this.routes = const [],
    this.backdatedSickDays = 7,
    this.longestRequestDays = 15,
    this.blackouts = const [],
    this.allowNegative = false,
    this.negativeLimit = 2,
    this.cancelApprovedNotStarted = true,
    this.optionalHolidaysPerYear = 1,
    this.updatedAt,
    this.updatedBy = '',
  });

  final List<ApprovalRoute> routes;
  final int backdatedSickDays;
  final int longestRequestDays;
  final List<Blackout> blackouts;
  final bool allowNegative;
  final double negativeLimit;
  final bool cancelApprovedNotStarted;
  final int optionalHolidaysPerYear;
  final DateTime? updatedAt;
  final String updatedBy;

  LeavePolicy copyWith({
    List<ApprovalRoute>? routes,
    int? backdatedSickDays,
    int? longestRequestDays,
    List<Blackout>? blackouts,
    bool? allowNegative,
    double? negativeLimit,
    bool? cancelApprovedNotStarted,
    int? optionalHolidaysPerYear,
    DateTime? updatedAt,
    String? updatedBy,
  }) => LeavePolicy(
    routes: routes ?? this.routes,
    backdatedSickDays: backdatedSickDays ?? this.backdatedSickDays,
    longestRequestDays: longestRequestDays ?? this.longestRequestDays,
    blackouts: blackouts ?? this.blackouts,
    allowNegative: allowNegative ?? this.allowNegative,
    negativeLimit: negativeLimit ?? this.negativeLimit,
    cancelApprovedNotStarted:
        cancelApprovedNotStarted ?? this.cancelApprovedNotStarted,
    optionalHolidaysPerYear:
        optionalHolidaysPerYear ?? this.optionalHolidaysPerYear,
    updatedAt: updatedAt ?? this.updatedAt,
    updatedBy: updatedBy ?? this.updatedBy,
  );
}

enum HalfDay {
  full('Full days'),
  first('First half'),
  second('Second half');

  const HalfDay(this.label);

  final String label;
}

enum LeaveStatus {
  pending('Pending'),
  changesRequested('Changes requested'),
  approved('Approved'),
  rejected('Rejected'),
  withdrawn('Withdrawn'),
  cancelled('Cancelled');

  const LeaveStatus(this.label);

  final String label;

  /// Still holds balance and blocks overlapping requests.
  bool get isOpen => this == pending || this == changesRequested;
  bool get holdsDays => isOpen || this == approved;
}

/// Who decides a step.
enum ApproverKind { manager, branchManager, hr }

/// One step of a request's approval (board S57 "Routed to HR").
@immutable
class ApprovalStep {
  const ApprovalStep({
    required this.kind,
    this.approverId,
    this.note = '',
    this.decidedBy,
    this.decidedAt,
    this.approved,
  });

  final ApproverKind kind;

  /// The employee who should decide (manager / branch manager).
  final String? approverId;

  /// Why it was routed, e.g. "approver cannot approve own request".
  final String note;
  final String? decidedBy;
  final DateTime? decidedAt;
  final bool? approved;

  bool get isDone => approved != null;

  ApprovalStep decide({
    required bool approve,
    required String by,
    required DateTime at,
  }) => ApprovalStep(
    kind: kind,
    approverId: approverId,
    note: note,
    decidedBy: by,
    decidedAt: at,
    approved: approve,
  );
}

/// A request history line (boards S57, S91).
typedef LeaveEvent = ({DateTime at, String text, String by});

/// A leave request (boards S57, S61, S89–S91).
@immutable
class LeaveRequest {
  const LeaveRequest({
    required this.id,
    required this.employeeId,
    required this.typeKey,
    required this.from,
    required this.to,
    required this.createdAt,
    this.half = HalfDay.full,
    this.reason = '',
    this.status = LeaveStatus.pending,
    this.steps = const [],
    this.history = const [],
    this.decisionNote = '',
    this.amendedFrom,
  });

  /// "L-2298".
  final String id;
  final String employeeId;
  final String typeKey;

  /// Floating dates, inclusive.
  final DateTime from;
  final DateTime to;
  final HalfDay half;
  final String reason;
  final DateTime createdAt;
  final LeaveStatus status;
  final List<ApprovalStep> steps;
  final List<LeaveEvent> history;

  /// Rejection or change-request note shown to the employee.
  final String decisionNote;

  /// Dates before an amendment, e.g. (2 Nov, 6 Nov).
  final (DateTime, DateTime)? amendedFrom;

  ApprovalStep? get currentStep => steps.where((s) => !s.isDone).firstOrNull;
  bool get isSingleDay => from == to;

  LeaveRequest copyWith({
    String? typeKey,
    DateTime? from,
    DateTime? to,
    HalfDay? half,
    String? reason,
    LeaveStatus? status,
    List<ApprovalStep>? steps,
    List<LeaveEvent>? history,
    String? decisionNote,
    (DateTime, DateTime)? amendedFrom,
  }) => LeaveRequest(
    id: id,
    employeeId: employeeId,
    typeKey: typeKey ?? this.typeKey,
    from: from ?? this.from,
    to: to ?? this.to,
    half: half ?? this.half,
    reason: reason ?? this.reason,
    createdAt: createdAt,
    status: status ?? this.status,
    steps: steps ?? this.steps,
    history: history ?? this.history,
    decisionNote: decisionNote ?? this.decisionNote,
    amendedFrom: amendedFrom ?? this.amendedFrom,
  );
}

/// An HR balance change (board S60), or a carried-forward balance.
@immutable
class LeaveAdjustment {
  const LeaveAdjustment({
    required this.id,
    required this.employeeId,
    required this.typeKey,
    required this.days,
    required this.effective,
    required this.reason,
    required this.by,
    this.carry = false,
  });

  final String id;
  final String employeeId;
  final String typeKey;

  /// Positive adds days, negative removes them.
  final double days;
  final DateTime effective;
  final String reason;
  final String by;

  /// A carried-forward balance from last year (not a manual change).
  final bool carry;
}

/// Everything the leave module stores.
@immutable
class LeaveData {
  const LeaveData({
    this.types = const [],
    this.policy = const LeavePolicy(),
    this.requests = const [],
    this.adjustments = const [],
  });

  final List<LeaveType> types;
  final LeavePolicy policy;
  final List<LeaveRequest> requests;
  final List<LeaveAdjustment> adjustments;

  LeaveType? type(String key) => types.where((t) => t.key == key).firstOrNull;
}

/// Field errors for a leave type (board S58); empty when it can be saved.
/// [others] are the organization's other types (names must be unique).
Map<String, String> validateLeaveType(LeaveType t, List<LeaveType> others) {
  final errors = <String, String>{};
  final name = t.name.trim();
  if (name.length < 2) {
    errors['name'] = 'Enter a name.';
  } else if (others.any(
    (o) => o.key != t.key && o.name.toLowerCase() == name.toLowerCase(),
  )) {
    errors['name'] = 'Another leave type has this name.';
  }
  switch (t.method) {
    case AccrualMethod.upfront when t.allowance <= 0 || t.allowance > 60:
      errors['allowance'] = 'Enter 0.5 to 60 days a year.';
    case AccrualMethod.monthly when t.allowance <= 0 || t.allowance > 5:
      errors['allowance'] = 'Enter 0.25 to 5 days a month.';
    default:
  }
  if (t.startsAfterMonths < 0 || t.startsAfterMonths > 24) {
    errors['startsAfter'] = 'Enter 0 to 24 months.';
  }
  if (t.carryForwardMax < 0 || t.carryForwardMax > 60) {
    errors['carry'] = 'Enter 0 to 60 days.';
  }
  if (t.minDays < 0.5 || t.minDays > t.maxDays) {
    errors['minDays'] = 'At least 0.5 and not more than the maximum.';
  }
  if (t.maxDays < 0.5 || t.maxDays > 90) {
    errors['maxDays'] = 'Enter 0.5 to 90 days.';
  }
  if (t.noticeDays < 0 || t.noticeDays > 90) {
    errors['notice'] = 'Enter 0 to 90 days.';
  }
  if (t.backdateDays < 0 || t.backdateDays > 30) {
    errors['backdate'] =
        'Must be 30 days or less, so attendance for a closed month isn’t changed.';
  }
  return errors;
}

/// Field errors for the leave policy (board S59); empty when it can be saved.
Map<String, String> validateLeavePolicy(LeavePolicy p) {
  final errors = <String, String>{};
  if (p.backdatedSickDays < 0 || p.backdatedSickDays > 30) {
    errors['backdated'] =
        'Must be 30 days or less, so attendance for a closed month isn’t changed.';
  }
  if (p.longestRequestDays < 1 || p.longestRequestDays > 90) {
    errors['longest'] = 'Enter 1 to 90 working days.';
  }
  if (p.negativeLimit < 0 || p.negativeLimit > 10) {
    errors['negative'] = 'Enter 0 to 10 days.';
  }
  if (p.optionalHolidaysPerYear < 0 || p.optionalHolidaysPerYear > 10) {
    errors['optional'] = 'Enter 0 to 10.';
  }
  final scopes = <String>{};
  for (final r in p.routes) {
    if (!scopes.add('${r.branchId}|${r.typeKey}')) {
      errors['routes'] = 'Two routes apply to the same branch and type.';
    }
    if ((r.second == SecondStep.hrIfDays ||
            r.second == SecondStep.branchManagerIfDays) &&
        (r.minDays < 1 || r.minDays > 90)) {
      errors['routes'] = 'Route day thresholds must be 1 to 90.';
    }
  }
  if (!p.routes.any((r) => r.branchId == null && r.typeKey == null)) {
    errors['routes'] = 'Keep a default route for all branches.';
  }
  for (final b in p.blackouts) {
    if (b.name.trim().isEmpty) {
      errors['blackouts'] = 'Name every blackout period.';
    } else if (b.to.isBefore(b.from)) {
      errors['blackouts'] = '“${b.name}” ends before it starts.';
    }
  }
  return errors;
}

/// A worked example for someone joining 1 March of [year] (board S58),
/// following the same rules as `LeaveBook.entitlement`.
String accrualExample(LeaveType t, int year) {
  if (!t.tracksBalance) {
    return 'No balance is kept; every request is approved on its own.';
  }
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final from = DateTime(year, 3 + t.startsAfterMonths);
  final after = t.startsAfterMonths == 0
      ? 'Eligible from 1 Mar'
      : 'Eligible from 1 ${months[from.month - 1]}${from.year != year ? ' ${from.year}' : ''} (after ${t.startsAfterMonths} ${t.startsAfterMonths == 1 ? 'month' : 'months'})';
  final carry = t.carryForwardMax > 0
      ? 'up to ${_n(t.carryForwardMax)} carried into ${year + 1}'
      : 'unused days lapse on 31 Dec';
  if (from.year > year) return '$after → nothing in $year → $carry.';
  final left = 12 - from.month + 1;
  if (t.method == AccrualMethod.monthly) {
    final total = double.parse((t.allowance * left).toStringAsFixed(2));
    return '$after → accrues ${_n(t.allowance)} days on the 1st of each month → ${_n(total)} days by 31 Dec → $carry.';
  }
  final prorated = (t.allowance * left / 12 * 2).round() / 2;
  return '$after → ${_n(prorated)} of ${_n(t.allowance)} days granted for the rest of $year → $carry.';
}
