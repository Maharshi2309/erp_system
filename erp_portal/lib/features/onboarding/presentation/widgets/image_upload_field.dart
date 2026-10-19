import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/image_picking.dart';
import '../../../../core/widgets/app_button.dart';

/// Logo or photo picker with preview, Replace and Remove (boards S13, S16).
class ImageUploadField extends ConsumerStatefulWidget {
  const ImageUploadField({
    super.key,
    required this.label,
    required this.image,
    required this.onChanged,
    this.hint = 'PNG or JPG · up to 2 MB · square works best',
    this.round = false,
    this.placeholder,
  });

  final String label;
  final Uint8List? image;
  final ValueChanged<Uint8List?> onChanged;
  final String hint;
  final bool round;

  /// Shown when there is no image (e.g. initials).
  final Widget? placeholder;

  @override
  ConsumerState<ImageUploadField> createState() => _ImageUploadFieldState();
}

class _ImageUploadFieldState extends ConsumerState<ImageUploadField> {
  String? _error;

  Future<void> _pick() async {
    final picked = await ref.read(imagePickingProvider).pickImage();
    if (picked == null || !mounted) return;
    final error = validateImage(picked);
    setState(() => _error = error);
    if (error == null) widget.onChanged(picked.bytes);
  }

  @override
  Widget build(BuildContext context) {
    final image = widget.image;
    final radius = BorderRadius.circular(widget.round ? 28 : AppRadius.md);
    final preview = Container(
      width: 56,
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: radius,
      ),
      clipBehavior: Clip.antiAlias,
      child: image != null
          ? Image.memory(
              image,
              fit: BoxFit.cover,
              width: 56,
              height: 56,
              // A damaged file shows a broken-image mark, not an error.
              errorBuilder: (_, _, _) =>
                  const Icon(Icons.broken_image_outlined),
            )
          : (widget.placeholder ??
                const Icon(Icons.upload_outlined, color: AppColors.primary)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text.rich(
          TextSpan(
            text: widget.label,
            children: [
              TextSpan(
                text: ' (optional)',
                style: AppTypography.label.copyWith(
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
          style: AppTypography.label,
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: image == null ? AppColors.surfaceMuted : AppColors.surface,
            border: Border.all(
              color: _error != null ? AppColors.danger : AppColors.border,
            ),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Row(
            children: [
              Semantics(
                image: true,
                label: image == null
                    ? 'No image yet'
                    : '${widget.label} preview',
                child: preview,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  image == null
                      ? widget.hint
                      : 'Shown in the header and on employee screens.',
                  style: AppTypography.helper,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.xs,
                children: [
                  AppButton(
                    label: image == null ? 'Upload' : 'Replace',
                    size: AppButtonSize.small,
                    variant: AppButtonVariant.secondary,
                    onPressed: _pick,
                  ),
                  if (image != null)
                    AppButton(
                      label: 'Remove',
                      size: AppButtonSize.small,
                      variant: AppButtonVariant.ghost,
                      onPressed: () {
                        setState(() => _error = null);
                        widget.onChanged(null);
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 6),
          Semantics(
            liveRegion: true,
            child: Text(
              _error!,
              style: AppTypography.helper.copyWith(color: AppColors.danger),
            ),
          ),
        ],
      ],
    );
  }
}
