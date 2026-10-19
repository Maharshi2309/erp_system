import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/route_names.dart';
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
import '../../../../core/widgets/form_field_frame.dart';
import '../../../../core/widgets/page_header.dart';
import '../../../../core/widgets/selection_controls.dart';
import '../../../../core/widgets/skeleton.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../auth/presentation/widgets/auth_widgets.dart';
import '../../../organization/domain/branch.dart';
import '../../../organization/presentation/providers/organization_providers.dart';
import '../../domain/custom_field.dart';
import '../../domain/employee.dart';
import '../providers/employee_providers.dart';
import '../widgets/employee_widgets.dart';

/// Board S45 — define, reorder and archive custom employee fields.
class FieldBuilderScreen extends ConsumerStatefulWidget {
  const FieldBuilderScreen({super.key});

  @override
  ConsumerState<FieldBuilderScreen> createState() => _FieldBuilderScreenState();
}

class _FieldBuilderScreenState extends ConsumerState<FieldBuilderScreen> {
  String? _selectedId;

  /// The editor's working copy; null when nothing is selected.
  CustomField? _draft;
  bool _isNew = false;
  bool _dirty = false;
  bool _busy = false;
  Map<String, String> _errors = {};

  /// Option rows: (original value or null for new, controller).
  List<(String?, TextEditingController)> _options = [];
  late final _label = TextEditingController();
  late final _description = TextEditingController();

  @override
  void dispose() {
    _label.dispose();
    _description.dispose();
    for (final (_, c) in _options) {
      c.dispose();
    }
    super.dispose();
  }

  void _edit(CustomField field, {bool isNew = false}) {
    for (final (_, c) in _options) {
      c.dispose();
    }
    setState(() {
      _selectedId = field.id;
      _draft = field;
      _isNew = isNew;
      _dirty = isNew;
      _errors = {};
      _label.text = field.label;
      _description.text = field.description;
      _options = [
        for (final o in field.options)
          (isNew ? null : o, TextEditingController(text: o)),
      ];
    });
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    return showConfirmDialog(
      context,
      title: 'Discard changes?',
      message:
          'Your changes to “${_draft?.label ?? 'this field'}” haven’t been saved.',
      confirmLabel: 'Discard',
      destructive: true,
    );
  }

  Future<void> _select(CustomField field) async {
    if (field.id == _selectedId) return;
    if (!await _confirmDiscard()) return;
    _edit(field);
  }

  Future<void> _newField() async {
    if (!await _confirmDiscard()) return;
    _edit(
      const CustomField(
        id: '',
        key: '',
        label: '',
        type: CustomFieldType.shortText,
      ),
      isNew: true,
    );
  }

  void _change(CustomField Function(CustomField) update) => setState(() {
    _draft = update(_draft!);
    _dirty = true;
  });

  CustomField _current() {
    final d = _draft!;
    return CustomField(
      id: d.id,
      key: _isNew ? fieldKeyFor(_label.text) : d.key,
      label: _label.text.trim(),
      type: d.type,
      description: _description.text.trim(),
      options: d.type.hasOptions
          ? [for (final (_, c) in _options) c.text.trim()]
          : const [],
      required: d.required,
      sensitive: d.sensitive,
      archived: d.archived,
      departments: d.departments,
      branchIds: d.branchIds,
      access: d.access,
      createdAt: d.createdAt,
    );
  }

  Future<void> _save({bool? archived}) async {
    if (_busy || _draft == null) return;
    var field = _current();
    if (archived != null) field = field.copyWith(archived: archived);
    final all = ref.read(customFieldsProvider).value ?? const <CustomField>[];
    final errors = validateFieldDefinition(field, others: all);
    if (field.key.isEmpty && !errors.containsKey('label')) {
      errors['label'] = 'Use letters or numbers in the label.';
    }
    setState(() => _errors = errors);
    if (errors.isNotEmpty) return;
    final renames = <String, String>{
      for (final (original, c) in _options)
        if (original != null && original != c.text.trim())
          original: c.text.trim(),
    };
    setState(() => _busy = true);
    try {
      final saved = await ref
          .read(customFieldsProvider.notifier)
          .save(field, renamedOptions: renames);
      if (!mounted) return;
      _edit(saved);
      showAppToast(
        context,
        archived == true
            ? '${saved.label} archived · no longer collected'
            : (archived == false
                  ? '${saved.label} restored'
                  : '${saved.label} saved'),
      );
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

  @override
  Widget build(BuildContext context) {
    final fields = ref.watch(customFieldsProvider);
    final employees = ref.watch(employeesProvider).value ?? const <Employee>[];
    final branches = ref.watch(branchesProvider).value ?? const <Branch>[];
    return ResponsivePage(
      child: fields.when(
        loading: () => const LoadingSkeleton(
          label: 'Loading fields',
          child: SkeletonList(rows: 6),
        ),
        error: (error, _) => ErrorState(
          message: userMessageFor(error),
          onRetry: () => ref.invalidate(customFieldsProvider),
        ),
        data: (list) {
          final list0 = list;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Breadcrumbs(
                items: [
                  BreadcrumbItem(
                    'Settings',
                    onTap: () => context.go(AppRoutes.settings),
                  ),
                  const BreadcrumbItem('Employee fields'),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              PageHeader(
                title: 'Employee fields',
                subtitle: 'Drag to reorder how fields appear on forms.',
                actions: [
                  AppButton(
                    label: 'New field',
                    icon: Icons.add,
                    onPressed: _newField,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              LayoutBuilder(
                builder: (context, c) {
                  final listView = _FieldList(
                    fields: list0,
                    selectedId: _selectedId,
                    onSelect: _select,
                    onReorder: (ids) =>
                        ref.read(customFieldsProvider.notifier).reorder(ids),
                  );
                  final editor = _draft == null
                      ? const AppCard(
                          child: EmptyState(
                            icon: Icons.tune_outlined,
                            title: 'Choose a field to edit',
                            message:
                                'Or create a new one. Fields appear on the add and edit employee forms and in imports.',
                          ),
                        )
                      : _editor(employees, branches);
                  if (c.maxWidth < 900) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        listView,
                        const SizedBox(height: AppSpacing.lg),
                        editor,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 340, child: listView),
                      const SizedBox(width: AppSpacing.lg),
                      Expanded(child: editor),
                    ],
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _editor(List<Employee> employees, List<Branch> branches) {
    final d = _draft!;
    final field = _current();
    final used = employees
        .where((e) => !isBlankValue(e.customValues[d.key]))
        .length;
    final hasValues = !_isNew && used > 0;
    final allowedTypes = allowedTypeChanges(
      ref
              .read(customFieldsProvider)
              .value
              ?.where((f) => f.id == d.id)
              .firstOrNull
              ?.type ??
          d.type,
      hasValues: hasValues,
    );
    final missing = d.required ? missingValues(field, employees) : 0;
    final scopeDepartments = d.departments.isEmpty
        ? 'all departments'
        : d.departments.join(', ');

    return AppCard(
      header: CardHeader(
        title: _isNew ? 'New field' : d.label,
        subtitle: _isNew
            ? 'Not saved yet'
            : 'Used on $used ${used == 1 ? 'employee' : 'employees'}'
                  '${d.createdAt == null ? '' : ' · created ${employeeDateFormat.format(d.createdAt!)}'}'
                  '${d.archived ? ' · archived' : ''}',
        trailing: Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            if (!_isNew)
              AppButton(
                label: d.archived ? 'Restore' : 'Archive',
                variant: AppButtonVariant.secondary,
                onPressed: _busy ? null : () => _save(archived: !d.archived),
              ),
            AppButton(
              label: 'Save field',
              busy: _busy,
              busyLabel: 'Saving…',
              onPressed: _save,
            ),
          ],
        ),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final form = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_errors['form'] case final m?) ...[
                Text(
                  m,
                  style: AppTypography.small.copyWith(color: AppColors.danger),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              AppTextField(
                label: 'Label',
                controller: _label,
                isRequired: true,
                errorText: _errors['label'],
                onChanged: (_) => setState(() {
                  _dirty = true;
                  _errors.remove('label');
                }),
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                label: 'Field key',
                controller: TextEditingController(
                  text: _isNew ? fieldKeyFor(_label.text) : d.key,
                ),
                readOnly: true,
                monospace: true,
                helperText: 'Used in imports and exports. Can’t be changed.',
              ),
              const SizedBox(height: AppSpacing.md),
              AppDropdownField<CustomFieldType>(
                label: 'Field type',
                value: d.type,
                errorText: _errors['type'],
                helperText:
                    hasValues &&
                        allowedTypes.length < CustomFieldType.values.length
                    ? (allowedTypes.length == 1
                          ? 'Locked because values exist.'
                          : 'Locked because values exist. Can switch to '
                                '${allowedTypes.where((t) => t != d.type).map((t) => t.label).join(', ')} only.')
                    : null,
                options: [
                  for (final t in CustomFieldType.values)
                    AppDropdownOption(
                      t,
                      t.label,
                      enabled: allowedTypes.contains(t),
                    ),
                ],
                onChanged: (t) {
                  if (t == null) return;
                  _change((f) => f.copyWith(type: t));
                  if (t.hasOptions && _options.isEmpty) {
                    setState(
                      () => _options = [(null, TextEditingController())],
                    );
                  }
                },
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                label: 'Description',
                controller: _description,
                isOptional: true,
                onChanged: (_) => setState(() => _dirty = true),
              ),
              if (d.type.hasOptions) ...[
                const SizedBox(height: AppSpacing.lg),
                _optionsEditor(d, employees),
              ],
              const SizedBox(height: AppSpacing.lg),
              SwitchRow(
                label: 'Required',
                value: d.required,
                description: d.required && missing > 0
                    ? '$missing ${missing == 1 ? 'employee' : 'employees'} in $scopeDepartments '
                          'have no value. They won’t be blocked — HR will see them flagged '
                          'as incomplete until filled.'
                    : 'Required fields must be filled when adding, importing or editing someone.',
                onChanged: (v) => _change((f) => f.copyWith(required: v)),
              ),
              const SizedBox(height: AppSpacing.lg),
              _accessMatrix(d),
              const SizedBox(height: AppSpacing.md),
              LabeledCheckbox(
                value: d.sensitive,
                label: const Text(
                  'Sensitive — hide from exports unless permitted',
                  style: AppTypography.body,
                ),
                onChanged: (v) => _change((f) => f.copyWith(sensitive: v)),
              ),
              const SizedBox(height: AppSpacing.md),
              _appliesTo(d, branches),
            ],
          );
          final preview = _Preview(field: field);
          if (c.maxWidth < 760) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                form,
                const SizedBox(height: AppSpacing.lg),
                preview,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: form),
              const SizedBox(width: AppSpacing.xl),
              SizedBox(width: 280, child: preview),
            ],
          );
        },
      ),
    );
  }

  Widget _optionsEditor(CustomField d, List<Employee> employees) {
    final saved = ref
        .read(customFieldsProvider)
        .value
        ?.where((f) => f.id == d.id)
        .firstOrNull;
    return FormFieldFrame(
      label: 'Options',
      errorText: _errors['options'],
      helperText:
          'Options in use can be renamed but not removed. Archive the field to stop collecting it.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < _options.length; i++)
            () {
              final (original, controller) = _options[i];
              final count = original == null || saved == null
                  ? 0
                  : optionUsage(saved, original, employees);
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Row(
                  children: [
                    Expanded(
                      child: Semantics(
                        label: 'Option ${i + 1}',
                        textField: true,
                        child: TextField(
                          controller: controller,
                          onChanged: (_) => setState(() {
                            _dirty = true;
                            _errors.remove('options');
                          }),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    SizedBox(
                      width: 80,
                      child: Text(
                        '$count people',
                        style: AppTypography.helper,
                        textAlign: TextAlign.end,
                      ),
                    ),
                    IconButton(
                      tooltip: count > 0
                          ? 'In use — can’t be removed'
                          : 'Remove option ${controller.text}',
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: count > 0
                          ? null
                          : () => setState(() {
                              _options.removeAt(i).$2.dispose();
                              _dirty = true;
                            }),
                    ),
                  ],
                ),
              );
            }(),
          Align(
            alignment: Alignment.centerLeft,
            child: AppButton(
              label: 'Add option',
              icon: Icons.add,
              size: AppButtonSize.small,
              variant: AppButtonVariant.ghost,
              onPressed: () => setState(() {
                _options.add((null, TextEditingController()));
                _dirty = true;
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _accessMatrix(CustomField d) {
    void set(FieldAudience a, {bool? view, bool? edit}) {
      final current = d.access[a] ?? const FieldAccess();
      var v = view ?? current.view;
      var e = edit ?? current.edit;
      if (e) v = true; // Editing implies viewing.
      if (!v) e = false;
      _change(
        (f) => f.copyWith(
          access: {
            ...f.access,
            a: FieldAccess(view: v, edit: e),
          },
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: const Text('Who can see and edit', style: AppTypography.label),
        ),
        const SizedBox(height: AppSpacing.xs),
        const Text(
          'The owner can always see and edit every field.',
          style: AppTypography.helper,
        ),
        const SizedBox(height: AppSpacing.sm),
        Table(
          columnWidths: const {
            0: FlexColumnWidth(),
            1: FixedColumnWidth(64),
            2: FixedColumnWidth(64),
          },
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            const TableRow(
              children: [
                Text('ROLE', style: AppTypography.tableHeader),
                Center(child: Text('VIEW', style: AppTypography.tableHeader)),
                Center(child: Text('EDIT', style: AppTypography.tableHeader)),
              ],
            ),
            for (final a in FieldAudience.values)
              TableRow(
                children: [
                  Text(
                    a.label,
                    style: AppTypography.small.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Checkbox(
                    value: d.access[a]?.view ?? false,
                    semanticLabel: '${a.label} can view',
                    onChanged: (v) => set(a, view: v ?? false),
                  ),
                  Checkbox(
                    value: d.access[a]?.edit ?? false,
                    semanticLabel: '${a.label} can edit',
                    onChanged: (v) => set(a, edit: v ?? false),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }

  Widget _appliesTo(CustomField d, List<Branch> branches) {
    Widget chips(
      List<(String, String)> options,
      List<String> selected,
      ValueChanged<List<String>> onChanged,
      String allLabel,
    ) => Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      children: [
        FilterChip(
          label: Text(allLabel),
          selected: selected.isEmpty,
          onSelected: (_) => onChanged(const []),
        ),
        for (final (value, label) in options)
          FilterChip(
            label: Text(label),
            selected: selected.contains(value),
            onSelected: (on) => onChanged(
              on
                  ? [...selected, value]
                  : selected.where((s) => s != value).toList(),
            ),
          ),
      ],
    );
    return FormFieldFrame(
      label: 'Applies to',
      helperText:
          'People outside these departments and branches don’t see the field.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          chips(
            [for (final dep in departments) (dep, dep)],
            d.departments,
            (v) => _change((f) => f.copyWith(departments: v)),
            'All departments',
          ),
          const SizedBox(height: AppSpacing.sm),
          chips(
            [for (final b in branches.where((b) => b.isActive)) (b.id, b.name)],
            d.branchIds,
            (v) => _change((f) => f.copyWith(branchIds: v)),
            'All branches',
          ),
        ],
      ),
    );
  }
}

class _FieldList extends StatelessWidget {
  const _FieldList({
    required this.fields,
    required this.selectedId,
    required this.onSelect,
    required this.onReorder,
  });

  final List<CustomField> fields;
  final String? selectedId;
  final ValueChanged<CustomField> onSelect;
  final ValueChanged<List<String>> onReorder;

  @override
  Widget build(BuildContext context) {
    if (fields.isEmpty) {
      return const AppCard(
        child: EmptyState(
          icon: Icons.tune_outlined,
          title: 'No custom fields yet',
          message:
              'Add fields like uniform size or locker number. They appear on employee forms and imports.',
        ),
      );
    }
    return AppCard(
      padding: EdgeInsets.zero,
      child: ReorderableListView(
        shrinkWrap: true,
        buildDefaultDragHandles: false,
        physics: const NeverScrollableScrollPhysics(),
        onReorderItem: (from, to) {
          final ids = [for (final f in fields) f.id];
          ids.insert(to, ids.removeAt(from));
          onReorder(ids);
        },
        children: [
          for (var i = 0; i < fields.length; i++)
            Material(
              key: ValueKey(fields[i].id),
              color: fields[i].id == selectedId
                  ? AppColors.primarySelected
                  : AppColors.surface,
              child: InkWell(
                onTap: () => onSelect(fields[i]),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(
                        color: fields[i].id == selectedId
                            ? AppColors.primary
                            : Colors.transparent,
                        width: 3,
                      ),
                      bottom: const BorderSide(color: AppColors.divider),
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(4, 10, AppSpacing.md, 10),
                  child: Row(
                    children: [
                      ReorderableDragStartListener(
                        index: i,
                        child: Tooltip(
                          message: 'Reorder ${fields[i].label}',
                          child: const Padding(
                            padding: EdgeInsets.all(AppSpacing.sm),
                            child: Icon(
                              Icons.drag_indicator,
                              size: 18,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    fields[i].label,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTypography.bodyStrong.copyWith(
                                      color: fields[i].archived
                                          ? AppColors.textMuted
                                          : AppColors.textPrimary,
                                    ),
                                  ),
                                ),
                                if (fields[i].sensitive) ...[
                                  const SizedBox(width: 4),
                                  const Icon(
                                    Icons.lock_outline,
                                    size: 13,
                                    color: AppColors.textMuted,
                                  ),
                                ],
                              ],
                            ),
                            Text(
                              '${fields[i].type.label} · ${_scope(fields[i])}',
                              style: AppTypography.helper,
                            ),
                          ],
                        ),
                      ),
                      StatusBadge(
                        label: fields[i].archived
                            ? 'Archived'
                            : (fields[i].required ? 'Required' : 'Optional'),
                        tone: !fields[i].archived && fields[i].required
                            ? StatusTone.danger
                            : StatusTone.neutral,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  static String _scope(CustomField f) {
    final parts = [
      if (f.departments.isNotEmpty)
        f.departments.length == 1
            ? f.departments.single
            : '${f.departments.length} departments',
      if (f.branchIds.isNotEmpty)
        '${f.branchIds.length} ${f.branchIds.length == 1 ? 'branch' : 'branches'}',
    ];
    return parts.isEmpty ? 'All' : parts.join(' · ');
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.field});

  final CustomField field;

  @override
  Widget build(BuildContext context) {
    final label = field.label.isEmpty ? 'Untitled field' : field.label;
    final selfAccess = field.access[FieldAudience.self] ?? const FieldAccess();
    final Widget input = switch (field.type) {
      CustomFieldType.singleSelect => AppDropdownField<String>(
        label: label,
        isRequired: field.required,
        value: null,
        hintText: 'Select an option',
        options: [
          for (final o in field.options.where((o) => o.trim().isNotEmpty))
            AppDropdownOption(o, o),
        ],
        onChanged: (_) {},
        helperText: field.description.isEmpty ? null : field.description,
      ),
      CustomFieldType.yesNo => SwitchRow(
        label: label,
        value: false,
        onChanged: (_) {},
      ),
      CustomFieldType.multiSelect => FormFieldFrame(
        label: label,
        isRequired: field.required,
        helperText: field.description.isEmpty ? null : field.description,
        child: Wrap(
          spacing: AppSpacing.sm,
          children: [
            for (final o in field.options.where((o) => o.trim().isNotEmpty))
              FilterChip(label: Text(o), selected: false, onSelected: (_) {}),
          ],
        ),
      ),
      _ => AppTextField(
        label: label,
        isRequired: field.required,
        hintText: field.type == CustomFieldType.date ? 'Choose a date' : null,
        helperText: field.description.isEmpty ? null : field.description,
      ),
    };
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Preview on employee form', style: AppTypography.helper),
          const SizedBox(height: AppSpacing.md),
          ExcludeSemantics(child: AbsorbPointer(child: input)),
          const SizedBox(height: AppSpacing.md),
          Text(
            !selfAccess.view
                ? 'Employees don’t see this on their profile.'
                : (selfAccess.edit
                      ? 'Employees can fill this in on their profile.'
                      : 'Employees see this as read-only on their profile.'),
            style: AppTypography.helper,
          ),
        ],
      ),
    );
  }
}

/// Link from the Settings page (built in Phase 7) to the field builder.
class EmployeeFieldsButton extends StatelessWidget {
  const EmployeeFieldsButton({super.key});

  @override
  Widget build(BuildContext context) => AppButton(
    label: 'Employee fields',
    icon: Icons.tune_outlined,
    variant: AppButtonVariant.secondary,
    onPressed: () => context.go(AppRoutes.employeeFields),
  );
}
