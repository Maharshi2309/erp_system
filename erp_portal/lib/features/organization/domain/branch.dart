import 'package:flutter/foundation.dart';

const weekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];
const weekdayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// Indian states offered on the branch form (board S18).
const indianStates = [
  'Gujarat',
  'Maharashtra',
  'Rajasthan',
  'Madhya Pradesh',
  'Karnataka',
  'Delhi',
  'Tamil Nadu',
  'Other',
];

/// Opening hours for one weekday, in minutes after local midnight.
@immutable
class DayHours {
  const DayHours({
    required this.open,
    this.opensAt = 570,
    this.closesAt = 1110,
  });

  const DayHours.closed() : this(open: false);

  final bool open;
  final int opensAt;
  final int closesAt;

  int get minutes => open && closesAt > opensAt ? closesAt - opensAt : 0;
  bool get isValid => !open || closesAt > opensAt;

  DayHours copyWith({bool? open, int? opensAt, int? closesAt}) => DayHours(
    open: open ?? this.open,
    opensAt: opensAt ?? this.opensAt,
    closesAt: closesAt ?? this.closesAt,
  );

  @override
  bool operator ==(Object other) =>
      other is DayHours &&
      other.open == open &&
      other.opensAt == opensAt &&
      other.closesAt == closesAt;

  @override
  int get hashCode => Object.hash(open, opensAt, closesAt);
}

/// Monday-first list of seven [DayHours].
typedef WeeklyHours = List<DayHours>;

int hm(int hour, int minute) => hour * 60 + minute;

/// Quick-fill presets on the branch form (board S18).
abstract final class HoursPresets {
  static WeeklyHours monToSat(int opens, int closes) => [
    for (var i = 0; i < 7; i++)
      i < 6
          ? DayHours(open: true, opensAt: opens, closesAt: closes)
          : const DayHours.closed(),
  ];

  static final WeeklyHours monSat930 = monToSat(hm(9, 30), hm(18, 30));
  static final WeeklyHours monFri900 = [
    for (var i = 0; i < 7; i++)
      i < 5
          ? DayHours(open: true, opensAt: hm(9, 0), closesAt: hm(18, 0))
          : const DayHours.closed(),
  ];
  static final WeeklyHours everyDay1000 = [
    for (var i = 0; i < 7; i++)
      DayHours(open: true, opensAt: hm(10, 0), closesAt: hm(20, 0)),
  ];
}

/// "6 days · 54 h a week" / "Closed all week".
String hoursSummary(WeeklyHours hours) {
  final open = hours.where((d) => d.open).toList();
  if (open.isEmpty) return 'Closed all week';
  final total = open.fold<int>(0, (sum, d) => sum + d.minutes);
  final h = (total / 60 * 10).round() / 10;
  final text = h == h.roundToDouble() ? h.toInt().toString() : h.toString();
  return '${open.length} ${open.length == 1 ? 'day' : 'days'} · $text h a week';
}

// ---------- Setup steps (board S21 side panels) ----------

enum PunchMethod { app, kiosk, both }

enum ShiftMode { branchHours, several }

@immutable
class AttendanceRules {
  const AttendanceRules({
    this.method = PunchMethod.app,
    this.graceMinutes = 10,
    this.earlyLeaveMinutes = 30,
    this.halfDayLateMinutes = 120,
    this.shiftMode = ShiftMode.branchHours,
    this.selfieCheck = false,
  });

  final PunchMethod method;
  final int graceMinutes;
  final int earlyLeaveMinutes;
  final int halfDayLateMinutes;
  final ShiftMode shiftMode;

  /// Employees take a selfie with each punch, matched to their enrolled
  /// face (D-70).
  final bool selfieCheck;

  AttendanceRules copyWith({
    PunchMethod? method,
    int? graceMinutes,
    int? earlyLeaveMinutes,
    int? halfDayLateMinutes,
    ShiftMode? shiftMode,
    bool? selfieCheck,
  }) => AttendanceRules(
    method: method ?? this.method,
    graceMinutes: graceMinutes ?? this.graceMinutes,
    earlyLeaveMinutes: earlyLeaveMinutes ?? this.earlyLeaveMinutes,
    halfDayLateMinutes: halfDayLateMinutes ?? this.halfDayLateMinutes,
    shiftMode: shiftMode ?? this.shiftMode,
    selfieCheck: selfieCheck ?? this.selfieCheck,
  );

  static const maxGrace = 120;
  static const maxEarlyLeave = 240;
  static const maxHalfDayLate = 480;

  bool get isComplete =>
      graceMinutes >= 0 &&
      graceMinutes <= maxGrace &&
      earlyLeaveMinutes >= 0 &&
      earlyLeaveMinutes <= maxEarlyLeave &&
      halfDayLateMinutes >= 0 &&
      halfDayLateMinutes <= maxHalfDayLate;
}

enum HolidaySource { gujarat, national, none }

enum HolidayCategory {
  festival('Festival'),
  national('National'),
  regional('Regional'),
  company('Company');

  const HolidayCategory(this.label);

  final String label;
}

@immutable
class HolidayItem {
  const HolidayItem({
    required this.name,
    required this.date,
    this.observed = true,
    this.custom = false,
    this.everyYear = false,
    this.category = HolidayCategory.festival,
    this.optional = false,
    this.orgWide = false,
    this.description = '',
  });

  final String name;
  final DateTime date;
  final bool observed;
  final bool custom;
  final bool everyYear;
  final HolidayCategory category;

  /// Employees choose to take it (board S64); it isn't a day off by itself.
  final bool optional;

  /// Added for the whole organization, including future branches (S64).
  final bool orgWide;
  final String description;

  /// The same holiday (by date and name).
  bool sameAs(HolidayItem o) =>
      o.name.toLowerCase() == name.toLowerCase() &&
      o.date.year == date.year &&
      o.date.month == date.month &&
      o.date.day == date.day;

  HolidayItem copyWith({
    bool? observed,
    String? name,
    DateTime? date,
    HolidayCategory? category,
    bool? optional,
    bool? orgWide,
    String? description,
  }) => HolidayItem(
    name: name ?? this.name,
    date: date ?? this.date,
    observed: observed ?? this.observed,
    custom: custom,
    everyYear: everyYear,
    category: category ?? this.category,
    optional: optional ?? this.optional,
    orgWide: orgWide ?? this.orgWide,
    description: description ?? this.description,
  );
}

/// Public holiday lists offered as starting points (board S21).
abstract final class HolidayLists {
  static final gujarat = [
    HolidayItem(name: 'Dussehra', date: DateTime(2026, 10, 20)),
    HolidayItem(name: 'Diwali', date: DateTime(2026, 11, 8)),
    HolidayItem(name: 'Gujarati New Year', date: DateTime(2026, 11, 10)),
    HolidayItem(name: 'Bhai Bij', date: DateTime(2026, 11, 11)),
    HolidayItem(name: 'Christmas', date: DateTime(2026, 12, 25)),
    HolidayItem(name: 'Uttarayan', date: DateTime(2027, 1, 14)),
    HolidayItem(
      name: 'Republic Day',
      date: DateTime(2027, 1, 26),
      category: HolidayCategory.national,
    ),
  ];
  static final national = [
    HolidayItem(
      name: 'Republic Day',
      date: DateTime(2027, 1, 26),
      category: HolidayCategory.national,
    ),
    HolidayItem(
      name: 'Independence Day',
      date: DateTime(2027, 8, 15),
      category: HolidayCategory.national,
    ),
    HolidayItem(
      name: 'Gandhi Jayanti',
      date: DateTime(2027, 10, 2),
      category: HolidayCategory.national,
    ),
  ];

  static List<HolidayItem> of(HolidaySource source) => switch (source) {
    HolidaySource.gujarat => gujarat,
    HolidaySource.national => national,
    HolidaySource.none => const [],
  };
}

@immutable
class HolidaySetup {
  const HolidaySetup({required this.source, required this.items});

  factory HolidaySetup.from(HolidaySource source) =>
      HolidaySetup(source: source, items: HolidayLists.of(source));

  final HolidaySource source;
  final List<HolidayItem> items;

  int get observedCount => items.where((h) => h.observed).length;

  /// Any choice of starting list completes the step (board S21).
  bool get isComplete => true;
}

enum LeaveApproval { manager, managerThenHr, owner }

@immutable
class LeaveTypeSetup {
  const LeaveTypeSetup({
    required this.key,
    required this.name,
    required this.daysPerYear,
    required this.accrual,
    required this.enabled,
    this.tracksBalance = true,
  });

  final String key;
  final String name;
  final int daysPerYear;
  final String accrual;
  final bool enabled;

  /// Unpaid leave has no balance or yearly allowance.
  final bool tracksBalance;

  bool get isValid => !enabled || !tracksBalance || daysPerYear > 0;

  LeaveTypeSetup copyWith({bool? enabled, int? daysPerYear}) => LeaveTypeSetup(
    key: key,
    name: name,
    daysPerYear: daysPerYear ?? this.daysPerYear,
    accrual: accrual,
    enabled: enabled ?? this.enabled,
    tracksBalance: tracksBalance,
  );
}

@immutable
class LeaveSetup {
  const LeaveSetup({
    required this.types,
    this.approval = LeaveApproval.manager,
  });

  /// Defaults from the onboarding prototype.
  static const defaults = LeaveSetup(
    types: [
      LeaveTypeSetup(
        key: 'casual',
        name: 'Casual leave',
        daysPerYear: 12,
        accrual: 'Credited at the start of the year',
        enabled: true,
      ),
      LeaveTypeSetup(
        key: 'sick',
        name: 'Sick leave',
        daysPerYear: 8,
        accrual: 'Credited at the start of the year',
        enabled: true,
      ),
      LeaveTypeSetup(
        key: 'earned',
        name: 'Earned leave',
        daysPerYear: 15,
        accrual: 'Earned monthly · 1.25 days',
        enabled: true,
      ),
      LeaveTypeSetup(
        key: 'unpaid',
        name: 'Unpaid leave',
        daysPerYear: 0,
        accrual: 'Used when other balances run out',
        enabled: false,
        tracksBalance: false,
      ),
    ],
  );

  final List<LeaveTypeSetup> types;
  final LeaveApproval approval;

  int get enabledCount => types.where((t) => t.enabled).length;

  bool get isComplete =>
      types.any((t) => t.enabled) && types.every((t) => t.isValid);
}

enum BranchManagerChoice { owner, invite }

@immutable
class RolesSetup {
  const RolesSetup({
    this.manager = BranchManagerChoice.owner,
    this.managerEmail = '',
    this.managerCanApproveLeave = true,
    this.managerCanCorrectAttendance = true,
    this.managerCanSeeReports = true,
    this.managerCanEditPeople = false,
    this.employeesCanRequestLeave = true,
    this.employeesCanSeeTeamOff = false,
  });

  final BranchManagerChoice manager;
  final String managerEmail;
  final bool managerCanApproveLeave;
  final bool managerCanCorrectAttendance;
  final bool managerCanSeeReports;
  final bool managerCanEditPeople;

  /// Punching in and out is always on (board S21).
  bool get employeesCanPunch => true;
  final bool employeesCanRequestLeave;
  final bool employeesCanSeeTeamOff;

  bool get isComplete =>
      manager == BranchManagerChoice.owner ||
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$').hasMatch(managerEmail.trim());
}

@immutable
class ReminderSettings {
  const ReminderSettings({
    this.punchInReminder = true,
    this.missingPunchSummary = true,
    this.weeklyLeaveDigest = false,
  });

  final bool punchInReminder;
  final bool missingPunchSummary;
  final bool weeklyLeaveDigest;

  int get onCount => [
    punchInReminder,
    missingPunchSummary,
    weeklyLeaveDigest,
  ].where((v) => v).length;
}

enum BranchStatus { active, inactive }

@immutable
class Branch {
  const Branch({
    required this.id,
    required this.name,
    required this.address,
    required this.city,
    required this.state,
    required this.pin,
    required this.hours,
    this.code = '',
    this.phone = '',
    this.email = '',
    this.timeZone,
    this.status = BranchStatus.active,
    this.employeeCount = 0,
    this.attendance,
    this.holidays,
    this.leave,
    this.roles,
    this.reminders,
    this.reviewed = false,
    this.openedOn,
  });

  final String id;
  final String name;

  /// Unique within the organization, e.g. "SUR-01".
  final String code;
  final String address;
  final String city;
  final String state;
  final String pin;
  final String phone;
  final String email;

  /// IANA id; null means "inherit the organization's" (Q-07).
  final String? timeZone;
  final WeeklyHours hours;
  final BranchStatus status;

  /// Filled from employee records from Phase 4 on.
  final int employeeCount;
  final AttendanceRules? attendance;
  final HolidaySetup? holidays;
  final LeaveSetup? leave;
  final RolesSetup? roles;
  final ReminderSettings? reminders;
  final bool reviewed;
  final DateTime? openedOn;

  bool get isActive => status == BranchStatus.active;

  Branch copyWith({
    String? name,
    String? code,
    String? address,
    String? city,
    String? state,
    String? pin,
    String? phone,
    String? email,
    String? timeZone,
    bool inheritTimeZone = false,
    WeeklyHours? hours,
    BranchStatus? status,
    int? employeeCount,
    AttendanceRules? attendance,
    HolidaySetup? holidays,
    LeaveSetup? leave,
    RolesSetup? roles,
    ReminderSettings? reminders,
    bool? reviewed,
  }) => Branch(
    id: id,
    name: name ?? this.name,
    code: code ?? this.code,
    address: address ?? this.address,
    city: city ?? this.city,
    state: state ?? this.state,
    pin: pin ?? this.pin,
    phone: phone ?? this.phone,
    email: email ?? this.email,
    timeZone: inheritTimeZone ? null : (timeZone ?? this.timeZone),
    hours: hours ?? this.hours,
    status: status ?? this.status,
    employeeCount: employeeCount ?? this.employeeCount,
    attendance: attendance ?? this.attendance,
    holidays: holidays ?? this.holidays,
    leave: leave ?? this.leave,
    roles: roles ?? this.roles,
    reminders: reminders ?? this.reminders,
    reviewed: reviewed ?? this.reviewed,
    openedOn: openedOn,
  );
}
