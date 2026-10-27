import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/router/route_names.dart';
import '../../../core/errors/failure.dart';
import '../../../core/responsive/responsive_page.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_overlays.dart';
import '../../../core/widgets/page_header.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_badge.dart';
import '../../auth/presentation/widgets/auth_widgets.dart';
import '../../employees/presentation/providers/employee_providers.dart';
import '../domain/attendance.dart';
import 'attendance_providers.dart';
import 'selfie_capture.dart';

/// The three enrolment poses, in order.
const facePoses = [
  'Look straight at the camera.',
  'Turn your head slightly to the left.',
  'Turn your head slightly to the right.',
];

/// D-71 — the employee's consent and face set-up for selfie punches.
class FaceSetupScreen extends ConsumerStatefulWidget {
  const FaceSetupScreen({super.key});

  @override
  ConsumerState<FaceSetupScreen> createState() => _FaceSetupScreenState();
}

class _FaceSetupScreenState extends ConsumerState<FaceSetupScreen> {
  bool _agreed = false;
  bool _busy = false;
  final _photos = <Uint8List>[];

  /// True while retaking after a rejection or deletion.
  bool _restart = false;

  Future<void> _capture() async {
    final capture = ref.read(selfieCaptureProvider);
    while (_photos.length < facePoses.length) {
      final photo = await capture.capture(
        context,
        title: 'Photo ${_photos.length + 1} of ${facePoses.length}',
        instruction: facePoses[_photos.length],
      );
      if (photo == null || !mounted) return;
      setState(() => _photos.add(photo));
    }
  }

  Future<void> _send() async {
    setState(() => _busy = true);
    try {
      await ref.read(attendanceDataProvider.notifier).enrolFace(_photos);
      if (!mounted) return;
      setState(() {
        _photos.clear();
        _restart = false;
        _agreed = false;
      });
      showAppToast(context, 'Sent to HR for approval');
    } on Failure catch (f) {
      if (mounted) showAppToast(context, f.message, icon: Icons.error_outline);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showConfirmDialog(
      context,
      title: 'Delete your face data?',
      message:
          'Your set-up photos are deleted. If your branch uses selfie punches, your manager will check each punch selfie until you set up again.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok) return;
    setState(() => _busy = true);
    try {
      await ref.read(attendanceDataProvider.notifier).deleteFace();
      if (mounted) showAppToast(context, 'Face data deleted');
    } on Failure catch (f) {
      if (mounted) showAppToast(context, f.message, icon: Icons.error_outline);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(attendanceDataProvider);
    final self = ref.watch(selfEmployeeProvider);
    if (data.isLoading) {
      return const ResponsivePage(
        child: LoadingSkeleton(label: 'Loading', child: SkeletonList(rows: 4)),
      );
    }
    if (data.hasError) {
      return ErrorState(
        message: userMessageFor(data.error!),
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
    final profile = data.value!.faceProfileOf(self.id);
    final exempt = data.value!.faceExemptions
        .where((x) => x.employeeId == self.id)
        .firstOrNull;
    final setUp =
        profile == null ||
        profile.status == FaceEnrolStatus.rejected ||
        _restart;

    return ResponsivePage(
      maxWidth: 720,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Breadcrumbs(
            items: [
              BreadcrumbItem(
                'Profile',
                onTap: () => context.go(AppRoutes.myProfile),
              ),
              const BreadcrumbItem('Face for attendance'),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          const PageHeader(
            title: 'Face for attendance',
            subtitle: 'Used to check it’s you when you punch with a selfie.',
          ),
          const SizedBox(height: AppSpacing.lg),
          if (exempt != null) ...[
            AppCard(
              child: Text(
                'You don’t need a selfie to punch: “${exempt.reason}” (set by ${exempt.by}).',
                style: AppTypography.small,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          if (profile != null && !_restart) ...[
            AppCard(
              header: CardHeader(
                title: 'Your set-up',
                trailing: StatusBadge(
                  label: profile.status.label,
                  tone: switch (profile.status) {
                    FaceEnrolStatus.approved => StatusTone.success,
                    FaceEnrolStatus.pending => StatusTone.warning,
                    FaceEnrolStatus.rejected => StatusTone.danger,
                  },
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FacePhotos(photos: profile.photos),
                  const SizedBox(height: AppSpacing.md),
                  Text(switch (profile.status) {
                    FaceEnrolStatus.pending =>
                      'Sent ${DateFormat('d MMM, HH:mm').format(profile.submittedAt.toLocal())}. HR checks the photos before selfie punches can be verified.',
                    FaceEnrolStatus.approved =>
                      'Approved by ${profile.decidedBy ?? 'HR'}. Your punch selfies are compared with these photos.',
                    FaceEnrolStatus.rejected =>
                      'Not approved by ${profile.decidedBy ?? 'HR'}: “${profile.rejectReason}”. Take the photos again below.',
                  }, style: AppTypography.small),
                  if (profile.status != FaceEnrolStatus.rejected) ...[
                    const SizedBox(height: AppSpacing.md),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        AppButton(
                          label: 'Take new photos',
                          variant: AppButtonVariant.secondary,
                          onPressed: _busy
                              ? null
                              : () => setState(() => _restart = true),
                        ),
                        AppButton(
                          label: 'Delete my face data',
                          variant: AppButtonVariant.dangerOutline,
                          onPressed: _busy ? null : _delete,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          if (setUp) ...[
            const AppCard(
              header: CardHeader(title: 'Before you start'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Point(
                    'What we collect',
                    'Three photos of your face now, and a selfie each time you punch.',
                  ),
                  _Point(
                    'Why',
                    'To confirm it’s you punching in and out, not someone else.',
                  ),
                  _Point(
                    'Who sees them',
                    'HR approves your set-up. Your manager sees a punch selfie only when it couldn’t be verified.',
                  ),
                  _Point(
                    'How long',
                    'Punch selfies are deleted after 90 days. Set-up photos are kept until you delete them or leave.',
                  ),
                  _Point(
                    'Your choice',
                    'You can delete your face data on this page at any time. Without it, your manager checks each punch selfie instead.',
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            AppCard(
              header: const CardHeader(
                title: 'Take three photos',
                subtitle: 'Good light, no mask or sunglasses.',
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_photos.isNotEmpty) ...[
                    FacePhotos(photos: _photos),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  LabeledCheckbox(
                    value: _agreed,
                    onChanged: (v) => setState(() => _agreed = v),
                    label: const Text(
                      'I agree to my face being used to check my attendance, as described above.',
                      style: AppTypography.body,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      if (_photos.length < facePoses.length)
                        AppButton(
                          label: _photos.isEmpty
                              ? 'Start'
                              : 'Continue (${_photos.length} of ${facePoses.length})',
                          icon: Icons.photo_camera_outlined,
                          onPressed: _agreed && !_busy ? _capture : null,
                        )
                      else ...[
                        AppButton(
                          label: 'Send for approval',
                          busy: _busy,
                          onPressed: _agreed ? _send : null,
                        ),
                        AppButton(
                          label: 'Retake',
                          variant: AppButtonVariant.secondary,
                          onPressed: _busy
                              ? null
                              : () => setState(_photos.clear),
                        ),
                      ],
                      if (_restart)
                        AppButton(
                          label: 'Cancel',
                          variant: AppButtonVariant.ghost,
                          onPressed: () => setState(() {
                            _restart = false;
                            _photos.clear();
                          }),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point(this.title, this.text);

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTypography.label),
          Text(text, style: AppTypography.small),
        ],
      ),
    ),
  );
}

/// A row of face photos (enrolment or punch selfie), 96 px each.
class FacePhotos extends StatelessWidget {
  const FacePhotos({super.key, required this.photos, this.labels});

  final List<Uint8List> photos;
  final List<String>? labels;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: AppSpacing.sm,
    runSpacing: AppSpacing.sm,
    children: [
      for (final (i, p) in photos.indexed)
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: SizedBox(
                width: 96,
                height: 128,
                child: Image.memory(
                  p,
                  fit: BoxFit.cover,
                  semanticLabel: labels?.elementAtOrNull(i) ?? 'Face photo',
                  errorBuilder: (_, _, _) => const ColoredBox(
                    color: AppColors.neutralSoft,
                    child: Icon(Icons.face, color: AppColors.textMuted),
                  ),
                ),
              ),
            ),
            if (labels?.elementAtOrNull(i) case final label?)
              Text(label, style: AppTypography.helper),
          ],
        ),
    ],
  );
}
