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
import '../../../core/widgets/app_overlays.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/kpi_card.dart';
import '../../../core/widgets/selection_controls.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/state_views.dart';
import '../../dashboard/presentation/dashboard_widgets.dart';
import '../../employees/domain/employee.dart';
import '../../employees/presentation/providers/employee_providers.dart';
import '../domain/attendance.dart';
import '../domain/attendance_book.dart';
import 'attendance_providers.dart';
import 'attendance_widgets.dart';

/// Shared loading/empty handling for the self-service pages.
Widget _withSelf(
  WidgetRef ref,
  Widget Function(AttendanceBook book, Employee self) build,
) {
  final self = ref.watch(selfEmployeeProvider);
  final book = ref.watch(attendanceBookProvider);
  if (book.isLoading || ref.watch(employeesProvider).isLoading) {
    return const ResponsivePage(
      child: LoadingSkeleton(label: 'Loading', child: SkeletonList(rows: 6)),
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
          message: 'Your account isn’t linked to an employee record yet.',
        ),
      ),
    );
  }
  return build(book.value!, self);
}

/// "10:12 → 18:34", "09:24 → now", "—".
String timesOf(DayRecord r) {
  if (r.sessions.isEmpty) return '—';
  final first = r.sessions.first;
  final last = r.sessions.last;
  final start = first.inPunch == null
      ? '—'
      : clockTime(first.inPunch!.at, r.zone);
  final end = last.outPunch != null
      ? clockTime(last.outPunch!.at, r.zone)
      : (r.status == DayStatus.working ? 'now' : '—');
  return '$start → $end';
}

/// The small note under a day row (board S87).
(String, Color) noteOf(DayRecord r, AttendanceBook book) {
  if (r.status == DayStatus.working) {
    return ('Session in progress', AppColors.success);
  }
  if (r.pendingCorrection != null) {
    return ('Correction waiting for approval', AppColors.primary);
  }
  if (book.openRequest(r.employee, r.date) != null) {
    return ('Correction requested', AppColors.primary);
  }
  if (r.corrected) return ('Corrected by ${r.correctedBy}', AppColors.primary);
  if (r.status == DayStatus.missingPunch) {
    return (r.missingWhat, AppColors.danger);
  }
  if (r.lateMinutes > 0) {
    return ('${r.lateMinutes} min late', const Color(0xFF8A4F00));
  }
  if (r.holidayName != null) return (r.holidayName!, AppColors.textMuted);
  return ('', AppColors.textMuted);
}

/// Board S87 — the employee's month.
class MyAttendanceScreen extends ConsumerStatefulWidget {
  const MyAttendanceScreen({super.key});

  @override
  ConsumerState<MyAttendanceScreen> createState() => _MyAttendanceScreenState();
}

class _MyAttendanceScreenState extends ConsumerState<MyAttendanceScreen> {
  int _monthsBack = 0;

  @override
  Widget build(BuildContext context) => _withSelf(ref, (book, self) {
    final today = book.todayFor(self);
    final month = DateTime(today.year, today.month - _monthsBack);
    final last = _monthsBack == 0
        ? today
        : DateTime(month.year, month.month + 1, 0);
    final days = book
        .range(self, month, last)
        .where((r) => r.status != DayStatus.none)
        .toList();
    final counts = AttendanceBook.count(
      days.where((d) => d.status != DayStatus.working),
    );
    final working = days
        .where((d) => d.scheduled && d.status != DayStatus.upcoming)
        .length;
    final present = days.where((d) => d.status.attended).length;
    final worked = days.fold(0, (s, d) => s + d.workedMinutes);
    final expected = days
        .where((d) => d.status != DayStatus.working)
        .fold(0, (s, d) => s + d.expectedMinutes);

    return ResponsivePage(
      maxWidth: 960,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            children: [
              Semantics(
                header: true,
                child: const Text(
                  'My attendance',
                  style: AppTypography.pageTitle,
                ),
              ),
              SizedBox(
                width: 180,
                child: DashboardSelect<int>(
                  label: 'Period',
                  value: _monthsBack,
                  options: [
                    for (var i = 0; i < 3; i++)
                      (
                        i,
                        DateFormat(
                          'MMMM y',
                        ).format(DateTime(today.year, today.month - i)),
                      ),
                  ],
                  onChanged: (v) => setState(() => _monthsBack = v ?? 0),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          ResponsiveGrid(
            minItemWidth: 150,
            maxColumns: 4,
            children: [
              KpiCard(
                label: 'Present',
                value: '$present',
                caption: 'of $working working days',
              ),
              KpiCard(
                label: 'Late',
                value: '${counts.late}',
                caption: counts.late == 0
                    ? 'On time all month'
                    : 'avg ${counts.averageLate} min',
              ),
              KpiCard(
                label: 'Worked',
                value: formatMinutes(worked),
                caption: 'expected ${formatMinutes(expected)}',
              ),
              KpiCard(
                label: 'Leave',
                value: '${counts.onLeave}',
                caption: counts.onLeave == 1
                    ? 'day this month'
                    : 'days this month',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (final r in days)
                  InkWell(
                    onTap:
                        r.status == DayStatus.weeklyOff ||
                            r.status == DayStatus.upcoming
                        ? null
                        : () => context.go(AppRoutes.myDay(r.date)),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: r.corrected || r.pendingCorrection != null
                            ? AppColors.primarySelected
                            : null,
                        border: const Border(
                          bottom: BorderSide(color: AppColors.divider),
                        ),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 44,
                            child: Column(
                              children: [
                                Text(
                                  DateFormat('EEE').format(r.date),
                                  style: AppTypography.helper,
                                ),
                                Text(
                                  '${r.date.day}',
                                  style: AppTypography.code.copyWith(
                                    fontSize: 17,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  timesOf(r),
                                  style: AppTypography.code.copyWith(
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                if (noteOf(r, book).$1.isNotEmpty)
                                  Text(
                                    noteOf(r, book).$1,
                                    style: AppTypography.helper.copyWith(
                                      color: noteOf(r, book).$2,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          // Shrinks at large text sizes instead of overflowing.
                          Flexible(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  r.workedMinutes == 0
                                      ? '—'
                                      : formatMinutes(r.workedMinutes),
                                  style: AppTypography.code.copyWith(
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                DayStatusBadge(r.status),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          const Text(
            'Something wrong? Open the day and tap “Request correction” within 3 days.',
            textAlign: TextAlign.center,
            style: AppTypography.helper,
          ),
        ],
      ),
    );
  });
}

/// Board S88 — one day, with "Request correction".
class MyDayScreen extends ConsumerWidget {
  const MyDayScreen({super.key, required this.date});

  final DateTime? date;

  @override
  Widget build(BuildContext context, WidgetRef ref) => _withSelf(ref, (
    book,
    self,
  ) {
    if (date == null) {
      return const ErrorState(
        headline: '404',
        title: 'That date isn’t valid',
        message: 'Open a day from your attendance.',
      );
    }
    final r = book.day(self, date!);
    final everyone = ref.watch(employeesProvider).value ?? const <Employee>[];
    final manager = everyone.where((e) => e.id == self.managerId).firstOrNull;
    final today = book.todayFor(self);
    final deadline = DateTime(
      r.date.year,
      r.date.month,
      r.date.day + requestWindowDays,
    );
    final request = book.openRequest(self, r.date);
    final canRequest =
        !r.date.isAfter(today) &&
        !today.isAfter(deadline) &&
        r.status != DayStatus.weeklyOff &&
        r.status != DayStatus.holiday &&
        r.status != DayStatus.working &&
        request == null &&
        r.pendingCorrection == null;
    final rules = book.branchOf(self)?.attendance;

    final exceptions = <(String, String, Color)>[
      if (r.lateMinutes > 0)
        (
          'LATE',
          'Arrived ${r.lateMinutes} min after shift start (${rules?.graceMinutes ?? 10} min grace).',
          const Color(0xFF8A4F00),
        ),
      if (r.earlyMinutes > 0)
        (
          'EARLY',
          'Left ${r.earlyMinutes} min before shift end.',
          const Color(0xFF8A4F00),
        ),
      if (r.status == DayStatus.missingPunch)
        (
          'MISSING',
          'There is ${r.missingWhat}. Worked time excludes the open session until it is corrected.',
          AppColors.danger,
        ),
      if (r.corrected)
        (
          'FIXED',
          'Corrected by ${r.correctedBy} — “${r.correctionReason}”',
          AppColors.primary,
        ),
      if (r.pendingCorrection case final c?)
        (
          'PENDING',
          'A correction by ${c.by} is waiting for approval.',
          AppColors.primary,
        ),
      if (request != null)
        (
          'REQUESTED',
          'You asked for a correction: ${request.kind.label.toLowerCase()} at ${clockTime(request.proposedAt, r.zone)}.',
          AppColors.primary,
        ),
    ];

    return ResponsivePage(
      maxWidth: 720,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Back to my attendance',
                onPressed: () => context.go(AppRoutes.myAttendance),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    DateFormat('EEE d MMM').format(r.date),
                    style: AppTypography.pageTitle,
                  ),
                ),
              ),
              DayStatusBadge(r.status),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          ResponsiveGrid(
            minItemWidth: 140,
            maxColumns: 4,
            children: [
              KpiCard(
                label: 'Worked',
                value: r.workedMinutes == 0
                    ? '—'
                    : formatMinutes(r.workedMinutes),
              ),
              KpiCard(
                label: 'Expected',
                value: formatMinutes(r.expectedMinutes),
              ),
              KpiCard(
                label: 'Break',
                value: '${r.breakMinutes}m',
                caption: 'of ${allowedBreakMinutes}m',
              ),
              KpiCard(
                label: 'Shift',
                value:
                    r.shift?.label.split('(').last.replaceAll(')', '') ?? '—',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            header: const CardHeader(title: 'Timeline'),
            child: PunchTimeline(record: r),
          ),
          if (exceptions.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            AppCard(
              header: const CardHeader(title: 'Exceptions'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (tag, text, color) in exceptions)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '$tag  ',
                              style: AppTypography.code.copyWith(
                                color: color,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            TextSpan(
                              text: text,
                              style: AppTypography.small.copyWith(
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          if (canRequest) ...[
            AppButton(
              label: 'Request correction',
              variant: AppButtonVariant.secondary,
              expand: true,
              onPressed: () => _request(context, ref, r, manager),
            ),
            const SizedBox(height: 4),
            Text(
              'Available until ${DateFormat('EEE d MMM').format(deadline)} · goes to ${manager?.fullName ?? 'your manager'}',
              textAlign: TextAlign.center,
              style: AppTypography.helper,
            ),
          ] else if (!r.date.isAfter(today) &&
              today.isAfter(deadline) &&
              r.status.isException)
            Text(
              'The 3-day window for requesting a correction has passed. Ask ${manager?.fullName ?? 'your manager'} directly.',
              textAlign: TextAlign.center,
              style: AppTypography.helper,
            ),
        ],
      ),
    );
  });

  Future<void> _request(
    BuildContext context,
    WidgetRef ref,
    DayRecord r,
    Employee? manager,
  ) async {
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _RequestSheet(
        record: r,
        managerName: manager?.fullName ?? 'your manager',
      ),
    );
    if (sent == true && context.mounted) {
      showAppToast(
        context,
        'Request sent to ${manager?.fullName ?? 'your manager'}',
      );
    }
  }
}

/// Correction request form (Q-12 option b: which punch, proposed time, reason).
class _RequestSheet extends ConsumerStatefulWidget {
  const _RequestSheet({required this.record, required this.managerName});

  final DayRecord record;
  final String managerName;

  @override
  ConsumerState<_RequestSheet> createState() => _RequestSheetState();
}

class _RequestSheetState extends ConsumerState<_RequestSheet> {
  late PunchKind _kind = widget.record.sessions.any((s) => s.isOrphanOut)
      ? PunchKind.punchIn
      : PunchKind.punchOut;
  late int _minutes = _kind == PunchKind.punchIn
      ? (widget.record.shift == null
            ? 9 * 60 + 30
            : _localMinutes(widget.record.shift!.start))
      : (widget.record.shift == null
            ? 18 * 60 + 30
            : _localMinutes(widget.record.shift!.end));
  final _reason = TextEditingController();
  String? _error;
  bool _busy = false;

  int _localMinutes(DateTime instant) {
    final t = wallTime(instant, widget.record.zone);
    return t.hour * 60 + t.minute;
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_reason.text.trim().length < 5) {
      setState(
        () =>
            _error = 'Tell your manager what happened (at least 5 characters).',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = widget.record;
    try {
      await ref
          .read(attendanceDataProvider.notifier)
          .request(
            CorrectionRequest(
              id: '',
              employeeId: r.employee.id,
              workDate: r.date,
              kind: _kind,
              proposedAt: instantOf(
                r.date.add(Duration(minutes: _minutes)),
                r.zone,
              ),
              message: _reason.text.trim(),
              createdAt: wallTime(ref.read(clockProvider)(), r.zone),
            ),
          );
      if (mounted) Navigator.of(context).pop(true);
    } on Failure catch (f) {
      if (mounted) setState(() => _error = f.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                'Request a correction · ${DateFormat('EEE d MMM').format(widget.record.date)}',
                style: AppTypography.sectionTitle,
              ),
            ),
            Text(
              'Goes to ${widget.managerName}. Your original punches are kept.',
              style: AppTypography.small,
            ),
            const SizedBox(height: AppSpacing.lg),
            const Text('Which punch?', style: AppTypography.label),
            const SizedBox(height: 6),
            ChoiceChips<PunchKind>(
              options: const [
                (PunchKind.punchIn, 'Punch in'),
                (PunchKind.punchOut, 'Punch out'),
              ],
              selected: _kind,
              onSelected: (k) => setState(() => _kind = k),
            ),
            const SizedBox(height: AppSpacing.md),
            const Text('Correct time', style: AppTypography.label),
            const SizedBox(height: 6),
            TimeField(
              minutes: _minutes,
              semanticLabel: 'Proposed time',
              onChanged: (m) => setState(() => _minutes = m),
            ),
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              label: 'What happened?',
              controller: _reason,
              isRequired: true,
              errorText: _error,
              helperText: 'Visible to your manager.',
            ),
            const SizedBox(height: AppSpacing.lg),
            AppButton(
              label: 'Send request',
              busy: _busy,
              busyLabel: 'Sending…',
              expand: true,
              onPressed: _send,
            ),
          ],
        ),
      ),
    );
  }
}
