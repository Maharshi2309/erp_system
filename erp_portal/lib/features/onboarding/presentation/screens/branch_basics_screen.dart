import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/route_names.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_dropdown_field.dart';
import '../../../../core/widgets/app_overlays.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/form_error_summary.dart';
import '../../../../core/widgets/skeleton.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../auth/presentation/widgets/auth_layout.dart';
import '../../../organization/domain/branch.dart';
import '../../../organization/domain/branch_validation.dart';
import '../../../organization/domain/setup_progress.dart';
import '../../../organization/presentation/providers/organization_providers.dart';
import '../../../organization/presentation/widgets/weekly_hours_editor.dart';
import '../widgets/focus_layout.dart';

/// Boards S18–S19 (and S26 on phones) — branch basics and weekly hours.
/// Creates a branch, or edits the basics of [branchId]. Rules, holidays,
/// leave and permissions come afterwards on the branch's checklist.
class BranchBasicsScreen extends ConsumerStatefulWidget {
  const BranchBasicsScreen({super.key, this.branchId});

  /// Null to create a new branch.
  final String? branchId;

  @override
  ConsumerState<BranchBasicsScreen> createState() => _BranchBasicsScreenState();
}

class _BranchBasicsScreenState extends ConsumerState<BranchBasicsScreen> {
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _city = TextEditingController();
  final _pin = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  String _state = indianStates.first;
  WeeklyHours _hours = [...HoursPresets.monSat930];
  bool _contactOpen = false;
  bool _loaded = false;
  bool _busy = false;
  bool _submitted = false;
  Map<String, String> _errors = {};

  bool get _editing => widget.branchId != null;

  @override
  void dispose() {
    for (final c in [_name, _address, _city, _pin, _phone, _email]) {
      c.dispose();
    }
    super.dispose();
  }

  void _fill(Branch branch) {
    if (_loaded) return;
    _loaded = true;
    _name.text = branch.name;
    _address.text = branch.address;
    _city.text = branch.city;
    _pin.text = branch.pin;
    _phone.text = branch.phone;
    _email.text = branch.email;
    _state = indianStates.contains(branch.state) ? branch.state : 'Other';
    _hours = [...branch.hours];
    _contactOpen = branch.phone.isNotEmpty || branch.email.isNotEmpty;
  }

  Future<void> _submit(List<Branch> all) async {
    if (_busy) return;
    final others = all.where((b) => b.id != widget.branchId);
    final errors = validateBranchDetails(
      name: _name.text,
      address: _address.text,
      city: _city.text,
      pin: _pin.text,
      email: _email.text,
      phone: _phone.text,
      hours: _hours,
      otherBranchNames: others.map((b) => b.name),
    );
    setState(() {
      _submitted = true;
      _errors = errors;
      if (errors.containsKey('email')) _contactOpen = true;
    });
    if (errors.isNotEmpty) return;

    setState(() => _busy = true);
    final notifier = ref.read(branchesProvider.notifier);
    try {
      if (_editing) {
        final current = all.firstWhere((b) => b.id == widget.branchId);
        await notifier.save(
          current.copyWith(
            name: _name.text.trim(),
            address: _address.text.trim(),
            city: _city.text.trim(),
            state: _state,
            pin: _pin.text,
            phone: _phone.text.trim(),
            email: _email.text.trim(),
            hours: _hours,
          ),
        );
        if (!mounted) return;
        showAppToast(context, 'Branch details saved');
        context.go(AppRoutes.branchSetup(current.id));
      } else {
        final created = await notifier.create(
          Branch(
            id: '',
            name: _name.text.trim(),
            address: _address.text.trim(),
            city: _city.text.trim(),
            state: _state,
            pin: _pin.text,
            phone: _phone.text.trim(),
            email: _email.text.trim(),
            hours: _hours,
          ),
        );
        await ref
            .read(setupBookmarkProvider.notifier)
            .remember(created.id, SetupStep.attendance);
        if (!mounted) return;
        showAppToast(context, '${created.name} created · 25% set up');
        context.go(AppRoutes.branchSetup(created.id));
      }
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

  void _cancel() => context.go(
    _editing ? AppRoutes.branchSetup(widget.branchId!) : AppRoutes.overview,
  );

  @override
  Widget build(BuildContext context) {
    final branches = ref.watch(branchesProvider);
    final organization = ref.watch(organizationProvider).value;
    final all = branches.value ?? const <Branch>[];
    if (_editing && branches.hasValue) {
      final match = all.where((b) => b.id == widget.branchId).firstOrNull;
      if (match != null) _fill(match);
    }
    final missing =
        _editing &&
        branches.hasValue &&
        !all.any((b) => b.id == widget.branchId);

    final orgName = organization?.name ?? '';
    final kicker = _editing
        ? 'Manage branch'
        : (all.isEmpty
              ? '$orgName · setup step 3 of 3'
              : '$orgName · new branch');
    final heading = _editing
        ? 'Branch details & hours'
        : (all.isEmpty ? 'Set up your first branch' : 'Add a branch');
    final lead = _editing
        ? 'Changes apply from today. Past attendance keeps the hours it was '
              'recorded with.'
        : 'Just the basics: where it is and when it’s open. You’ll configure '
              'the rest step by step afterwards.';
    final fieldErrorCount = _errors.keys.where((k) => k != 'form').length;

    return FocusLayout(
      organizationName: organization?.name,
      maxWidth: 720,
      headerAction: AppButton(
        label: 'Save & go to dashboard',
        size: AppButtonSize.small,
        variant: AppButtonVariant.secondary,
        onPressed: () => context.go(AppRoutes.overview),
      ),
      actions: [
        AppButton(
          label: _editing ? 'Cancel' : 'Back to dashboard',
          variant: AppButtonVariant.secondary,
          onPressed: _cancel,
        ),
        AppButton(
          label: _editing ? 'Save changes' : 'Create Branch',
          busyLabel: _editing ? 'Saving…' : 'Creating…',
          busy: _busy,
          onPressed: branches.hasValue && !missing ? () => _submit(all) : null,
        ),
      ],
      child: missing
          ? const ErrorState(
              headline: '404',
              title: 'This branch doesn’t exist',
              message: 'It may have been removed, or the link is mistyped.',
            )
          : !branches.hasValue
          ? const LoadingSkeleton(
              label: 'Loading branch',
              child: SkeletonList(rows: 4),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(kicker, style: AppTypography.helper),
                Semantics(
                  header: true,
                  child: Text(heading, style: AppTypography.pageTitle),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(lead, style: AppTypography.small),
                const SizedBox(height: AppSpacing.lg),
                if (_errors['form'] case final message?) ...[
                  FormErrorSummary(title: message),
                  const SizedBox(height: AppSpacing.lg),
                ] else if (_submitted && fieldErrorCount > 0) ...[
                  FormErrorSummary(
                    title:
                        'Please fix ${fieldErrorCount == 1 ? '1 thing' : '$fieldErrorCount things'} '
                        'below. Nothing you entered was lost.',
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],
                FormSection(title: 'Branch details', child: _detailsFields()),
                const SizedBox(height: AppSpacing.lg),
                FormSection(
                  title: 'Working hours',
                  subtitle:
                      'When this branch is open. Each day can be different.',
                  trailing: Text(
                    hoursSummary(_hours),
                    style: AppTypography.code,
                  ),
                  child: WeeklyHoursEditor(
                    hours: _hours,
                    errors: _errors,
                    onCopied: (message) => showAppToast(context, message),
                    onChanged: (hours) => setState(() {
                      _hours = hours;
                      _errors.removeWhere((k, _) => k.startsWith('hours'));
                    }),
                  ),
                ),
                if (!_editing) ...[
                  const SizedBox(height: AppSpacing.md),
                  const Text(
                    'Attendance rules, holidays, leave and permissions aren’t '
                    'needed now — they come next, one at a time, on the '
                    'branch’s setup checklist.',
                    style: AppTypography.helper,
                  ),
                ],
              ],
            ),
    );
  }

  Widget _detailsFields() {
    void clear(String key) {
      if (_errors.containsKey(key)) setState(() => _errors.remove(key));
    }

    final city = AppTextField(
      label: 'City',
      controller: _city,
      errorText: _errors['city'],
      autofillHints: const [AutofillHints.addressCity],
      onChanged: (_) => clear('city'),
    );
    final state = AppDropdownField<String>(
      label: 'State',
      value: _state,
      options: [for (final s in indianStates) AppDropdownOption(s, s)],
      onChanged: (value) => setState(() => _state = value ?? _state),
    );
    final pin = AppTextField(
      label: 'PIN code',
      controller: _pin,
      monospace: true,
      hintText: '6 digits',
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      maxLength: 6,
      errorText: _errors['pin'],
      autofillHints: const [AutofillHints.postalCode],
      onChanged: (_) => clear('pin'),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(
          label: 'Branch name',
          controller: _name,
          hintText: 'e.g. Surat',
          errorText: _errors['name'],
          onChanged: (_) => clear('name'),
        ),
        const SizedBox(height: AppSpacing.lg),
        AppTextField(
          label: 'Address',
          controller: _address,
          hintText: 'Building, street, area',
          errorText: _errors['address'],
          autofillHints: const [AutofillHints.streetAddressLine1],
          onChanged: (_) => clear('address'),
        ),
        const SizedBox(height: AppSpacing.lg),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 520) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  city,
                  const SizedBox(height: AppSpacing.lg),
                  state,
                  const SizedBox(height: AppSpacing.lg),
                  pin,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: city),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: state),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: pin),
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.md),
        const Divider(),
        const SizedBox(height: AppSpacing.sm),
        Align(
          alignment: Alignment.centerLeft,
          child: TextLink(
            _contactOpen
                ? '− Contact details (optional)'
                : '+ Add contact details (optional)',
            onTap: () => setState(() => _contactOpen = !_contactOpen),
          ),
        ),
        if (_contactOpen) ...[
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            label: 'Phone',
            isOptional: true,
            controller: _phone,
            monospace: true,
            keyboardType: TextInputType.phone,
            errorText: _errors['phone'],
          ),
          const SizedBox(height: AppSpacing.lg),
          AppTextField(
            label: 'Email',
            isOptional: true,
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            errorText: _errors['email'],
            onChanged: (_) => clear('email'),
          ),
        ],
      ],
    );
  }
}
