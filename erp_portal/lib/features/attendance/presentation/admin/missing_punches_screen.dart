import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/router/route_names.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/permissions/permissions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_overlays.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../auth/presentation/widgets/auth_layout.dart';
import '../../../dashboard/presentation/dashboard_widgets.dart';
import '../../../employees/presentation/widgets/employee_widgets.dart';
import '../../domain/attendance.dart';
import '../../domain/attendance_book.dart';
import '../attendance_providers.dart';
import 'attendance_section.dart';

enum _Which { any, punchIn, punchOut }

/// Board S54 — open sessions to fix.
class MissingPunchesScreen extends ConsumerStatefulWidget {
  const MissingPunchesScreen({super.key});

  @override
  ConsumerState<MissingPunchesScreen> createState() =>
      _MissingPunchesScreenState();
}

class _MissingPunchesScreenState extends ConsumerState<MissingPunchesScreen> {
  String? _branch;
  _Which _which = _Which.any;

  Future<void> _remind(List<DayRecord> rows) async {
    try {
      final n = await ref.read(attendanceDataProvider.notifier).remind([
        for (final r in rows) (employeeId: r.employee.id, workDate: r.date),
      ]);
      if (mounted) {
        showAppToast(
          context,
          n == 1
              ? 'Reminder sent to ${rows.single.employee.fullName}'
              : 'Reminders sent to $n employees',
        );
      }
    } on Failure catch (f) {
      if (mounted) showAppToast(context, f.message, icon: Icons.error_outline);
    }
  }

  Future<void> _rejectRequest(CorrectionRequest request, String name) async {
    final input = await showLifecycleDialog(
      context,
      title: 'Reject $name’s request?',
      message:
          'They’ll see your reason. The day stays as a missing punch until someone corrects it.',
      confirmLabel: 'Reject request',
      destructive: true,
    );
    if (input == null || !mounted) return;
    await ref
        .read(attendanceDataProvider.notifier)
        .rejectRequest(request.id, input.reason);
    if (mounted) showAppToast(context, 'Request rejected');
  }

  @override
  Widget build(BuildContext context) {
    return AttendanceSection(
      current: AppRoutes.missingPunches,
      body: (context, scope) {
        final book = scope.book;
        final canCorrect = scope.session.permissions.can(
          PermissionModule.attendance,
          PermissionAction.correct,
        );
        final people = [
          for (final e in scope.people)
            if (_branch == null || e.branchId == _branch) e,
        ];
        final all = book
            .missingPunches(people)
            .where((r) => r.date.isBefore(book.todayFor(r.employee)))
            .toList();
        final rows = all.where((r) {
          final noIn = r.sessions.any((s) => s.isOrphanOut);
          return switch (_which) {
            _Which.any => true,
            _Which.punchIn => noIn,
            _Which.punchOut => !noIn,
          };
        }).toList();
        final overdue = rows.where(book.isOverdue).toList();
        final recent = rows.where((r) => !book.isOverdue(r)).toList()
          ..sort((a, b) => b.date.compareTo(a.date));
        final branchName = scope.branches
            .where((b) => b.id == _branch)
            .firstOrNull
            ?.name;

        Widget group(
          String title,
          String note,
          Color color,
          List<DayRecord> items,
        ) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.lg),
          child: AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '$title  ',
                          style: AppTypography.cardTitle.copyWith(color: color),
                        ),
                        TextSpan(text: note, style: AppTypography.helper),
                      ],
                    ),
                  ),
                ),
                for (final r in items) _row(context, book, r, canCorrect),
              ],
            ),
          ),
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AttendanceHeader(
              title: 'Missing punches',
              subtitle:
                  '${rows.length} open ${rows.length == 1 ? 'session' : 'sessions'} · worked time for these days is excluded until corrected',
              actions: [
                if (scope.branches.length > 1)
                  SizedBox(
                    width: 170,
                    child: DashboardSelect<String?>(
                      label: 'Branch',
                      value: _branch,
                      options: [
                        (null, 'All branches'),
                        for (final b in scope.branches) (b.id, b.name),
                      ],
                      onChanged: (v) => setState(() => _branch = v),
                    ),
                  ),
                SizedBox(
                  width: 200,
                  child: DashboardSelect<_Which>(
                    label: 'Missing',
                    value: _which,
                    options: const [
                      (_Which.any, 'Punch-in or punch-out'),
                      (_Which.punchIn, 'Missing punch-in'),
                      (_Which.punchOut, 'Missing punch-out'),
                    ],
                    onChanged: (v) => setState(() => _which = v ?? _Which.any),
                  ),
                ),
                AppButton(
                  label: 'Remind all employees',
                  variant: AppButtonVariant.secondary,
                  onPressed: rows.isEmpty ? null : () => _remind(rows),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            if (rows.isEmpty)
              AppCard(
                child: EmptyState(
                  icon: Icons.check_circle_outline,
                  iconTone: AppColors.success,
                  title: '${branchName ?? 'Everyone'} is all clear',
                  message: 'No open sessions in the last 30 days.',
                ),
              ),
            if (overdue.isNotEmpty)
              group(
                'Overdue · older than $overdueAfterDays days',
                'Blocks payroll export for these days',
                AppColors.danger,
                overdue,
              ),
            if (recent.isNotEmpty)
              group(
                'Recent',
                'Employees can still request a correction',
                AppColors.textPrimary,
                recent,
              ),
          ],
        );
      },
    );
  }

  Widget _row(
    BuildContext context,
    AttendanceBook book,
    DayRecord r,
    bool canCorrect,
  ) {
    final request = book.openRequest(r.employee, r.date);
    final reminder = book.lastReminder(r.employee, r.date);
    final (state, tone) = r.pendingCorrection != null
        ? ('Waiting for approval', StatusTone.info)
        : request != null
        ? ('Correction requested', StatusTone.info)
        : reminder != null
        ? (
            'Reminded ${DateFormat('d MMM').format(reminder.at)}',
            StatusTone.neutral,
          )
        : ('No response', StatusTone.warning);
    final recorded = [
      for (final e in r.timeline)
        if (e.kind == PunchKind.punchIn || e.kind == PunchKind.punchOut)
          '${e.kind == PunchKind.punchIn ? 'In' : 'Out'} ${clockTime(e.at, r.zone)}',
    ];
    final recordedText = r.sessions.any((s) => s.isOrphanOut)
        ? '→ ${recorded.join(' → ')}'
        : '${recorded.join(' → ')} →';

    final actions = <Widget>[
      if (request != null && canCorrect)
        AppButton(
          label: 'Reject request',
          size: AppButtonSize.small,
          variant: AppButtonVariant.secondary,
          onPressed: () => _rejectRequest(request, r.employee.fullName),
        )
      else if (r.pendingCorrection == null)
        AppButton(
          label: reminder == null ? 'Remind' : 'Remind again',
          size: AppButtonSize.small,
          variant: AppButtonVariant.secondary,
          onPressed: () => _remind([r]),
        ),
      if (canCorrect && r.pendingCorrection == null)
        AppButton(
          label: request != null ? 'Review request' : 'Correct',
          size: AppButtonSize.small,
          onPressed: () =>
              context.go(AppRoutes.correctAttendance(r.employee.id, r.date)),
        ),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppSpacing.lg,
        runSpacing: AppSpacing.sm,
        children: [
          SizedBox(
            width: 220,
            child: Row(
              children: [
                EmployeeAvatar(employee: r.employee, size: 32),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextLink(
                        r.employee.fullName,
                        onTap: () =>
                            context.go(AppRoutes.employee(r.employee.id)),
                      ),
                      Text(
                        '${r.employee.code} · ${book.branchOf(r.employee)?.name ?? ''}',
                        style: AppTypography.helper,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 110,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Date', style: AppTypography.helper),
                Text(
                  DateFormat('EEE d MMM').format(r.date),
                  style: AppTypography.small.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 260,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Recorded', style: AppTypography.helper),
                Text(
                  recordedText,
                  style: AppTypography.code.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  r.missingWhat,
                  style: AppTypography.helper.copyWith(color: AppColors.danger),
                ),
              ],
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: StatusBadge(label: state, tone: tone),
          ),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: actions,
          ),
        ],
      ),
    );
  }
}
