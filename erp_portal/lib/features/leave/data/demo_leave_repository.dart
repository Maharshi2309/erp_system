import '../../../core/errors/failure.dart';
import '../../../core/permissions/system_roles.dart';
import '../../../core/utils/demo_random.dart';
import '../../employees/domain/employee.dart';
import '../../holidays/data/holiday_seed.dart';
import '../../holidays/domain/work_calendar.dart';
import '../../organization/domain/branch.dart';
import '../domain/leave.dart';
import '../domain/leave_book.dart';
import '../domain/leave_repository.dart';

/// DEMO ONLY — leave in memory. Types, policy and requests are seeded
/// relative to "today" so the design's stories stay current (boards S34,
/// S57–S61, S89–S92). Past approved leave lands on days the attendance
/// demo leaves absent, so both agree.
class DemoLeaveRepository implements LeaveRepository {
  DemoLeaveRepository({
    this.latency = const Duration(milliseconds: 500),
    required this.today,
    required this.now,
  });

  final Duration latency;

  /// Floating date / time in the organization's zone.
  final DateTime Function() today;
  final DateTime Function() now;

  final _orgs = <String, _Org>{};
  int _next = 2300;

  Future<void> _delay() =>
      latency == Duration.zero ? Future.value() : Future.delayed(latency);

  _Org _org(String id) => _orgs.putIfAbsent(id, _Org.new);
  bool isSeeded(String id) => _orgs.containsKey(id);

  static const defaultTypes = [
    LeaveType(
      key: 'casual',
      name: 'Casual leave',
      color: 0xFF2B4ACB,
      allowance: 8,
    ),
    LeaveType(
      key: 'sick',
      name: 'Sick leave',
      color: 0xFF0B7A62,
      allowance: 7,
      backdateDays: 7,
    ),
    LeaveType(
      key: 'earned',
      name: 'Earned leave',
      color: 0xFF8A4F00,
      method: AccrualMethod.monthly,
      allowance: 1.25,
      startsAfterMonths: 6,
      carryForwardMax: 30,
      minDays: 1,
      noticeDays: 7,
      allowHalfDays: false,
    ),
    LeaveType(
      key: 'unpaid',
      name: 'Unpaid leave',
      color: 0xFF475467,
      paid: false,
      method: AccrualMethod.none,
      maxDays: 30,
    ),
    LeaveType(
      key: 'parental',
      name: 'Maternity / paternity',
      color: 0xFFA9B3C2,
      method: AccrualMethod.none,
      maxDays: 182,
      active: false,
    ),
    LeaveType(
      key: 'optional',
      name: 'Optional holiday',
      color: 0xFF667085,
      method: AccrualMethod.none,
      maxDays: 1,
      allowHalfDays: false,
      optionalHolidaysOnly: true,
    ),
  ];

  /// Generates types, policy and requests once per organization.
  void ensureSeeded(
    String organizationId, {
    required List<Employee> employees,
    required List<Branch> branches,
  }) {
    if (_orgs.containsKey(organizationId)) return;
    final org = _org(organizationId);
    final t = today();
    org.types.addAll(defaultTypes);
    org.policy = LeavePolicy(
      routes: [
        const ApprovalRoute(
          id: 'rt-1',
          second: SecondStep.hrIfDays,
          minDays: 5,
        ),
        if (branches.any((b) => b.id == 'b-sur'))
          const ApprovalRoute(
            id: 'rt-2',
            branchId: 'b-sur',
            second: SecondStep.branchManagerIfDays,
            minDays: 3,
          ),
        const ApprovalRoute(
          id: 'rt-3',
          typeKey: 'earned',
          second: SecondStep.hrAlways,
        ),
      ],
      blackouts: [
        Blackout(
          name: 'Year-end audit',
          from: DateTime(t.year, 12, 26),
          to: DateTime(t.year, 12, 31),
          departments: const ['Finance'],
        ),
        Blackout(
          name: 'Diwali dispatch peak',
          from: DateTime(t.year, 11, 1),
          to: DateTime(t.year, 11, 7),
          departments: const ['Logistics'],
          branchIds: const ['b-sur'],
          blockedTypes: const ['earned'],
        ),
      ],
      updatedAt: DateTime(t.year, 4, 1),
      updatedBy: 'Ankit Patel',
    );

    // Earned leave carried from last year.
    for (final e in employees) {
      if (!e.status.isEmployed || e.joiningDate.year >= t.year) continue;
      final carry = (demoRandom('carry${e.code}') % 7) * 0.5;
      if (carry > 0) {
        org.adjustments.add(
          LeaveAdjustment(
            id: 'adj-${_next++}',
            employeeId: e.id,
            typeKey: 'earned',
            days: carry,
            effective: DateTime(t.year),
            reason: 'Carried from ${t.year - 1}',
            by: 'System',
            carry: true,
          ),
        );
      }
    }

    final book = LeaveBook(
      data: LeaveData(types: org.types, policy: org.policy),
      employees: employees,
      branches: branches,
      today: t,
      // The same demo holidays the calendar repository starts with.
      calendar: WorkCalendar(const [], holidays: demoCompanyHolidays()),
    );
    Employee? byCode(String c) =>
        employees.where((e) => e.code == c).firstOrNull;
    DateTime day(int offset) => DateTime(t.year, t.month, t.day + offset);
    DateTime nextWeekday(int weekday, {int weeks = 0}) {
      var d = day(1);
      while (d.weekday != weekday) {
        d = DateTime(d.year, d.month, d.day + 1);
      }
      return DateTime(d.year, d.month, d.day + 7 * weeks);
    }

    void add(
      String code,
      String type,
      DateTime from,
      DateTime to, {
      LeaveStatus status = LeaveStatus.pending,
      HalfDay half = HalfDay.full,
      String reason = '',
      int createdDaysAgo = 1,
      String note = '',
      (DateTime, DateTime)? amendedFrom,
    }) {
      final e = byCode(code);
      final lt = org.types.where((x) => x.key == type).firstOrNull;
      if (e == null || lt == null) return;
      final created = DateTime(
        t.year,
        t.month,
        t.day - createdDaysAgo,
        10 + createdDaysAgo % 9,
        11,
      );
      var steps = book.route(
        e,
        lt,
        book
            .countDays(e, lt, from, to, half)
            .fold(0.0, (s, d) => s + d.counted),
      );
      final history = <LeaveEvent>[
        (at: created, text: 'Submitted', by: e.fullName),
      ];
      for (final s in steps.where((s) => s.note.isNotEmpty)) {
        history.add((at: created, text: s.note, by: 'System'));
      }
      if (status == LeaveStatus.approved || status == LeaveStatus.rejected) {
        final decidedAt = created.add(const Duration(hours: 8));
        steps = [
          for (final s in steps)
            if (status == LeaveStatus.rejected && !identical(s, steps.first))
              s
            else
              s.decide(
                approve: status == LeaveStatus.approved,
                by: book.approverName(s).replaceAll(' (HR Admin)', ''),
                at: decidedAt,
              ),
        ];
        history.add((
          at: decidedAt,
          text: status == LeaveStatus.approved ? 'Approved' : 'Rejected',
          by: steps.first.decidedBy ?? '',
        ));
      }
      if (status == LeaveStatus.withdrawn) {
        history.add((
          at: created.add(const Duration(days: 1)),
          text: 'Withdrawn by employee',
          by: e.fullName,
        ));
      }
      if (status == LeaveStatus.cancelled) {
        history.add((
          at: created.add(const Duration(days: 1)),
          text: 'Cancelled by employee',
          by: e.fullName,
        ));
      }
      if (amendedFrom != null) {
        history.add((
          at: created.add(const Duration(days: 1)),
          text: 'Dates changed by employee · approval asked again',
          by: e.fullName,
        ));
      }
      org.requests.add(
        LeaveRequest(
          id: 'L-${_next++}',
          employeeId: e.id,
          typeKey: type,
          from: from,
          to: to,
          half: half,
          reason: reason,
          createdAt: created,
          status: status,
          steps: steps,
          history: history,
          decisionNote: note,
          amendedFrom: amendedFrom,
        ),
      );
    }

    // The design's requests (boards S34, S57, S61, S90–S92).
    final monday = nextWeekday(DateTime.monday);
    add(
      'EMP-0229',
      'casual',
      monday,
      monday,
      reason: 'Personal work at the RTO — licence renewal appointment.',
    );
    add(
      'EMP-0229',
      'casual',
      day(-20),
      day(-20),
      status: LeaveStatus.rejected,
      createdDaysAgo: 24,
      note: 'Audit week, please move',
      reason: 'Family visit',
    );
    add(
      'EMP-0229',
      'sick',
      day(-29),
      day(-29),
      half: HalfDay.first,
      status: LeaveStatus.cancelled,
      createdDaysAgo: 30,
      reason: 'Dentist',
    );
    final wed = nextWeekday(
      DateTime.wednesday,
      weeks: monday.isAfter(nextWeekday(DateTime.wednesday)) ? 0 : 1,
    );
    add(
      'EMP-0233',
      'casual',
      wed,
      wed,
      reason: 'Family function',
      createdDaysAgo: 2,
    );
    add(
      'EMP-0201',
      'casual',
      day(1),
      day(2),
      status: LeaveStatus.approved,
      createdDaysAgo: 2,
      reason: 'Child’s school event',
    );
    final nov = nextWeekday(DateTime.monday, weeks: 2);
    add(
      'EMP-0198',
      'earned',
      nov,
      DateTime(nov.year, nov.month, nov.day + 4),
      status: LeaveStatus.approved,
      createdDaysAgo: 5,
      reason: 'Diwali travel',
      amendedFrom: (
        DateTime(nov.year, nov.month, nov.day - 1),
        DateTime(nov.year, nov.month, nov.day + 4),
      ),
    );
    add(
      'EMP-0102',
      'earned',
      nov,
      DateTime(nov.year, nov.month, nov.day + 4),
      reason: 'Diwali travel',
      createdDaysAgo: 1,
    );
    add(
      'EMP-0236',
      'casual',
      day(-5),
      day(-5),
      status: LeaveStatus.withdrawn,
      createdDaysAgo: 9,
      reason: 'Personal',
    );
    add(
      'EMP-0217',
      'casual',
      day(-6),
      day(-5),
      status: LeaveStatus.approved,
      createdDaysAgo: 12,
      reason: 'Wedding in the family',
    );
    add(
      'EMP-0176',
      'sick',
      day(0),
      day(0),
      half: HalfDay.second,
      reason: 'Fever since morning, will see a doctor.',
      createdDaysAgo: 0,
    );

    // Past approved leave on days the attendance demo leaves people absent.
    var placed = 0;
    for (final e in employees) {
      if (!e.status.isEmployed || placed >= 60) continue;
      for (var i = 2; i <= 40; i++) {
        final d = day(-i);
        if (d.year != t.year || !demoAbsent(e.code, d)) continue;
        // Some absences stay unexplained.
        if (demoRandom('leave${e.code}$i') % 3 == 0) continue;
        final type = demoRandom('type${e.code}$i') % 3 == 0 ? 'sick' : 'casual';
        add(
          e.code,
          type,
          d,
          d,
          status: LeaveStatus.approved,
          createdDaysAgo: i + (type == 'sick' ? 0 : 3),
          reason: type == 'sick' ? 'Unwell' : 'Personal',
        );
        placed++;
      }
    }

    // A few waiting in Ahmedabad and Vadodara.
    final others = employees
        .where(
          (e) =>
              e.status.isEmployed &&
              e.role == SystemRole.employee &&
              e.branchId != 'b-sur',
        )
        .toList();
    for (var i = 0; i < 4 && i < others.length; i++) {
      final e = others[i * 17 % others.length];
      final type = org.types.firstWhere(
        (x) => x.key == (i.isEven ? 'casual' : 'sick'),
      );
      // The next day that counts (skips weekly offs and holidays).
      var from = day(8 + i * 3);
      while (book.countDays(e, type, from, from, HalfDay.full).first.counted ==
          0) {
        from = DateTime(from.year, from.month, from.day + 1);
      }
      add(
        e.code,
        type.key,
        from,
        from,
        reason: i.isEven ? 'Family function' : 'Medical check-up',
        createdDaysAgo: i,
      );
    }
  }

  @override
  Future<LeaveData> load(String organizationId) async {
    await _delay();
    final o = _org(organizationId);
    return LeaveData(
      types: List.unmodifiable(o.types),
      policy: o.policy,
      requests: List.unmodifiable(o.requests),
      adjustments: List.unmodifiable(o.adjustments),
    );
  }

  LeaveRequest _get(_Org o, String id) =>
      o.requests.where((r) => r.id == id).firstOrNull ??
      (throw const NotFoundFailure());

  void _put(_Org o, LeaveRequest r) =>
      o.requests[o.requests.indexWhere((x) => x.id == r.id)] = r;

  @override
  Future<LeaveRequest> submit(String organizationId, LeaveRequest draft) async {
    await _delay();
    final o = _org(organizationId);
    final saved = LeaveRequest(
      id: 'L-${_next++}',
      employeeId: draft.employeeId,
      typeKey: draft.typeKey,
      from: draft.from,
      to: draft.to,
      half: draft.half,
      reason: draft.reason,
      createdAt: now(),
      steps: draft.steps,
      history: draft.history,
    );
    o.requests.add(saved);
    return saved;
  }

  @override
  Future<LeaveRequest> decide(
    String organizationId,
    String id, {
    required bool approve,
    required String by,
    required String byEmployeeId,
    String note = '',
  }) async {
    await _delay();
    final o = _org(organizationId);
    final r = _get(o, id);
    if (r.status != LeaveStatus.pending) {
      throw const ConflictFailure('This request has already been decided.');
    }
    if (r.employeeId == byEmployeeId) {
      throw const PermissionFailure('You can’t decide your own request.');
    }
    if (!approve && note.trim().length < 3) {
      throw const ValidationFailure(
        'Add a reason.',
        fieldErrors: {'note': 'Give a reason of at least 3 characters.'},
      );
    }
    final at = now();
    var decided = false;
    final steps = [
      for (final s in r.steps)
        if (!decided && !s.isDone)
          () {
            decided = true;
            return s.decide(approve: approve, by: by, at: at);
          }()
        else
          s,
    ];
    final finished = !approve || steps.every((s) => s.isDone);
    final updated = r.copyWith(
      steps: steps,
      status: !approve
          ? LeaveStatus.rejected
          : (finished ? LeaveStatus.approved : LeaveStatus.pending),
      decisionNote: approve ? '' : note.trim(),
      history: [
        ...r.history,
        (
          at: at,
          text: approve
              ? (finished ? 'Approved' : 'Approved · sent to the next step')
              : 'Rejected · “${note.trim()}”',
          by: by,
        ),
      ],
    );
    _put(o, updated);
    return updated;
  }

  @override
  Future<LeaveRequest> requestChanges(
    String organizationId,
    String id, {
    required String by,
    required String note,
  }) async {
    await _delay();
    final o = _org(organizationId);
    final r = _get(o, id);
    if (r.status != LeaveStatus.pending) {
      throw const ConflictFailure('This request has already been decided.');
    }
    if (note.trim().length < 3) {
      throw const ValidationFailure(
        'Add a note.',
        fieldErrors: {
          'note': 'Say what should change (at least 3 characters).',
        },
      );
    }
    final updated = r.copyWith(
      status: LeaveStatus.changesRequested,
      decisionNote: note.trim(),
      history: [
        ...r.history,
        (at: now(), text: 'Changes requested · “${note.trim()}”', by: by),
      ],
    );
    _put(o, updated);
    return updated;
  }

  @override
  Future<LeaveRequest> withdraw(
    String organizationId,
    String id, {
    required String by,
  }) async {
    await _delay();
    final o = _org(organizationId);
    final r = _get(o, id);
    if (!r.status.isOpen) {
      throw const ConflictFailure('Only pending requests can be withdrawn.');
    }
    final updated = r.copyWith(
      status: LeaveStatus.withdrawn,
      history: [
        ...r.history,
        (at: now(), text: 'Withdrawn by employee', by: by),
      ],
    );
    _put(o, updated);
    return updated;
  }

  @override
  Future<LeaveRequest> cancel(
    String organizationId,
    String id, {
    required String by,
  }) async {
    await _delay();
    final o = _org(organizationId);
    final r = _get(o, id);
    if (r.status != LeaveStatus.approved) {
      throw const ConflictFailure('Only approved leave can be cancelled.');
    }
    if (!o.policy.cancelApprovedNotStarted) {
      throw const PermissionFailure(
        'Approved leave can’t be cancelled. Ask HR.',
      );
    }
    if (!r.from.isAfter(today())) {
      throw const ConflictFailure('Leave that has started can’t be cancelled.');
    }
    final updated = r.copyWith(
      status: LeaveStatus.cancelled,
      history: [
        ...r.history,
        (at: now(), text: 'Cancelled by employee', by: by),
      ],
    );
    _put(o, updated);
    return updated;
  }

  @override
  Future<LeaveRequest> amend(
    String organizationId,
    LeaveRequest changed, {
    required String by,
  }) async {
    await _delay();
    final o = _org(organizationId);
    final r = _get(o, changed.id);
    final canAmend =
        r.status.isOpen ||
        (r.status == LeaveStatus.approved && r.from.isAfter(today()));
    if (!canAmend) {
      throw const ConflictFailure('This request can no longer be changed.');
    }
    final updated = r.copyWith(
      typeKey: changed.typeKey,
      from: changed.from,
      to: changed.to,
      half: changed.half,
      reason: changed.reason,
      steps: changed.steps,
      status: LeaveStatus.pending,
      decisionNote: '',
      amendedFrom: (r.from, r.to),
      history: [
        ...r.history,
        (
          at: now(),
          text: 'Dates changed by employee · approval asked again',
          by: by,
        ),
      ],
    );
    _put(o, updated);
    return updated;
  }

  @override
  Future<LeaveAdjustment> adjust(
    String organizationId,
    LeaveAdjustment a,
  ) async {
    await _delay();
    if (a.days == 0 || a.days.abs() > 30) {
      throw const ValidationFailure(
        'Check the change.',
        fieldErrors: {'days': 'Enter a change between −30 and 30, not 0.'},
      );
    }
    if (a.reason.trim().length < 5) {
      throw const ValidationFailure(
        'Add a reason.',
        fieldErrors: {'reason': 'Give a reason of at least 5 characters.'},
      );
    }
    final saved = LeaveAdjustment(
      id: 'evt_${(_next++).toRadixString(16)}',
      employeeId: a.employeeId,
      typeKey: a.typeKey,
      days: a.days,
      effective: a.effective,
      reason: a.reason.trim(),
      by: a.by,
    );
    _org(organizationId).adjustments.add(saved);
    return saved;
  }

  @override
  Future<LeaveType> saveType(String organizationId, LeaveType type) async {
    await _delay();
    final o = _org(organizationId);
    final errors = validateLeaveType(type, o.types);
    if (errors.isNotEmpty) {
      throw ValidationFailure(errors.values.first, fieldErrors: errors);
    }
    final i = o.types.indexWhere((t) => t.key == type.key);
    if (i < 0) {
      o.types.add(type);
    } else {
      o.types[i] = type;
    }
    return type;
  }

  @override
  Future<LeavePolicy> savePolicy(
    String organizationId,
    LeavePolicy policy,
  ) async {
    await _delay();
    final errors = validateLeavePolicy(policy);
    if (errors.isNotEmpty) {
      throw ValidationFailure(errors.values.first, fieldErrors: errors);
    }
    final saved = policy.copyWith(updatedAt: now());
    _org(organizationId).policy = saved;
    return saved;
  }
}

class _Org {
  final types = <LeaveType>[];
  LeavePolicy policy = const LeavePolicy();
  final requests = <LeaveRequest>[];
  final adjustments = <LeaveAdjustment>[];
}
