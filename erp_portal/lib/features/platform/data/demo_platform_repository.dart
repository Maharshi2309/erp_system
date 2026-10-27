import '../../../core/utils/zoned_time.dart';
import '../../attendance/data/demo_attendance_repository.dart';
import '../../attendance/domain/attendance.dart';
import '../../employees/domain/employee.dart';
import '../../employees/domain/employee_repository.dart';
import '../../holidays/data/demo_calendar_repository.dart';
import '../../holidays/domain/work_calendar.dart';
import '../../leave/data/demo_leave_repository.dart';
import '../../leave/domain/leave.dart';
import '../../organization/data/demo_organization_repository.dart';
import '../../organization/domain/branch.dart';
import '../../organization/domain/setup_progress.dart';
import '../domain/platform_stats.dart';

/// DEMO ONLY — platform statistics calculated from the in-memory demo
/// stores of every organization. Only counts leave this class; a backend
/// does the same aggregation in the database.
class DemoPlatformRepository implements PlatformRepository {
  DemoPlatformRepository({
    required this.organizations,
    required this.employees,
    required this.attendance,
    required this.leave,
    required this.calendar,
    required this.clock,
  });

  final DemoOrganizationRepository organizations;
  final EmployeeRepository employees;
  final DemoAttendanceRepository attendance;
  final DemoLeaveRepository leave;
  final DemoCalendarRepository calendar;

  /// UTC instant.
  final DateTime Function() clock;

  @override
  Future<PlatformSnapshot> snapshot() async {
    final now = clock();
    final out = <OrgStats>[];
    List<DateTime>? days;
    for (final id in organizations.organizationIds) {
      final org = await organizations.organization(id);
      final branches = await organizations.branches(id);
      final people = await employees.employees(id);
      await _ensureHistory(id, people, branches, org.timeZone);
      final data = await attendance.load(id);
      final leaveData = await leave.load(id);

      final today = dateOnly(wallTime(now, org.timeZone));
      final range = [
        for (var i = 29; i >= 0; i--)
          DateTime(today.year, today.month, today.day - i),
      ];
      days ??= range;
      final rejected = {
        for (final r in data.faceReviews)
          if (!r.accepted) r.punchId,
      };
      final punchedOn = <DateTime, Set<String>>{};
      DateTime? last;
      var punches30 = 0;
      for (final p in data.punches) {
        if (rejected.contains(p.id)) continue;
        final day = dateOnly(wallTime(p.at, org.timeZone));
        (punchedOn[day] ??= {}).add(p.employeeId);
        if (!day.isBefore(range.first)) punches30++;
        if (!p.at.isAfter(now) && (last == null || p.at.isAfter(last))) {
          last = p.at;
        }
      }
      final employed = people.where((e) => e.status.isEmployed).toList();
      final todaySet = punchedOn[today] ?? const <String>{};
      final since = now.subtract(const Duration(days: 30));

      out.add(
        OrgStats(
          id: org.id,
          name: org.name,
          industry: org.industry,
          city: org.city,
          state: org.state,
          sizeRange: org.employeeRange,
          createdAt: org.createdAt,
          branches: [
            for (final b in branches)
              BranchStats(
                id: b.id,
                name: b.name,
                code: b.code,
                city: b.city,
                active: b.isActive,
                employees: employed.where((e) => e.branchId == b.id).length,
                setupPercent: SetupProgress(b).percent,
                activeToday: employed
                    .where((e) => e.branchId == b.id && todaySet.contains(e.id))
                    .length,
                selfieCheck: b.attendance?.selfieCheck ?? false,
              ),
          ],
          employees: employed.length,
          inactiveEmployees: people
              .where((e) => e.status == EmploymentStatus.inactive)
              .length,
          accountsSignedIn: employed
              .where((e) => e.accountStatus == AccountStatus.signedIn)
              .length,
          accountsInvited: employed
              .where(
                (e) =>
                    e.accountStatus == AccountStatus.invited ||
                    e.accountStatus == AccountStatus.inviteExpired,
              )
              .length,
          dailyActive: [for (final d in range) punchedOn[d]?.length ?? 0],
          punches30: punches30,
          leaveRequests30: leaveData.requests
              .where((r) => r.createdAt.isAfter(since))
              .length,
          leavePending: leaveData.requests
              .where((r) => r.status == LeaveStatus.pending)
              .length,
          customFields: (await employees.customFields(id)).length,
          imports: (await employees.imports(id)).length,
          faceEnrolled: data.faceProfiles
              .where((f) => f.status == FaceEnrolStatus.approved)
              .length,
          lastActivity: last,
        ),
      );
    }
    return PlatformSnapshot(
      generatedAt: now,
      days: days ?? const [],
      orgs: out,
    );
  }

  /// The demo generates an organization's history the first time anyone
  /// opens it; the statistics need it too. Same order as the members' path:
  /// calendar, then leave, then attendance that skips approved leave.
  Future<void> _ensureHistory(
    String id,
    List<Employee> people,
    List<Branch> branches,
    String zone,
  ) async {
    if (attendance.isSeeded(id)) return;
    calendar.ensureSeeded(id, people);
    if (!leave.isSeeded(id)) {
      leave.ensureSeeded(id, employees: people, branches: branches);
    }
    final leaveData = await leave.load(id);
    attendance.ensureSeeded(
      id,
      employees: people,
      branches: branches,
      orgZone: zone,
      onLeave: (e, d) => leaveData.requests.any(
        (r) =>
            r.employeeId == e.id &&
            r.status == LeaveStatus.approved &&
            r.half == HalfDay.full &&
            !d.isBefore(r.from) &&
            !d.isAfter(r.to),
      ),
      calendar: WorkCalendar(const [], holidays: await calendar.holidays(id)),
    );
  }
}
