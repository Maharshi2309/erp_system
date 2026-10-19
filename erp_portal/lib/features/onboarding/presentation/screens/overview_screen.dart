import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/permissions/system_roles.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../dashboard/presentation/admin_dashboard_screen.dart';
import '../../../employees/presentation/providers/employee_providers.dart';
import 'setup_home_screen.dart';

/// The owner chose "Open full dashboard" on the setup home.
final dashboardChosenProvider = NotifierProvider<ValueHolder<bool>, bool>(
  () => ValueHolder(false),
);

/// `/overview`: the owner's setup home (S15–S25) until the organization has
/// employees or the owner opens the full dashboard; everyone else gets the
/// dashboard (S30) straight away (D-19, updated in Phase 4).
class OverviewScreen extends ConsumerWidget {
  const OverviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(sessionProvider)?.role;
    if (role != SystemRole.owner) return const AdminDashboardScreen();
    final employees = ref.watch(employeesProvider);
    final chosen = ref.watch(dashboardChosenProvider);
    if (employees.isLoading && !employees.hasValue) {
      return const Center(child: CircularProgressIndicator());
    }
    final hasPeople = employees.value?.isNotEmpty ?? false;
    return hasPeople || chosen
        ? const AdminDashboardScreen()
        : const SetupHomeScreen();
  }
}
