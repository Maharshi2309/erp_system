import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/route_names.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/initials.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_overlays.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/selection_controls.dart';
import '../../../../core/widgets/skeleton.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../organization/domain/organization.dart';
import '../../../organization/presentation/providers/organization_providers.dart';
import '../widgets/focus_layout.dart';
import '../widgets/image_upload_field.dart';

/// Board S16 — the owner's profile. Name and email come from sign-in;
/// phone, designation and a photo are the only things to add.
class OwnerProfileScreen extends ConsumerStatefulWidget {
  const OwnerProfileScreen({super.key});

  @override
  ConsumerState<OwnerProfileScreen> createState() => _OwnerProfileScreenState();
}

class _OwnerProfileScreenState extends ConsumerState<OwnerProfileScreen> {
  static const _designations = [
    'Founder',
    'Managing Director',
    'Proprietor',
    'HR Head',
  ];

  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _designation = TextEditingController();
  final _email = TextEditingController();
  Uint8List? _photo;
  bool _loaded = false;
  bool _busy = false;
  Map<String, String> _errors = {};

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _designation.dispose();
    _email.dispose();
    super.dispose();
  }

  void _fill(OwnerProfile? saved) {
    if (_loaded) return;
    _loaded = true;
    final session = ref.read(sessionProvider);
    _name.text = saved?.fullName ?? session?.displayName ?? '';
    _email.text = session?.email ?? '';
    _phone.text = saved?.phone ?? '';
    _designation.text = saved?.designation ?? '';
    _photo = saved?.photo;
  }

  Future<void> _save() async {
    if (_busy) return;
    final errors = {
      if (_name.text.trim().isEmpty)
        'name': 'Enter your full name.'
      else if (!Validators.isPersonName(_name.text, max: 80))
        'name': Validators.nameMessage,
      if (_phone.text.trim().isNotEmpty && !Validators.isMobile(_phone.text))
        'phone': Validators.mobileMessage,
    };
    setState(() => _errors = errors);
    if (errors.isNotEmpty) return;

    final session = ref.read(sessionProvider)!;
    final hadBranches =
        (ref.read(branchesProvider).value ?? const []).isNotEmpty;
    setState(() => _busy = true);
    try {
      await ref
          .read(ownerProfileProvider.notifier)
          .save(
            OwnerProfile(
              fullName: _name.text.trim(),
              email: session.email,
              phone: _phone.text.trim(),
              designation: _designation.text.trim(),
              photo: _photo,
            ),
          );
      if (!mounted) return;
      showAppToast(
        context,
        hadBranches
            ? 'Owner profile saved'
            : 'Owner profile saved. Next: your first branch.',
      );
      context.go(AppRoutes.overview);
    } on Failure catch (failure) {
      if (mounted) setState(() => _errors = {'name': failure.message});
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final saved = ref.watch(ownerProfileProvider);
    final organization = ref.watch(organizationProvider).value;
    if (saved.hasValue) _fill(saved.value);

    return FocusLayout(
      organizationName: organization?.name,
      headerAction: AppButton(
        label: 'Save & go to dashboard',
        size: AppButtonSize.small,
        variant: AppButtonVariant.secondary,
        onPressed: _busy ? null : _save,
      ),
      actions: [
        AppButton(
          label: 'Back to dashboard',
          variant: AppButtonVariant.secondary,
          onPressed: () => context.go(AppRoutes.overview),
        ),
        AppButton(
          label: 'Save Owner Profile',
          busyLabel: 'Saving…',
          busy: _busy,
          onPressed: _save,
        ),
      ],
      child: !saved.hasValue
          ? const LoadingSkeleton(
              label: 'Loading your profile',
              child: SkeletonList(rows: 4),
            )
          : Container(
              padding: const EdgeInsets.all(AppSpacing.xl),
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${organization?.name ?? ''} · setup step 2 of 3',
                    style: AppTypography.helper,
                  ),
                  Semantics(
                    header: true,
                    child: const Text(
                      'Owner profile',
                      style: AppTypography.sectionTitle,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  const Text(
                    'This is your account as the organisation’s owner. It stays '
                    'separate from employee records and branch settings. We’ve '
                    'filled in what we already know.',
                    style: AppTypography.small,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  ImageUploadField(
                    label: 'Profile photo',
                    image: _photo,
                    round: true,
                    placeholder: Text(
                      initialsOf(_name.text),
                      style: AppTypography.cardTitle.copyWith(
                        color: AppColors.primaryHover,
                      ),
                    ),
                    onChanged: (photo) => setState(() => _photo = photo),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _TwoColumns(
                    left: AppTextField(
                      label: 'Full name',
                      controller: _name,
                      errorText: _errors['name'],
                      autofillHints: const [AutofillHints.name],
                      onChanged: (_) => setState(() => _errors.remove('name')),
                    ),
                    right: AppTextField(
                      label: 'Email',
                      controller: _email,
                      readOnly: true,
                      helperText:
                          'From your sign-in. Change it in your account settings.',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _TwoColumns(
                    left: AppTextField(
                      label: 'Mobile number',
                      controller: _phone,
                      monospace: true,
                      hintText: '+91 98250 41736',
                      keyboardType: TextInputType.phone,
                      errorText: _errors['phone'],
                      helperText: 'Used only for account recovery.',
                      onChanged: (_) => setState(() => _errors.remove('phone')),
                    ),
                    right: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AppTextField(
                          label: 'Designation',
                          isOptional: true,
                          controller: _designation,
                          hintText: 'e.g. Managing Director',
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        ChoiceChips<String>(
                          options: [for (final d in _designations) (d, d)],
                          selected: _designation.text,
                          onSelected: (d) =>
                              setState(() => _designation.text = d),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

/// Two fields side by side, stacked below 520 px.
class _TwoColumns extends StatelessWidget {
  const _TwoColumns({required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 520) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              left,
              const SizedBox(height: AppSpacing.lg),
              right,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: left),
            const SizedBox(width: AppSpacing.lg),
            Expanded(child: right),
          ],
        );
      },
    );
  }
}
