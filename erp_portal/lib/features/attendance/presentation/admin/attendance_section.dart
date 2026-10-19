import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/route_names.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/responsive/responsive_page.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/skeleton.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../../core/widgets/tab_strip.dart';
import '../../../../shared/models/app_session.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../employees/domain/employee.dart';
import '../../../employees/presentation/providers/employee_providers.dart';
import '../../../organization/domain/branch.dart';
import '../../../organization/presentation/providers/organization_providers.dart';
import '../../domain/attendance_book.dart';
import '../attendance_providers.dart';

/// Pages of the attendance area, in menu order (board S52 sidebar).
const attendancePages = [
  ('Overview', AppRoutes.attendance),
  ('Records', AppRoutes.attendanceRecords),
  ('Missing punches', AppRoutes.missingPunches),
  ('Corrections', AppRoutes.corrections),
  ('Monthly summary', AppRoutes.monthlySummary),
  ('Exports', AppRoutes.attendanceExports),
];

/// What every attendance admin page needs.
typedef AttendanceScope = ({
  AttendanceBook book,
  AppSession session,
  List<Employee> people,
  List<Branch> branches,
});

/// Loads the book and the people this member may see, then builds [body].
/// Adds the section tabs (owners and HR have one "Attendance" menu item).
class AttendanceSection extends ConsumerWidget {
  const AttendanceSection({
    super.key,
    required this.current,
    required this.body,
    this.scrollable = true,
  });

  final String current;
  final Widget Function(BuildContext context, AttendanceScope scope) body;
  final bool scrollable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final book = ref.watch(attendanceBookProvider);
    final visible = ref.watch(visibleEmployeesProvider);
    if (session == null) return const SizedBox.shrink();
    if (book.isLoading || visible.isLoading) {
      return const ResponsivePage(
        child: LoadingSkeleton(
          label: 'Loading attendance',
          child: SkeletonList(rows: 6),
        ),
      );
    }
    final error = book.error ?? visible.error;
    if (error != null) {
      return ErrorState(
        message: userMessageFor(error),
        onRetry: () => ref.invalidate(attendanceDataProvider),
      );
    }
    final branches = [
      for (final b in ref.watch(branchesProvider).value ?? const <Branch>[])
        if (session.coversBranch(b.id) && b.isActive) b,
    ];
    final people = [
      for (final e in visible.value!)
        if (e.status.isEmployed) e,
    ];
    final index = attendancePages.indexWhere((p) => p.$2 == current);
    return ResponsivePage(
      scrollable: scrollable,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTabStrip(
            tabs: [for (final p in attendancePages) p.$1],
            selected: index < 0 ? 0 : index,
            onSelected: (i) => context.go(attendancePages[i].$2),
          ),
          const SizedBox(height: AppSpacing.lg),
          body(context, (
            book: book.value!,
            session: session,
            people: people,
            branches: branches,
          )),
        ],
      ),
    );
  }
}

/// Daily / Weekly / Monthly style segmented toggle (boards S52, S53, S56).
class SegmentToggle<T> extends StatelessWidget {
  const SegmentToggle({
    super.key,
    required this.label,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    // Scrolls sideways on narrow screens instead of overflowing.
    return Semantics(
      container: true,
      label: label,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.borderStrong),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          clipBehavior: Clip.antiAlias,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (v, text) in options)
                Semantics(
                  button: true,
                  selected: v == value,
                  child: InkWell(
                    onTap: () => onChanged(v),
                    child: Container(
                      height: 38,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      color: v == value ? AppColors.ink : AppColors.surface,
                      child: Text(
                        text,
                        style: AppTypography.label.copyWith(
                          color: v == value
                              ? AppColors.surface
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Page title with a subtitle and actions on the right.
class AttendanceHeader extends StatelessWidget {
  const AttendanceHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.actions = const [],
  });

  final String title;
  final String subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.spaceBetween,
    crossAxisAlignment: WrapCrossAlignment.end,
    spacing: AppSpacing.md,
    runSpacing: AppSpacing.md,
    children: [
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            header: true,
            child: Text(title, style: AppTypography.pageTitle),
          ),
          Text(subtitle, style: AppTypography.small),
        ],
      ),
      Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: actions,
      ),
    ],
  );
}
