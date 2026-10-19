import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/route_names.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/permissions/permissions.dart';
import '../../../../core/responsive/responsive_page.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/skeleton.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../../core/widgets/tab_strip.dart';
import '../../../../shared/models/app_session.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../employees/domain/employee.dart';
import '../../../employees/presentation/providers/employee_providers.dart';
import '../../../leave/presentation/leave_providers.dart';
import '../../../organization/domain/branch.dart';
import '../../../organization/presentation/providers/organization_providers.dart';
import '../../domain/company_holiday.dart';
import '../../domain/work_calendar.dart';
import '../calendar_providers.dart';

/// Pages of Holidays & Calendar (boards S62, S63, S65, S66). Import and
/// export need `holidays.create`.
List<(String, String)> holidayPagesFor(PermissionSet p) => [
  ('Calendar', AppRoutes.holidays),
  ('Holiday list', AppRoutes.holidayList),
  if (p.can(PermissionModule.holidays, PermissionAction.create))
    ('Import / export', AppRoutes.holidayImport),
  ('Schedules', AppRoutes.schedules),
];

/// What the holiday pages share.
class HolidayScope {
  HolidayScope({
    required this.session,
    required this.holidays,
    required this.allBranches,
    required this.employees,
    required this.calendar,
    required this.today,
  });

  final AppSession session;
  final List<CompanyHoliday> holidays;
  final List<Branch> allBranches;
  final List<Employee> employees;
  final WorkCalendar calendar;
  final DateTime today;

  /// Active branches the member may see.
  late final branches = [
    for (final b in allBranches)
      if (b.isActive && session.coversBranch(b.id)) b,
  ];

  bool get canEdit => session.permissions.can(
    PermissionModule.holidays,
    PermissionAction.create,
  );

  /// Organization holidays that reach the member's branches.
  late final visible = [
    for (final h in holidays)
      if (h.orgWide ||
          session.branchIds.isEmpty ||
          h.branchIds.any(session.branchIds.contains))
        h,
  ];

  String branchName(String id) =>
      allBranches.where((b) => b.id == id).firstOrNull?.name ?? id;

  /// Employed people at the branches a holiday reaches.
  List<Employee> peopleFor(CompanyHoliday h) => [
    for (final e in employees)
      if (e.status.isEmployed && h.appliesTo(e.branchId)) e,
  ];

  /// "Past", "Today", "In 6 days", "Upcoming", "Upcoming · on a weekly off".
  String statusOf(CompanyHoliday h) {
    if (h.endDate.isBefore(today)) return 'Past';
    if (h.covers(today)) return 'Today';
    final days = h.date.difference(today).inDays;
    final reach = [
      for (final b in branches)
        if (h.appliesTo(b.id)) b,
    ];
    final offEverywhere =
        !h.isRange &&
        reach.isNotEmpty &&
        reach.every((b) => !b.hours[h.date.weekday - 1].open);
    final base = days <= 14
        ? 'In $days ${days == 1 ? 'day' : 'days'}'
        : 'Upcoming';
    return offEverywhere ? '$base · on a weekly off' : base;
  }
}

class HolidaySection extends ConsumerWidget {
  const HolidaySection({super.key, required this.current, required this.body});

  final String current;
  final Widget Function(BuildContext context, HolidayScope scope) body;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final holidays = ref.watch(companyHolidaysProvider);
    final branches = ref.watch(branchesProvider);
    final employees = ref.watch(employeesProvider);
    if (session == null) return const SizedBox.shrink();
    if (holidays.isLoading || branches.isLoading || employees.isLoading) {
      return const ResponsivePage(
        child: LoadingSkeleton(
          label: 'Loading holidays',
          child: SkeletonList(rows: 6),
        ),
      );
    }
    final error = holidays.error ?? branches.error ?? employees.error;
    if (error != null) {
      return ErrorState(
        message: userMessageFor(error),
        onRetry: () => ref.invalidate(companyHolidaysProvider),
      );
    }
    final pages = holidayPagesFor(session.permissions);
    final index = pages.indexWhere((p) => p.$2 == current);
    // Leave data is loaded here too so impact panels can count requests.
    ref.watch(leaveBookProvider);
    return ResponsivePage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTabStrip(
            tabs: [for (final p in pages) p.$1],
            selected: index < 0 ? 0 : index,
            onSelected: (i) => context.go(pages[i].$2),
          ),
          const SizedBox(height: AppSpacing.lg),
          body(
            context,
            HolidayScope(
              session: session,
              holidays: holidays.value!,
              allBranches: branches.value!,
              employees: employees.value!,
              calendar: ref.watch(workCalendarProvider),
              today: DateTime(
                ref.watch(orgNowProvider)().year,
                ref.watch(orgNowProvider)().month,
                ref.watch(orgNowProvider)().day,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
