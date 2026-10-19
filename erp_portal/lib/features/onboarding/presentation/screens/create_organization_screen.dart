import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/route_names.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_overlays.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/form_error_summary.dart';
import '../../../../core/widgets/selection_controls.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../auth/presentation/widgets/auth_widgets.dart';
import '../../../organization/domain/organization.dart';
import '../../../organization/presentation/providers/organization_providers.dart';
import '../widgets/focus_layout.dart';
import '../widgets/image_upload_field.dart';

/// Boards S13–S14 — create the organization with three fields only.
/// Everything else waits until the owner is inside (design guide p. 6).
class CreateOrganizationScreen extends ConsumerStatefulWidget {
  const CreateOrganizationScreen({super.key});

  @override
  ConsumerState<CreateOrganizationScreen> createState() =>
      _CreateOrganizationScreenState();
}

class _CreateOrganizationScreenState
    extends ConsumerState<CreateOrganizationScreen> {
  final _name = TextEditingController();
  final _nameFocus = FocusNode();
  Uint8List? _logo;
  String? _range;
  bool _busy = false;
  bool _submitted = false;
  Map<String, String> _errors = {};

  @override
  void dispose() {
    _name.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_busy) return;
    final name = _name.text.trim();
    final errors = <String, String>{
      if (name.isEmpty)
        'name': 'Enter your organisation name.'
      else if (name.length < 2)
        'name': 'Use at least 2 characters.',
      if (_range == null) 'range': 'Choose how many people work here.',
    };
    setState(() {
      _submitted = true;
      _errors = errors;
    });
    if (errors.isNotEmpty) return;

    final auth = ref.read(authControllerProvider.notifier);
    final account = auth.currentAccount;
    if (account == null) return;
    setState(() => _busy = true);
    try {
      final organization = await ref
          .read(organizationRepositoryProvider)
          .createOrganization(
            ownerAccountId: account.id,
            ownerName: account.fullName,
            ownerEmail: account.email,
            name: name,
            employeeRange: _range!,
            logo: _logo,
          );
      await auth.enterNewOrganization(organization.id);
      if (!mounted) return;
      showAppToast(
        context,
        '${organization.name} is created. Next: your owner profile.',
      );
      context.go(AppRoutes.overview);
    } on ValidationFailure catch (failure) {
      if (mounted) {
        setState(
          () => _errors = failure.fieldErrors.isEmpty
              ? {'form': failure.message}
              : {...failure.fieldErrors},
        );
      }
    } on Failure catch (failure) {
      if (mounted) setState(() => _errors = {'form': failure.message});
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fieldErrors = _errors.keys.where((k) => k != 'form').length;
    return FocusLayout(
      actions: [
        AppButton(
          label: 'Cancel',
          variant: AppButtonVariant.secondary,
          onPressed: () => context.go(AppRoutes.onboarding),
        ),
        AppButton(
          label: 'Create Organisation',
          busyLabel: 'Creating…',
          busy: _busy,
          onPressed: _create,
        ),
      ],
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.xl),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: const Text(
                'Create your organisation',
                style: AppTypography.sectionTitle,
              ),
            ),
            const Text(
              'Three quick details. Everything else can wait until you’re '
              'inside.',
              style: AppTypography.helper,
            ),
            const SizedBox(height: AppSpacing.lg),
            if (_errors['form'] case final message?) ...[
              AuthNotice(message: message, tone: NoticeTone.error),
              const SizedBox(height: AppSpacing.lg),
            ] else if (_submitted && fieldErrors > 0) ...[
              FormErrorSummary(
                title:
                    'Please fix ${fieldErrors == 1 ? '1 thing' : '$fieldErrors things'} '
                    'before creating your organisation.',
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
            ImageUploadField(
              label: 'Organisation logo',
              image: _logo,
              onChanged: (logo) => setState(() => _logo = logo),
            ),
            const SizedBox(height: AppSpacing.lg),
            AppTextField(
              label: 'Organisation name',
              controller: _name,
              focusNode: _nameFocus,
              hintText: 'Enter organisation name',
              errorText: _errors['name'],
              onChanged: (_) => setState(() => _errors.remove('name')),
              onSubmitted: (_) => _create(),
            ),
            const SizedBox(height: AppSpacing.lg),
            Semantics(
              header: true,
              child: const Text(
                'How many people work here?',
                style: AppTypography.label,
              ),
            ),
            const SizedBox(height: 6),
            ChoiceChips<String>(
              options: [for (final r in employeeRanges) (r, r)],
              selected: _range,
              hasError: _errors.containsKey('range'),
              minWidth: 88,
              onSelected: (r) => setState(() {
                _range = r;
                _errors.remove('range');
              }),
            ),
            const SizedBox(height: 6),
            Text(
              _errors['range'] ??
                  'Helps us suggest sensible defaults. You can change it later.',
              style: AppTypography.helper.copyWith(
                color: _errors.containsKey('range')
                    ? AppColors.danger
                    : AppColors.textMuted,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            const Text(
              'You can change any of this later in Settings.',
              textAlign: TextAlign.end,
              style: AppTypography.helper,
            ),
          ],
        ),
      ),
    );
  }
}
