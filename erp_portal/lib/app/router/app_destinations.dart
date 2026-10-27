import 'package:flutter/material.dart';

import '../../core/permissions/permissions.dart';
import '../../core/permissions/system_roles.dart';
import 'route_names.dart';

/// A page in a role's menu.
class AppDestination {
  const AppDestination({
    required this.label,
    required this.icon,
    required this.path,
    required this.screenId,
    required this.phase,
    this.module,
    this.section,
  });

  final String label;
  final IconData icon;
  final String path;

  /// Design screen this page implements (docs/screen_inventory.md).
  final String screenId;

  /// Implementation phase that builds the page.
  final int phase;

  /// Module the member needs `view` on. Null means every signed-in member.
  final PermissionModule? module;

  /// Menu group heading, e.g. "ME", "MY TEAM" (board S34).
  final String? section;

  bool matches(String location) =>
      location == path || location.startsWith('$path/');
}

// Shared entries.
const _employees = AppDestination(
  label: 'Employees',
  icon: Icons.people_outline,
  path: AppRoutes.employees,
  screenId: 'S39',
  phase: 4,
  module: PermissionModule.employees,
);
const _holidays = AppDestination(
  label: 'Holidays & Calendar',
  icon: Icons.calendar_month_outlined,
  path: AppRoutes.holidays,
  screenId: 'S62',
  phase: 6,
  module: PermissionModule.holidays,
);
const _leave = AppDestination(
  label: 'Leave Management',
  icon: Icons.event_available_outlined,
  path: AppRoutes.leave,
  screenId: 'S57',
  phase: 6,
  module: PermissionModule.leave,
);
const _reports = AppDestination(
  label: 'Reports & Analytics',
  icon: Icons.bar_chart_outlined,
  path: AppRoutes.reports,
  screenId: 'S73',
  phase: 7,
  module: PermissionModule.reports,
);

/// Owner and HR-admin menu in design order (board S30). Items are shown
/// only when the role can view the module (Q-04).
const adminDestinations = <AppDestination>[
  AppDestination(
    label: 'Overview',
    icon: Icons.grid_view_outlined,
    path: AppRoutes.overview,
    screenId: 'S30',
    phase: 4,
    module: PermissionModule.reports,
  ),
  AppDestination(
    label: 'Organization',
    icon: Icons.apartment_outlined,
    path: AppRoutes.organization,
    screenId: 'S35',
    phase: 3,
    module: PermissionModule.organization,
  ),
  AppDestination(
    label: 'Branches',
    icon: Icons.location_on_outlined,
    path: AppRoutes.branches,
    screenId: 'S36',
    phase: 3,
    module: PermissionModule.organization,
  ),
  _employees,
  AppDestination(
    label: 'Attendance',
    icon: Icons.schedule_outlined,
    path: AppRoutes.attendance,
    screenId: 'S52',
    phase: 5,
    module: PermissionModule.attendance,
  ),
  _leave,
  _holidays,
  AppDestination(
    label: 'Roles & Permissions',
    icon: Icons.verified_user_outlined,
    path: AppRoutes.roles,
    screenId: 'S67',
    phase: 7,
    module: PermissionModule.roles,
  ),
  _reports,
  AppDestination(
    label: 'Notifications',
    icon: Icons.notifications_none_outlined,
    path: AppRoutes.notifications,
    screenId: 'S76',
    phase: 7,
  ),
  AppDestination(
    label: 'Settings',
    icon: Icons.tune_outlined,
    path: AppRoutes.settings,
    screenId: 'S80',
    phase: 7,
    module: PermissionModule.settings,
  ),
  AppDestination(
    label: 'Audit Log',
    icon: Icons.receipt_long_outlined,
    path: AppRoutes.auditLog,
    screenId: 'S77',
    phase: 7,
    module: PermissionModule.auditLog,
  ),
];

/// Board S33 sidebar.
const branchManagerDestinations = <AppDestination>[
  AppDestination(
    label: 'Branch dashboard',
    icon: Icons.grid_view_outlined,
    path: AppRoutes.branchDashboard,
    screenId: 'S33',
    phase: 4,
    module: PermissionModule.reports,
  ),
  _employees,
  AppDestination(
    label: 'Attendance exceptions',
    icon: Icons.schedule_outlined,
    path: AppRoutes.attendance,
    screenId: 'S53',
    phase: 5,
    module: PermissionModule.attendance,
  ),
  AppDestination(
    label: 'Leave approvals',
    icon: Icons.event_available_outlined,
    path: AppRoutes.leave,
    screenId: 'S57',
    phase: 6,
    module: PermissionModule.leave,
  ),
  AppDestination(
    label: 'Holidays',
    icon: Icons.calendar_month_outlined,
    path: AppRoutes.holidays,
    screenId: 'S62',
    phase: 6,
    module: PermissionModule.holidays,
  ),
  AppDestination(
    label: 'Branch reports',
    icon: Icons.bar_chart_outlined,
    path: AppRoutes.reports,
    screenId: 'S73',
    phase: 7,
    module: PermissionModule.reports,
  ),
];

/// Board S52 sidebar.
const attendanceManagerDestinations = <AppDestination>[
  AppDestination(
    label: 'Attendance overview',
    icon: Icons.grid_view_outlined,
    path: AppRoutes.attendance,
    screenId: 'S52',
    phase: 5,
    module: PermissionModule.attendance,
  ),
  AppDestination(
    label: 'Records',
    icon: Icons.schedule_outlined,
    path: AppRoutes.attendanceRecords,
    screenId: 'S53',
    phase: 5,
    module: PermissionModule.attendance,
  ),
  AppDestination(
    label: 'Missing punches',
    icon: Icons.warning_amber_outlined,
    path: AppRoutes.missingPunches,
    screenId: 'S54',
    phase: 5,
    module: PermissionModule.attendance,
  ),
  AppDestination(
    label: 'Corrections',
    icon: Icons.edit_outlined,
    path: AppRoutes.corrections,
    screenId: 'S55',
    phase: 5,
    module: PermissionModule.attendance,
  ),
  AppDestination(
    label: 'Monthly summary',
    icon: Icons.calendar_today_outlined,
    path: AppRoutes.monthlySummary,
    screenId: 'S56',
    phase: 5,
    module: PermissionModule.attendance,
  ),
  AppDestination(
    label: 'Attendance exports',
    icon: Icons.bar_chart_outlined,
    path: AppRoutes.attendanceExports,
    screenId: 'S73',
    phase: 5,
    module: PermissionModule.attendance,
  ),
  AppDestination(
    label: 'Face check',
    icon: Icons.face_retouching_natural_outlined,
    path: AppRoutes.faceCheck,
    screenId: 'D-70',
    phase: 9,
    module: PermissionModule.attendance,
  ),
];

/// Employee self-service: phone bottom tabs (board S86) and, on wider
/// screens, the sidebar (Q-03).
const employeeDestinations = <AppDestination>[
  AppDestination(
    label: 'Home',
    icon: Icons.home_outlined,
    path: AppRoutes.home,
    screenId: 'S86',
    phase: 5,
    section: 'ME',
  ),
  AppDestination(
    label: 'Attendance',
    icon: Icons.schedule_outlined,
    path: AppRoutes.myAttendance,
    screenId: 'S87',
    phase: 5,
    section: 'ME',
  ),
  AppDestination(
    label: 'Leave',
    icon: Icons.event_available_outlined,
    path: AppRoutes.myLeave,
    screenId: 'S90',
    phase: 6,
    section: 'ME',
  ),
  AppDestination(
    label: 'Holidays',
    icon: Icons.calendar_month_outlined,
    path: AppRoutes.myHolidays,
    screenId: 'S93',
    phase: 6,
    section: 'ME',
  ),
  AppDestination(
    label: 'Profile',
    icon: Icons.person_outline,
    path: AppRoutes.myProfile,
    screenId: 'S94',
    phase: 4,
    section: 'ME',
  ),
];

/// Board S34: the approver's own items plus their team. "Team calendar" is
/// not designed and stays hidden (Q-12).
const leaveApproverDestinations = <AppDestination>[
  ...employeeDestinations,
  AppDestination(
    label: 'Approvals',
    icon: Icons.fact_check_outlined,
    path: AppRoutes.teamApprovals,
    screenId: 'S34',
    phase: 6,
    module: PermissionModule.leave,
    section: 'MY TEAM',
  ),
];

/// Every routed page, once per path (first definition wins).
final List<AppDestination> allDestinations = () {
  final seen = <String>{};
  return [
    for (final d in [
      ...adminDestinations,
      ...branchManagerDestinations,
      ...attendanceManagerDestinations,
      ...leaveApproverDestinations,
    ])
      if (seen.add(d.path)) d,
  ];
}();

List<AppDestination> menuFor(SystemRole role) => switch (role) {
  SystemRole.owner || SystemRole.hrAdmin => adminDestinations,
  SystemRole.branchManager => branchManagerDestinations,
  SystemRole.attendanceManager => attendanceManagerDestinations,
  SystemRole.leaveApprover => leaveApproverDestinations,
  SystemRole.employee => employeeDestinations,
};

/// The role's menu, minus items its permissions don't allow.
List<AppDestination> visibleDestinations(
  SystemRole role,
  PermissionSet permissions,
) => [
  for (final d in menuFor(role))
    if (d.module == null || permissions.canView(d.module!)) d,
];

/// The most specific destination for [location] in [destinations].
AppDestination? bestMatch(
  String location,
  Iterable<AppDestination> destinations,
) {
  AppDestination? best;
  for (final d in destinations) {
    if (d.matches(location) &&
        (best == null || d.path.length > best.path.length)) {
      best = d;
    }
  }
  return best;
}
