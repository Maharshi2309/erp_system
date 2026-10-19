import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/router/route_names.dart';
import '../../../core/errors/failure.dart';
import '../../../core/responsive/responsive_grid.dart';
import '../../../core/responsive/responsive_page.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/zoned_time.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../../auth/presentation/widgets/auth_layout.dart';
import '../../dashboard/domain/dashboard_metrics.dart';
import '../../employees/presentation/providers/employee_providers.dart';
import '../../holidays/presentation/calendar_providers.dart';
import '../../leave/domain/leave.dart';
import '../../leave/presentation/leave_providers.dart';
import '../../leave/presentation/leave_widgets.dart';
import '../domain/attendance.dart';
import '../domain/attendance_book.dart';
import 'attendance_providers.dart';
import 'attendance_widgets.dart';

/// Board S86 — the employee's home with punch in / out.
class EmployeeHomeScreen extends ConsumerStatefulWidget {
  const EmployeeHomeScreen({super.key});

  @override
  ConsumerState<EmployeeHomeScreen> createState() => _EmployeeHomeScreenState();
}

class _EmployeeHomeScreenState extends ConsumerState<EmployeeHomeScreen> {
  bool _pending = false;
  bool _failed = false;

  /// Kept until the server confirms, so a retry can't record twice.
  String? _requestId;

  Future<void> _punch(PunchKind kind) async {
    if (_pending) return;
    _requestId ??=
        '${ref.read(clockProvider)().microsecondsSinceEpoch}-${kind.name}';
    setState(() {
      _pending = true;
      _failed = false;
    });
    try {
      await ref
          .read(attendanceDataProvider.notifier)
          .punch(kind, requestId: _requestId!);
      _requestId = null;
      if (mounted) setState(() => _pending = false);
    } on NetworkFailure {
      if (mounted) {
        setState(() {
          _pending = false;
          _failed = true;
        });
      }
    } on Failure catch (f) {
      _requestId = null;
      if (mounted) {
        setState(() => _pending = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(f.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final self = ref.watch(selfEmployeeProvider);
    final book = ref.watch(attendanceBookProvider);
    if (session == null) return const SizedBox.shrink();
    if (book.isLoading || ref.watch(employeesProvider).isLoading) {
      return const ResponsivePage(
        child: LoadingSkeleton(label: 'Loading', child: SkeletonList(rows: 4)),
      );
    }
    if (book.hasError) {
      return ErrorState(
        message: userMessageFor(book.error!),
        onRetry: () => ref.invalidate(attendanceDataProvider),
      );
    }
    if (self == null) {
      return const ResponsivePage(
        child: AppCard(
          child: EmptyState(
            icon: Icons.badge_outlined,
            title: 'No employee record',
            message:
                'Your account isn’t linked to an employee record yet. Ask HR to link it.',
          ),
        ),
      );
    }
    final b = book.value!;
    final branch = b.branchOf(self);
    final zone = b.zoneOf(self);
    final today = b.todayFor(self);
    final record = b.day(self, today);
    final shift = record.shift;
    final open = record.sessions.where((s) => s.isOpen).lastOrNull;
    final closedMinutes = record.workedMinutes;
    final clock = ref.read(clockProvider);
    final local = wallTime(clock(), zone);
    final expected = shift?.expected ?? 8 * 60;

    final statusLabel = _pending
        ? 'Sending…'
        : (open != null
              ? 'Punched in'
              : (record.sessions.isEmpty
                    ? 'Not punched in yet'
                    : 'Punched out'));
    final statusSub = open != null
        ? 'since ${clockTime(open.inPunch!.at, zone)}'
        : 'Not working now';

    final corrected = b
        .correctionsFor([self])
        .where(
          (c) =>
              c.status == CorrectionStatus.approved &&
              today.difference(dateOnly(c.workDate)).inDays <= 7,
        )
        .firstOrNull;
    final recent =
        [
              for (var i = 1; i <= 21; i++)
                b.day(self, DateTime(today.year, today.month, today.day - i)),
            ]
            .where(
              (r) =>
                  r.status != DayStatus.weeklyOff && r.status != DayStatus.none,
            )
            .take(4)
            .toList();
    final holidays = ref
        .watch(workCalendarProvider)
        .holidaysBetween(branch, today, DateTime(today.year + 1, 12, 31));

    final punchCard = AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: open != null && !_pending
                      ? AppColors.successSoft
                      : AppColors.neutralSoft,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    statusLabel,
                    style: AppTypography.label.copyWith(
                      color: open != null && !_pending
                          ? AppColors.success
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text(statusSub, style: AppTypography.small)),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Current session', style: AppTypography.helper),
                    LiveText(
                      text: () => open == null
                          ? '—'
                          : hms(clock().difference(open.inPunch!.at)),
                      style: AppTypography.kpiValue.copyWith(
                        fontFamily: AppTypography.mono,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Today total', style: AppTypography.helper),
                    LiveText(
                      text: () => formatMinutes(
                        closedMinutes +
                            (open == null
                                ? 0
                                : clock()
                                      .difference(open.inPunch!.at)
                                      .inMinutes),
                      ),
                      style: AppTypography.kpiValue.copyWith(
                        fontFamily: AppTypography.mono,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value:
                  ((closedMinutes +
                              (open == null
                                  ? 0
                                  : clock()
                                        .difference(open.inPunch!.at)
                                        .inMinutes)) /
                          expected)
                      .clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: AppColors.primarySoft,
              color: AppColors.primary,
            ),
          ),
          if (_failed) ...[
            const SizedBox(height: AppSpacing.md),
            Semantics(
              liveRegion: true,
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.dangerSoft,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Text(
                  'Punch not recorded. We couldn’t reach the server. Your status hasn’t changed — try again.',
                  style: AppTypography.small.copyWith(
                    color: AppColors.dangerText,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          AppButton(
            label: open != null ? 'Punch out' : 'Punch in',
            busy: _pending,
            busyLabel: open != null ? 'Punching out…' : 'Punching in…',
            expand: true,
            size: AppButtonSize.large,
            variant: open != null
                ? AppButtonVariant.dangerOutline
                : AppButtonVariant.primary,
            onPressed: () =>
                _punch(open != null ? PunchKind.punchOut : PunchKind.punchIn),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: AppSpacing.md,
            children: [
              Text(
                'Expected ${formatMinutes(expected)} · $allowedBreakMinutes m break',
                style: AppTypography.helper,
              ),
              TextLink(
                'Today’s punches',
                onTap: () => context.go(AppRoutes.myDay(today)),
              ),
            ],
          ),
        ],
      ),
    );

    return ResponsivePage(
      maxWidth: 960,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              '${greetingFor(local)}, ${self.firstName}',
              style: AppTypography.pageTitle,
            ),
          ),
          Text(
            '${DateFormat('EEE d MMM').format(local)} · ${branch?.name ?? ''} · Shift ${shift?.label.split('(').last.replaceAll(')', '') ?? '—'}',
            style: AppTypography.small,
          ),
          const SizedBox(height: AppSpacing.lg),
          punchCard,
          if (corrected != null) ...[
            const SizedBox(height: AppSpacing.md),
            _Notice(
              text:
                  'Your ${DateFormat('d MMM').format(corrected.workDate)} '
                  '${corrected.changes.first.kind == PunchKind.punchIn ? 'punch-in' : 'punch-out'} was corrected to '
                  '${clockTime(corrected.changes.first.at, zone)} by ${corrected.by}.',
              onView: () =>
                  context.go(AppRoutes.myDay(dateOnly(corrected.workDate))),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          ResponsiveGrid(
            minItemWidth: 300,
            maxColumns: 2,
            spacing: AppSpacing.lg,
            children: [
              AppCard(
                header: CardHeader(
                  title: 'Leave balance',
                  trailing: TextLink(
                    'Apply',
                    onTap: () => context.go(AppRoutes.applyLeave),
                  ),
                ),
                child: const _LeaveTiles(),
              ),
              AppCard(
                header: CardHeader(
                  title: 'Recent attendance',
                  trailing: TextLink(
                    'History',
                    onTap: () => context.go(AppRoutes.myAttendance),
                  ),
                ),
                child: Column(
                  children: [
                    if (recent.isEmpty)
                      const Text(
                        'No attendance yet.',
                        style: AppTypography.small,
                      ),
                    for (final r in recent)
                      InkWell(
                        onTap: () => context.go(AppRoutes.myDay(r.date)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  DateFormat('EEE d').format(r.date),
                                  style: AppTypography.body,
                                ),
                              ),
                              Text(
                                r.workedMinutes == 0
                                    ? '—'
                                    : formatMinutes(r.workedMinutes),
                                style: AppTypography.code,
                              ),
                              const SizedBox(width: AppSpacing.md),
                              Flexible(child: DayStatusBadge(r.status)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              AppCard(
                header: const CardHeader(title: 'Upcoming holidays'),
                child: Column(
                  children: [
                    if (holidays.isEmpty)
                      const Text(
                        'No holidays coming up.',
                        style: AppTypography.small,
                      ),
                    for (final h in holidays.take(3))
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(h.name, style: AppTypography.body),
                            ),
                            Text(
                              DateFormat('EEE d MMM').format(h.date),
                              style: AppTypography.code,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, required this.onView});

  final String text;
  final VoidCallback onView;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.primarySoft,
      borderRadius: BorderRadius.circular(AppRadius.md),
    ),
    child: Row(
      children: [
        const Icon(Icons.edit_note, color: AppColors.primary),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            text,
            style: AppTypography.small.copyWith(color: AppColors.textPrimary),
          ),
        ),
        TextLink('View', onTap: onView),
      ],
    ),
  );
}

class _LeaveTiles extends ConsumerWidget {
  const _LeaveTiles();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final book = ref.watch(leaveBookProvider).value;
    final self = ref.watch(selfEmployeeProvider);
    if (book == null || self == null) {
      return const SkeletonBox(height: 88);
    }
    final balances = book.balances(self, book.today.year);
    if (balances.isEmpty) {
      return const Text(
        'Your branch has no leave policy yet.',
        style: AppTypography.small,
      );
    }
    final open = book.requestsOf(self).where((r) => r.status.isOpen).toList()
      ..sort((a, b) => a.from.compareTo(b.from));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, c) => Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final b in balances)
                Container(
                  width: ((c.maxWidth - 2 * AppSpacing.sm) / 3).clamp(
                    96.0,
                    c.maxWidth,
                  ),
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: MergeSemantics(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          b.type.name.replaceAll(' leave', ''),
                          style: AppTypography.helper,
                        ),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            formatDays(b.available),
                            style: AppTypography.metric,
                          ),
                        ),
                        Text(
                          [
                            b.type.method == AccrualMethod.monthly
                                ? 'accrued'
                                : 'of ${formatDays(b.total)}',
                            if (b.pending > 0)
                              '${formatDays(b.pending)} pending',
                          ].join(' · '),
                          style: AppTypography.helper,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        for (final r in open.take(2)) ...[
          const SizedBox(height: AppSpacing.sm),
          InkWell(
            onTap: () => context.go(AppRoutes.myLeaveRequest(r.id)),
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          requestTitle(book, r),
                          style: AppTypography.bodyStrong,
                        ),
                        Text(
                          r.status == LeaveStatus.changesRequested
                              ? 'Changes requested'
                              : 'Waiting for ${r.currentStep == null ? 'approval' : book.approverName(r.currentStep!)}',
                          style: AppTypography.helper,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Flexible(child: LeaveStatusBadge(r.status)),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
