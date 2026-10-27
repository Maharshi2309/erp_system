import 'package:erp_portal/app/router/app_destinations.dart';
import 'package:erp_portal/app/router/route_guards.dart';
import 'package:erp_portal/app/router/route_names.dart';
import 'package:erp_portal/core/permissions/system_roles.dart';
import 'package:erp_portal/features/auth/domain/auth_models.dart';
import 'package:erp_portal/features/auth/domain/auth_state.dart';
import 'package:erp_portal/shared/models/app_session.dart';
import 'package:flutter_test/flutter_test.dart';

const _account = UserAccount(id: 'u', fullName: 'Ankit Patel', email: 'a@x.in');

SignedIn signedInAs(SystemRole role, {bool canSwitch = false}) => SignedIn(
  _account,
  AppSession(
    userId: 'u',
    displayName: 'Ankit Patel',
    email: 'a@x.in',
    organizationId: 'org',
    organizationName: 'Meridian Textiles',
    role: role,
    canSwitchOrganization: canSwitch,
  ),
  const [],
);

String? go(String location, AuthState auth) =>
    resolveRedirect(uri: Uri.parse(location), auth: auth);

Uri goUri(String location, AuthState auth) => Uri.parse(go(location, auth)!);

void main() {
  group('while restoring a saved session', () {
    test('every page waits on /loading, remembering the target', () {
      final uri = goUri('/employees', const RestoringSession());
      expect(uri.path, AppRoutes.loading);
      expect(uri.queryParameters['from'], '/employees');
    });
    test('/loading itself is allowed', () {
      expect(go(AppRoutes.loading, const RestoringSession()), isNull);
    });
  });

  group('signed out', () {
    const out = SignedOut();
    test('root goes to welcome', () => expect(go('/', out), AppRoutes.welcome));

    test('sign-in pages are open', () {
      for (final path in AppRoutes.signedOutPaths) {
        expect(go(path, out), isNull, reason: path);
      }
    });

    test('protected pages go to welcome, keeping the target', () {
      final uri = goUri('/employees?branch=surat', out);
      expect(uri.path, AppRoutes.welcome);
      expect(uri.queryParameters['from'], '/employees?branch=surat');
    });

    test('finishing restore with nothing saved resumes the target', () {
      expect(go('/loading?from=/register', out), '/register');
      expect(go(AppRoutes.loading, out), AppRoutes.welcome);
    });

    test('two-step page needs a pending sign-in', () {
      expect(goUri(AppRoutes.twoStep, out).path, AppRoutes.welcome);
    });
  });

  group('mid sign-in', () {
    test('awaiting two-step: only the code page', () {
      const state = AwaitingTwoStep(_account);
      expect(go(AppRoutes.twoStep, state), isNull);
      final uri = goUri('/welcome?from=/leave', state);
      expect(uri.path, AppRoutes.twoStep);
      expect(uri.queryParameters['from'], '/leave');
    });

    test('awaiting email code: verify page or back to register', () {
      const state = AwaitingEmailVerification('a@x.in');
      expect(go(AppRoutes.verifyEmail, state), isNull);
      expect(go(AppRoutes.register, state), isNull);
      expect(goUri('/overview', state).path, AppRoutes.verifyEmail);
    });

    test('choosing an organization: selector or onboarding', () {
      const state = AwaitingOrganizationChoice(_account, []);
      expect(go(AppRoutes.chooseOrganization, state), isNull);
      expect(go(AppRoutes.onboarding, state), isNull);
      expect(goUri('/overview', state).path, AppRoutes.chooseOrganization);
    });

    test('no organization yet: onboarding (and the verified page)', () {
      const state = NeedsOrganization(_account);
      expect(go(AppRoutes.onboarding, state), isNull);
      expect(go(AppRoutes.verifyEmail, state), isNull);
      expect(goUri('/overview', state).path, AppRoutes.onboarding);
    });
  });

  group('signed in', () {
    test('root goes to the role’s home', () {
      final homes = {
        SystemRole.owner: AppRoutes.overview,
        SystemRole.hrAdmin: AppRoutes.overview,
        SystemRole.branchManager: AppRoutes.branchDashboard,
        SystemRole.attendanceManager: AppRoutes.attendance,
        SystemRole.leaveApprover: AppRoutes.teamApprovals,
        SystemRole.employee: AppRoutes.home,
      };
      homes.forEach((role, home) {
        expect(go('/', signedInAs(role)), home, reason: role.name);
      });
    });

    test('sign-in pages send members home, or to the remembered target', () {
      final owner = signedInAs(SystemRole.owner);
      expect(go(AppRoutes.welcome, owner), AppRoutes.overview);
      expect(go('/sign-in/verify?from=/leave', owner), '/leave');
    });

    test('remembered targets must be same-site paths', () {
      final owner = signedInAs(SystemRole.owner);
      expect(
        go('/welcome?from=https://evil.example', owner),
        AppRoutes.overview,
      );
      expect(go('/welcome?from=//evil.example', owner), AppRoutes.overview);
    });

    test('owner may open every page', () {
      for (final d in allDestinations) {
        expect(
          go(d.path, signedInAs(SystemRole.owner)),
          isNull,
          reason: d.path,
        );
      }
    });

    test('HR admin sees organization and branches but not roles', () {
      // Answer of 20 Oct 2026: HR sees every branch; only the owner edits.
      final hr = signedInAs(SystemRole.hrAdmin);
      expect(go(AppRoutes.organization, hr), isNull);
      expect(go(AppRoutes.branches, hr), isNull);
      expect(go(AppRoutes.branch('b-sur'), hr), isNull);
      for (final path in [
        AppRoutes.roles,
        AppRoutes.newBranch,
        AppRoutes.branchEdit('b-sur'),
      ]) {
        final uri = goUri(path, hr);
        expect(uri.path, AppRoutes.accessDenied, reason: path);
        expect(uri.queryParameters['from'], path);
      }
    });

    test('employee is denied admin pages but reaches self-service', () {
      final employee = signedInAs(SystemRole.employee);
      for (final path in [
        AppRoutes.overview,
        AppRoutes.employees,
        AppRoutes.teamApprovals,
      ]) {
        expect(
          goUri(path, employee).path,
          AppRoutes.accessDenied,
          reason: path,
        );
      }
      for (final d in employeeDestinations) {
        expect(go(d.path, employee), isNull, reason: d.path);
      }
    });

    test('nested paths use the most specific rule', () {
      final attendance = signedInAs(SystemRole.attendanceManager);
      expect(go(AppRoutes.missingPunches, attendance), isNull);
      expect(
        goUri('/roles/branch-manager', attendance).path,
        AppRoutes.accessDenied,
      );
    });

    test('organization selector only for members of several', () {
      expect(
        go(AppRoutes.chooseOrganization, signedInAs(SystemRole.owner)),
        AppRoutes.overview,
      );
      expect(
        go(
          AppRoutes.chooseOrganization,
          signedInAs(SystemRole.owner, canSwitch: true),
        ),
        isNull,
      );
    });
  });

  group('menus', () {
    List<String> labels(SystemRole role) => visibleDestinations(
      role,
      role.permissions,
    ).map((d) => d.label).toList();

    test('owner: the full admin menu (board S30)', () {
      expect(labels(SystemRole.owner), [
        'Overview',
        'Organization',
        'Branches',
        'Employees',
        'Attendance',
        'Leave Management',
        'Holidays & Calendar',
        'Roles & Permissions',
        'Reports & Analytics',
        'Notifications',
        'Settings',
        'Audit Log',
      ]);
    });

    test('HR admin: admin menu without roles', () {
      expect(labels(SystemRole.hrAdmin), [
        'Overview',
        'Organization',
        'Branches',
        'Employees',
        'Attendance',
        'Leave Management',
        'Holidays & Calendar',
        'Reports & Analytics',
        'Notifications',
        'Settings',
        'Audit Log',
      ]);
    });

    test('branch manager: board S33 menu', () {
      expect(labels(SystemRole.branchManager), [
        'Branch dashboard',
        'Employees',
        'Attendance exceptions',
        'Leave approvals',
        'Holidays',
        'Branch reports',
      ]);
    });

    test('attendance manager: board S52 menu', () {
      expect(labels(SystemRole.attendanceManager), [
        'Attendance overview',
        'Records',
        'Missing punches',
        'Corrections',
        'Monthly summary',
        'Attendance exports',
        'Face check', // D-70
      ]);
    });

    test('leave approver: ME items plus team approvals (board S34)', () {
      expect(labels(SystemRole.leaveApprover), [
        'Home',
        'Attendance',
        'Leave',
        'Holidays',
        'Profile',
        'Approvals',
      ]);
    });

    test('employee: the five phone tabs (board S86)', () {
      expect(labels(SystemRole.employee), [
        'Home',
        'Attendance',
        'Leave',
        'Holidays',
        'Profile',
      ]);
    });

    test('every home page is in that role’s visible menu', () {
      for (final role in SystemRole.values) {
        final paths = visibleDestinations(
          role,
          role.permissions,
        ).map((d) => d.path);
        expect(paths, contains(AppRoutes.homeFor(role)), reason: role.name);
      }
    });

    test('bestMatch prefers the most specific path', () {
      expect(
        bestMatch(
          '/attendance/records/today',
          attendanceManagerDestinations,
        )?.label,
        'Records',
      );
      expect(bestMatch('/leaves', allDestinations), isNull);
    });
  });

  group('organization and branch setup (Phase 3)', () {
    test('a new account can open the create-organization form', () {
      const needs = NeedsOrganization(_account);
      expect(go(AppRoutes.createOrganization, needs), isNull);
      expect(go(AppRoutes.branches, needs), startsWith(AppRoutes.onboarding));
      const choosing = AwaitingOrganizationChoice(_account, []);
      expect(go(AppRoutes.createOrganization, choosing), isNull);
    });

    const editPaths = [
      AppRoutes.ownerProfile,
      AppRoutes.newBranch,
      '/branches/b-sur/edit',
      '/branches/b-sur/basics',
      '/branches/b-sur/setup',
    ];

    test('the owner can open every setup and edit page', () {
      for (final path in editPaths) {
        expect(go(path, signedInAs(SystemRole.owner)), isNull, reason: path);
      }
      expect(go('/branches/b-sur', signedInAs(SystemRole.owner)), isNull);
    });

    test('roles that cannot edit the organization are refused', () {
      for (final role in [SystemRole.branchManager, SystemRole.employee]) {
        for (final path in editPaths) {
          final uri = goUri(path, signedInAs(role));
          expect(uri.path, AppRoutes.accessDenied, reason: '$role $path');
          expect(uri.queryParameters['from'], path);
        }
      }
    });
  });

  group('employees (Phase 4)', () {
    test('owner and HR admin reach every employee page', () {
      for (final role in [SystemRole.owner, SystemRole.hrAdmin]) {
        for (final path in [
          AppRoutes.employees,
          AppRoutes.newEmployee,
          AppRoutes.employee('e-1'),
          AppRoutes.employeeEdit('e-1'),
          AppRoutes.employeeImport,
          AppRoutes.importResult('imp-1'),
          AppRoutes.employeeFields,
        ]) {
          expect(go(path, signedInAs(role)), isNull, reason: '$role $path');
        }
      }
    });

    test('branch managers can add and edit but not import or edit fields', () {
      final bm = signedInAs(SystemRole.branchManager);
      expect(go(AppRoutes.newEmployee, bm), isNull);
      expect(go(AppRoutes.employeeEdit('e-1'), bm), isNull);
      expect(goUri(AppRoutes.employeeImport, bm).path, AppRoutes.accessDenied);
      expect(goUri(AppRoutes.employeeFields, bm).path, AppRoutes.accessDenied);
    });

    test('employees and attendance managers have no directory', () {
      for (final role in [
        SystemRole.employee,
        SystemRole.attendanceManager,
        SystemRole.leaveApprover,
      ]) {
        expect(
          goUri(AppRoutes.employees, signedInAs(role)).path,
          AppRoutes.accessDenied,
        );
        expect(
          goUri(AppRoutes.employee('e-1'), signedInAs(role)).path,
          AppRoutes.accessDenied,
        );
      }
    });
  });

  group('attendance (Phase 5)', () {
    final correct = AppRoutes.correctAttendance('e-1', DateTime(2026, 10, 13));

    test('attendance roles reach every attendance page', () {
      for (final role in [
        SystemRole.owner,
        SystemRole.hrAdmin,
        SystemRole.attendanceManager,
        SystemRole.branchManager,
      ]) {
        for (final path in [
          AppRoutes.attendance,
          AppRoutes.attendanceRecords,
          AppRoutes.missingPunches,
          AppRoutes.corrections,
          AppRoutes.monthlySummary,
          AppRoutes.attendanceExports,
          correct,
        ]) {
          expect(go(path, signedInAs(role)), isNull, reason: '$role $path');
        }
      }
    });

    test('employees and approvers only see their own attendance', () {
      for (final role in [SystemRole.employee, SystemRole.leaveApprover]) {
        expect(
          goUri(AppRoutes.attendanceRecords, signedInAs(role)).path,
          AppRoutes.accessDenied,
        );
        expect(goUri(correct, signedInAs(role)).path, AppRoutes.accessDenied);
        expect(go(AppRoutes.myAttendance, signedInAs(role)), isNull);
        expect(
          go(AppRoutes.myDay(DateTime(2026, 10, 13)), signedInAs(role)),
          isNull,
        );
      }
    });

    test('dates in URLs round-trip', () {
      expect(isoDate(DateTime(2026, 1, 5)), '2026-01-05');
      expect(parseIsoDate('2026-01-05'), DateTime(2026, 1, 5));
      expect(parseIsoDate('2026-02-30'), isNull);
      expect(parseIsoDate('yesterday'), isNull);
    });
  });

  group('leave and holidays (Phase 6)', () {
    String? at(String path, SystemRole role) => go(path, signedInAs(role));
    bool denied(String path, SystemRole role) =>
        goUri(path, signedInAs(role)).path == AppRoutes.accessDenied;

    final settingsPages = [AppRoutes.leaveTypes, AppRoutes.leavePolicy];
    final holidayEdits = [
      AppRoutes.newHoliday,
      AppRoutes.holidayEdit('hol-9'),
      AppRoutes.holidayImport,
    ];

    test('owner and HR reach every leave and holiday page', () {
      for (final role in [SystemRole.owner, SystemRole.hrAdmin]) {
        for (final path in [
          AppRoutes.leave,
          AppRoutes.leaveRequests,
          AppRoutes.leaveBalances,
          ...settingsPages,
          AppRoutes.holidays,
          AppRoutes.holidayList,
          AppRoutes.schedules,
          ...holidayEdits,
        ]) {
          expect(at(path, role), isNull, reason: '$role $path');
        }
      }
    });

    test('branch managers decide leave but can’t change rules or holidays', () {
      const bm = SystemRole.branchManager;
      for (final path in [
        AppRoutes.leave,
        AppRoutes.leaveRequests,
        AppRoutes.leaveBalances,
        AppRoutes.holidays,
        AppRoutes.holidayList,
        AppRoutes.schedules,
      ]) {
        expect(at(path, bm), isNull, reason: path);
      }
      for (final path in [...settingsPages, ...holidayEdits]) {
        expect(denied(path, bm), isTrue, reason: path);
      }
    });

    test('leave approvers have their team inbox, not leave management', () {
      const la = SystemRole.leaveApprover;
      expect(at(AppRoutes.teamApprovals, la), isNull);
      expect(at(AppRoutes.leave, la), isNull);
      for (final path in [...settingsPages, AppRoutes.holidays]) {
        expect(denied(path, la), isTrue, reason: path);
      }
    });

    test('employees only reach their own leave and holidays', () {
      const e = SystemRole.employee;
      for (final path in [
        AppRoutes.myLeave,
        AppRoutes.applyLeave,
        AppRoutes.leaveHistory,
        AppRoutes.myLeaveRequest('L-1'),
        AppRoutes.myHolidays,
      ]) {
        expect(at(path, e), isNull, reason: path);
      }
      for (final path in [
        AppRoutes.leave,
        AppRoutes.teamApprovals,
        AppRoutes.leaveBalances,
        AppRoutes.holidays,
        ...holidayEdits,
      ]) {
        expect(denied(path, e), isTrue, reason: path);
      }
    });
  });

  group('roles, settings, reports, notifications, audit (Phase 7)', () {
    String? at(String path, SystemRole role) => go(path, signedInAs(role));
    bool denied(String path, SystemRole role) =>
        goUri(path, signedInAs(role)).path == AppRoutes.accessDenied;

    test('only the owner reaches roles, security and data settings', () {
      for (final path in [
        AppRoutes.roles,
        AppRoutes.people,
        AppRoutes.newRole,
        AppRoutes.role('branchManager'),
        AppRoutes.settingsSecurity,
        AppRoutes.settingsData,
      ]) {
        expect(at(path, SystemRole.owner), isNull, reason: path);
        for (final role in [
          SystemRole.hrAdmin,
          SystemRole.branchManager,
          SystemRole.employee,
        ]) {
          expect(denied(path, role), isTrue, reason: '$role $path');
        }
      }
    });

    test('invitations follow the right to invite people', () {
      expect(at(AppRoutes.invitations, SystemRole.owner), isNull);
      expect(at(AppRoutes.invitations, SystemRole.hrAdmin), isNull);
      expect(at(AppRoutes.invitations, SystemRole.branchManager), isNull);
      expect(
        denied(AppRoutes.invitations, SystemRole.attendanceManager),
        isTrue,
      );
      expect(denied(AppRoutes.invitations, SystemRole.employee), isTrue);
    });

    test('settings pages need settings access', () {
      for (final path in [
        AppRoutes.settings,
        AppRoutes.settingsAttendance,
        AppRoutes.settingsSchedules,
        AppRoutes.settingsNotifications,
        AppRoutes.settingsBranding,
      ]) {
        expect(at(path, SystemRole.hrAdmin), isNull, reason: path);
        expect(denied(path, SystemRole.branchManager), isTrue, reason: path);
        expect(denied(path, SystemRole.employee), isTrue, reason: path);
      }
    });

    test('reports and the audit log follow their modules', () {
      for (final path in [
        AppRoutes.reports,
        AppRoutes.reportResults,
        AppRoutes.exportHistory,
      ]) {
        expect(at(path, SystemRole.hrAdmin), isNull, reason: path);
        expect(at(path, SystemRole.branchManager), isNull, reason: path);
        expect(
          denied(path, SystemRole.attendanceManager),
          isTrue,
          reason: path,
        );
        expect(denied(path, SystemRole.employee), isTrue, reason: path);
      }
      expect(at(AppRoutes.auditLog, SystemRole.hrAdmin), isNull);
      expect(at(AppRoutes.auditEvent('evt_1'), SystemRole.hrAdmin), isNull);
      expect(denied(AppRoutes.auditLog, SystemRole.branchManager), isTrue);
    });

    test('everyone has notifications and their profile', () {
      for (final role in SystemRole.values) {
        expect(at(AppRoutes.notifications, role), isNull, reason: '$role');
        expect(at(AppRoutes.myNotifications, role), isNull, reason: '$role');
        expect(at(AppRoutes.myProfile, role), isNull, reason: '$role');
      }
    });
  });
}
