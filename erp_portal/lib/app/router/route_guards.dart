import '../../core/permissions/permissions.dart';
import '../../features/auth/domain/auth_state.dart';
import 'app_destinations.dart';
import 'route_names.dart';

/// Decides where a navigation should go instead, or null to allow it.
///
/// A pure function so every rule is unit-tested. This is a usability guard:
/// the backend must still authorise every request (PRD §11).
String? resolveRedirect({required Uri uri, required AuthState auth}) {
  final path = uri.path;
  final from = _safeReturnPath(uri.queryParameters['from']);

  /// [target], remembering the page the person was trying to open.
  String keepingTarget(String target) {
    final original = from ?? (path == AppRoutes.root ? null : uri.toString());
    return Uri(
      path: target,
      queryParameters: original == null ? null : {'from': original},
    ).toString();
  }

  String? onlyAllow(Set<String> allowed, String fallback) =>
      allowed.contains(path) ? null : keepingTarget(fallback);

  switch (auth) {
    case RestoringSession():
      return path == AppRoutes.loading
          ? null
          : keepingTarget(AppRoutes.loading);

    case SignedOut():
      if (path == AppRoutes.loading) return from ?? AppRoutes.welcome;
      if (AppRoutes.signedOutPaths.contains(path)) return null;
      return keepingTarget(AppRoutes.welcome);

    case AwaitingEmailVerification():
      return onlyAllow({
        AppRoutes.verifyEmail,
        AppRoutes.register,
      }, AppRoutes.verifyEmail);

    case AwaitingTwoStep():
      return onlyAllow({AppRoutes.twoStep}, AppRoutes.twoStep);

    case AwaitingOrganizationChoice():
      return onlyAllow({
        AppRoutes.chooseOrganization,
        AppRoutes.onboarding,
        AppRoutes.createOrganization,
      }, AppRoutes.chooseOrganization);

    case NeedsOrganization():
      // The verify page stays open long enough to show "Email verified".
      return onlyAllow({
        AppRoutes.onboarding,
        AppRoutes.createOrganization,
        AppRoutes.verifyEmail,
      }, AppRoutes.onboarding);

    case PlatformSignedIn():
      // The platform admin has no organization: platform pages only.
      if (path == AppRoutes.platform || path.startsWith('/platform/')) {
        return null;
      }
      return AppRoutes.platform;

    case SignedIn(:final session):
      final home = AppRoutes.homeFor(session.role);
      if (path == AppRoutes.root) return home;
      // Organization members never reach platform pages.
      if (path == AppRoutes.platform || path.startsWith('/platform/')) {
        return Uri(
          path: AppRoutes.accessDenied,
          queryParameters: {'from': path},
        ).toString();
      }
      if (AppRoutes.signInPaths.contains(path)) return from ?? home;
      if (path == AppRoutes.chooseOrganization &&
          !session.canSwitchOrganization) {
        return home;
      }
      // Invitations sit under Roles but belong to whoever invites people.
      final module = switch (path) {
        AppRoutes.invitations => PermissionModule.employees,
        // Under Settings, but its own permission (D-73).
        AppRoutes.employeeFields => PermissionModule.employeeFields,
        _ => bestMatch(path, allDestinations)?.module,
      };
      final denied =
          (module != null && !session.permissions.canView(module)) ||
          _requiredFor(
            path,
          ).any((p) => !session.permissions.can(p.module, p.action));
      if (denied) {
        return Uri(
          path: AppRoutes.accessDenied,
          queryParameters: {'from': path},
        ).toString();
      }
      return null;
  }
}

/// Extra permissions a page needs beyond viewing its module.
List<Permission> _requiredFor(String path) {
  const orgEdit = Permission(
    PermissionModule.organization,
    PermissionAction.edit,
  );
  if (path == AppRoutes.ownerProfile ||
      path == AppRoutes.newBranch ||
      RegExp(r'^/branches/[^/]+/(edit|basics|setup)$').hasMatch(path)) {
    return const [orgEdit];
  }
  if (path == AppRoutes.newEmployee) {
    return const [
      Permission(PermissionModule.employees, PermissionAction.create),
    ];
  }
  if (path.startsWith('${AppRoutes.employeeImport}/results/')) {
    return const [
      Permission(PermissionModule.importExport, PermissionAction.view),
    ];
  }
  if (path == AppRoutes.employeeImport) {
    return const [
      Permission(PermissionModule.importExport, PermissionAction.create),
      Permission(PermissionModule.employees, PermissionAction.create),
    ];
  }
  if (RegExp(r'^/employees/[^/]+/edit$').hasMatch(path)) {
    return const [
      Permission(PermissionModule.employees, PermissionAction.edit),
    ];
  }
  if (path.startsWith('/attendance/correct/')) {
    return const [
      Permission(PermissionModule.attendance, PermissionAction.correct),
    ];
  }
  if (path == AppRoutes.attendanceExports) {
    return const [
      Permission(PermissionModule.attendance, PermissionAction.export),
    ];
  }
  // Owner-only settings use the owner-only roles permission (D-58).
  if (path == AppRoutes.settingsSecurity || path == AppRoutes.settingsData) {
    return const [Permission(PermissionModule.roles, PermissionAction.edit)];
  }
  if (path == AppRoutes.invitations) {
    return const [
      Permission(PermissionModule.employees, PermissionAction.create),
    ];
  }
  if (path == AppRoutes.newRole) {
    return const [Permission(PermissionModule.roles, PermissionAction.create)];
  }
  if (path == AppRoutes.leaveTypes || path == AppRoutes.leavePolicy) {
    return const [Permission(PermissionModule.leave, PermissionAction.edit)];
  }
  if (path == AppRoutes.newHoliday ||
      path == AppRoutes.holidayImport ||
      RegExp(r'^/holidays/[^/]+/edit$').hasMatch(path)) {
    return const [
      Permission(PermissionModule.holidays, PermissionAction.create),
    ];
  }
  return const [];
}

/// Only same-site paths are followed after sign-in (no open redirects).
String? _safeReturnPath(String? from) {
  if (from == null || !from.startsWith('/') || from.startsWith('//')) {
    return null;
  }
  return from;
}
