import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/config/app_config.dart';
import '../../../app/router/route_names.dart';
import '../../../core/errors/failure.dart';
import '../../../core/permissions/system_roles.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/zoned_time.dart';
import '../../../shared/models/app_session.dart';
import '../../audit/presentation/audit_providers.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../../employees/domain/employee.dart';
import '../../employees/presentation/providers/employee_providers.dart';
import '../../holidays/data/demo_calendar_repository.dart';
import '../../holidays/domain/work_calendar.dart';
import '../../holidays/presentation/calendar_providers.dart';
import '../../leave/domain/leave.dart';
import '../../leave/presentation/leave_providers.dart';
import '../../notifications/domain/notifications.dart';
import '../../notifications/presentation/notification_providers.dart';
import '../../organization/domain/organization.dart';
import '../../organization/presentation/providers/organization_providers.dart';
import '../data/demo_attendance_repository.dart';
import '../domain/attendance.dart';
import '../domain/attendance_book.dart';
import '../domain/attendance_repository.dart';

final attendanceRepositoryProvider = Provider<AttendanceRepository>(
  (ref) => DemoAttendanceRepository(
    latency: ref.watch(demoLatencyProvider),
    clock: ref.watch(clockProvider),
    // Read at call time to avoid a dependency cycle at build.
    wallClock: () => wallTime(
      ref.read(clockProvider)(),
      ref.read(organizationProvider).value?.timeZone ?? defaultTimeZone,
    ),
  ),
);

String _orgZone(Ref ref) =>
    ref.watch(organizationProvider).value?.timeZone ?? defaultTimeZone;

/// Every punch, correction, request and reminder of the organization.
final attendanceDataProvider =
    AsyncNotifierProvider<AttendanceNotifier, AttendanceData>(
      AttendanceNotifier.new,
    );

class AttendanceNotifier extends AsyncNotifier<AttendanceData> {
  AttendanceRepository get _repo => ref.read(attendanceRepositoryProvider);
  AppSession get _session => ref.read(sessionProvider)!;

  @override
  Future<AttendanceData> build() async {
    final session = ref.watch(sessionProvider);
    if (session == null) throw const PermissionFailure();
    final repo = ref.watch(attendanceRepositoryProvider);
    if (repo is DemoAttendanceRepository &&
        !repo.isSeeded(session.organizationId)) {
      // Demo only: generate history from the people and branches.
      final employees = await ref
          .read(employeeRepositoryProvider)
          .employees(session.organizationId);
      final branches = await ref
          .read(organizationRepositoryProvider)
          .branches(session.organizationId);
      final org = await ref.read(organizationProvider.future);
      final calendar = ref.read(calendarRepositoryProvider);
      if (calendar is DemoCalendarRepository) {
        calendar.ensureSeeded(session.organizationId, employees);
      }
      // Demo only: leave is seeded first so punches skip approved leave.
      final leave = await ref.read(leaveDataProvider.future);
      repo.ensureSeeded(
        session.organizationId,
        employees: employees,
        branches: branches,
        orgZone: org.timeZone,
        onLeave: (e, d) => leave.requests.any(
          (r) =>
              r.employeeId == e.id &&
              r.status == LeaveStatus.approved &&
              r.half == HalfDay.full &&
              !d.isBefore(r.from) &&
              !d.isAfter(r.to),
        ),
        calendar: WorkCalendar(
          const [],
          holidays: await calendar.holidays(session.organizationId),
        ),
      );
    }
    return repo.load(session.organizationId);
  }

  Future<void> _reload() async =>
      state = AsyncData(await _repo.load(_session.organizationId));

  /// Punches the signed-in member in or out. The state changes only after
  /// the server confirms (board S86).
  Future<Punch> punch(PunchKind kind, {required String requestId}) async {
    final self = ref.read(selfEmployeeProvider);
    if (self == null) {
      throw const PermissionFailure('You don’t have an employee record.');
    }
    final p = await _repo.punch(
      _session.organizationId,
      employeeId: self.id,
      kind: kind,
      source: PunchSource.web,
      requestId: requestId,
    );
    await _reload();
    return p;
  }

  Employee? _person(String id) =>
      ref.read(employeesProvider).value?.where((e) => e.id == id).firstOrNull;

  /// Audit entry and, once it counts, the employee's notification.
  Future<void> _logCorrection(
    Correction c,
    String action,
    String summary,
  ) async {
    final e = _person(c.employeeId);
    final day = DateFormat('d MMM').format(c.workDate);
    await ref
        .read(auditRecorderProvider)
        .record(
          action: action,
          entityType: 'Attendance',
          entityId: c.employeeId,
          entityLabel: '${e?.fullName ?? c.employeeId} · $day',
          entityRoute: e == null
              ? null
              : AppRoutes.correctAttendance(e.id, c.workDate),
          branchId: e?.branchId,
          summary: summary,
          reason: c.reason,
          changes: [
            for (final ch in c.changes)
              (
                field: ch.kind == PunchKind.punchIn ? 'Punch-in' : 'Punch-out',
                before: '—',
                after: DateFormat(
                  'HH:mm',
                ).format(wallTime(ch.at, _orgZone(ref))),
              ),
          ],
        );
    if (e != null && c.status == CorrectionStatus.approved) {
      await ref
          .read(notifierServiceProvider)
          .send(
            NotifyEvent.correctionDecided,
            category: NotificationCategory.attendance,
            title: 'Attendance corrected',
            short: 'Your attendance on $day was corrected by ${c.by}.',
            employee: e,
            includeHr: false,
            employeeRoute: AppRoutes.myDay(c.workDate),
            tone: NotificationTone.fix,
          );
    }
  }

  Future<Correction> correct(
    Correction draft, {
    required bool needsSecondApproval,
  }) async {
    final saved = await _repo.correct(
      _session.organizationId,
      draft,
      needsSecondApproval: needsSecondApproval,
    );
    await _reload();
    await _logCorrection(
      saved,
      'attendance.correct',
      needsSecondApproval
          ? 'Correction proposed — waiting for a second approver'
          : 'Corrected — “${saved.reason}”',
    );
    return saved;
  }

  Future<Correction> decide(String id, {required bool approve}) async {
    final saved = await _repo.decide(
      _session.organizationId,
      id,
      approve: approve,
      by: _session.displayName,
    );
    await _reload();
    await _logCorrection(
      saved,
      approve ? 'attendance.approve' : 'attendance.reject',
      approve ? 'Correction approved' : 'Correction rejected',
    );
    return saved;
  }

  Future<CorrectionRequest> request(CorrectionRequest r) async {
    final saved = await _repo.request(_session.organizationId, r);
    await _reload();
    return saved;
  }

  Future<void> rejectRequest(String id, String reason) async {
    await _repo.rejectRequest(_session.organizationId, id, reason: reason);
    await _reload();
  }

  Future<int> remind(
    List<({String employeeId, DateTime workDate})> items,
  ) async {
    final n = await _repo.remind(_session.organizationId, items);
    await _reload();
    return n;
  }
}

/// Attendance computed for "now". Re-created when data, people, branches
/// or the time zone change.
final attendanceBookProvider = Provider<AsyncValue<AttendanceBook>>((ref) {
  final data = ref.watch(attendanceDataProvider);
  final employees = ref.watch(employeesProvider);
  final branches = ref.watch(branchesProvider);
  final now = ref.watch(clockProvider)();
  final zone = _orgZone(ref);
  // Approved leave shows as "On leave" once leave data has loaded.
  final leave = ref.watch(leaveBookProvider).value;
  if (data.hasError) return AsyncError(data.error!, data.stackTrace!);
  if (employees.hasError) {
    return AsyncError(employees.error!, employees.stackTrace!);
  }
  if (branches.hasError) {
    return AsyncError(branches.error!, branches.stackTrace!);
  }
  if (!data.hasValue || !employees.hasValue || !branches.hasValue) {
    return const AsyncLoading();
  }
  return AsyncData(
    AttendanceBook(
      data: data.value!,
      employees: employees.value!,
      branches: branches.value!,
      orgZone: zone,
      now: now,
      calendar: ref.watch(workCalendarProvider),
      onLeave: leave == null ? null : (e, d) => leave.leaveOn(e, d) != null,
    ),
  );
});

/// Does a correction by [session] for [employee] need a second person?
/// Policy (board S55): yes when the corrector is the employee's own manager
/// or the employee themselves. The backend must apply the same rule.
bool needsSecondApproval(
  AppSession session,
  Employee employee,
  Employee? self,
) {
  if (session.role == SystemRole.owner) return false;
  if (self == null) return false;
  return employee.managerId == self.id || employee.id == self.id;
}

/// Who approves a routed correction, e.g. "Hetal Shah (HR Admin)".
String approverFor(List<Employee> everyone) {
  final hr = everyone
      .where((e) => e.role == SystemRole.hrAdmin && e.status.isEmployed)
      .firstOrNull;
  return hr == null ? 'the owner' : '${hr.fullName} (HR Admin)';
}
