import 'dart:typed_data';

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
import '../../../../core/utils/zoned_time.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_overlays.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../employees/domain/employee.dart';
import '../../../employees/presentation/providers/employee_providers.dart';
import '../../../employees/presentation/widgets/employee_widgets.dart';
import '../../domain/attendance.dart';
import '../attendance_providers.dart';
import '../face_setup_screen.dart';
import 'attendance_section.dart';

/// D-70 — punch selfies to review, face set-ups to approve, and who in the
/// selfie branches is set up.
class FaceCheckScreen extends ConsumerWidget {
  const FaceCheckScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => AttendanceSection(
    current: AppRoutes.faceCheck,
    body: (context, scope) {
      final data = scope.book.data;
      final session = scope.session;
      final self = ref.watch(selfEmployeeProvider);
      final selfieBranches = [
        for (final b in scope.branches)
          if (b.attendance?.selfieCheck == true) b,
      ];
      final byId = {for (final e in scope.people) e.id: e};
      final canReview = session.permissions.can(
        PermissionModule.attendance,
        PermissionAction.approve,
      );
      // Set-ups are approved by HR and the owner (organization scope).
      final canApproveSetup =
          session.scope == DataScope.organization &&
          session.permissions.can(
            PermissionModule.employees,
            PermissionAction.edit,
          );
      final toReview = [
        for (final p in data.punchesToReview)
          if (byId.containsKey(p.employeeId)) p,
      ]..sort((a, b) => a.at.compareTo(b.at));
      final setups = [
        for (final f in data.faceProfiles)
          if (f.status == FaceEnrolStatus.pending &&
              byId.containsKey(f.employeeId))
            f,
      ];
      final people = [
        for (final e in scope.people)
          if (selfieBranches.any((b) => b.id == e.branchId)) e,
      ]..sort((a, b) => a.fullName.compareTo(b.fullName));

      Future<void> run(Future<void> Function() action, String done) async {
        try {
          await action();
          if (context.mounted) showAppToast(context, done);
        } on Failure catch (f) {
          if (context.mounted) {
            showAppToast(context, f.message, icon: Icons.error_outline);
          }
        }
      }

      Future<void> review(Punch p, Employee e, bool accept) async {
        String note = '';
        if (!accept) {
          final reason = await showReasonDialog(
            context,
            title: 'Don’t accept this punch?',
            message:
                '${e.fullName}’s ${p.kind.label.toLowerCase()} won’t count. They can request a correction if it was them.',
            confirmLabel: 'Don’t accept',
            label: 'Reason the employee will see',
          );
          if (reason == null) return;
          note = reason;
        }
        await run(
          () => ref
              .read(attendanceDataProvider.notifier)
              .reviewFacePunch(p, accept: accept, note: note),
          accept ? 'Punch accepted' : 'Punch not accepted',
        );
      }

      Future<void> decideSetup(Employee e, bool approve) async {
        String reason = '';
        if (!approve) {
          final r = await showReasonDialog(
            context,
            title: 'Don’t approve this set-up?',
            message: '${e.fullName} will be asked to take the photos again.',
            confirmLabel: 'Don’t approve',
            label: 'Reason the employee will see',
          );
          if (r == null) return;
          reason = r;
        }
        await run(
          () => ref
              .read(attendanceDataProvider.notifier)
              .decideFace(e, approve: approve, reason: reason),
          approve ? 'Set-up approved' : 'Set-up not approved',
        );
      }

      Future<void> exempt(Employee e, bool on) async {
        String? reason;
        if (on) {
          reason = await showReasonDialog(
            context,
            title: 'Punch without a selfie?',
            message:
                '${e.fullName} will punch without a selfie until you change this.',
            confirmLabel: 'Allow',
            destructive: false,
          );
          if (reason == null) return;
        }
        await run(
          () => ref
              .read(attendanceDataProvider.notifier)
              .setFaceExemption(e, reason: reason),
          on ? 'Selfie not needed for ${e.firstName}' : 'Selfie needed again',
        );
      }

      if (selfieBranches.isEmpty && toReview.isEmpty && setups.isEmpty) {
        return AppCard(
          child: EmptyState(
            icon: Icons.face_retouching_natural_outlined,
            title: 'Selfie punches are off',
            message:
                'When a branch turns them on, employees take a selfie with each punch and it’s matched to their enrolled face. Punches that can’t be verified wait here for review.',
            actions: [
              if (session.permissions.can(
                PermissionModule.settings,
                PermissionAction.edit,
              ))
                AppButton(
                  label: 'Open attendance policy',
                  variant: AppButtonVariant.secondary,
                  onPressed: () => context.go(AppRoutes.settingsAttendance),
                ),
            ],
          ),
        );
      }

      final zone = scope.book.orgZone;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AttendanceHeader(
            title: 'Face check',
            subtitle: selfieBranches.isEmpty
                ? 'Selfie punches are off in your branches'
                : 'Selfie punches on at ${selfieBranches.map((b) => b.name).join(', ')}',
          ),
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            header: CardHeader(
              title: 'Punches to review',
              subtitle: 'Saved, but the face wasn’t verified',
              trailing: StatusBadge(
                label: '${toReview.length}',
                tone: toReview.isEmpty
                    ? StatusTone.neutral
                    : StatusTone.warning,
              ),
            ),
            child: toReview.isEmpty
                ? const Text('Nothing to review.', style: AppTypography.small)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final p in toReview)
                        _ReviewRow(
                          punch: p,
                          employee: byId[p.employeeId]!,
                          enrolled: data
                              .faceProfileOf(p.employeeId)
                              ?.photos
                              .firstOrNull,
                          when: DateFormat(
                            'EEE d MMM, HH:mm',
                          ).format(wallTime(p.at, zone)),
                          own: p.employeeId == self?.id,
                          canReview: canReview,
                          onAccept: () => review(p, byId[p.employeeId]!, true),
                          onReject: () => review(p, byId[p.employeeId]!, false),
                        ),
                    ],
                  ),
          ),
          if (canApproveSetup) ...[
            const SizedBox(height: AppSpacing.lg),
            AppCard(
              header: CardHeader(
                title: 'Set-ups waiting for approval',
                subtitle: 'Check the photos are clear and of the same person',
                trailing: StatusBadge(
                  label: '${setups.length}',
                  tone: setups.isEmpty ? StatusTone.neutral : StatusTone.info,
                ),
              ),
              child: setups.isEmpty
                  ? const Text(
                      'No set-ups waiting.',
                      style: AppTypography.small,
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final f in setups)
                          _SetupRow(
                            profile: f,
                            employee: byId[f.employeeId]!,
                            own: f.employeeId == self?.id,
                            onApprove: () =>
                                decideSetup(byId[f.employeeId]!, true),
                            onReject: () =>
                                decideSetup(byId[f.employeeId]!, false),
                          ),
                      ],
                    ),
            ),
          ],
          if (people.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            AppCard(
              header: CardHeader(
                title: 'People in selfie branches',
                subtitle:
                    '${people.where((e) => data.faceProfileOf(e.id)?.status == FaceEnrolStatus.approved).length} of ${people.length} set up',
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final e in people)
                    _PersonRow(
                      employee: e,
                      profile: data.faceProfileOf(e.id),
                      exemption: data.faceExemptions
                          .where((x) => x.employeeId == e.id)
                          .firstOrNull,
                      canExempt: canApproveSetup,
                      onExempt: (on) => exempt(e, on),
                    ),
                ],
              ),
            ),
          ],
        ],
      );
    },
  );
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({
    required this.punch,
    required this.employee,
    required this.enrolled,
    required this.when,
    required this.own,
    required this.canReview,
    required this.onAccept,
    required this.onReject,
  });

  final Punch punch;
  final Employee employee;
  final Uint8List? enrolled;
  final String when;
  final bool own;
  final bool canReview;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final face = punch.face!;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Wrap(
        spacing: AppSpacing.lg,
        runSpacing: AppSpacing.md,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          FacePhotos(
            photos: [?face.photo, ?enrolled],
            labels: ['Punch selfie', if (enrolled != null) 'Enrolled'],
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 200, maxWidth: 320),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(employee.fullName, style: AppTypography.label),
                Text(
                  '${employee.code} · ${punch.kind.label} · $when',
                  style: AppTypography.small,
                ),
                const SizedBox(height: AppSpacing.xs),
                StatusBadge(
                  label: face.score == null
                      ? face.result.label
                      : '${face.result.label} · ${(face.score! * 100).round()}% similar',
                  tone: StatusTone.warning,
                ),
              ],
            ),
          ),
          if (own)
            const Text(
              'Your own punch — someone else reviews it.',
              style: AppTypography.helper,
            )
          else if (canReview)
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                AppButton(label: 'Accept', onPressed: onAccept),
                AppButton(
                  label: 'Don’t accept…',
                  variant: AppButtonVariant.dangerOutline,
                  onPressed: onReject,
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _SetupRow extends StatelessWidget {
  const _SetupRow({
    required this.profile,
    required this.employee,
    required this.own,
    required this.onApprove,
    required this.onReject,
  });

  final FaceProfile profile;
  final Employee employee;
  final bool own;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AppColors.divider)),
    ),
    child: Wrap(
      spacing: AppSpacing.lg,
      runSpacing: AppSpacing.md,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        FacePhotos(photos: profile.photos),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 200, maxWidth: 320),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(employee.fullName, style: AppTypography.label),
              Text(
                '${employee.code} · ${employee.designation} · sent ${DateFormat('d MMM').format(profile.submittedAt.toLocal())}',
                style: AppTypography.small,
              ),
            ],
          ),
        ),
        if (own)
          const Text(
            'Your own set-up — someone else approves it.',
            style: AppTypography.helper,
          )
        else
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              AppButton(label: 'Approve', onPressed: onApprove),
              AppButton(
                label: 'Don’t approve…',
                variant: AppButtonVariant.dangerOutline,
                onPressed: onReject,
              ),
            ],
          ),
      ],
    ),
  );
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({
    required this.employee,
    required this.profile,
    required this.exemption,
    required this.canExempt,
    required this.onExempt,
  });

  final Employee employee;
  final FaceProfile? profile;
  final FaceExemption? exemption;
  final bool canExempt;
  final ValueChanged<bool> onExempt;

  @override
  Widget build(BuildContext context) {
    final (label, tone) = exemption != null
        ? ('No selfie needed', StatusTone.neutral)
        : switch (profile?.status) {
            FaceEnrolStatus.approved => ('Set up', StatusTone.success),
            FaceEnrolStatus.pending => (
              'Waiting for approval',
              StatusTone.info,
            ),
            FaceEnrolStatus.rejected => ('Not approved', StatusTone.danger),
            null => ('Not set up', StatusTone.warning),
          };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          EmployeeAvatar(employee: employee, size: 32),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(employee.fullName, style: AppTypography.label),
                Text(
                  exemption == null
                      ? employee.code
                      : '${employee.code} · “${exemption!.reason}”',
                  style: AppTypography.helper,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          StatusBadge(label: label, tone: tone),
          if (canExempt)
            PopupMenuButton<bool>(
              tooltip: 'Selfie options for ${employee.fullName}',
              onSelected: onExempt,
              itemBuilder: (_) => [
                if (exemption == null)
                  const PopupMenuItem(
                    value: true,
                    child: Text('Punch without a selfie…'),
                  )
                else
                  const PopupMenuItem(
                    value: false,
                    child: Text('Require a selfie again'),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
