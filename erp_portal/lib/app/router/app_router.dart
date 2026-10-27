import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/attendance/presentation/admin/attendance_exports_screen.dart';
import '../../features/attendance/presentation/admin/attendance_overview_screen.dart';
import '../../features/attendance/presentation/admin/attendance_records_screen.dart';
import '../../features/attendance/presentation/admin/correction_screen.dart';
import '../../features/attendance/presentation/admin/corrections_screen.dart';
import '../../features/attendance/presentation/admin/face_check_screen.dart';
import '../../features/attendance/presentation/admin/missing_punches_screen.dart';
import '../../features/attendance/presentation/admin/monthly_summary_screen.dart';
import '../../features/attendance/presentation/employee_home_screen.dart';
import '../../features/attendance/presentation/face_setup_screen.dart';
import '../../features/attendance/presentation/my_attendance_screen.dart';
import '../../features/audit/presentation/audit_screens.dart';
import '../../features/auth/domain/auth_state.dart';
import '../../features/auth/presentation/providers/auth_providers.dart';
import '../../features/auth/presentation/screens/accept_invite_screen.dart';
import '../../features/auth/presentation/screens/access_denied_screen.dart';
import '../../features/auth/presentation/screens/choose_organization_screen.dart';
import '../../features/auth/presentation/screens/forgot_password_screen.dart';
import '../../features/auth/presentation/screens/register_screen.dart';
import '../../features/auth/presentation/screens/reset_password_screen.dart';
import '../../features/auth/presentation/screens/two_step_screen.dart';
import '../../features/auth/presentation/screens/verify_email_screen.dart';
import '../../features/auth/presentation/screens/welcome_screen.dart';
import '../../features/dashboard/presentation/branch_dashboard_screen.dart';
import '../../features/employees/presentation/screens/employee_directory_screen.dart';
import '../../features/employees/presentation/screens/employee_form_screen.dart';
import '../../features/employees/presentation/screens/employee_profile_screen.dart';
import '../../features/employees/presentation/screens/field_builder_screen.dart';
import '../../features/employees/presentation/screens/import_wizard_screen.dart';
import '../../features/employees/presentation/screens/my_profile_screen.dart';
import '../../features/holidays/presentation/admin/holiday_calendar_screens.dart';
import '../../features/holidays/presentation/admin/holiday_form_screen.dart';
import '../../features/holidays/presentation/admin/holiday_tools_screens.dart';
import '../../features/holidays/presentation/my_holidays_screen.dart';
import '../../features/leave/presentation/admin/leave_approvals_screen.dart';
import '../../features/leave/presentation/admin/leave_records_screens.dart';
import '../../features/leave/presentation/admin/leave_settings_screens.dart';
import '../../features/leave/presentation/my_leave_screens.dart';
import '../../features/leave/presentation/team_approvals_screen.dart';
import '../../features/notifications/presentation/notification_screens.dart';
import '../../features/onboarding/presentation/screens/branch_basics_screen.dart';
import '../../features/onboarding/presentation/screens/branch_setup_screen.dart';
import '../../features/onboarding/presentation/screens/create_organization_screen.dart';
import '../../features/onboarding/presentation/screens/onboarding_start_screen.dart';
import '../../features/onboarding/presentation/screens/overview_screen.dart';
import '../../features/onboarding/presentation/screens/owner_profile_screen.dart';
import '../../features/organization/presentation/screens/branch_detail_screen.dart';
import '../../features/organization/presentation/screens/branch_edit_screen.dart';
import '../../features/organization/presentation/screens/branches_screen.dart';
import '../../features/organization/presentation/screens/organization_profile_screen.dart';
import '../../features/platform/presentation/platform_screens.dart';
import '../../features/reports/presentation/report_screens.dart';
import '../../features/roles/presentation/role_editor_screen.dart';
import '../../features/roles/presentation/roles_screens.dart';
import '../../features/settings/presentation/settings_screens.dart';
import '../config/app_config.dart';
import '../dev/design_system_gallery.dart';
import '../dev/pending_screen.dart';
import '../shell/app_shell.dart';
import 'app_destinations.dart';
import 'loading_screen.dart';
import 'not_found_screen.dart';
import 'route_guards.dart';
import 'route_names.dart';

/// The app's router. Re-evaluates guards whenever the sign-in state changes.
final appRouterProvider = Provider<GoRouter>((ref) {
  final config = ref.watch(appConfigProvider);

  final authChanges = ValueNotifier<int>(0);
  late final GoRouter router;
  ref.listen(authControllerProvider, (previous, next) {
    // Signing out starts clean: the next person to sign in must not be
    // sent back to the previous person's page.
    if (previous is SignedIn && next is SignedOut) {
      router.go(AppRoutes.welcome);
    }
    authChanges.value++;
  });
  // Role changes re-check the current page (D-53).
  ref.listen(sessionProvider, (_, _) => authChanges.value++);

  GoRoute page(String path, Widget Function(GoRouterState state) build) =>
      GoRoute(path: path, builder: (context, state) => build(state));

  NoTransitionPage<void> inShell(GoRouterState state, Widget child) =>
      NoTransitionPage(key: state.pageKey, child: child);

  // Screens built so far; other menu entries show their placeholder.
  const built = <String, Widget>{
    AppRoutes.overview: OverviewScreen(),
    AppRoutes.organization: OrganizationProfileScreen(),
    AppRoutes.branches: BranchesScreen(),
    AppRoutes.employees: EmployeeDirectoryScreen(),
    AppRoutes.branchDashboard: BranchDashboardScreen(),
    AppRoutes.attendance: AttendanceOverviewScreen(),
    AppRoutes.missingPunches: MissingPunchesScreen(),
    AppRoutes.corrections: CorrectionsScreen(),
    AppRoutes.monthlySummary: MonthlySummaryScreen(),
    AppRoutes.attendanceExports: AttendanceExportsScreen(),
    AppRoutes.faceCheck: FaceCheckScreen(),
    AppRoutes.home: EmployeeHomeScreen(),
    AppRoutes.myAttendance: MyAttendanceScreen(),
    AppRoutes.myLeave: MyLeaveScreen(),
    AppRoutes.roles: RoleDirectoryScreen(),
    AppRoutes.notifications: AdminNotificationsScreen(),
    AppRoutes.auditLog: AuditLogScreen(),
    AppRoutes.reports: ReportCenterScreen(),
    AppRoutes.myProfile: MyProfileScreen(),
    AppRoutes.teamApprovals: TeamApprovalsScreen(),
    AppRoutes.myHolidays: MyHolidaysScreen(),
    AppRoutes.holidays: HolidayCalendarScreen(),
    AppRoutes.settings: SettingsOverviewScreen(),
  };

  router = GoRouter(
    initialLocation: AppRoutes.root,
    refreshListenable: authChanges,
    redirect: (context, state) =>
        resolveRedirect(uri: state.uri, auth: effectiveAuth(ref)),
    errorBuilder: (context, state) => NotFoundScreen(path: state.uri.path),
    routes: [
      // Always redirected by the guard; never rendered.
      page(AppRoutes.root, (_) => const SizedBox.shrink()),
      page(AppRoutes.loading, (_) => const LoadingScreen()),
      page(AppRoutes.welcome, (_) => const WelcomeScreen()),
      page(AppRoutes.register, (_) => const RegisterScreen()),
      page(AppRoutes.verifyEmail, (_) => const VerifyEmailScreen()),
      page(AppRoutes.twoStep, (_) => const TwoStepScreen()),
      page(AppRoutes.forgotPassword, (_) => const ForgotPasswordScreen()),
      page(
        AppRoutes.resetPassword,
        (state) =>
            ResetPasswordScreen(token: state.uri.queryParameters['token']),
      ),
      page(
        AppRoutes.acceptInvite,
        (state) =>
            AcceptInviteScreen(token: state.uri.queryParameters['token']),
      ),
      page(
        AppRoutes.chooseOrganization,
        (_) => const ChooseOrganizationScreen(),
      ),
      page(AppRoutes.onboarding, (_) => const OnboardingStartScreen()),
      page(
        AppRoutes.createOrganization,
        (_) => const CreateOrganizationScreen(),
      ),
      // Focus pages sit outside the shell; declared before it so
      // `/branches/new` is not read as a branch ID.
      page(AppRoutes.ownerProfile, (_) => const OwnerProfileScreen()),
      page(AppRoutes.newBranch, (_) => const BranchBasicsScreen()),
      page(
        AppRoutes.branchBasics(':id'),
        (state) => BranchBasicsScreen(branchId: state.pathParameters['id']),
      ),
      page(
        AppRoutes.branchEdit(':id'),
        (state) => BranchEditScreen(branchId: state.pathParameters['id']!),
      ),
      page(AppRoutes.newHoliday, (_) => const HolidayFormScreen()),
      page(
        AppRoutes.holidayEdit(':id'),
        (state) => HolidayFormScreen(holidayId: state.pathParameters['id']),
      ),
      page(AppRoutes.newEmployee, (_) => const EmployeeFormScreen()),
      page(AppRoutes.employeeImport, (_) => const ImportWizardScreen()),
      page(
        AppRoutes.importResult(':id'),
        (state) => ImportResultScreen(recordId: state.pathParameters['id']!),
      ),
      page(
        AppRoutes.employeeEdit(':id'),
        (state) => EmployeeFormScreen(employeeId: state.pathParameters['id']),
      ),
      ShellRoute(
        builder: (context, state, child) => PlatformShell(child: child),
        routes: [
          GoRoute(
            path: AppRoutes.platform,
            pageBuilder: (context, state) =>
                inShell(state, const PlatformOverviewScreen()),
          ),
          GoRoute(
            path: AppRoutes.platformOrg(':id'),
            pageBuilder: (context, state) => inShell(
              state,
              PlatformOrgScreen(orgId: state.pathParameters['id']!),
            ),
          ),
        ],
      ),
      ShellRoute(
        builder: (context, state, child) =>
            AppShell(location: state.uri.path, child: child),
        routes: [
          for (final destination in allDestinations)
            GoRoute(
              path: destination.path,
              pageBuilder: (context, state) => inShell(
                state,
                (destination.path == AppRoutes.leave
                        ? LeaveApprovalsScreen(
                            requestId: state.uri.queryParameters['request'],
                          )
                        : null) ??
                    (destination.path == AppRoutes.attendanceRecords
                        ? AttendanceRecordsScreen(
                            date: parseIsoDate(
                              state.uri.queryParameters['date'],
                            ),
                            branchId: state.uri.queryParameters['branch'],
                          )
                        : null) ??
                    built[destination.path] ??
                    PendingScreen(
                      title: destination.label,
                      screenId: destination.screenId,
                      phase: destination.phase,
                    ),
              ),
            ),
          GoRoute(
            path: '/attendance/correct/:employeeId/:date',
            pageBuilder: (context, state) => inShell(
              state,
              CorrectionScreen(
                employeeId: state.pathParameters['employeeId']!,
                date: parseIsoDate(state.pathParameters['date']),
              ),
            ),
          ),
          GoRoute(
            path: '/my/attendance/:date',
            pageBuilder: (context, state) => inShell(
              state,
              MyDayScreen(date: parseIsoDate(state.pathParameters['date'])),
            ),
          ),
          GoRoute(
            path: AppRoutes.leaveRequests,
            pageBuilder: (context, state) =>
                inShell(state, const LeaveRequestsScreen()),
          ),
          GoRoute(
            path: AppRoutes.auditEvent(':id'),
            pageBuilder: (context, state) => inShell(
              state,
              AuditEventScreen(eventId: state.pathParameters['id']!),
            ),
          ),
          GoRoute(
            path: AppRoutes.settingsAttendance,
            pageBuilder: (context, state) =>
                inShell(state, const AttendancePolicyScreen()),
          ),
          GoRoute(
            path: AppRoutes.settingsSchedules,
            pageBuilder: (context, state) =>
                inShell(state, const SchedulesSettingsScreen()),
          ),
          GoRoute(
            path: AppRoutes.settingsNotifications,
            pageBuilder: (context, state) =>
                inShell(state, const NotificationSettingsScreen()),
          ),
          GoRoute(
            path: AppRoutes.settingsSecurity,
            pageBuilder: (context, state) =>
                inShell(state, const SecuritySettingsScreen()),
          ),
          GoRoute(
            path: AppRoutes.settingsData,
            pageBuilder: (context, state) =>
                inShell(state, const DataSettingsScreen()),
          ),
          GoRoute(
            path: AppRoutes.settingsBranding,
            pageBuilder: (context, state) =>
                inShell(state, const BrandingSettingsScreen()),
          ),
          GoRoute(
            path: AppRoutes.reportResults,
            pageBuilder: (context, state) => inShell(
              state,
              ReportResultsScreen(
                key: ValueKey(state.uri.query),
                query: state.uri.queryParameters,
              ),
            ),
          ),
          GoRoute(
            path: AppRoutes.exportHistory,
            pageBuilder: (context, state) =>
                inShell(state, const ExportHistoryScreen()),
          ),
          GoRoute(
            path: AppRoutes.myNotifications,
            pageBuilder: (context, state) =>
                inShell(state, const MyNotificationsScreen()),
          ),
          GoRoute(
            path: AppRoutes.people,
            pageBuilder: (context, state) => inShell(
              state,
              PeopleAccessScreen(roleId: state.uri.queryParameters['role']),
            ),
          ),
          GoRoute(
            path: AppRoutes.invitations,
            pageBuilder: (context, state) =>
                inShell(state, const InvitationsScreen()),
          ),
          GoRoute(
            path: AppRoutes.newRole,
            pageBuilder: (context, state) => inShell(
              state,
              RoleEditorScreen(fromId: state.uri.queryParameters['from']),
            ),
          ),
          GoRoute(
            path: AppRoutes.role(':id'),
            pageBuilder: (context, state) => inShell(
              state,
              RoleEditorScreen(
                key: ValueKey(state.pathParameters['id']),
                roleId: state.pathParameters['id'],
              ),
            ),
          ),
          GoRoute(
            path: AppRoutes.holidayList,
            pageBuilder: (context, state) =>
                inShell(state, const HolidayListScreen()),
          ),
          GoRoute(
            path: AppRoutes.holidayImport,
            pageBuilder: (context, state) =>
                inShell(state, const HolidayImportScreen()),
          ),
          GoRoute(
            path: AppRoutes.schedules,
            pageBuilder: (context, state) =>
                inShell(state, const SchedulesScreen()),
          ),
          GoRoute(
            path: AppRoutes.leaveTypes,
            pageBuilder: (context, state) =>
                inShell(state, const LeaveTypesScreen()),
          ),
          GoRoute(
            path: AppRoutes.leavePolicy,
            pageBuilder: (context, state) =>
                inShell(state, const LeavePolicyScreen()),
          ),
          GoRoute(
            path: AppRoutes.leaveBalances,
            pageBuilder: (context, state) =>
                inShell(state, const LeaveBalancesScreen()),
          ),
          GoRoute(
            path: AppRoutes.applyLeave,
            pageBuilder: (context, state) => inShell(
              state,
              ApplyLeaveScreen(
                amendId: state.uri.queryParameters['amend'],
                initialType: state.uri.queryParameters['type'],
                initialFrom: parseIsoDate(state.uri.queryParameters['from']),
                initialTo: parseIsoDate(state.uri.queryParameters['to']),
              ),
            ),
          ),
          GoRoute(
            path: AppRoutes.myFace,
            pageBuilder: (context, state) =>
                inShell(state, const FaceSetupScreen()),
          ),
          GoRoute(
            path: AppRoutes.leaveHistory,
            pageBuilder: (context, state) =>
                inShell(state, const LeaveHistoryScreen()),
          ),
          GoRoute(
            path: AppRoutes.myLeaveRequest(':id'),
            pageBuilder: (context, state) => inShell(
              state,
              LeaveRequestScreen(requestId: state.pathParameters['id']!),
            ),
          ),
          GoRoute(
            path: AppRoutes.employeeFields,
            pageBuilder: (context, state) =>
                inShell(state, const FieldBuilderScreen()),
          ),
          GoRoute(
            path: AppRoutes.employee(':id'),
            pageBuilder: (context, state) => inShell(
              state,
              EmployeeProfileScreen(employeeId: state.pathParameters['id']!),
            ),
          ),
          GoRoute(
            path: AppRoutes.branch(':id'),
            pageBuilder: (context, state) => inShell(
              state,
              BranchDetailScreen(branchId: state.pathParameters['id']!),
            ),
          ),
          GoRoute(
            path: AppRoutes.branchSetup(':id'),
            pageBuilder: (context, state) => inShell(
              state,
              BranchSetupScreen(
                branchId: state.pathParameters['id']!,
                openStep: state.uri.queryParameters['step'],
              ),
            ),
          ),
          GoRoute(
            path: AppRoutes.accessDenied,
            pageBuilder: (context, state) => inShell(
              state,
              AccessDeniedScreen(from: state.uri.queryParameters['from']),
            ),
          ),
          if (config.showDevTools)
            GoRoute(
              path: AppRoutes.designSystem,
              pageBuilder: (context, state) =>
                  inShell(state, const DesignSystemGallery()),
            ),
        ],
      ),
    ],
  );

  ref.onDispose(router.dispose);
  ref.onDispose(authChanges.dispose);
  return router;
});
