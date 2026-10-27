import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/route_names.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/permissions/permissions.dart';
import '../../../../core/permissions/system_roles.dart';
import '../../../../core/responsive/responsive_grid.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_date_field.dart';
import '../../../../core/widgets/app_dropdown_field.dart';
import '../../../../core/widgets/app_overlays.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/form_error_summary.dart';
import '../../../../core/widgets/form_field_frame.dart';
import '../../../../core/widgets/selection_controls.dart';
import '../../../../core/widgets/skeleton.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../../shared/models/app_session.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../organization/domain/branch.dart';
import '../../../organization/presentation/providers/organization_providers.dart';
import '../../../organization/presentation/setup_text.dart';
import '../../domain/custom_field.dart';
import '../../domain/employee.dart';
import '../../domain/employee_rules.dart';
import '../../domain/field_settings.dart';
import '../providers/employee_providers.dart';
import '../widgets/employee_widgets.dart';

enum _Section {
  identity('Identity', 'identity'),
  contact('Contact information', 'contact'),
  employment('Employment details', 'employment'),
  branch('Organization & branch', 'branch'),
  manager('Reporting manager', 'manager'),
  schedule('Work schedule & shift', 'schedule'),
  policy('Attendance policy', 'policy'),
  custom('Custom fields', 'custom'),
  account('Account & invitation', 'account');

  const _Section(this.title, this.id);

  final String title;
  final String id;
}

/// Which section shows the error for a field key.
_Section _sectionOf(String key) => switch (key) {
  'firstName' || 'lastName' || 'code' || 'displayName' => _Section.identity,
  'workEmail' ||
  'mobile' ||
  'personalEmail' ||
  'dateOfBirth' ||
  'emergencyContact' => _Section.contact,
  'designation' || 'department' || 'joiningDate' => _Section.employment,
  'branchId' || 'effectiveFrom' || 'workLocation' => _Section.branch,
  'managerId' => _Section.manager,
  'shift' => _Section.schedule,
  _ when key.startsWith('custom.') => _Section.custom,
  _ => _Section.identity,
};

const _ownerManager = '__owner';

/// Boards S43 (add) and S44 (edit). [employeeId] null = add.
class EmployeeFormScreen extends ConsumerStatefulWidget {
  const EmployeeFormScreen({super.key, this.employeeId});

  final String? employeeId;

  @override
  ConsumerState<EmployeeFormScreen> createState() => _EmployeeFormScreenState();
}

class _EmployeeFormScreenState extends ConsumerState<EmployeeFormScreen> {
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _code = TextEditingController();
  final _display = TextEditingController();
  final _email = TextEditingController();
  final _mobile = TextEditingController();
  final _personalEmail = TextEditingController();
  final _emergency = TextEditingController();
  final _designation = TextEditingController();
  final _location = TextEditingController();
  final _customText = <String, TextEditingController>{};
  final _sectionKeys = {for (final s in _Section.values) s: GlobalKey()};

  String? _department;
  EmploymentType _type = EmploymentType.fullTime;
  DateTime? _joining;
  DateTime? _birth;
  int _probation = 6;
  String? _branchId;
  String? _managerId;
  String? _shift;
  int? _weeklyOff;
  DateTime? _effectiveFrom;
  SystemRole _role = SystemRole.employee;
  final _custom = <String, Object?>{};

  Employee? _original;
  bool _loaded = false;
  bool _busy = false;
  bool _submitted = false;
  Map<String, String> _errors = {};

  bool get _editing => widget.employeeId != null;

  @override
  void dispose() {
    for (final c in [
      _first,
      _last,
      _code,
      _display,
      _email,
      _mobile,
      _personalEmail,
      _emergency,
      _designation,
      _location,
      ..._customText.values,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _load(Employee? e, List<Employee> everyone, AppSession session) {
    if (_loaded) return;
    _loaded = true;
    if (e == null) {
      _code.text = nextEmployeeCode(everyone.map((x) => x.code));
      _branchId = session.branchIds.length == 1
          ? session.branchIds.single
          : null;
      _joining = null;
      return;
    }
    _original = e;
    _first.text = e.firstName;
    _last.text = e.lastName;
    _code.text = e.code;
    _display.text = e.displayName;
    _email.text = e.workEmail;
    _mobile.text = e.mobile;
    _personalEmail.text = e.personalEmail;
    _emergency.text = e.emergencyContact;
    _designation.text = e.designation;
    _location.text = e.workLocation;
    _department = e.department;
    _type = e.type;
    _joining = e.joiningDate;
    _birth = e.dateOfBirth;
    _probation = e.probationMonths;
    _branchId = e.branchId;
    _managerId =
        e.managerId ?? (reportsToOwnerAllowed(e) ? _ownerManager : null);
    _shift = e.shift;
    _weeklyOff = e.weeklyOff;
    _role = e.role;
    _custom.addAll(e.customValues);
  }

  TextEditingController _textFor(String key) => _customText.putIfAbsent(
    key,
    () => TextEditingController(
      text: switch (_custom[key]) {
        null => '',
        final v => '$v',
      },
    ),
  );

  Employee _draft(String organizationId) {
    final base = _original;
    final managerId = _managerId == _ownerManager ? null : _managerId;
    final draft = Employee(
      id: base?.id ?? 'new',
      organizationId: organizationId,
      code: _code.text.trim().toUpperCase(),
      firstName: _first.text.trim(),
      lastName: _last.text.trim(),
      displayName: _display.text.trim(),
      workEmail: _email.text.trim().toLowerCase(),
      mobile: _mobile.text.trim(),
      personalEmail: _personalEmail.text.trim(),
      dateOfBirth: _birth,
      emergencyContact: _emergency.text.trim(),
      designation: _designation.text.trim(),
      department: _department ?? '',
      type: _type,
      joiningDate: _joining ?? DateTime(1970),
      probationMonths: _probation,
      status: base?.status ?? EmploymentStatus.active,
      statusReason: base?.statusReason ?? '',
      lastWorkingDay: base?.lastWorkingDay,
      branchId: _branchId ?? '',
      workLocation: _location.text.trim(),
      managerId: managerId,
      shift: _shift ?? '',
      weeklyOff: _weeklyOff,
      accountStatus: base?.accountStatus ?? AccountStatus.noAccount,
      role: _role,
      invitedAt: base?.invitedAt,
      lastSignInAt: base?.lastSignInAt,
      customValues: {
        for (final e in _custom.entries)
          if (!isBlankValue(e.value)) e.key: e.value,
      },
      hasAttendance: base?.hasAttendance ?? false,
      activity: base?.activity ?? const [],
    );
    return draft;
  }

  /// (label, before, after) for each changed value (board S44).
  List<(String, String, String)> _changes(
    Employee draft,
    List<Branch> branches,
    List<Employee> everyone,
  ) {
    final o = _original;
    if (o == null) return const [];
    String branch(String id) =>
        branches.where((b) => b.id == id).firstOrNull?.name ?? '—';
    String person(String? id) => id == null
        ? 'The owner'
        : (everyone.where((e) => e.id == id).firstOrNull?.fullName ??
              'Not chosen yet');
    String date(DateTime? d) => d == null ? '—' : employeeDateFormat.format(d);
    final list = <(String, String, String)>[];
    void add(String label, String before, String after) {
      if (before != after) {
        list.add((
          label,
          before.isEmpty ? '—' : before,
          after.isEmpty ? '—' : after,
        ));
      }
    }

    add('First name', o.firstName, draft.firstName);
    add('Last name', o.lastName, draft.lastName);
    add('Display name', o.displayName, draft.displayName);
    add('Work email', o.workEmail, draft.workEmail);
    add('Personal email', o.personalEmail, draft.personalEmail);
    add('Emergency contact', o.emergencyContact, draft.emergencyContact);
    add('Date of birth', date(o.dateOfBirth), date(draft.dateOfBirth));
    add('Designation', o.designation, draft.designation);
    add('Department', o.department, draft.department);
    add('Employment type', o.type.label, draft.type.label);
    add('Joining date', date(o.joiningDate), date(draft.joiningDate));
    add(
      'Probation',
      '${o.probationMonths} months',
      '${draft.probationMonths} months',
    );
    final effective = _effectiveFrom == null
        ? ''
        : ' (from ${employeeDateFormat.format(_effectiveFrom!)})';
    add(
      'Branch',
      branch(o.branchId),
      draft.branchId.isEmpty ? '—' : '${branch(draft.branchId)}$effective',
    );
    add('Work location', o.workLocation, draft.workLocation);
    add(
      'Reporting manager',
      person(o.managerId),
      _managerId == null ? 'Not chosen yet' : person(draft.managerId),
    );
    add('Shift', o.shift, draft.shift);
    add(
      'Weekly off',
      o.weeklyOff == null ? 'Branch default' : weekdayNames[o.weeklyOff!],
      draft.weeklyOff == null
          ? 'Branch default'
          : weekdayNames[draft.weeklyOff!],
    );
    final fields =
        ref.read(customFieldsProvider).value ?? const <CustomField>[];
    for (final f in fields) {
      final before = _show(o.customValues[f.key]);
      final after = _show(draft.customValues[f.key]);
      add(f.label, before, after);
    }
    return list;
  }

  String _show(Object? v) => switch (v) {
    null => '',
    final DateTime d => employeeDateFormat.format(d),
    final List<Object?> l => l.join(', '),
    final bool b => b ? 'Yes' : 'No',
    _ => '$v',
  };

  void _jumpTo(_Section s) {
    final ctx = _sectionKeys[s]!.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 250),
        alignment: 0.05,
      );
    }
  }

  Future<void> _save({required bool invite}) async {
    if (_busy) return;
    final session = ref.read(sessionProvider)!;
    final everyone = ref.read(employeesProvider).value ?? const <Employee>[];
    final branches = ref.read(branchesProvider).value ?? const <Branch>[];
    final fields =
        ref.read(customFieldsProvider).value ?? const <CustomField>[];
    final draft = _draft(session.organizationId);
    final branch = branches.where((b) => b.id == draft.branchId).firstOrNull;
    final errors = validateEmployee(
      draft,
      others: everyone.where((e) => e.id != draft.id),
      fields: fields,
      branch: branch,
      sendInvite: invite,
      settings:
          ref.read(fieldSettingsProvider).value ??
          const EmployeeFieldSettings(),
      seesRestricted: _seesRestricted(session),
    );
    if (_joining == null) errors['joiningDate'] = 'Choose the joining date.';
    if (_editing &&
        _original!.branchId != draft.branchId &&
        _effectiveFrom == null) {
      errors['effectiveFrom'] = 'Choose when the move takes effect.';
    }
    setState(() {
      _submitted = true;
      _errors = errors;
    });
    if (errors.isNotEmpty) {
      _jumpTo(_sectionOf(errors.keys.first));
      return;
    }

    final notifier = ref.read(employeesProvider.notifier);
    if (_editing) {
      final changes = _changes(draft, branches, everyone);
      if (changes.isEmpty) {
        context.go(AppRoutes.employee(draft.id));
        return;
      }
      final ok = await showConfirmDialog(
        context,
        title:
            'Save ${changes.length} ${changes.length == 1 ? 'change' : 'changes'}?',
        message: [
          for (final (label, before, after) in changes)
            '$label: $before → $after',
          '',
          'Saved to the history with your name.',
        ].join('\n'),
        confirmLabel: 'Save changes',
      );
      if (!ok || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      if (_editing) {
        final changes = _changes(draft, branches, everyone);
        final saved = await notifier.save(
          draft,
          notes: [
            for (final (label, before, after) in changes)
              '$label: $before → $after',
          ],
        );
        if (!mounted) return;
        showAppToast(context, 'Changes saved');
        context.go(AppRoutes.employee(saved.id));
      } else {
        final created = await notifier.create(draft, sendInvite: invite);
        if (!mounted) return;
        showAppToast(
          context,
          invite
              ? '${created.fullName} added · invitation sent to ${created.workEmail}'
              : '${created.fullName} added without an invitation',
        );
        context.go(AppRoutes.employee(created.id));
      }
    } on ValidationFailure catch (f) {
      if (mounted) {
        setState(
          () => _errors = f.fieldErrors.isEmpty
              ? {'form': f.message}
              : {...f.fieldErrors},
        );
      }
    } on Failure catch (f) {
      if (mounted) setState(() => _errors = {'form': f.message});
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deactivate(Employee e) async {
    final input = await showLifecycleDialog(
      context,
      title: 'Deactivate ${e.fullName}?',
      message:
          'Removes sign-in access. Attendance, leave and audit history are kept.',
      confirmLabel: 'Deactivate',
      destructive: true,
    );
    if (input == null || !mounted) return;
    try {
      await ref
          .read(employeesProvider.notifier)
          .setStatus(e.id, EmploymentStatus.inactive, reason: input.reason);
      if (!mounted) return;
      showAppToast(context, '${e.fullName} deactivated');
      context.go(AppRoutes.employee(e.id));
    } on Failure catch (f) {
      if (mounted) showAppToast(context, f.message, icon: Icons.error_outline);
    }
  }

  void _close() => context.go(
    _editing ? AppRoutes.employee(widget.employeeId!) : AppRoutes.employees,
  );

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final employees = ref.watch(employeesProvider);
    final branchesValue = ref.watch(branchesProvider);
    final fieldsValue = ref.watch(customFieldsProvider);
    if (session == null) return const SizedBox.shrink();
    if (employees.isLoading ||
        branchesValue.isLoading ||
        fieldsValue.isLoading) {
      return const Scaffold(
        body: Center(
          child: LoadingSkeleton(
            label: 'Loading form',
            child: SkeletonList(rows: 6),
          ),
        ),
      );
    }
    final everyone = employees.value ?? const <Employee>[];
    final existing = _editing
        ? ref.watch(employeeProvider(widget.employeeId!)).value
        : null;
    if (_editing && existing == null) {
      return Scaffold(
        body: ErrorState(
          headline: '404',
          title: 'This person isn’t here',
          message: 'They may be outside the branches you can see.',
          actions: [
            AppButton(
              label: 'Go to employees',
              onPressed: () => context.go(AppRoutes.employees),
            ),
          ],
        ),
      );
    }
    _load(existing, everyone, session);

    final branches = [
      for (final b in branchesValue.value ?? const <Branch>[])
        if (session.coversBranch(b.id) &&
            (b.isActive || b.id == _original?.branchId))
          b,
    ];
    final branch = branches.where((b) => b.id == _branchId).firstOrNull;
    final fields = fieldsValue.value ?? const <CustomField>[];
    final draft = _draft(session.organizationId);
    final changes = _changes(draft, branches, everyone);
    final orgName = session.organizationName;
    final errorCount = _errors.keys.where((k) => k != 'form').length;

    final actions = _editing
        ? [
            AppButton(
              label: 'Cancel',
              variant: AppButtonVariant.secondary,
              onPressed: _close,
            ),
            AppButton(
              label: 'Review & save',
              busy: _busy,
              busyLabel: 'Saving…',
              onPressed: () => _save(invite: false),
            ),
          ]
        : [
            AppButton(
              label: 'Save without inviting',
              variant: AppButtonVariant.secondary,
              onPressed: _busy ? null : () => _save(invite: false),
            ),
            AppButton(
              label: 'Save & send invite',
              busy: _busy,
              busyLabel: 'Saving…',
              onPressed: () => _save(invite: true),
            ),
          ];

    final form = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_errors['form'] case final message?) ...[
          FormErrorSummary(title: message),
          const SizedBox(height: AppSpacing.lg),
        ] else if (_submitted && errorCount > 0) ...[
          FormErrorSummary(
            title:
                '$errorCount ${errorCount == 1 ? 'field needs' : 'fields need'} attention before saving',
            items: [
              for (final e in _errors.entries)
                FormErrorItem(
                  '${_labelFor(e.key, fields)} — ${e.value}',
                  onTap: () => _jumpTo(_sectionOf(e.key)),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
        ..._sections(session, everyone, branches, branch, fields, draft),
        if (_editing &&
            _original!.status.isEmployed &&
            session.permissions.can(
              PermissionModule.employees,
              PermissionAction.deactivate,
            )) ...[
          const SizedBox(height: AppSpacing.lg),
          _DangerZone(onDeactivate: () => _deactivate(_original!)),
        ],
      ],
    );

    return _FormScaffold(
      title: _editing ? 'Edit · ${_original!.fullName}' : 'Add employee',
      code: _editing ? _original!.code : null,
      subtitle: _editing ? null : '$orgName · fields marked * are required',
      changeCount: _editing ? changes.length : null,
      actions: actions,
      onClose: _close,
      index: _editing
          ? null
          : _SectionIndex(
              sections: _visibleSections(fields, draft),
              errorSections: {
                for (final k in _errors.keys)
                  if (k != 'form') _sectionOf(k),
              },
              onTap: _jumpTo,
            ),
      changesPanel: _editing
          ? _ChangesPanel(changes: changes, name: _original!.firstName)
          : null,
      child: form,
    );
  }

  bool _seesRestricted(AppSession session) =>
      session.scope == DataScope.organization &&
      session.permissions.can(
        PermissionModule.employees,
        PermissionAction.edit,
      );

  String _labelFor(String key, List<CustomField> fields) => switch (key) {
    'firstName' => 'First name',
    'lastName' => 'Last name',
    'code' => 'Employee ID',
    'workEmail' => 'Work email',
    'mobile' => 'Mobile number',
    'personalEmail' => 'Personal email',
    'displayName' => 'Display name',
    'dateOfBirth' => 'Date of birth',
    'emergencyContact' => 'Emergency contact',
    'workLocation' => 'Work location',
    'designation' => 'Designation',
    'department' => 'Department',
    'joiningDate' => 'Joining date',
    'branchId' => 'Branch',
    'effectiveFrom' => 'Effective from',
    'managerId' => 'Reports to',
    'shift' => 'Shift',
    _ when key.startsWith('custom.') =>
      fields.where((f) => 'custom.${f.key}' == key).firstOrNull?.label ??
          'Custom field',
    _ => key,
  };

  List<_Section> _visibleSections(List<CustomField> fields, Employee draft) => [
    for (final s in _Section.values)
      if (s != _Section.account || !_editing)
        if (s != _Section.custom ||
            fields.any((f) => f.appliesToEmployee(draft)))
          s,
  ];

  String? _err(String key) => _errors[key];

  void _clearError(String key) {
    if (_errors.containsKey(key)) {
      setState(() => _errors = {..._errors}..remove(key));
    }
  }

  /// Highlights a field the edit changed (board S44 "Changed · Was: …").
  Widget _tracked(String label, Widget child) {
    final change = _original == null
        ? null
        : _changes(
            _draft(_original!.organizationId),
            ref.read(branchesProvider).value ?? const [],
            ref.read(employeesProvider).value ?? const [],
          ).where((c) => c.$1 == label).firstOrNull;
    if (change == null) return child;
    return Container(
      padding: const EdgeInsets.only(left: AppSpacing.sm + 2),
      decoration: const BoxDecoration(
        border: Border(left: BorderSide(color: Color(0xFFD9A441), width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          child,
          const SizedBox(height: 2),
          Text(
            'Changed · was: ${change.$2}',
            style: AppTypography.helper.copyWith(
              color: const Color(0xFF8A4F00),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _sections(
    AppSession session,
    List<Employee> everyone,
    List<Branch> branches,
    Branch? branch,
    List<CustomField> fields,
    Employee draft,
  ) {
    final o = _original;
    final seesPrivate = _seesRestricted(session);
    final rules =
        ref.watch(fieldSettingsProvider).value ?? const EmployeeFieldSettings();
    bool shows(StandardField f) => rules.shows(f);
    bool req(StandardField f) => rules.requires(f);
    final isOwner = session.role == SystemRole.owner;
    final shifts = branch == null ? const <BranchShift>[] : shiftsFor(branch);
    final managers = [
      for (final e in everyone)
        if (e.branchId == _branchId && e.status.isEmployed && e.id != o?.id) e,
    ]..sort((a, b) => a.fullName.compareTo(b.fullName));
    final canReportToOwner = reportsToOwnerAllowed(draft);
    final applicable = [
      for (final f in fields)
        if (f.appliesToEmployee(draft) && f.canView(session.role)) f,
    ];
    final probationEnd = _joining == null || _probation == 0
        ? null
        : DateTime(_joining!.year, _joining!.month + _probation, _joining!.day);

    Widget section(
      _Section s,
      List<Widget> children, {
      String? description,
      Widget? callout,
    }) {
      final visible = _visibleSections(fields, draft);
      if (!visible.contains(s)) return const SizedBox.shrink();
      return Padding(
        key: _sectionKeys[s],
        padding: const EdgeInsets.only(bottom: AppSpacing.lg),
        child: _FormCard(
          number: _editing ? null : visible.indexOf(s) + 1,
          title: s.title,
          description: description,
          callout: callout,
          children: children,
        ),
      );
    }

    return [
      section(_Section.identity, [
        _tracked(
          'First name',
          AppTextField(
            label: 'First name',
            controller: _first,
            isRequired: true,
            errorText: _err('firstName'),
            onChanged: (_) {
              _clearError('firstName');
              setState(() {});
            },
          ),
        ),
        _tracked(
          'Last name',
          AppTextField(
            label: 'Last name',
            controller: _last,
            isRequired: true,
            errorText: _err('lastName'),
            onChanged: (_) {
              _clearError('lastName');
              setState(() {});
            },
          ),
        ),
        AppTextField(
          label: 'Employee ID',
          controller: _code,
          isRequired: true,
          monospace: true,
          readOnly: o?.hasAttendance ?? false,
          errorText: _err('code'),
          helperText: o == null
              ? 'Suggested next ID. You can change it.'
              : (o.hasAttendance
                    ? 'IDs never change once attendance exists.'
                    : null),
          inputFormatters: [UpperCaseTextFormatter()],
          onChanged: (_) => _clearError('code'),
        ),
        if (shows(StandardField.displayName))
          _tracked(
            'Display name',
            AppTextField(
              label: 'Display name',
              controller: _display,
              isRequired: req(StandardField.displayName),
              isOptional: !req(StandardField.displayName),
              hintText: 'Shown in lists',
              errorText: _err('displayName'),
              onChanged: (_) {
                _clearError('displayName');
                setState(() {});
              },
            ),
          ),
      ]),
      section(_Section.contact, [
        _tracked(
          'Work email',
          AppTextField(
            label: 'Work email',
            controller: _email,
            isRequired: !_editing || req(StandardField.workEmail),
            keyboardType: TextInputType.emailAddress,
            errorText: _err('workEmail'),
            helperText: _editing
                ? null
                : 'Needed to send the sign-in invitation.',
            onChanged: (_) {
              _clearError('workEmail');
              setState(() {});
            },
          ),
        ),
        if (shows(StandardField.mobile))
          AppTextField(
            label: 'Mobile number',
            controller: _mobile,
            isRequired: req(StandardField.mobile),
            isOptional: o == null && !req(StandardField.mobile),
            monospace: true,
            keyboardType: TextInputType.phone,
            readOnly: o != null && o.mobile.isNotEmpty,
            helperText: o != null && o.mobile.isNotEmpty
                ? 'Only the employee can change this.'
                : null,
            errorText: _err('mobile'),
            onChanged: (_) => _clearError('mobile'),
          ),
        if (seesPrivate) ...[
          if (shows(StandardField.personalEmail))
            _tracked(
              'Personal email',
              AppTextField(
                label: 'Personal email',
                controller: _personalEmail,
                isRequired: req(StandardField.personalEmail),
                isOptional: !req(StandardField.personalEmail),
                keyboardType: TextInputType.emailAddress,
                helperText: 'Only HR admins can see this.',
                errorText: _err('personalEmail'),
                onChanged: (_) {
                  _clearError('personalEmail');
                  setState(() {});
                },
              ),
            ),
          if (shows(StandardField.dateOfBirth))
            _tracked(
              'Date of birth',
              AppDateField(
                label: 'Date of birth',
                value: _birth,
                isRequired: req(StandardField.dateOfBirth),
                isOptional: !req(StandardField.dateOfBirth),
                allowClear: true,
                lastDate: DateTime.now(),
                helperText: 'Restricted to HR admins.',
                errorText: _err('dateOfBirth'),
                onChanged: (d) => setState(() {
                  _birth = d;
                  _clearError('dateOfBirth');
                }),
              ),
            ),
          if (shows(StandardField.emergencyContact))
            _tracked(
              'Emergency contact',
              AppTextField(
                label: 'Emergency contact',
                controller: _emergency,
                isRequired: req(StandardField.emergencyContact),
                isOptional: !req(StandardField.emergencyContact),
                hintText: 'Name and phone',
                errorText: _err('emergencyContact'),
                onChanged: (_) {
                  _clearError('emergencyContact');
                  setState(() {});
                },
              ),
            ),
        ],
      ]),
      section(_Section.employment, [
        if (shows(StandardField.designation))
          _tracked(
            'Designation',
            AppTextField(
              label: 'Designation',
              controller: _designation,
              isRequired: req(StandardField.designation),
              isOptional: !req(StandardField.designation),
              errorText: _err('designation'),
              onChanged: (_) {
                _clearError('designation');
                setState(() {});
              },
            ),
          ),
        if (shows(StandardField.department))
          _tracked(
            'Department',
            AppDropdownField<String>(
              label: 'Department',
              isRequired: req(StandardField.department),
              value: _department,
              hintText: 'Choose a department',
              errorText: _err('department'),
              options: [for (final d in departments) AppDropdownOption(d, d)],
              onChanged: (v) => setState(() {
                _department = v;
                _clearError('department');
              }),
            ),
          ),
        _tracked(
          'Employment type',
          AppDropdownField<EmploymentType>(
            label: 'Employment type',
            isRequired: true,
            value: _type,
            options: [
              for (final t in EmploymentType.values)
                AppDropdownOption(t, t.label),
            ],
            onChanged: (v) => setState(() => _type = v ?? _type),
          ),
        ),
        _tracked(
          'Joining date',
          AppDateField(
            label: 'Joining date',
            isRequired: true,
            value: _joining,
            errorText: _err('joiningDate'),
            helperText: o != null && !isOwner
                ? 'Ask the owner to correct this.'
                : null,
            onChanged: o != null && !isOwner
                ? null
                : (d) => setState(() {
                    _joining = d;
                    _clearError('joiningDate');
                  }),
          ),
        ),
        if (shows(StandardField.probation))
          _tracked(
            'Probation',
            AppDropdownField<int>(
              label: 'Probation',
              value: _probation,
              helperText: probationEnd == null
                  ? null
                  : 'Ends ${employeeDateFormat.format(probationEnd)}.',
              options: const [
                AppDropdownOption(0, 'No probation'),
                AppDropdownOption(3, '3 months'),
                AppDropdownOption(6, '6 months'),
              ],
              onChanged: (v) => setState(() => _probation = v ?? 0),
            ),
          ),
      ]),
      section(
        _Section.branch,
        [
          _tracked(
            'Branch',
            AppDropdownField<String>(
              label: 'Branch',
              isRequired: true,
              value: _branchId,
              hintText: 'Choose a branch',
              errorText: _err('branchId'),
              options: [
                for (final b in branches)
                  AppDropdownOption(b.id, b.name, enabled: b.isActive),
              ],
              onChanged: (v) => setState(() {
                if (v != _branchId) {
                  _managerId = null;
                  _shift = null;
                }
                _branchId = v;
                if (o != null && v == o.branchId) {
                  _managerId =
                      o.managerId ??
                      (reportsToOwnerAllowed(o) ? _ownerManager : null);
                  _shift = o.shift;
                  _effectiveFrom = null;
                } else if (o != null) {
                  _effectiveFrom ??= ref.read(orgNowProvider)();
                }
                _clearError('branchId');
              }),
            ),
          ),
          if (o != null && _branchId != o.branchId)
            AppDateField(
              label: 'Effective from',
              isRequired: true,
              value: _effectiveFrom,
              errorText: _err('effectiveFrom'),
              onChanged: (d) => setState(() {
                _effectiveFrom = d;
                _clearError('effectiveFrom');
              }),
            ),
          if (shows(StandardField.workLocation))
            _tracked(
              'Work location',
              AppTextField(
                label: 'Work location',
                controller: _location,
                isRequired: req(StandardField.workLocation),
                isOptional: !req(StandardField.workLocation),
                hintText: 'e.g. Ring Road unit',
                errorText: _err('workLocation'),
                onChanged: (_) {
                  _clearError('workLocation');
                  setState(() {});
                },
              ),
            ),
        ],
        callout: o != null && branch != null && _branchId != o.branchId
            ? _Consequences(
                items: branchMoveConsequences(
                  before: o,
                  to: branch,
                  pendingLeaveRequests: 0,
                ),
              )
            : null,
      ),
      section(_Section.manager, [
        _tracked(
          'Reporting manager',
          AppDropdownField<String>(
            label: 'Reports to',
            isRequired: !canReportToOwner,
            value: _managerId,
            hintText: _branchId == null
                ? 'Choose a branch first'
                : (branch == null
                      ? 'Choose a manager'
                      : 'Choose a manager at ${branch.name}'),
            helperText: 'Leave requests route here first.',
            errorText: _err('managerId'),
            options: [
              if (canReportToOwner)
                const AppDropdownOption(
                  _ownerManager,
                  'The owner (no manager)',
                ),
              for (final m in managers)
                AppDropdownOption(m.id, '${m.fullName} — ${m.designation}'),
            ],
            onChanged: _branchId == null
                ? null
                : (v) => setState(() {
                    _managerId = v;
                    _clearError('managerId');
                  }),
          ),
        ),
      ]),
      section(_Section.schedule, [
        _tracked(
          'Shift',
          AppDropdownField<String>(
            label: 'Shift',
            isRequired: true,
            value: shifts.any((s) => s.name == _shift) ? _shift : null,
            hintText: _branchId == null
                ? 'Choose a branch first'
                : 'Select a shift',
            errorText: _err('shift'),
            options: [
              for (final s in shifts) AppDropdownOption(s.name, shiftLabel(s)),
            ],
            onChanged: _branchId == null
                ? null
                : (v) => setState(() {
                    _shift = v;
                    _clearError('shift');
                  }),
          ),
        ),
        if (shows(StandardField.weeklyOff))
          _tracked(
            'Weekly off',
            AppDropdownField<int?>(
              label: 'Weekly off',
              value: _weeklyOff,
              options: [
                AppDropdownOption(
                  null,
                  branch == null
                      ? 'Branch default'
                      : '${_closedDays(branch)} (branch default)',
                ),
                for (var i = 0; i < 7; i++)
                  AppDropdownOption(i, weekdayNames[i]),
              ],
              onChanged: (v) => setState(() => _weeklyOff = v),
            ),
          ),
      ]),
      section(_Section.policy, [
        AppDropdownField<String>(
          label: 'Policy',
          value: 'default',
          helperText: branch?.attendance == null
              ? 'This branch has no attendance rules yet.'
              : attendanceSummary(branch!.attendance!),
          options: [
            AppDropdownOption(
              'default',
              branch == null
                  ? 'Branch default'
                  : '${branch.name} rules (branch default)',
            ),
          ],
          onChanged: null,
        ),
      ]),
      section(
        _Section.custom,
        [for (final f in applicable) _customInput(f, session)],
        description:
            'Defined by your organization. Fields shown depend on department.',
      ),
      if (!_editing)
        section(_Section.account, [
          AppDropdownField<SystemRole>(
            label: 'Role',
            value: _role,
            helperText:
                'More roles and custom permissions arrive with Roles (Phase 7).',
            options: [
              const AppDropdownOption(
                SystemRole.employee,
                'Employee — own records',
              ),
              const AppDropdownOption(
                SystemRole.leaveApprover,
                'Leave Approver — own team',
              ),
              if (isOwner) ...[
                const AppDropdownOption(
                  SystemRole.branchManager,
                  'Branch Manager — assigned branch',
                ),
                const AppDropdownOption(
                  SystemRole.attendanceManager,
                  'Attendance Manager — assigned branch',
                ),
                const AppDropdownOption(
                  SystemRole.hrAdmin,
                  'HR Admin — all branches',
                ),
              ],
            ],
            onChanged: (v) => setState(() => _role = v ?? _role),
          ),
          const AppDropdownField<String>(
            label: 'Invitation expires',
            value: '7',
            helperText:
                'Set in Security settings. “Save & send invite” emails a sign-in link; '
                'nobody ever receives a password.',
            options: [AppDropdownOption('7', 'After 7 days')],
            onChanged: null,
          ),
        ]),
    ];
  }

  String _closedDays(Branch b) {
    final closed = [
      for (var i = 0; i < 7; i++)
        if (!b.hours[i].open) weekdayNames[i],
    ];
    return closed.isEmpty ? 'None' : closed.join(', ');
  }

  Widget _customInput(CustomField f, AppSession session) {
    final editable = f.canEdit(session.role);
    final key = 'custom.${f.key}';
    final error = _err(key);
    final value = _custom[f.key];
    void set(Object? v) => setState(() {
      _custom[f.key] = v;
      _clearError(key);
    });
    final helper = [
      if (f.description.isNotEmpty) f.description,
      if (!editable) 'Your role can see but not change this.',
    ].join(' ');
    final Widget input = switch (f.type) {
      CustomFieldType.date => AppDateField(
        label: f.label,
        value: value is DateTime ? value : null,
        isRequired: f.required,
        isOptional: !f.required,
        allowClear: true,
        errorText: error,
        helperText: helper.isEmpty ? null : helper,
        onChanged: editable ? set : null,
      ),
      CustomFieldType.singleSelect => AppDropdownField<String>(
        label: f.label,
        value: f.options.contains(value) ? value as String : null,
        hintText: 'Select an option',
        isRequired: f.required,
        isOptional: !f.required,
        errorText: error,
        helperText: helper.isEmpty ? null : helper,
        options: [for (final o in f.options) AppDropdownOption(o, o)],
        onChanged: editable ? set : null,
      ),
      CustomFieldType.multiSelect => FormFieldFrame(
        label: f.label,
        isRequired: f.required,
        isOptional: !f.required,
        errorText: error,
        helperText: helper.isEmpty ? null : helper,
        child: Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            for (final o in f.options)
              FilterChip(
                label: Text(o),
                selected: value is List && value.contains(o),
                onSelected: editable
                    ? (on) {
                        final current = value is List
                            ? value.cast<String>().toList()
                            : <String>[];
                        on ? current.add(o) : current.remove(o);
                        set(current);
                      }
                    : null,
              ),
          ],
        ),
      ),
      CustomFieldType.yesNo => SwitchRow(
        label: f.label,
        description: helper.isEmpty ? null : helper,
        value: value == true,
        onChanged: editable ? set : null,
      ),
      _ => AppTextField(
        label: f.label,
        controller: _textFor(f.key),
        isRequired: f.required,
        isOptional: !f.required,
        readOnly: !editable,
        monospace: f.type == CustomFieldType.number,
        keyboardType: switch (f.type) {
          CustomFieldType.number => TextInputType.number,
          CustomFieldType.url => TextInputType.url,
          _ => null,
        },
        errorText: error,
        helperText: helper.isEmpty ? null : helper,
        onChanged: (t) => set(
          f.type == CustomFieldType.number
              ? (num.tryParse(t) ?? (t.isEmpty ? null : t))
              : t,
        ),
      ),
    };
    return _tracked(f.label, input);
  }
}

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => newValue.copyWith(text: newValue.text.toUpperCase());
}

class _FormScaffold extends StatelessWidget {
  const _FormScaffold({
    required this.title,
    required this.actions,
    required this.onClose,
    required this.child,
    this.subtitle,
    this.code,
    this.changeCount,
    this.index,
    this.changesPanel,
  });

  final String title;
  final String? subtitle;
  final String? code;
  final int? changeCount;
  final List<Widget> actions;
  final VoidCallback onClose;
  final Widget child;
  final Widget? index;
  final Widget? changesPanel;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final phone = width < 600;
    final wide = width >= 1100;
    final header = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Close',
            onPressed: onClose,
            icon: const Icon(Icons.close),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  spacing: AppSpacing.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(title, style: AppTypography.sectionTitle),
                    ),
                    if (code != null) Text(code!, style: AppTypography.code),
                    if (changeCount != null && changeCount! > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.warningSoft,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                        child: Text(
                          '$changeCount ${changeCount == 1 ? 'change' : 'changes'}',
                          style: AppTypography.helper.copyWith(
                            color: AppColors.warningText,
                          ),
                        ),
                      ),
                  ],
                ),
                if (subtitle != null)
                  Text(subtitle!, style: AppTypography.small),
              ],
            ),
          ),
          if (!phone)
            Flexible(
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: actions,
              ),
            ),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: Column(
          children: [
            header,
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(phone ? AppSpacing.lg : AppSpacing.xl),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1240),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (index != null && wide) ...[
                          SizedBox(width: 220, child: index),
                          const SizedBox(width: AppSpacing.xl),
                        ],
                        Expanded(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 780),
                            // Narrower screens show the changes under the
                            // form, inside the scroll (Phase 8 QA).
                            child: changesPanel != null && !wide
                                ? Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      child,
                                      const SizedBox(height: AppSpacing.lg),
                                      changesPanel!,
                                    ],
                                  )
                                : child,
                          ),
                        ),
                        if (changesPanel != null && wide) ...[
                          const SizedBox(width: AppSpacing.xl),
                          SizedBox(width: 320, child: changesPanel),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (phone)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  border: Border(top: BorderSide(color: AppColors.border)),
                ),
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: actions,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SectionIndex extends StatelessWidget {
  const _SectionIndex({
    required this.sections,
    required this.errorSections,
    required this.onTap,
  });

  final List<_Section> sections;
  final Set<_Section> errorSections;
  final ValueChanged<_Section> onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Form sections',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < sections.length; i++)
            InkWell(
              borderRadius: BorderRadius.circular(AppRadius.md),
              onTap: () => onTap(sections[i]),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Text('${i + 1}', style: AppTypography.code),
                    const SizedBox(width: AppSpacing.sm + 2),
                    Expanded(
                      child: Text(
                        sections[i].title,
                        style: AppTypography.small.copyWith(
                          color: errorSections.contains(sections[i])
                              ? AppColors.danger
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
                    if (errorSections.contains(sections[i]))
                      Semantics(
                        label: 'has errors',
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: AppColors.danger,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FormCard extends StatelessWidget {
  const _FormCard({
    required this.title,
    required this.children,
    this.number,
    this.description,
    this.callout,
  });

  final int? number;
  final String title;
  final String? description;
  final Widget? callout;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg + 4),
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
            child: Text(
              number == null ? title : '$number  $title',
              style: AppTypography.cardTitle,
            ),
          ),
          if (description != null)
            Text(description!, style: AppTypography.helper),
          const SizedBox(height: AppSpacing.lg),
          ResponsiveGrid(
            minItemWidth: 260,
            maxColumns: 2,
            spacing: AppSpacing.lg,
            children: children,
          ),
          if (callout != null) ...[
            const SizedBox(height: AppSpacing.lg),
            callout!,
          ],
        ],
      ),
    );
  }
}

class _Consequences extends StatelessWidget {
  const _Consequences({required this.items});

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.warningSoft,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Moving branches changes these too',
            style: AppTypography.label.copyWith(color: AppColors.warningText),
          ),
          const SizedBox(height: AppSpacing.xs),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '• $item',
                style: AppTypography.small.copyWith(
                  color: AppColors.warningText,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ChangesPanel extends StatelessWidget {
  const _ChangesPanel({required this.changes, required this.name});

  final List<(String, String, String)> changes;
  final String name;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1100;
    if (!wide && changes.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: EdgeInsets.only(bottom: wide ? 0 : AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            header: true,
            child: const Text('Your changes', style: AppTypography.cardTitle),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (changes.isEmpty)
            const Text('Nothing changed yet.', style: AppTypography.small)
          else if (wide)
            for (final (label, before, after) in changes)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: '$label\n', style: AppTypography.label),
                      TextSpan(
                        text: before,
                        style: AppTypography.small.copyWith(
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                      const TextSpan(text: ' → ', style: AppTypography.small),
                      TextSpan(
                        text: after,
                        style: AppTypography.small.copyWith(
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              )
          else
            Text(
              changes.map((c) => c.$1).join(', '),
              style: AppTypography.small,
            ),
          if (wide) ...[
            const Divider(height: AppSpacing.xl),
            Text(
              'Saved to the history with your name. $name is told about branch and manager changes once notifications exist (Phase 7).',
              style: AppTypography.helper,
            ),
          ],
        ],
      ),
    );
  }
}

class _DangerZone extends StatelessWidget {
  const _DangerZone({required this.onDeactivate});

  final VoidCallback onDeactivate;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg + 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.dangerBorder),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.md,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Deactivate employee', style: AppTypography.cardTitle),
                Text(
                  'Removes sign-in access. Attendance, leave and audit history are kept.',
                  style: AppTypography.small,
                ),
              ],
            ),
          ),
          AppButton(
            label: 'Deactivate…',
            variant: AppButtonVariant.dangerOutline,
            onPressed: onDeactivate,
          ),
        ],
      ),
    );
  }
}
