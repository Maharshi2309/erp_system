import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/permissions/permissions.dart';
import '../../../../core/responsive/responsive_grid.dart';
import '../../../../core/responsive/responsive_page.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/initials.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_dropdown_field.dart';
import '../../../../core/widgets/app_overlays.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/form_error_summary.dart';
import '../../../../core/widgets/page_header.dart';
import '../../../../core/widgets/skeleton.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../onboarding/presentation/widgets/image_upload_field.dart';
import '../../domain/branch.dart';
import '../../domain/organization.dart';
import '../providers/organization_providers.dart';

/// Board S35 — organization profile. Legal name and default time zone are
/// sensitive: saving a change to them asks for confirmation.
class OrganizationProfileScreen extends ConsumerStatefulWidget {
  const OrganizationProfileScreen({super.key});

  @override
  ConsumerState<OrganizationProfileScreen> createState() =>
      _OrganizationProfileScreenState();
}

class _OrganizationProfileScreenState
    extends ConsumerState<OrganizationProfileScreen> {
  static const _fields = [
    'name',
    'industry',
    'legalName',
    'registrationNumber',
    'contactEmail',
    'contactPhone',
    'address',
    'city',
    'pin',
  ];

  final _controllers = {for (final f in _fields) f: TextEditingController()};
  final _organizationId = TextEditingController();
  bool _editing = false;
  bool _busy = false;
  String _state = indianStates.first;
  String _timeZone = defaultTimeZone;
  Uint8List? _logo;
  Map<String, String> _errors = {};

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    _organizationId.dispose();
    super.dispose();
  }

  void _startEdit(Organization org) {
    final values = {
      'name': org.name,
      'industry': org.industry,
      'legalName': org.legalName,
      'registrationNumber': org.registrationNumber,
      'contactEmail': org.contactEmail,
      'contactPhone': org.contactPhone,
      'address': org.address,
      'city': org.city,
      'pin': org.pin,
    };
    values.forEach((k, v) => _controllers[k]!.text = v);
    _organizationId.text = org.id;
    setState(() {
      _state = indianStates.contains(org.state)
          ? org.state
          : indianStates.first;
      _timeZone = org.timeZone;
      _logo = org.logo;
      _errors = {};
      _editing = true;
    });
  }

  String _text(String key) => _controllers[key]!.text.trim();

  Organization _edited(Organization org) => org.copyWith(
    name: _text('name'),
    industry: _text('industry'),
    legalName: _text('legalName'),
    registrationNumber: _text('registrationNumber'),
    contactEmail: _text('contactEmail'),
    contactPhone: _text('contactPhone'),
    address: _text('address'),
    city: _text('city'),
    state: _state,
    pin: _text('pin'),
    timeZone: _timeZone,
    logo: _logo,
    clearLogo: _logo == null,
  );

  Future<void> _save(Organization org) async {
    if (_busy) return;
    final errors = {
      if (_text('name').isEmpty) 'name': 'Enter the display name.',
      if (_text('contactEmail').isNotEmpty &&
          !Validators.isEmail(_text('contactEmail')))
        'contactEmail': 'Check the email address.',
      if (_text('pin').isNotEmpty && !RegExp(r'^\d{6}$').hasMatch(_text('pin')))
        'pin': 'PIN codes have 6 digits.',
    };
    setState(() => _errors = errors);
    if (errors.isNotEmpty) return;

    final edited = _edited(org);
    final sensitive = [
      if (edited.legalName != org.legalName)
        'Legal name: “${org.legalName}” → “${edited.legalName}”',
      if (edited.timeZone != org.timeZone)
        'Default time zone: ${org.timeZone} → ${edited.timeZone}. Branches '
            'that inherit it switch too; past attendance keeps the zone it '
            'was recorded in.',
    ];
    if (sensitive.isNotEmpty) {
      final confirmed = await showConfirmDialog(
        context,
        title: 'Confirm sensitive changes',
        message: sensitive.join('\n\n'),
        confirmLabel: 'Save changes',
      );
      if (!confirmed) return;
    }

    setState(() => _busy = true);
    try {
      await ref.read(organizationProvider.notifier).save(edited);
      if (!mounted) return;
      setState(() => _editing = false);
      showAppToast(context, 'Organization profile saved.');
    } on ValidationFailure catch (failure) {
      if (mounted) setState(() => _errors = {...failure.fieldErrors});
    } on Failure catch (failure) {
      if (mounted) setState(() => _errors = {'form': failure.message});
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final organization = ref.watch(organizationProvider);
    final branches = ref.watch(branchesProvider).value ?? const <Branch>[];
    final canEdit =
        ref
            .watch(sessionProvider)
            ?.permissions
            .can(PermissionModule.organization, PermissionAction.edit) ??
        false;

    return organization.when(
      loading: () => const ResponsivePage(
        child: LoadingSkeleton(
          label: 'Loading organization profile',
          child: SkeletonList(rows: 6),
        ),
      ),
      error: (error, _) => ErrorState(
        message: userMessageFor(error),
        onRetry: () => ref.invalidate(organizationProvider),
      ),
      data: (org) => ResponsivePage(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: 'Organization',
              actions: [
                if (canEdit && !_editing)
                  AppButton(
                    label: 'Edit profile',
                    onPressed: () => _startEdit(org),
                  ),
                if (_editing) ...[
                  AppButton(
                    label: 'Cancel',
                    variant: AppButtonVariant.secondary,
                    onPressed: () => setState(() => _editing = false),
                  ),
                  AppButton(
                    label: 'Save changes',
                    busyLabel: 'Saving…',
                    busy: _busy,
                    onPressed: () => _save(org),
                  ),
                ],
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            _Identity(organization: org, branches: branches, editing: _editing),
            const SizedBox(height: AppSpacing.lg),
            if (_editing && _errors.isNotEmpty) ...[
              FormErrorSummary(
                title: _errors['form'] ?? 'Please fix the highlighted fields.',
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
            if (_editing) _editForm() else _readOnly(org),
            const SizedBox(height: AppSpacing.md),
            if (org.createdAt != null)
              Text(
                'Created ${DateFormat('d MMM y').format(org.createdAt!)}'
                '${org.updatedAt == null ? '' : ' · last updated ${DateFormat('d MMM y').format(org.updatedAt!)}'}'
                '${org.updatedBy.isEmpty ? '' : ' by ${org.updatedBy}'}',
                style: AppTypography.helper,
              ),
          ],
        ),
      ),
    );
  }

  Widget _readOnly(Organization org) {
    String masked(String value) => value.length <= 4
        ? value
        : '${value.substring(0, value.length - 4)}••••';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Section(
          title: 'General',
          fields: [
            ('Display name', org.name, false),
            ('Organization ID', org.id, true),
            ('Industry', org.industry, false),
            ('People', org.employeeRange, false),
          ],
        ),
        _Section(
          title: 'Legal & contact',
          fields: [
            ('Legal name', org.legalName, false),
            ('Registration number', masked(org.registrationNumber), true),
            ('Contact email', org.contactEmail, false),
            ('Contact phone', org.contactPhone, true),
          ],
        ),
        _Section(
          title: 'Address & time zone',
          note: 'Branches inherit the time zone unless they set their own.',
          fields: [
            ('Address', org.address, false),
            (
              'City · state · PIN',
              [
                org.city,
                org.state,
                org.pin,
              ].where((v) => v.isNotEmpty).join(' · '),
              false,
            ),
            ('Country', org.country, false),
            ('Default time zone', timeZoneLabel(org.timeZone), false),
          ],
        ),
      ],
    );
  }

  Widget _editForm() {
    AppTextField field(
      String key,
      String label, {
      bool sensitive = false,
      bool mono = false,
      TextInputType? keyboard,
      List<TextInputFormatter>? formatters,
      int? maxLength,
    }) => AppTextField(
      label: sensitive ? '$label · needs confirmation' : label,
      controller: _controllers[key],
      monospace: mono,
      keyboardType: keyboard,
      inputFormatters: formatters,
      maxLength: maxLength,
      errorText: _errors[key],
      onChanged: (_) => setState(() => _errors.remove(key)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _EditSection(
          title: 'General',
          children: [
            field('name', 'Display name'),
            AppTextField(
              label: 'Organization ID',
              controller: _organizationId,
              readOnly: true,
              monospace: true,
              helperText: 'Used in sign-in links. Can’t be changed.',
            ),
            field('industry', 'Industry'),
          ],
        ),
        _EditSection(
          title: 'Legal & contact',
          children: [
            field('legalName', 'Legal name', sensitive: true),
            field('registrationNumber', 'Registration number', mono: true),
            field(
              'contactEmail',
              'Contact email',
              keyboard: TextInputType.emailAddress,
            ),
            field(
              'contactPhone',
              'Contact phone',
              mono: true,
              keyboard: TextInputType.phone,
            ),
          ],
        ),
        _EditSection(
          title: 'Address & time zone',
          children: [
            field('address', 'Address'),
            field('city', 'City'),
            AppDropdownField<String>(
              label: 'State',
              value: _state,
              options: [for (final s in indianStates) AppDropdownOption(s, s)],
              onChanged: (v) => setState(() => _state = v ?? _state),
            ),
            field(
              'pin',
              'PIN code',
              mono: true,
              keyboard: TextInputType.number,
              formatters: [FilteringTextInputFormatter.digitsOnly],
              maxLength: 6,
            ),
            AppDropdownField<String>(
              label: 'Default time zone · needs confirmation',
              value: _timeZone,
              helperText: 'Branches inherit this unless they set their own.',
              options: [
                for (final (id, label) in commonTimeZones)
                  AppDropdownOption(id, label),
              ],
              onChanged: (v) => setState(() => _timeZone = v ?? _timeZone),
            ),
          ],
        ),
        _EditSection(
          title: 'Branding',
          children: [
            ImageUploadField(
              label: 'Logo',
              image: _logo,
              onChanged: (logo) => setState(() => _logo = logo),
            ),
          ],
        ),
      ],
    );
  }
}

class _Identity extends StatelessWidget {
  const _Identity({
    required this.organization,
    required this.branches,
    required this.editing,
  });

  final Organization organization;
  final List<Branch> branches;
  final bool editing;

  @override
  Widget build(BuildContext context) {
    final active = branches.where((b) => b.isActive).length;
    final people = branches.fold<int>(0, (sum, b) => sum + b.employeeCount);
    final logo = organization.logo;
    return AppCard(
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: AppColors.ink,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: logo != null
                ? Image.memory(
                    logo,
                    fit: BoxFit.cover,
                    width: 52,
                    height: 52,
                    // A damaged file shows a broken-image mark, not an error.
                    errorBuilder: (_, _, _) =>
                        const Icon(Icons.broken_image_outlined),
                  )
                : Text(
                    initialsOf(organization.name),
                    style: AppTypography.cardTitle.copyWith(
                      color: AppColors.surface,
                    ),
                  ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(organization.name, style: AppTypography.sectionTitle),
                Text(
                  [
                    if (organization.legalName.isNotEmpty)
                      organization.legalName,
                    '$active ${active == 1 ? 'branch' : 'branches'}',
                    '$people employees',
                  ].join(' · '),
                  style: AppTypography.helper,
                ),
              ],
            ),
          ),
          if (editing)
            const StatusBadge(
              label: 'Editing · not saved',
              tone: StatusTone.warning,
            )
          else
            const StatusBadge(label: 'Active', tone: StatusTone.success),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.fields, this.note});

  final String title;
  final String? note;
  final List<(String, String, bool)> fields;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: AppCard(
        header: CardHeader(title: title, subtitle: note),
        child: ResponsiveGrid(
          minItemWidth: 220,
          maxColumns: 3,
          spacing: AppSpacing.lg,
          children: [
            for (final (label, value, mono) in fields)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: AppTypography.helper),
                  const SizedBox(height: 2),
                  Text(
                    value.isEmpty ? '—' : value,
                    style: mono
                        ? AppTypography.code.copyWith(
                            color: AppColors.textPrimary,
                          )
                        : AppTypography.small.copyWith(
                            color: AppColors.textPrimary,
                          ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _EditSection extends StatelessWidget {
  const _EditSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: AppCard(
        header: CardHeader(title: title),
        child: ResponsiveGrid(
          minItemWidth: 260,
          maxColumns: 2,
          spacing: AppSpacing.lg,
          children: children,
        ),
      ),
    );
  }
}
