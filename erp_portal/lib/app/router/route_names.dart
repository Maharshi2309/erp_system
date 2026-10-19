import '../../core/permissions/system_roles.dart';

/// URL paths. Screen IDs refer to docs/screen_inventory.md.
abstract final class AppRoutes {
  static const root = '/';
  static const loading = '/loading';

  // Getting in (Phase 2).
  static const welcome = '/welcome'; // S03
  static const register = '/register'; // S04
  static const verifyEmail = '/verify-email'; // S05
  static const twoStep = '/sign-in/verify'; // S06
  static const forgotPassword = '/forgot-password'; // S07
  static const resetPassword = '/reset-password'; // S08, ?token=
  static const acceptInvite = '/invite'; // S09, ?token=
  static const chooseOrganization = '/choose-organization'; // S10
  static const onboarding = '/onboarding'; // S12
  static const createOrganization = '/onboarding/create'; // S13–S14

  // Owner / HR admin.
  static const overview = '/overview'; // S30
  static const organization = '/organization'; // S35
  static const branches = '/branches'; // S36
  static const employees = '/employees'; // S39
  static const attendance = '/attendance'; // S52
  static const leave = '/leave'; // S57
  static const holidays = '/holidays'; // S62
  static const roles = '/roles'; // S67
  static const reports = '/reports'; // S73
  static const notifications = '/notifications'; // S76
  static const settings = '/settings'; // S80
  static const auditLog = '/audit-log'; // S77
  static const accessDenied = '/access-denied'; // S72

  // Organization and branch setup (Phase 3).
  static const ownerProfile = '/organization/owner-profile'; // S16
  static const newBranch = '/branches/new'; // S18–S19
  static String branch(String id) => '/branches/$id'; // S38
  static String branchSetup(String id) => '/branches/$id/setup'; // S20–S22
  static String branchBasics(String id) => '/branches/$id/basics'; // S18 edit
  static String branchEdit(String id) => '/branches/$id/edit'; // S37

  // Roles, settings, reports, notifications and audit (Phase 7).
  static const people = '/roles/people'; // S70
  static const invitations = '/roles/invitations'; // S71
  static const newRole = '/roles/new'; // S68, ?from=
  static String role(String id) => '/roles/$id'; // S68 / S69
  static String auditEvent(String id) => '/audit-log/$id'; // S78
  static const reportResults = '/reports/results'; // S74, ?report=
  static const exportHistory = '/reports/exports'; // S75
  static const settingsAttendance = '/settings/attendance'; // S79
  static const settingsSchedules = '/settings/schedules'; // S81
  static const settingsNotifications = '/settings/notifications'; // S82
  static const settingsSecurity = '/settings/security'; // S83
  static const settingsData = '/settings/data'; // S84
  static const settingsBranding = '/settings/branding'; // S85
  static const myNotifications = '/my/notifications'; // S95

  // Leave and holidays (Phase 6).
  static const leaveRequests = '/leave/requests'; // S61
  static const leaveBalances = '/leave/balances'; // S60
  static const leaveTypes = '/leave/types'; // S58
  static const leavePolicy = '/leave/policy'; // S59
  static const holidayList = '/holidays/list'; // S63
  static const holidayImport = '/holidays/import'; // S65
  static const schedules = '/holidays/schedules'; // S66
  static const newHoliday = '/holidays/new'; // S64
  static String holidayEdit(String id) => '/holidays/$id/edit'; // S64

  // Employees (Phase 4).
  static const newEmployee = '/employees/new'; // S43
  static const employeeImport = '/employees/import'; // S46–S50
  static String employee(String id) => '/employees/$id'; // S42
  static String employeeEdit(String id) => '/employees/$id/edit'; // S44
  static String importResult(String id) =>
      '/employees/import/results/$id'; // S51
  static const employeeFields = '/settings/employee-fields'; // S45

  // Branch manager.
  static const branchDashboard = '/branch-dashboard'; // S33

  // Attendance manager.
  static const attendanceRecords = '/attendance/records'; // S53
  static const missingPunches = '/attendance/missing-punches'; // S54
  static const corrections = '/attendance/corrections'; // Q-12
  static const monthlySummary = '/attendance/monthly'; // S56
  static const attendanceExports = '/attendance/exports'; // Q-12
  static String correctAttendance(String employeeId, DateTime date) =>
      '/attendance/correct/$employeeId/${isoDate(date)}'; // S55

  // Employee self-service and leave approver.
  static const home = '/home'; // S86
  static const myAttendance = '/my/attendance'; // S87
  static const myLeave = '/my/leave'; // S90
  static const applyLeave =
      '/my/leave/apply'; // S89, ?amend= or ?type=&from=&to=
  static const leaveHistory = '/my/leave/history'; // S92
  static String myLeaveRequest(String id) => '/my/leave/$id'; // S91
  static const myHolidays = '/my/holidays'; // S93
  static const myProfile = '/my/profile'; // S94
  static String myDay(DateTime date) =>
      '/my/attendance/${isoDate(date)}'; // S88
  static const teamApprovals = '/team/approvals'; // S34

  // Demo builds only.
  static const designSystem = '/dev/design-system'; // S01, S02

  /// Reachable while signed out.
  static const signedOutPaths = {
    welcome,
    register,
    forgotPassword,
    resetPassword,
    acceptInvite,
  };

  /// Sign-in pages a signed-in member is sent away from.
  static const signInPaths = {...signedOutPaths, verifyEmail, twoStep, loading};

  /// Where each role lands after sign-in (design guide p. 4, "Lands on").
  static String homeFor(SystemRole role) => switch (role) {
    SystemRole.owner || SystemRole.hrAdmin => overview,
    SystemRole.branchManager => branchDashboard,
    SystemRole.attendanceManager => attendance,
    SystemRole.leaveApprover => teamApprovals,
    SystemRole.employee => home,
  };
}

/// "2026-10-13" for URLs.
String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Parses [isoDate] output; null when malformed.
DateTime? parseIsoDate(String? text) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(text ?? '');
  if (m == null) return null;
  final d = DateTime(
    int.parse(m.group(1)!),
    int.parse(m.group(2)!),
    int.parse(m.group(3)!),
  );
  return d.month == int.parse(m.group(2)!) ? d : null;
}
