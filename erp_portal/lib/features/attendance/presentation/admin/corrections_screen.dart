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
import '../../../../core/widgets/status_badge.dart';
import '../../../employees/presentation/widgets/employee_widgets.dart';
import '../../domain/attendance.dart';
import '../../domain/attendance_book.dart';
import '../attendance_providers.dart';
import 'attendance_section.dart';

/// Corrections waiting for approval, open employee requests and recent
/// decisions (Q-12 option b: a list built from the S54 rows).
class CorrectionsScreen extends ConsumerWidget {
  const CorrectionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AttendanceSection(
      current: AppRoutes.corrections,
      body: (context, scope) {
        final book = scope.book;
        final me = scope.session.displayName;
        final canApprove = scope.session.permissions.can(
          PermissionModule.attendance,
          PermissionAction.approve,
        );
        final canCorrect = scope.session.permissions.can(
          PermissionModule.attendance,
          PermissionAction.correct,
        );
        final byId = {for (final e in scope.people) e.id: e};
        final all = book.correctionsFor(scope.people);
        final pending = all
            .where((c) => c.status == CorrectionStatus.pending)
            .toList();
        final decided = all
            .where((c) => c.status != CorrectionStatus.pending)
            .take(20)
            .toList();
        final requests =
            book.data.requests
                .where(
                  (r) =>
                      r.status == RequestStatus.open &&
                      byId.containsKey(r.employeeId),
                )
                .toList()
              ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

        Future<void> decide(Correction c, bool approve) async {
          if (!approve) {
            final ok = await showConfirmDialog(
              context,
              title: 'Reject this correction?',
              message:
                  '${c.by} will see it was rejected. The original punches stay as recorded.',
              confirmLabel: 'Reject',
              destructive: true,
            );
            if (!ok) return;
          }
          try {
            await ref
                .read(attendanceDataProvider.notifier)
                .decide(c.id, approve: approve);
            if (context.mounted) {
              showAppToast(
                context,
                approve ? 'Correction approved' : 'Correction rejected',
              );
            }
          } on Failure catch (f) {
            if (context.mounted) {
              showAppToast(context, f.message, icon: Icons.error_outline);
            }
          }
        }

        String describe(Correction c) {
          final e = byId[c.employeeId];
          final zone = e == null ? book.orgZone : book.zoneOf(e);
          return c.changes
              .map(
                (x) =>
                    '${x.kind == PunchKind.punchIn ? 'Punch-in' : 'Punch-out'} ${x.replaces == null ? 'added' : 'moved'} · ${clockTime(x.at, zone)}',
              )
              .join(', ');
        }

        Widget person(String id) {
          final e = byId[id];
          if (e == null) return const Text('—');
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              EmployeeAvatar(employee: e, size: 28),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(e.fullName, style: AppTypography.bodyStrong),
              ),
            ],
          );
        }

        Widget card(String title, String empty, List<Widget> rows) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.lg),
          child: AppCard(
            header: CardHeader(title: title),
            child: rows.isEmpty
                ? Text(empty, style: AppTypography.small)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: rows,
                  ),
          ),
        );

        Widget line(List<Widget> left, List<Widget> actions) => Container(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.divider)),
          ),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.sm,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: left,
                ),
              ),
              Wrap(spacing: AppSpacing.sm, children: actions),
            ],
          ),
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AttendanceHeader(
              title: 'Corrections',
              subtitle:
                  '${pending.length} waiting for approval · ${requests.length} employee ${requests.length == 1 ? 'request' : 'requests'}',
            ),
            const SizedBox(height: AppSpacing.lg),
            card('Waiting for approval', 'Nothing to approve.', [
              for (final c in pending)
                line(
                  [
                    person(c.employeeId),
                    const SizedBox(height: 4),
                    Text(
                      '${DateFormat('EEE d MMM').format(c.workDate)} · ${describe(c)}',
                      style: AppTypography.small.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      'By ${c.by} · “${c.reason}”',
                      style: AppTypography.helper,
                    ),
                  ],
                  [
                    if (canApprove && c.by != me) ...[
                      AppButton(
                        label: 'Reject',
                        size: AppButtonSize.small,
                        variant: AppButtonVariant.secondary,
                        onPressed: () => decide(c, false),
                      ),
                      AppButton(
                        label: 'Approve',
                        size: AppButtonSize.small,
                        onPressed: () => decide(c, true),
                      ),
                    ] else
                      Text(
                        c.by == me
                            ? 'You made this · ${c.approverNote} approves'
                            : 'Waiting for ${c.approverNote}',
                        style: AppTypography.helper,
                      ),
                  ],
                ),
            ]),
            card('Employee requests', 'No open requests.', [
              for (final r in requests)
                line(
                  [
                    person(r.employeeId),
                    const SizedBox(height: 4),
                    Text(
                      '${DateFormat('EEE d MMM').format(r.workDate)} · ${r.kind == PunchKind.punchIn ? 'punch-in' : 'punch-out'} at '
                      '${clockTime(r.proposedAt, byId[r.employeeId] == null ? book.orgZone : book.zoneOf(byId[r.employeeId]!))}',
                      style: AppTypography.small.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text('“${r.message}”', style: AppTypography.helper),
                  ],
                  [
                    if (canCorrect)
                      AppButton(
                        label: 'Review request',
                        size: AppButtonSize.small,
                        onPressed: () => context.go(
                          AppRoutes.correctAttendance(r.employeeId, r.workDate),
                        ),
                      ),
                  ],
                ),
            ]),
            card('Recent decisions', 'No corrections yet.', [
              for (final c in decided)
                line(
                  [
                    person(c.employeeId),
                    const SizedBox(height: 4),
                    Text(
                      '${DateFormat('EEE d MMM').format(c.workDate)} · ${describe(c)}',
                      style: AppTypography.small.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      'By ${c.by}${c.decidedBy == null ? '' : ' · ${c.status == CorrectionStatus.approved ? 'approved' : 'rejected'} by ${c.decidedBy}'} · “${c.reason}”',
                      style: AppTypography.helper,
                    ),
                  ],
                  [
                    StatusBadge(
                      label: c.status.label,
                      tone: c.status == CorrectionStatus.approved
                          ? StatusTone.success
                          : StatusTone.danger,
                    ),
                  ],
                ),
            ]),
          ],
        );
      },
    );
  }
}
