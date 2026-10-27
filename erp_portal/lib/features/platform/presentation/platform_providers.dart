import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/utils/clock.dart';
import '../../attendance/data/demo_attendance_repository.dart';
import '../../attendance/presentation/attendance_providers.dart';
import '../../auth/domain/auth_state.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../../employees/presentation/providers/employee_providers.dart';
import '../../holidays/data/demo_calendar_repository.dart';
import '../../holidays/presentation/calendar_providers.dart';
import '../../leave/data/demo_leave_repository.dart';
import '../../leave/presentation/leave_providers.dart';
import '../../organization/data/demo_organization_repository.dart';
import '../../organization/presentation/providers/organization_providers.dart';
import '../data/demo_platform_repository.dart';
import '../domain/platform_stats.dart';

final platformRepositoryProvider = Provider<PlatformRepository>(
  (ref) => DemoPlatformRepository(
    organizations:
        ref.watch(organizationRepositoryProvider) as DemoOrganizationRepository,
    employees: ref.watch(employeeRepositoryProvider),
    attendance:
        ref.watch(attendanceRepositoryProvider) as DemoAttendanceRepository,
    leave: ref.watch(leaveRepositoryProvider) as DemoLeaveRepository,
    calendar: ref.watch(calendarRepositoryProvider) as DemoCalendarRepository,
    clock: ref.watch(clockProvider),
  ),
);

/// Only the platform super admin gets statistics (D-75).
final platformSnapshotProvider = FutureProvider<PlatformSnapshot>((ref) {
  if (ref.watch(authControllerProvider) is! PlatformSignedIn) {
    throw const PermissionFailure();
  }
  return ref.watch(platformRepositoryProvider).snapshot();
});
