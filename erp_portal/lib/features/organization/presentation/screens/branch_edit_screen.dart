import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/route_names.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_dropdown_field.dart';
import '../../../../core/widgets/app_overlays.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/form_error_summary.dart';
import '../../../../core/widgets/selection_controls.dart';
import '../../../../core/widgets/skeleton.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../auth/presentation/widgets/auth_layout.dart';
import '../../../onboarding/presentation/widgets/focus_layout.dart';
import '../../domain/branch.dart';
import '../../domain/branch_validation.dart';
import '../../domain/organization.dart';
import '../../domain/setup_progress.dart';
import '../providers/organization_providers.dart';
import '../setup_text.dart';
import '../widgets/weekly_hours_editor.dart';

/// Inherit-from-organization choice in the time zone select.
const _inherit = '';

/// Board S37 — the full branch form, for edits after first setup.
class BranchEditScreen extends ConsumerStatefulWidget {
  const BranchEditScreen({super.key, required this.branchId});

  final String branchId;

  @override
  ConsumerState<BranchEditScreen> createState() => _BranchEditScreenState();
}

class _BranchEditScreenState extends ConsumerState<BranchEditScreen> {
  final _c = {
    for (final f in [
      'name',
      'code',
      'address',
      'city',
      'pin',
      'phone',
      'email',
    ])
      f: TextEditingController(),
  };
  String _state = indianStates.first;
  String _timeZone = _inherit;
  WeeklyHours _hours = [...HoursPresets.monSat930];
  BranchStatus _status = BranchStatus.active;
  bool _loaded = false;
  bool _busy = false;
  Map<String, String> _errors = {};

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _fill(Branch b) {
    if (_loaded) return;
    _loaded = true;
    _c['name']!.text = b.name;
    _c['code']!.text = b.code;
    _c['address']!.text = b.address;
    _c['city']!.text = b.city;
    _c['pin']!.text = b.pin;
    _c['phone']!.text = b.phone;
    _c['email']!.text = b.email;
    _state = indianStates.contains(b.state) ? b.state : 'Other';
    _timeZone = b.timeZone ?? _inherit;
    _hours = [...b.hours];
    _status = b.status;
  }

  String _t(String key) => _c[key]!.text.trim();

  Future<void> _save(Branch branch, List<Branch> all) async {
    if (_busy) return;
    final others = all.where((b) => b.id != branch.id);
    final errors = validateBranchDetails(
      name: _t('name'),
      code: _t('code'),
      address: _t('address'),
      city: _t('city'),
      pin: _t('pin'),
      email: _t('email'),
      phone: _t('phone'),
      hours: _hours,
      otherBranchNames: others.map((b) => b.name),
      otherBranchCodes: others.map((b) => b.code),
    );
    setState(() => _errors = errors);
    if (errors.isNotEmpty) return;

    setState(() => _busy = true);
    final notifier = ref.read(branchesProvider.notifier);
    try {
      await notifier.save(
        branch.copyWith(
          name: _t('name'),
          code: _t('code').toUpperCase(),
          address: _t('address'),
          city: _t('city'),
          state: _state,
          pin: _t('pin'),
          phone: _t('phone'),
          email: _t('email'),
          timeZone: _timeZone == _inherit ? null : _timeZone,
          inheritTimeZone: _timeZone == _inherit,
          hours: _hours,
        ),
      );
      if (_status != branch.status) {
        await notifier.setStatus(branch.id, _status);
      }
      if (!mounted) return;
      showAppToast(context, 'Branch saved');
      context.go(AppRoutes.branch(branch.id));
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
    final branches = ref.watch(branchesProvider);
    final organization = ref.watch(organizationProvider).value;
    final all = branches.value ?? const <Branch>[];
    final branch = all.where((b) => b.id == widget.branchId).firstOrNull;
    if (branch != null) _fill(branch);

    void close() => context.go(AppRoutes.branch(widget.branchId));

    return FocusLayout(
      organizationName: organization?.name,
      maxWidth: 760,
      actions: [
        AppButton(
          label: 'Cancel',
          variant: AppButtonVariant.secondary,
          onPressed: close,
        ),
        AppButton(
          label: 'Save branch',
          busyLabel: 'Saving…',
          busy: _busy,
          onPressed: branch == null ? null : () => _save(branch, all),
        ),
      ],
      child: !branches.hasValue
          ? const LoadingSkeleton(
              label: 'Loading branch',
              child: SkeletonList(rows: 5),
            )
          : branch == null
          ? const ErrorState(
              headline: '404',
              title: 'This branch doesn’t exist',
              message: 'It may have been removed, or the link is mistyped.',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Close',
                      onPressed: close,
                      icon: const Icon(Icons.close),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Semantics(
                            header: true,
                            child: Text(
                              'Edit branch · ${branch.name}',
                              style: AppTypography.pageTitle,
                            ),
                          ),
                          const Text(
                            'Fields marked * are required',
                            style: AppTypography.helper,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                if (_errors.isNotEmpty) ...[
                  FormErrorSummary(
                    title:
                        _errors['form'] ??
                        'Please fix ${_errors.length == 1 ? '1 thing' : '${_errors.length} things'} '
                            'below. Nothing you entered was lost.',
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],
                ..._sections(branch, organization),
              ],
            ),
    );
  }

  List<Widget> _sections(Branch branch, Organization? organization) {
    AppTextField field(
      String key,
      String label, {
      bool required = true,
      bool mono = false,
      String? helper,
      TextInputType? keyboard,
      List<TextInputFormatter>? formatters,
      int? maxLength,
    }) => AppTextField(
      label: label,
      isRequired: required,
      isOptional: !required,
      controller: _c[key],
      monospace: mono,
      helperText: helper,
      keyboardType: keyboard,
      inputFormatters: formatters,
      maxLength: maxLength,
      errorText: _errors[key],
      onChanged: (_) => setState(() => _errors.remove(key)),
    );

    Widget pair(Widget a, Widget b) => LayoutBuilder(
      builder: (context, c) => c.maxWidth < 520
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                a,
                const SizedBox(height: AppSpacing.lg),
                b,
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: a),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: b),
              ],
            ),
    );

    const gap = SizedBox(height: AppSpacing.lg);
    final orgZone = organization?.timeZone ?? defaultTimeZone;
    final hasEmployees = branch.employeeCount > 0;

    return [
      FormSection(
        title: 'Basic information',
        child: pair(
          field('name', 'Branch name'),
          field(
            'code',
            'Branch code',
            mono: true,
            helper: 'Changing the code doesn’t change existing employee IDs.',
          ),
        ),
      ),
      gap,
      FormSection(
        title: 'Address & contact',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            field('address', 'Address'),
            gap,
            pair(
              field('city', 'City'),
              AppDropdownField<String>(
                label: 'State',
                value: _state,
                options: [
                  for (final s in indianStates) AppDropdownOption(s, s),
                ],
                onChanged: (v) => setState(() => _state = v ?? _state),
              ),
            ),
            gap,
            pair(
              field(
                'pin',
                'PIN code',
                mono: true,
                keyboard: TextInputType.number,
                formatters: [FilteringTextInputFormatter.digitsOnly],
                maxLength: 6,
              ),
              field(
                'phone',
                'Phone',
                required: false,
                mono: true,
                keyboard: TextInputType.phone,
              ),
            ),
            gap,
            field(
              'email',
              'Email',
              required: false,
              keyboard: TextInputType.emailAddress,
            ),
          ],
        ),
      ),
      gap,
      FormSection(
        title: 'Time zone & calendar',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppDropdownField<String>(
              label: 'Time zone',
              isRequired: true,
              value: _timeZone,
              helperText:
                  'Used for shift windows and late arrivals. Changes apply from '
                  'today; past attendance keeps the zone it was recorded in.',
              options: [
                AppDropdownOption(_inherit, 'Same as organization · $orgZone'),
                for (final (id, label) in commonTimeZones)
                  AppDropdownOption(id, label),
              ],
              onChanged: (v) => setState(() => _timeZone = v ?? _inherit),
            ),
            gap,
            _ReadOnlyLine(
              label: 'Holiday calendar',
              value: stepNote(branch, SetupStep.holidays),
              linkLabel: 'Change on the setup checklist',
              onTap: () => context.go(
                '${AppRoutes.branchSetup(branch.id)}?step=${SetupStep.holidays.name}',
              ),
            ),
          ],
        ),
      ),
      gap,
      FormSection(
        title: 'Work schedule',
        subtitle:
            'Default for employees here. Changes apply from today; past '
            'attendance is unchanged.',
        trailing: Text(hoursSummary(_hours), style: AppTypography.code),
        child: WeeklyHoursEditor(
          hours: _hours,
          errors: _errors,
          onCopied: (m) => showAppToast(context, m),
          onChanged: (h) => setState(() {
            _hours = h;
            _errors.removeWhere((k, _) => k.startsWith('hours'));
          }),
        ),
      ),
      gap,
      FormSection(
        title: 'Managers & approvers',
        child: _ReadOnlyLine(
          label: 'Branch manager',
          value: stepNote(branch, SetupStep.roles),
          linkLabel: 'Change on the setup checklist',
          onTap: () => context.go(
            '${AppRoutes.branchSetup(branch.id)}?step=${SetupStep.roles.name}',
          ),
        ),
      ),
      gap,
      FormSection(
        title: 'Status',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OptionCard(
              title: 'Active',
              selected: _status == BranchStatus.active,
              onTap: () => setState(() => _status = BranchStatus.active),
            ),
            const SizedBox(height: AppSpacing.sm),
            OptionCard(
              title: 'Inactive',
              description: hasEmployees && branch.isActive
                  ? '${branch.employeeCount} employees must be moved to another '
                        'branch first. History and reports are kept.'
                  : 'No new punches or leave here. History and reports are kept.',
              selected: _status == BranchStatus.inactive,
              onTap: () {
                if (hasEmployees && branch.isActive) return;
                setState(() => _status = BranchStatus.inactive);
              },
            ),
          ],
        ),
      ),
    ];
  }
}

class _ReadOnlyLine extends StatelessWidget {
  const _ReadOnlyLine({
    required this.label,
    required this.value,
    required this.linkLabel,
    required this.onTap,
  });

  final String label;
  final String value;
  final String linkLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTypography.label),
        const SizedBox(height: 2),
        Text(
          value,
          style: AppTypography.small.copyWith(color: AppColors.textPrimary),
        ),
        const SizedBox(height: 2),
        TextLink(linkLabel, onTap: onTap),
      ],
    );
  }
}
