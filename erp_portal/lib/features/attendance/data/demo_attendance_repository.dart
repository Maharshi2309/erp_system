import 'dart:typed_data';

import '../../../core/errors/failure.dart';
import '../../../core/permissions/system_roles.dart';
import '../../../core/utils/demo_random.dart';
import '../../../core/utils/zoned_time.dart';
import '../../employees/domain/employee.dart';
import '../../employees/domain/employee_rules.dart';
import '../../holidays/domain/work_calendar.dart';
import '../../organization/domain/branch.dart';
import '../domain/attendance.dart';
import '../domain/attendance_repository.dart';

/// DEMO ONLY — attendance in memory. History for the last 30 days is
/// generated from the employee and branch records relative to "now", with
/// the design's stories placed on yesterday (boards S53–S55, S86–S88).
class DemoAttendanceRepository implements AttendanceRepository {
  DemoAttendanceRepository({
    this.latency = const Duration(milliseconds: 500),
    required DateTime Function() clock,
    this.wallClock,
    this.faceOutcome,
  }) : _clock = clock; // ignore: prefer_initializing_formals

  final Duration latency;

  /// UTC instant.
  final DateTime Function() _clock;

  /// Floating local time for timestamps shown to people (requests).
  final DateTime Function()? wallClock;

  /// Tests set this to simulate a lost connection on the next punch.
  bool failNextPunch = false;

  /// DEMO ONLY — what the simulated face matcher answers for an enrolled
  /// person (picked on the selfie screen in demo builds). The real server
  /// compares the selfie with the enrolled face and checks liveness.
  final FaceResult Function()? faceOutcome;

  final _data = <String, _OrgData>{};
  int _nextId = 1;

  Future<void> _delay() =>
      latency == Duration.zero ? Future.value() : Future.delayed(latency);

  _OrgData _org(String id) => _data.putIfAbsent(id, _OrgData.new);

  bool isSeeded(String organizationId) => _data.containsKey(organizationId);

  // ---------- Seed ----------

  /// Generates history once per organization from its people and branches.
  void ensureSeeded(
    String organizationId, {
    required List<Employee> employees,
    required List<Branch> branches,
    required String orgZone,
    WorkCalendar calendar = const WorkCalendar([]),
    bool Function(Employee e, DateTime day)? onLeave,
  }) {
    if (_data.containsKey(organizationId)) return;
    final org = _org(organizationId);
    final now = _clock();
    final byId = {for (final b in branches) b.id: b};

    Punch punch(Employee e, DateTime at, PunchKind kind, PunchSource source) =>
        Punch(
          id: 'p-${_nextId++}',
          employeeId: e.id,
          at: at,
          kind: kind,
          source: source,
        );

    for (final e in employees) {
      final branch = byId[e.branchId];
      if (branch == null || !e.status.isEmployed) continue;
      final zone = branch.timeZone ?? orgZone;
      final today = dateOnly(wallTime(now, zone));
      final shifts = shiftsFor(branch);
      final shift =
          shifts.where((s) => s.name == e.shift).firstOrNull ?? shifts.first;
      final method = branch.attendance?.method ?? PunchMethod.app;

      for (var i = 30; i >= 0; i--) {
        final d = DateTime(today.year, today.month, today.day - i);
        if (d.isBefore(dateOnly(e.joiningDate))) continue;
        final weekday = d.weekday - 1;
        final open = e.weeklyOff != null
            ? e.weeklyOff != weekday
            : branch.hours[weekday].open;
        final holiday = calendar.holidayFor(branch, d) != null;
        // Nobody punches on a holiday or a full day of approved leave.
        if (!open || holiday || (onLeave?.call(e, d) ?? false)) continue;
        if (_story(e.code, i) != null) continue;

        final r = demoRandom('${e.code}${d.toIso8601String()}');
        final source = switch (method) {
          PunchMethod.app => PunchSource.app,
          PunchMethod.kiosk => PunchSource.kiosk,
          PunchMethod.both => r % 3 == 0 ? PunchSource.app : PunchSource.kiosk,
        };
        if (r % 100 < 5) continue; // absent
        DateTime at(int minutes) =>
            instantOf(d.add(Duration(minutes: minutes)), zone);
        final isLate = r % 100 >= 5 && r % 100 < 11;
        final leftEarly = r % 100 >= 11 && r % 100 < 13;
        final arrive = shift.start + (isLate ? 12 + r % 44 : -12 + r % 21);
        final night = shift.end <= shift.start;
        final leave =
            (night ? shift.end + 24 * 60 : shift.end) +
            (leftEarly ? -(45 + r % 75) : r % 26);
        final lunchOut = night ? shift.start + 240 : 13 * 60 + r % 26;
        final lunchBack = lunchOut + 30 + r % 31;

        final events = [
          (arrive, PunchKind.punchIn),
          (lunchOut, PunchKind.punchOut),
          (lunchBack, PunchKind.punchIn),
          (leave, PunchKind.punchOut),
        ];
        for (final (minutes, kind) in events) {
          final instant = at(minutes);
          if (instant.isAfter(now)) break;
          org.punches.add(punch(e, instant, kind, source));
        }
      }
    }
    _seedStories(org, employees, byId, orgZone, now, punch);
  }

  /// Days owned by a hand-written story (skipped by the generator).
  static String? _story(String code, int daysAgo) => switch ((code, daysAgo)) {
    ('EMP-0240', 1) ||
    ('EMP-0236', 1) ||
    ('EMP-0229', 1) ||
    ('EMP-0229', 0) => code,
    ('EMP-0152', 1) ||
    ('EMP-0233', 1) ||
    ('EMP-0176', 1) ||
    ('EMP-0201', 1) => code,
    ('EMP-0198', 1) || ('EMP-0217', 1) => code,
    _ => null,
  };

  void _seedStories(
    _OrgData org,
    List<Employee> employees,
    Map<String, Branch> branches,
    String orgZone,
    DateTime now,
    Punch Function(Employee, DateTime, PunchKind, PunchSource) punch,
  ) {
    Employee? byCode(String code) =>
        employees.where((e) => e.code == code).firstOrNull;
    String zoneOf(Employee e) => branches[e.branchId]?.timeZone ?? orgZone;
    DateTime dayAgo(Employee e, int n) {
      final t = dateOnly(wallTime(now, zoneOf(e)));
      return DateTime(t.year, t.month, t.day - n);
    }

    DateTime at(Employee e, int daysAgo, int h, int m) => instantOf(
      dayAgo(e, daysAgo).add(Duration(hours: h, minutes: m)),
      zoneOf(e),
    );
    final wall = wallClock ?? () => wallTime(now, orgZone);

    void day(
      String code,
      int daysAgo,
      List<(int, int, PunchKind)> events, {
      PunchSource source = PunchSource.kiosk,
    }) {
      final e = byCode(code);
      if (e == null) return;
      final open =
          branches[e.branchId]?.hours[dayAgo(e, daysAgo).weekday - 1].open ??
          false;
      if (!open) return;
      for (final (h, m, kind) in events) {
        final instant = at(e, daysAgo, h, m);
        if (!instant.isAfter(now)) {
          org.punches.add(punch(e, instant, kind, source));
        }
      }
    }

    const i = PunchKind.punchIn, o = PunchKind.punchOut;
    // Yesterday in Surat (board S53).
    day('EMP-0240', 1, [(9, 41, i), (13, 9, o), (14, 2, i)]);
    day('EMP-0236', 1, [(18, 31, o)]);
    day('EMP-0229', 1, [
      (10, 12, i),
      (13, 35, PunchKind.breakStart),
      (13, 53, PunchKind.breakEnd),
    ]);
    day('EMP-0152', 1, [(9, 28, i), (13, 0, o), (14, 0, i), (16, 5, o)]);
    day('EMP-0176', 1, [(9, 30, i), (11, 30, o), (12, 0, i), (14, 0, o)]);
    day('EMP-0201', 1, [(9, 52, i), (13, 0, o), (14, 0, i), (19, 10, o)]);
    day('EMP-0217', 1, [(9, 33, i), (12, 30, o), (14, 30, i), (18, 10, o)]);
    day('EMP-0198', 1, [(9, 47, i), (13, 0, o), (14, 0, i), (18, 40, o)]);
    // Today: Isha punched in at 09:24 (board S86).
    day('EMP-0229', 0, [(9, 24, i)], source: PunchSource.app);

    // Isha's missing punch-out yesterday was corrected (boards S86–S88).
    final isha = byCode('EMP-0229');
    if (isha != null &&
        org.punches.any(
          (p) =>
              p.employeeId == isha.id &&
              dateOnly(wallTime(p.at, zoneOf(isha))) == dayAgo(isha, 1),
        )) {
      org.corrections.add(
        Correction(
          id: 'c-${_nextId++}',
          employeeId: isha.id,
          workDate: dayAgo(isha, 1),
          changes: [CorrectionChange(kind: o, at: at(isha, 1, 18, 34))],
          reason: 'Verified with CCTV log and supervisor.',
          by: 'Mitesh Rana',
          byEmployeeId: byCode('EMP-0110')?.id,
          createdAt: wall().subtract(const Duration(hours: 5)),
        ),
      );
    }

    // Employees asked for corrections (board S54 "Correction requested").
    final faisal = byCode('EMP-0240');
    if (faisal != null && org.punches.any((p) => p.employeeId == faisal.id)) {
      org.requests.add(
        CorrectionRequest(
          id: 'r-${_nextId++}',
          employeeId: faisal.id,
          workDate: dayAgo(faisal, 1),
          kind: o,
          proposedAt: at(faisal, 1, 18, 30),
          message:
              'Kiosk queue was long at closing and I left without punching. '
              'Supervisor saw me lock the store at 18:30.',
          createdAt: wall().subtract(const Duration(hours: 6)),
        ),
      );
    }
    final komal = byCode('EMP-0236');
    if (komal != null && org.punches.any((p) => p.employeeId == komal.id)) {
      org.requests.add(
        CorrectionRequest(
          id: 'r-${_nextId++}',
          employeeId: komal.id,
          workDate: dayAgo(komal, 1),
          kind: i,
          proposedAt: at(komal, 1, 9, 30),
          message:
              'The gate kiosk was down in the morning, so my punch-in didn’t record.',
          createdAt: wall().subtract(const Duration(hours: 5)),
        ),
      );
    }

    // Older open sessions in Ahmedabad and Surat (Vadodara stays clear).
    final ahmedabad = employees
        .where(
          (e) =>
              e.branchId == 'b-ahm' &&
              e.status.isEmployed &&
              e.role == SystemRole.employee,
        )
        .toList();
    final surat = employees
        .where(
          (e) =>
              e.branchId == 'b-sur' &&
              e.status.isEmployed &&
              e.role == SystemRole.employee &&
              e.shift == 'General' &&
              _story(e.code, 1) == null,
        )
        .toList();
    final night = employees.where((e) => e.shift == 'Night').firstOrNull;

    void openSession(
      Employee? e,
      int daysAgo,
      List<(int, int, PunchKind)> events, {
      bool remind = false,
    }) {
      if (e == null) return;
      final d = dayAgo(e, daysAgo);
      // Replace whatever the generator made for that day.
      // Night shifts run past midnight; clear the whole shift window.
      final from = instantOf(d, zoneOf(e));
      final to = instantOf(
        d.add(Duration(hours: e.shift == 'Night' ? 36 : 24)),
        zoneOf(e),
      );
      org.punches.removeWhere(
        (p) =>
            p.employeeId == e.id && !p.at.isBefore(from) && p.at.isBefore(to),
      );
      day(e.code, daysAgo, events);
      if (remind) {
        org.reminders.add((
          employeeId: e.id,
          workDate: d,
          at: wall().subtract(const Duration(days: 1)),
        ));
      }
    }

    openSession(ahmedabad.elementAtOrNull(30), 5, [(9, 24, i)]);
    openSession(ahmedabad.elementAtOrNull(55), 6, [
      (9, 31, i),
      (13, 2, o),
      (14, 5, i),
    ], remind: true);
    openSession(ahmedabad.elementAtOrNull(80), 1, [(9, 28, i)]);
    openSession(surat.elementAtOrNull(12), 2, [(9, 35, i)], remind: true);
    openSession(night, 2, [(21, 2, i)]);
  }

  // ---------- Operations ----------

  @override
  Future<AttendanceData> load(String organizationId) async {
    await _delay();
    final org = _org(organizationId);
    return AttendanceData(
      punches: List.unmodifiable(org.punches),
      corrections: List.unmodifiable(org.corrections),
      requests: List.unmodifiable(org.requests),
      reminders: List.unmodifiable(org.reminders),
      faceProfiles: List.unmodifiable(org.faces.values),
      faceReviews: List.unmodifiable(org.reviews.values),
      faceExemptions: List.unmodifiable(org.exemptions.values),
    );
  }

  @override
  Future<Punch> punch(
    String organizationId, {
    required String employeeId,
    required PunchKind kind,
    required PunchSource source,
    required String requestId,
    Uint8List? selfie,
  }) async {
    await _delay();
    final org = _org(organizationId);
    if (org.byRequest[requestId] case final saved?) return saved;
    if (failNextPunch) {
      failNextPunch = false;
      throw const NetworkFailure();
    }
    final now = _clock();
    final mine = org.punches.where((p) => p.employeeId == employeeId).toList()
      ..sort((a, b) => a.at.compareTo(b.at));
    final last = mine
        .where(
          (p) => p.kind == PunchKind.punchIn || p.kind == PunchKind.punchOut,
        )
        .lastOrNull;
    final open =
        last?.kind == PunchKind.punchIn &&
        now.difference(last!.at).inHours < 20;
    if (kind == PunchKind.punchIn && open) {
      throw const ConflictFailure(
        'You’re already punched in. Punch out first.',
      );
    }
    if (kind == PunchKind.punchOut && !open) {
      throw const ConflictFailure('You’re not punched in.');
    }
    final p = Punch(
      id: 'p-${_nextId++}',
      employeeId: employeeId,
      at: now,
      kind: kind,
      source: source,
      face: selfie == null ? null : _match(org, employeeId, selfie),
    );
    org.punches.add(p);
    org.byRequest[requestId] = p;
    return p;
  }

  FaceCheck _match(_OrgData org, String employeeId, Uint8List selfie) {
    final profile = org.faces[employeeId];
    final result = selfie.isEmpty
        ? FaceResult.noFace
        : profile?.status != FaceEnrolStatus.approved
        ? FaceResult.notEnrolled
        : faceOutcome?.call() ?? FaceResult.verified;
    return FaceCheck(
      result: result,
      score: switch (result) {
        FaceResult.verified => 0.94,
        FaceResult.notMatched => 0.41,
        _ => null,
      },
      photo: selfie,
    );
  }

  @override
  Future<FaceProfile> enrolFace(
    String organizationId, {
    required String employeeId,
    required List<Uint8List> photos,
  }) async {
    await _delay();
    if (photos.length < 3 || photos.any((p) => p.isEmpty)) {
      throw const ValidationFailure('Take all three photos.');
    }
    final now = _clock();
    return _org(organizationId).faces[employeeId] = FaceProfile(
      employeeId: employeeId,
      status: FaceEnrolStatus.pending,
      photos: List.unmodifiable(photos),
      consentAt: now,
      submittedAt: now,
    );
  }

  @override
  Future<FaceProfile> decideFace(
    String organizationId,
    String employeeId, {
    required bool approve,
    required String by,
    String reason = '',
  }) async {
    await _delay();
    final org = _org(organizationId);
    final f = org.faces[employeeId];
    if (f == null) throw const NotFoundFailure();
    if (f.status != FaceEnrolStatus.pending) {
      throw const ConflictFailure('This enrolment was already decided.');
    }
    if (!approve && reason.trim().length < 3) {
      throw const ValidationFailure(
        'Give a reason the employee will see.',
        fieldErrors: {'reason': 'Enter at least 3 characters.'},
      );
    }
    return org.faces[employeeId] = FaceProfile(
      employeeId: employeeId,
      status: approve ? FaceEnrolStatus.approved : FaceEnrolStatus.rejected,
      photos: f.photos,
      consentAt: f.consentAt,
      submittedAt: f.submittedAt,
      decidedBy: by,
      decidedAt: _clock(),
      rejectReason: approve ? '' : reason.trim(),
    );
  }

  @override
  Future<void> deleteFace(String organizationId, String employeeId) async {
    await _delay();
    _org(organizationId).faces.remove(employeeId);
  }

  @override
  Future<void> setFaceExemption(
    String organizationId,
    String employeeId, {
    required String? reason,
    required String by,
  }) async {
    await _delay();
    final org = _org(organizationId);
    if (reason == null) {
      org.exemptions.remove(employeeId);
      return;
    }
    if (reason.trim().length < 3) {
      throw const ValidationFailure(
        'Give a reason.',
        fieldErrors: {'reason': 'Enter at least 3 characters.'},
      );
    }
    org.exemptions[employeeId] = FaceExemption(
      employeeId: employeeId,
      reason: reason.trim(),
      by: by,
      at: _clock(),
    );
  }

  @override
  Future<FaceReview> reviewFacePunch(
    String organizationId,
    String punchId, {
    required bool accept,
    required String by,
    String note = '',
  }) async {
    await _delay();
    final org = _org(organizationId);
    final p = org.punches.where((p) => p.id == punchId).firstOrNull;
    if (p == null || p.face?.needsReview != true) {
      throw const NotFoundFailure();
    }
    if (org.reviews.containsKey(punchId)) {
      throw const ConflictFailure('Someone already reviewed this punch.');
    }
    if (!accept && note.trim().length < 3) {
      throw const ValidationFailure(
        'Give a reason the employee will see.',
        fieldErrors: {'note': 'Enter at least 3 characters.'},
      );
    }
    return org.reviews[punchId] = FaceReview(
      punchId: punchId,
      accepted: accept,
      by: by,
      at: _clock(),
      note: note.trim(),
    );
  }

  @override
  Future<Correction> correct(
    String organizationId,
    Correction correction, {
    required bool needsSecondApproval,
  }) async {
    await _delay();
    if (correction.reason.trim().length < 5) {
      throw const ValidationFailure(
        'Add a reason.',
        fieldErrors: {'reason': 'Give a reason of at least 5 characters.'},
      );
    }
    final org = _org(organizationId);
    final saved = Correction(
      id: 'c-${_nextId++}',
      employeeId: correction.employeeId,
      workDate: correction.workDate,
      changes: correction.changes,
      reason: correction.reason.trim(),
      by: correction.by,
      byEmployeeId: correction.byEmployeeId,
      createdAt: correction.createdAt,
      status: needsSecondApproval
          ? CorrectionStatus.pending
          : CorrectionStatus.approved,
      approverNote: correction.approverNote,
      requestId: correction.requestId,
    );
    org.corrections.add(saved);
    if (saved.requestId != null) {
      final i = org.requests.indexWhere((r) => r.id == saved.requestId);
      if (i >= 0) {
        org.requests[i] = org.requests[i].close(RequestStatus.resolved);
      }
    }
    return saved;
  }

  @override
  Future<Correction> decide(
    String organizationId,
    String correctionId, {
    required bool approve,
    required String by,
  }) async {
    await _delay();
    final org = _org(organizationId);
    final i = org.corrections.indexWhere((c) => c.id == correctionId);
    if (i < 0) throw const NotFoundFailure();
    final c = org.corrections[i];
    if (c.status != CorrectionStatus.pending) {
      throw const ConflictFailure('This correction has already been decided.');
    }
    if (c.by == by) {
      throw const PermissionFailure('You can’t approve your own correction.');
    }
    return org.corrections[i] = c.decide(
      approve: approve,
      by: by,
      at: (wallClock ?? _clock)(),
    );
  }

  @override
  Future<CorrectionRequest> request(
    String organizationId,
    CorrectionRequest request,
  ) async {
    await _delay();
    final org = _org(organizationId);
    if (org.requests.any(
      (r) =>
          r.employeeId == request.employeeId &&
          dateOnly(r.workDate) == dateOnly(request.workDate) &&
          r.status == RequestStatus.open,
    )) {
      throw const ConflictFailure(
        'You already asked for a correction for this day.',
      );
    }
    final saved = CorrectionRequest(
      id: 'r-${_nextId++}',
      employeeId: request.employeeId,
      workDate: request.workDate,
      kind: request.kind,
      proposedAt: request.proposedAt,
      message: request.message,
      createdAt: request.createdAt,
    );
    org.requests.add(saved);
    return saved;
  }

  @override
  Future<CorrectionRequest> rejectRequest(
    String organizationId,
    String requestId, {
    required String reason,
  }) async {
    await _delay();
    final org = _org(organizationId);
    final i = org.requests.indexWhere((r) => r.id == requestId);
    if (i < 0) throw const NotFoundFailure();
    return org.requests[i] = org.requests[i].close(
      RequestStatus.rejected,
      reason: reason,
    );
  }

  @override
  Future<int> remind(
    String organizationId,
    List<({String employeeId, DateTime workDate})> items,
  ) async {
    await _delay();
    final org = _org(organizationId);
    final at = (wallClock ?? _clock)();
    for (final item in items) {
      org.reminders.add((
        employeeId: item.employeeId,
        workDate: dateOnly(item.workDate),
        at: at,
      ));
    }
    return items.length;
  }
}

class _OrgData {
  final punches = <Punch>[];
  final corrections = <Correction>[];
  final requests = <CorrectionRequest>[];
  final reminders = <PunchReminder>[];
  final byRequest = <String, Punch>{};
  final faces = <String, FaceProfile>{};
  final reviews = <String, FaceReview>{};
  final exemptions = <String, FaceExemption>{};
}
