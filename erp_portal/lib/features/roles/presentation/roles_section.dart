import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/route_names.dart';
import '../../../core/errors/failure.dart';
import '../../../core/permissions/permissions.dart';
import '../../../core/responsive/responsive_page.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/tab_strip.dart';
import '../../../shared/models/app_session.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../../employees/domain/employee.dart';
import '../../employees/presentation/providers/employee_providers.dart';
import '../../organization/domain/branch.dart';
import '../../organization/presentation/providers/organization_providers.dart';
import '../domain/access.dart';
import 'access_providers.dart';

const rolesPages = [
  ('Roles', AppRoutes.roles),
  ('People & access', AppRoutes.people),
  ('Invitations', AppRoutes.invitations),
];

/// One member as listed on board S70.
typedef AccessRow = ({
  String key,
  String name,
  String email,
  RoleDefinition role,
  List<String> branchIds,
  int teamSize,
  Employee? employee,
});

/// What the access pages share.
class RolesScope {
  RolesScope({
    required this.session,
    required this.data,
    required this.employees,
    required this.branches,
  });

  final AppSession session;
  final AccessData data;
  final List<Employee> employees;
  final List<Branch> branches;

  bool get canEdit =>
      session.permissions.can(PermissionModule.roles, PermissionAction.edit);
  bool get canCreate =>
      session.permissions.can(PermissionModule.roles, PermissionAction.create);

  /// Everyone with a role: owners without an employee record first, then
  /// employed people (their assignment, else their employee role).
  late final List<AccessRow> rows = () {
    final out = <AccessRow>[];
    final employee = data.role('employee');
    for (final m in data.members) {
      final a = data.assignments[m.key];
      final role = data.role(a?.roleId ?? 'owner');
      if (role == null) continue;
      out.add((
        key: m.key,
        name: m.name,
        email: m.email,
        role: role,
        branchIds: a?.branchIds ?? const [],
        teamSize: 0,
        employee: null,
      ));
    }
    for (final e in employees) {
      if (e.status == EmploymentStatus.terminated) continue;
      final a = data.assignments[e.code];
      final role = data.role(a?.roleId ?? e.role.name) ?? employee;
      if (role == null) continue;
      out.add((
        key: e.code,
        name: e.fullName,
        email: e.workEmail,
        role: role,
        branchIds:
            a?.branchIds ??
            (role.scope == DataScope.assignedBranches
                ? [e.branchId]
                : const []),
        teamSize: employees.where((x) => x.managerId == e.id).length,
        employee: e,
      ));
    }
    return out;
  }();

  int holders(String roleId) => rows.where((r) => r.role.id == roleId).length;

  String branchName(String id) =>
      branches.where((b) => b.id == id).firstOrNull?.name ?? id;

  /// Whose information they see: "Everyone", "Surat, Vadodara",
  /// "Their team (6)", "Only themselves" (D-79 wording).
  String scopeOf(AccessRow r) => switch (r.role.scope) {
    DataScope.organization => 'Everyone',
    DataScope.assignedBranches =>
      r.branchIds.isEmpty
          ? 'No branch chosen'
          : r.branchIds.map(branchName).join(', '),
    DataScope.ownTeam => 'Their team (${r.teamSize})',
    DataScope.ownRecords => 'Only themselves',
  };
}

class RolesSection extends ConsumerWidget {
  const RolesSection({
    super.key,
    required this.current,
    required this.body,
    this.tabs = true,
  });

  final String current;
  final bool tabs;
  final Widget Function(BuildContext context, RolesScope scope) body;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final access = ref.watch(accessDataProvider);
    // Branch managers only see invitations for their own branches.
    final employees = ref.watch(visibleEmployeesProvider);
    final branches = ref.watch(branchesProvider);
    if (session == null) return const SizedBox.shrink();
    if (access.isLoading || employees.isLoading || branches.isLoading) {
      return const ResponsivePage(
        child: LoadingSkeleton(
          label: 'Loading roles',
          child: SkeletonList(rows: 6),
        ),
      );
    }
    final error = access.error ?? employees.error ?? branches.error;
    if (error != null) {
      return ErrorState(
        message: userMessageFor(error),
        onRetry: () => ref.invalidate(accessDataProvider),
      );
    }
    // HR admins reach Invitations without the Roles pages.
    final pages = [
      for (final p in rolesPages)
        if (p.$2 == AppRoutes.invitations ||
            session.permissions.canView(PermissionModule.roles))
          p,
    ];
    final index = pages.indexWhere((p) => p.$2 == current);
    return ResponsivePage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (tabs) ...[
            Semantics(
              header: true,
              child: const Text(
                'Roles & Permissions',
                style: AppTypography.pageTitle,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            AppTabStrip(
              tabs: [for (final p in pages) p.$1],
              selected: index < 0 ? 0 : index,
              onSelected: (i) => context.go(pages[i].$2),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          body(
            context,
            RolesScope(
              session: session,
              data: access.value!,
              employees: employees.value!,
              branches: branches.value!,
            ),
          ),
        ],
      ),
    );
  }
}
