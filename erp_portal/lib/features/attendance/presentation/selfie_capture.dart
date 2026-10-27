import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/state_views.dart';

/// Takes one selfie with the live front camera (D-70). Photos can't be
/// picked from the gallery, so an old picture can't stand in for a person.
abstract interface class SelfieCapture {
  /// The photo as JPEG, or null when the person cancels.
  Future<Uint8List?> capture(
    BuildContext context, {
    required String title,
    required String instruction,
  });
}

/// Tests override this with a fake camera.
final selfieCaptureProvider = Provider<SelfieCapture>(
  (ref) => const CameraSelfieCapture(),
);

class CameraSelfieCapture implements SelfieCapture {
  const CameraSelfieCapture();

  @override
  Future<Uint8List?> capture(
    BuildContext context, {
    required String title,
    required String instruction,
  }) => showDialog<Uint8List>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _SelfieDialog(title: title, instruction: instruction),
  );
}

class _SelfieDialog extends StatefulWidget {
  const _SelfieDialog({required this.title, required this.instruction});

  final String title;
  final String instruction;

  @override
  State<_SelfieDialog> createState() => _SelfieDialogState();
}

class _SelfieDialogState extends State<_SelfieDialog> {
  CameraController? _camera;
  String? _problem;
  Uint8List? _photo;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      // A camera that never answers (busy, blocked, no driver) must not
      // leave the person staring at a spinner (D-81).
      const wait = Duration(seconds: 10);
      final cameras = await availableCameras().timeout(wait);
      if (cameras.isEmpty) throw CameraException('none', 'No camera');
      final front =
          cameras
              .where((c) => c.lensDirection == CameraLensDirection.front)
              .firstOrNull ??
          cameras.first;
      final controller = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize().timeout(wait);
      if (!mounted) return controller.dispose();
      setState(() => _camera = controller);
    } on Object catch (e) {
      if (!mounted) return;
      setState(
        () => _problem = e is CameraException && e.code.contains('Access')
            ? 'Camera access is blocked. Allow the camera for this site or app in your settings, then try again.'
            : e is TimeoutException
            ? 'The camera didn’t start. Close other apps using it, then try again.'
            : 'No camera is available here. Use a phone, or a browser on a computer with a camera.',
      );
    }
  }

  Future<void> _take() async {
    final camera = _camera;
    if (camera == null || _busy) return;
    setState(() => _busy = true);
    try {
      final file = await camera.takePicture();
      final bytes = await file.readAsBytes();
      if (mounted) setState(() => _photo = bytes);
    } on Object {
      if (mounted) {
        setState(() => _problem = 'The photo couldn’t be taken. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _camera?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final phone = MediaQuery.sizeOf(context).width < 600;
    final camera = _camera;
    final Widget view;
    if (_problem != null) {
      view = EmptyState(
        icon: Icons.no_photography_outlined,
        title: 'Can’t use the camera',
        message: _problem!,
      );
    } else if (_photo != null) {
      view = Image.memory(_photo!, fit: BoxFit.cover);
    } else if (camera == null) {
      view = const Center(child: CircularProgressIndicator());
    } else {
      view = Stack(
        fit: StackFit.expand,
        children: [
          FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: camera.value.previewSize?.height ?? 480,
              height: camera.value.previewSize?.width ?? 640,
              child: CameraPreview(camera),
            ),
          ),
          // Oval guide: where to place the face.
          IgnorePointer(
            child: Center(
              child: FractionallySizedBox(
                widthFactor: 0.62,
                heightFactor: 0.72,
                child: DecoratedBox(
                  decoration: ShapeDecoration(
                    shape: OvalBorder(
                      side: BorderSide(
                        color: AppColors.surface.withValues(alpha: 0.9),
                        width: 3,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Dialog(
      insetPadding: phone
          ? EdgeInsets.zero
          : const EdgeInsets.all(AppSpacing.lg),
      shape: phone ? const RoundedRectangleBorder() : null,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(widget.title, style: AppTypography.sectionTitle),
              ),
              Text(
                _photo == null
                    ? widget.instruction
                    : 'Is your whole face clear and well lit?',
                style: AppTypography.small,
              ),
              const SizedBox(height: AppSpacing.md),
              Flexible(
                child: AspectRatio(
                  aspectRatio: 3 / 4,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    child: ColoredBox(color: AppColors.ink, child: view),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  AppButton(
                    label: 'Cancel',
                    variant: AppButtonVariant.secondary,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  if (_photo != null) ...[
                    AppButton(
                      label: 'Retake',
                      variant: AppButtonVariant.secondary,
                      onPressed: () => setState(() => _photo = null),
                    ),
                    AppButton(
                      label: 'Use photo',
                      onPressed: () => Navigator.of(context).pop(_photo),
                    ),
                  ] else if (_problem == null)
                    AppButton(
                      label: 'Take photo',
                      icon: Icons.photo_camera_outlined,
                      busy: _busy,
                      onPressed: camera == null ? null : _take,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
