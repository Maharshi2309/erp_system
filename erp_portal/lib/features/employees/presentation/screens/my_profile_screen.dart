import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/responsive/responsive_page.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_dropdown_field.dart';
import '../../../../core/widgets/app_overlays.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/skeleton.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../organization/presentation/providers/organization_providers.dart';
import '../../../settings/domain/settings.dart';
import '../../../settings/presentation/settings_providers.dart';
import '../../domain/employee.dart';
import '../../domain/employee_rules.dart';
import '../providers/employee_providers.dart';
import '../widgets/employee_widgets.dart';

/// Board S94 — the employee's own profile.
class MyProfileScreen extends ConsumerWidget {
  const MyProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final employees = ref.watch(employeesProvider);
    if (session == null || employees.isLoading) {
      return const ResponsivePage(
        child: LoadingSkeleton(label: 'Loading', child: SkeletonList(rows: 6)),
      );
    }
    final self = ref.watch(selfEmployeeProvider);
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
    final all = employees.value ?? const <Employee>[];
    final manager = all.where((e) => e.id == self.managerId).firstOrNull;
    final branch = (ref.watch(branchesProvider).value ?? const [])
        .where((b) => b.id == self.branchId)
        .firstOrNull;
    final settings = ref.watch(orgSettingsProvider).value;
    final language =
        self.customValues['preferred_language'] as String? ??
        settings?.branding.language ??
        'English (India)';
    final twoStep = settings?.security.twoStep.requires(session.role) ?? false;

    Future<void> edit() async {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => _ContactDialog(employee: self, language: language),
      );
      if (ok == true && context.mounted) {
        showAppToast(context, 'Contact details saved');
      }
    }

    Future<void> reset() async {
      await ref
          .read(authRepositoryProvider)
          .requestPasswordReset(session.email);
      if (context.mounted) {
        showAppToast(
          context,
          'We sent a password reset link to ${session.email}',
        );
      }
    }

    Widget row(String k, String v, {bool locked = false, Color? color}) =>
        MergeSemantics(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(k, style: AppTypography.helper),
                      Text(
                        v.isEmpty ? 'Not provided' : v,
                        style: AppTypography.small.copyWith(
                          color: color ?? AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (locked)
                  const Icon(
                    Icons.lock_outline,
                    size: 16,
                    color: AppColors.textMuted,
                    semanticLabel: 'Managed by HR',
                  ),
              ],
            ),
          ),
        );

    return ResponsivePage(
      maxWidth: 720,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: const Text('My profile', style: AppTypography.pageTitle),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              EmployeeAvatar(employee: self, size: 56),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(self.fullName, style: AppTypography.sectionTitle),
                    Text(
                      '${self.designation} · ${self.department}',
                      style: AppTypography.small,
                    ),
                    Text(self.code, style: AppTypography.code),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            header: CardHeader(
              title: 'Contact',
              subtitle: 'You can edit these',
              trailing: AppButton(
                label: 'Edit',
                size: AppButtonSize.small,
                variant: AppButtonVariant.secondary,
                onPressed: edit,
              ),
            ),
            child: Column(
              children: [
                row('Mobile', self.mobile),
                row('Emergency contact', self.emergencyContact),
                row('Preferred language', language),
                row('Work email', self.workEmail, locked: true),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            header: const CardHeader(
              title: 'Employment',
              subtitle: 'Managed by HR',
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                row('Branch', branch?.name ?? '', locked: true),
                row('Manager', manager?.fullName ?? '', locked: true),
                row('Shift', describeShift(self, branch), locked: true),
                row(
                  'Joined',
                  DateFormat('d MMM y').format(self.joiningDate),
                  locked: true,
                ),
                const SizedBox(height: AppSpacing.sm),
                const Text(
                  'Something wrong? Ask HR to update it.',
                  style: AppTypography.helper,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            header: const CardHeader(title: 'Account & security'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                row('Password', 'Never shown'),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: reset,
                    child: const Text('Reset by email'),
                  ),
                ),
                row(
                  'Two-step verification',
                  twoStep
                      ? 'Required by ${session.organizationName}'
                      : 'Optional — recommended',
                  color: twoStep ? null : AppColors.warningText,
                ),
                row('Signed in on', 'This browser'),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppButton(
            label: 'Sign out',
            variant: AppButtonVariant.secondary,
            expand: true,
            onPressed: () =>
                ref.read(authControllerProvider.notifier).signOut(),
          ),
        ],
      ),
    );
  }
}

class _ContactDialog extends ConsumerStatefulWidget {
  const _ContactDialog({required this.employee, required this.language});

  final Employee employee;
  final String language;

  @override
  ConsumerState<_ContactDialog> createState() => _ContactDialogState();
}

class _ContactDialogState extends ConsumerState<_ContactDialog> {
  late final _mobile = TextEditingController(text: widget.employee.mobile);
  late final _emergency = TextEditingController(
    text: widget.employee.emergencyContact,
  );
  late String _language = BrandingSettings.languages.contains(widget.language)
      ? widget.language
      : BrandingSettings.languages.first;
  bool _busy = false;
  Map<String, String> _errors = const {};

  @override
  void dispose() {
    _mobile.dispose();
    _emergency.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _errors = const {};
    });
    try {
      await ref
          .read(employeesProvider.notifier)
          .saveOwnContact(
            mobile: _mobile.text,
            emergencyContact: _emergency.text,
            language: _language,
          );
      if (mounted) Navigator.of(context).pop(true);
    } on Failure catch (f) {
      if (mounted) {
        setState(
          () => _errors = f is ValidationFailure
              ? f.fieldErrors
              : {'form': f.message},
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Edit contact'),
    content: SizedBox(
      width: 400,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTextField(
              label: 'Mobile',
              controller: _mobile,
              keyboardType: TextInputType.phone,
              errorText: _errors['mobile'],
            ),
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              label: 'Emergency contact',
              isOptional: true,
              controller: _emergency,
              helperText: 'Name and phone number',
            ),
            const SizedBox(height: AppSpacing.md),
            AppDropdownField<String>(
              label: 'Preferred language',
              value: _language,
              options: [
                for (final l in BrandingSettings.languages)
                  AppDropdownOption(l, l),
              ],
              onChanged: (v) => setState(() => _language = v ?? _language),
            ),
            if (_errors['form'] != null)
              Text(
                _errors['form']!,
                style: AppTypography.small.copyWith(color: AppColors.danger),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.of(context).pop(false),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _busy ? null : _save,
        child: Text(_busy ? 'Saving…' : 'Save'),
      ),
    ],
  );
}
