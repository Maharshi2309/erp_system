import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../app/router/route_names.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/responsive/responsive_grid.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_date_field.dart';
import '../../../../core/widgets/app_dropdown_field.dart';
import '../../../../core/widgets/app_overlays.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/selection_controls.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../employees/domain/employee.dart';
import '../../../organization/domain/branch.dart';
import '../../../organization/presentation/providers/organization_providers.dart';
import '../../domain/leave.dart';
import '../../domain/leave_book.dart';
import '../leave_providers.dart';
import '../leave_widgets.dart';
import 'leave_section.dart';

/// A number box that reports a parsed value (null when not a number).
class NumberField extends StatefulWidget {
  const NumberField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.unit,
    this.helperText,
    this.errorText,
  });

  final String label;
  final double value;
  final ValueChanged<double?> onChanged;
  final String? unit;
  final String? helperText;
  final String? errorText;

  @override
  State<NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<NumberField> {
  late final _c = TextEditingController(text: formatDays(widget.value));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppTextField(
    label: widget.unit == null
        ? widget.label
        : '${widget.label} (${widget.unit})',
    controller: _c,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    helperText: widget.helperText,
    errorText: widget.errorText,
    onChanged: (v) => widget.onChanged(double.tryParse(v.trim())),
  );
}

/// Multi-select chips where nothing selected means "all".
class AllOrSome<T> extends StatelessWidget {
  const AllOrSome({
    super.key,
    required this.label,
    required this.allLabel,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final String label;
  final String allLabel;
  final List<(T, String)> options;
  final List<T> selected;
  final ValueChanged<List<T>> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTypography.label),
        const SizedBox(height: 6),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            FilterChip(
              label: Text(allLabel),
              selected: selected.isEmpty,
              showCheckmark: false,
              onSelected: (_) => onChanged(const []),
            ),
            for (final (v, text) in options)
              FilterChip(
                label: Text(text),
                selected: selected.contains(v),
                showCheckmark: false,
                onSelected: (on) => onChanged(
                  on
                      ? [...selected, v]
                      : [
                          for (final x in selected)
                            if (x != v) x,
                        ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Keeps its own controller so typing doesn't reset the cursor.
class _NameField extends StatefulWidget {
  const _NameField({
    required this.initial,
    required this.onChanged,
    this.errorText,
  });

  final String initial;
  final ValueChanged<String> onChanged;
  final String? errorText;

  @override
  State<_NameField> createState() => _NameFieldState();
}

class _NameFieldState extends State<_NameField> {
  late final _c = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppTextField(
    label: 'Name',
    isRequired: true,
    controller: _c,
    maxLength: 40,
    errorText: widget.errorText,
    onChanged: widget.onChanged,
  );
}

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(title, style: AppTypography.cardTitle),
        ),
        const SizedBox(height: AppSpacing.sm),
        ResponsiveGrid(minItemWidth: 220, maxColumns: 3, children: children),
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }
}

/// Board S58 — leave types with an editor.
class LeaveTypesScreen extends ConsumerStatefulWidget {
  const LeaveTypesScreen({super.key});

  @override
  ConsumerState<LeaveTypesScreen> createState() => _LeaveTypesScreenState();
}

class _LeaveTypesScreenState extends ConsumerState<LeaveTypesScreen> {
  String? _key;
  LeaveType? _draft;

  /// Bumped to rebuild the number boxes after discard or a switch.
  int _version = 0;
  Map<String, String> _errors = const {};
  bool _busy = false;

  static const _palette = [
    0xFF2B4ACB,
    0xFF0B7A62,
    0xFF8A4F00,
    0xFF475467,
    0xFFB4471C,
    0xFF7A3FB8,
  ];

  Future<bool> _leave(LeaveType? saved) async {
    if (_draft == null || _same(_draft!, saved)) return true;
    return showConfirmDialog(
      context,
      title: 'Discard changes?',
      message: 'Your changes to ${_draft!.name} haven’t been saved.',
      confirmLabel: 'Discard',
      destructive: true,
    );
  }

  static bool _same(LeaveType a, LeaveType? b) =>
      b != null &&
      a.name == b.name &&
      a.paid == b.paid &&
      a.method == b.method &&
      a.allowance == b.allowance &&
      a.startsAfterMonths == b.startsAfterMonths &&
      a.carryForwardMax == b.carryForwardMax &&
      a.minDays == b.minDays &&
      a.maxDays == b.maxDays &&
      a.allowHalfDays == b.allowHalfDays &&
      a.countWeeklyOffs == b.countWeeklyOffs &&
      a.countHolidays == b.countHolidays &&
      a.noticeDays == b.noticeDays &&
      a.backdateDays == b.backdateDays &&
      a.active == b.active &&
      _list(a.eligibleTypes, b.eligibleTypes) &&
      _list(a.branchIds, b.branchIds) &&
      _list(a.departments, b.departments);

  static bool _list<T>(List<T> a, List<T> b) =>
      a.length == b.length && a.every(b.contains);

  Future<void> _save() async {
    final draft = _draft!;
    final book = ref.read(leaveBookProvider).value!;
    final errors = validateLeaveType(draft, book.data.types);
    setState(() => _errors = errors);
    if (errors.isNotEmpty) return;
    setState(() => _busy = true);
    try {
      final saved = await ref.read(leaveDataProvider.notifier).saveType(draft);
      if (!mounted) return;
      setState(() {
        _key = saved.key;
        _draft = null;
        _version++;
      });
      showAppToast(context, '${saved.name} saved');
    } on Failure catch (f) {
      if (mounted) {
        setState(
          () => _errors = f is ValidationFailure
              ? f.fieldErrors
              : {'name': f.message},
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => LeaveSection(
    current: AppRoutes.leaveTypes,
    body: (context, scope) {
      final book = scope.book;
      final types = book.data.types;
      final saved =
          types.where((t) => t.key == _key).firstOrNull ??
          (_key == '' ? null : types.firstOrNull);
      final t = _draft ?? saved;
      final dirty = t != null && (_draft != null && !_same(_draft!, saved));
      void edit(LeaveType Function(LeaveType) change) =>
          setState(() => _draft = change(_draft ?? saved!));

      final list = AppCard(
        padding: EdgeInsets.zero,
        header: CardHeader(
          title: 'Leave types',
          trailing: AppButton(
            label: 'New type',
            icon: Icons.add,
            size: AppButtonSize.small,
            variant: AppButtonVariant.secondary,
            onPressed: () async {
              if (!await _leave(saved)) return;
              setState(() {
                _key = '';
                _version++;
                _errors = const {};
                _draft = LeaveType(
                  key: '',
                  name: 'New leave type',
                  color: _palette[types.length % _palette.length],
                  allowance: 6,
                );
              });
            },
          ),
        ),
        child: Column(
          children: [
            for (final x in types)
              Semantics(
                selected: x.key == t?.key,
                button: true,
                child: InkWell(
                  onTap: () async {
                    if (x.key == t?.key || !await _leave(saved)) return;
                    setState(() {
                      _key = x.key;
                      _draft = null;
                      _errors = const {};
                      _version++;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: x.key == t?.key ? const Color(0xFFF7F8FE) : null,
                      border: Border(
                        left: BorderSide(
                          color: x.key == t?.key
                              ? AppColors.primary
                              : Colors.transparent,
                          width: 3,
                        ),
                        top: const BorderSide(color: AppColors.divider),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: Color(x.color),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(x.name, style: AppTypography.bodyStrong),
                              Text(x.summary, style: AppTypography.helper),
                            ],
                          ),
                        ),
                        StatusBadge(
                          label: x.active ? 'Active' : 'Inactive',
                          tone: x.active
                              ? StatusTone.success
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

      final editor = t == null
          ? const SizedBox.shrink()
          : _TypeEditor(
              key: ValueKey('${t.key}-$_version'),
              book: book,
              type: t,
              people: scope.people,
              errors: _errors,
              dirty: dirty,
              busy: _busy,
              onChange: edit,
              onDiscard: () => setState(() {
                _draft = null;
                _errors = const {};
                _version++;
                if (_key == '') _key = null;
              }),
              onSave: _save,
            );

      return LayoutBuilder(
        builder: (context, c) => c.maxWidth >= 1000
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 320, child: list),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(child: editor),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  list,
                  const SizedBox(height: AppSpacing.lg),
                  editor,
                ],
              ),
      );
    },
  );
}

class _TypeEditor extends ConsumerWidget {
  const _TypeEditor({
    super.key,
    required this.book,
    required this.type,
    required this.people,
    required this.errors,
    required this.dirty,
    required this.busy,
    required this.onChange,
    required this.onDiscard,
    required this.onSave,
  });

  final LeaveBook book;
  final LeaveType type;
  final List<Employee> people;
  final Map<String, String> errors;
  final bool dirty;
  final bool busy;
  final void Function(LeaveType Function(LeaveType)) onChange;
  final VoidCallback onDiscard;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = type;
    final branches = ref.watch(branchesProvider).value ?? const <Branch>[];
    final users = t.key.isEmpty
        ? 0
        : people.where((e) => book.offers(e, t)).length;
    final taken = t.key.isEmpty
        ? 0.0
        : book.data.requests
              .where(
                (r) =>
                    r.typeKey == t.key &&
                    r.status == LeaveStatus.approved &&
                    r.from.year == book.today.year,
              )
              .fold(0.0, (s, r) => s + book.daysOf(r));
    return AppCard(
      header: CardHeader(
        title: t.key.isEmpty ? 'New leave type' : t.name,
        subtitle: t.key.isEmpty
            ? 'Saved types apply to every branch that offers them.'
            : 'Offered to $users employees · ${formatDays(taken)} days taken in ${book.today.year}',
        trailing: Wrap(
          spacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (dirty)
              Text(
                'Unsaved changes',
                style: AppTypography.small.copyWith(
                  color: AppColors.warningText,
                ),
              ),
            AppButton(
              label: 'Discard',
              variant: AppButtonVariant.secondary,
              size: AppButtonSize.small,
              onPressed: dirty || t.key.isEmpty ? onDiscard : null,
            ),
            AppButton(
              label: 'Save',
              size: AppButtonSize.small,
              busy: busy,
              busyLabel: 'Saving…',
              onPressed: dirty || t.key.isEmpty ? onSave : null,
            ),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Group(
            title: 'Basics',
            children: [
              _NameField(
                initial: t.name,
                errorText: errors['name'],
                onChanged: (v) => onChange((x) => x.copyWith(name: v)),
              ),
              AppDropdownField<bool>(
                label: 'Pay',
                value: t.paid,
                options: const [
                  AppDropdownOption(true, 'Paid'),
                  AppDropdownOption(false, 'Unpaid'),
                ],
                onChanged: (v) => onChange((x) => x.copyWith(paid: v)),
              ),
              AppDropdownField<AccrualMethod>(
                label: 'Balance',
                value: t.method,
                options: [
                  for (final m in AccrualMethod.values)
                    AppDropdownOption(m, m.label),
                ],
                onChanged: t.optionalHolidaysOnly
                    ? null
                    : (v) => onChange((x) => x.copyWith(method: v)),
              ),
            ],
          ),
          SwitchRow(
            label: 'Active',
            description:
                'Inactive types can’t be requested; past requests stay.',
            value: t.active,
            onChanged: (v) => onChange((x) => x.copyWith(active: v)),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (t.tracksBalance)
            _Group(
              title: 'Allowance & accrual',
              children: [
                NumberField(
                  label: t.method == AccrualMethod.monthly
                      ? 'Per month'
                      : 'Per year',
                  unit: 'days',
                  value: t.allowance,
                  errorText: errors['allowance'],
                  helperText: 'A branch’s leave setup can override this.',
                  onChanged: (v) =>
                      onChange((x) => x.copyWith(allowance: v ?? -1)),
                ),
                NumberField(
                  label: 'Starts after',
                  unit: 'months',
                  value: t.startsAfterMonths.toDouble(),
                  errorText: errors['startsAfter'],
                  helperText: 'Applies to new joiners only.',
                  onChanged: (v) => onChange(
                    (x) => x.copyWith(startsAfterMonths: v?.round() ?? -1),
                  ),
                ),
                NumberField(
                  label: 'Carry forward up to',
                  unit: 'days',
                  value: t.carryForwardMax,
                  errorText: errors['carry'],
                  helperText: '0 means unused days lapse on 31 Dec.',
                  onChanged: (v) =>
                      onChange((x) => x.copyWith(carryForwardMax: v ?? -1)),
                ),
              ],
            ),
          _Group(
            title: 'Rules',
            children: [
              NumberField(
                label: 'Minimum per request',
                unit: 'days',
                value: t.minDays,
                errorText: errors['minDays'],
                onChanged: (v) => onChange((x) => x.copyWith(minDays: v ?? -1)),
              ),
              NumberField(
                label: 'Maximum per request',
                unit: 'days',
                value: t.maxDays,
                errorText: errors['maxDays'],
                onChanged: (v) => onChange((x) => x.copyWith(maxDays: v ?? -1)),
              ),
              NumberField(
                label: 'Notice',
                unit: 'days ahead',
                value: t.noticeDays.toDouble(),
                errorText: errors['notice'],
                helperText: '0 allows same-day requests.',
                onChanged: (v) =>
                    onChange((x) => x.copyWith(noticeDays: v?.round() ?? -1)),
              ),
              NumberField(
                label: 'Can be backdated',
                unit: 'days',
                value: t.backdateDays.toDouble(),
                errorText: errors['backdate'],
                helperText: 'Usually only sick leave.',
                onChanged: (v) =>
                    onChange((x) => x.copyWith(backdateDays: v?.round() ?? -1)),
              ),
            ],
          ),
          SwitchRow(
            label: 'Allow half days',
            value: t.allowHalfDays,
            onChanged: (v) => onChange((x) => x.copyWith(allowHalfDays: v)),
          ),
          SwitchRow(
            label: 'Count weekly offs inside a request',
            description: 'Off: weekly offs are skipped when counting days.',
            value: t.countWeeklyOffs,
            onChanged: (v) => onChange((x) => x.copyWith(countWeeklyOffs: v)),
          ),
          SwitchRow(
            label: 'Count holidays inside a request',
            description: 'Off: holidays are skipped when counting days.',
            value: t.countHolidays,
            onChanged: (v) => onChange((x) => x.copyWith(countHolidays: v)),
          ),
          const SizedBox(height: AppSpacing.lg),
          Semantics(
            header: true,
            child: const Text('Eligibility', style: AppTypography.cardTitle),
          ),
          const SizedBox(height: AppSpacing.sm),
          AllOrSome<EmploymentType>(
            label: 'Employment types',
            allLabel: 'Everyone',
            options: [for (final e in EmploymentType.values) (e, e.label)],
            selected: t.eligibleTypes,
            onChanged: (v) => onChange((x) => x.copyWith(eligibleTypes: v)),
          ),
          const SizedBox(height: AppSpacing.md),
          AllOrSome<String>(
            label: 'Branches',
            allLabel: 'All branches',
            options: [
              for (final b in branches)
                if (b.isActive) (b.id, b.name),
            ],
            selected: t.branchIds,
            onChanged: (v) => onChange((x) => x.copyWith(branchIds: v)),
          ),
          const SizedBox(height: AppSpacing.md),
          AllOrSome<String>(
            label: 'Departments',
            allLabel: 'All departments',
            options: [for (final d in departments) (d, d)],
            selected: t.departments,
            onChanged: (v) => onChange((x) => x.copyWith(departments: v)),
          ),
          const SizedBox(height: AppSpacing.lg),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Example · employee joining 1 Mar ${book.today.year}',
                  style: AppTypography.label,
                ),
                const SizedBox(height: 4),
                Text(
                  accrualExample(t, book.today.year),
                  style: AppTypography.small,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Board S59 — approval routes, request rules, blackouts and balance rules.
class LeavePolicyScreen extends ConsumerStatefulWidget {
  const LeavePolicyScreen({super.key});

  @override
  ConsumerState<LeavePolicyScreen> createState() => _LeavePolicyScreenState();
}

class _LeavePolicyScreenState extends ConsumerState<LeavePolicyScreen> {
  LeavePolicy? _draft;
  int _version = 0;
  bool _busy = false;

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await ref.read(leaveDataProvider.notifier).savePolicy(_draft!);
      if (!mounted) return;
      setState(() {
        _draft = null;
        _version++;
      });
      showAppToast(context, 'Leave policy saved');
    } on Failure catch (f) {
      if (mounted) showAppToast(context, f.message, icon: Icons.error_outline);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => LeaveSection(
    current: AppRoutes.leavePolicy,
    body: (context, scope) {
      final book = scope.book;
      final saved = book.policy;
      final p = _draft ?? saved;
      final dirty = _draft != null;
      final errors = validateLeavePolicy(p);
      final branches = ref.watch(branchesProvider).value ?? const <Branch>[];
      String branchName(String? id) => id == null
          ? 'All branches'
          : branches.where((b) => b.id == id).firstOrNull?.name ?? id;
      String typeName(String? key) =>
          key == null ? '' : book.data.type(key)?.name ?? key;
      void edit(LeavePolicy Function(LeavePolicy) change) =>
          setState(() => _draft = change(p));

      Future<void> editRoute(ApprovalRoute? r) async {
        final result = await showSidePanelRoute<ApprovalRoute>(
          context,
          barrierLabel: 'Close route',
          builder: (_) =>
              _RouteForm(route: r, branches: branches, types: book.data.types),
        );
        if (result == null) return;
        edit(
          (x) => x.copyWith(
            routes: [
              for (final o in x.routes)
                if (o.id != result.id) o,
              result,
            ],
          ),
        );
      }

      Future<void> editBlackout(int? index) async {
        final result = await showSidePanelRoute<Blackout>(
          context,
          barrierLabel: 'Close blackout period',
          builder: (_) => _BlackoutForm(
            blackout: index == null ? null : p.blackouts[index],
            branches: branches,
            types: book.data.types,
            today: book.today,
          ),
        );
        if (result == null) return;
        edit(
          (x) => x.copyWith(
            blackouts: [
              for (var i = 0; i < x.blackouts.length; i++)
                if (i == index) result else x.blackouts[i],
              if (index == null) result,
            ],
          ),
        );
      }

      final routes = [...p.routes]
        ..sort((a, b) => a.specificity.compareTo(b.specificity));

      return Column(
        key: ValueKey(_version),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: const Text(
                      'Leave policy',
                      style: AppTypography.pageTitle,
                    ),
                  ),
                  Text(
                    [
                      if (dirty) 'Unsaved changes',
                      if (saved.updatedAt != null)
                        'last saved ${DateFormat('d MMM, HH:mm').format(saved.updatedAt!)}${saved.updatedBy.isEmpty ? '' : ' by ${saved.updatedBy}'}',
                    ].join(' · '),
                    style: AppTypography.small.copyWith(
                      color: dirty ? AppColors.warningText : null,
                    ),
                  ),
                ],
              ),
              Wrap(
                spacing: AppSpacing.sm,
                children: [
                  AppButton(
                    label: 'Discard',
                    variant: AppButtonVariant.secondary,
                    onPressed: dirty
                        ? () => setState(() {
                            _draft = null;
                            _version++;
                          })
                        : null,
                  ),
                  AppButton(
                    label: errors.isEmpty
                        ? 'Save policy'
                        : 'Fix ${errors.length} ${errors.length == 1 ? 'error' : 'errors'} to save',
                    busy: _busy,
                    busyLabel: 'Saving…',
                    onPressed: dirty && errors.isEmpty ? _save : null,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            header: CardHeader(
              title: 'Approval routes',
              subtitle:
                  'Who decides. Nobody approves their own request — it skips to HR.',
              trailing: AppButton(
                label: 'Add route',
                icon: Icons.add,
                size: AppButtonSize.small,
                variant: AppButtonVariant.secondary,
                onPressed: () => editRoute(null),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final r in routes)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: AppColors.divider),
                      ),
                    ),
                    child: Wrap(
                      spacing: AppSpacing.lg,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SizedBox(
                          width: 220,
                          child: Text(
                            r.branchId == null && r.typeKey == null
                                ? 'All branches (default)'
                                : [
                                    if (r.typeKey != null) typeName(r.typeKey),
                                    if (r.branchId != null)
                                      branchName(r.branchId)
                                    else
                                      'all',
                                  ].join(' · '),
                            style: AppTypography.bodyStrong,
                          ),
                        ),
                        const SizedBox(
                          width: 160,
                          child: Text(
                            'Reporting manager',
                            style: AppTypography.small,
                          ),
                        ),
                        SizedBox(
                          width: 220,
                          child: Text(switch (r.second) {
                            SecondStep.none => 'No second step',
                            SecondStep.hrIfDays =>
                              'HR Admin if ${formatDays(r.minDays)}+ days',
                            SecondStep.branchManagerIfDays =>
                              'Branch Manager if ${formatDays(r.minDays)}+ days',
                            SecondStep.hrAlways => 'HR Admin always',
                          }, style: AppTypography.small),
                        ),
                        TextButton(
                          onPressed: () => editRoute(r),
                          child: const Text('Edit'),
                        ),
                        if (r.branchId != null || r.typeKey != null)
                          TextButton(
                            onPressed: () => edit(
                              (x) => x.copyWith(
                                routes: [
                                  for (final o in x.routes)
                                    if (o.id != r.id) o,
                                ],
                              ),
                            ),
                            child: const Text('Remove'),
                          ),
                      ],
                    ),
                  ),
                if (errors['routes'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: Text(
                      errors['routes']!,
                      style: AppTypography.small.copyWith(
                        color: AppColors.danger,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            header: const CardHeader(title: 'Request rules'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ResponsiveGrid(
                  minItemWidth: 220,
                  maxColumns: 3,
                  children: [
                    NumberField(
                      label: 'Backdated sick leave',
                      unit: 'days',
                      value: p.backdatedSickDays.toDouble(),
                      errorText: errors['backdated'],
                      helperText: 'Must be 30 days or less.',
                      onChanged: (v) => edit(
                        (x) => x.copyWith(backdatedSickDays: v?.round() ?? -1),
                      ),
                    ),
                    NumberField(
                      label: 'Longest single request',
                      unit: 'working days',
                      value: p.longestRequestDays.toDouble(),
                      errorText: errors['longest'],
                      onChanged: (v) => edit(
                        (x) => x.copyWith(longestRequestDays: v?.round() ?? -1),
                      ),
                    ),
                    NumberField(
                      label: 'Optional holidays a year',
                      value: p.optionalHolidaysPerYear.toDouble(),
                      errorText: errors['optional'],
                      onChanged: (v) => edit(
                        (x) => x.copyWith(
                          optionalHolidaysPerYear: v?.round() ?? -1,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Notice for planned leave is set per leave type${() {
                    final n = [for (final t in book.data.types)
                      if (t.noticeDays > 0) '${t.name}: ${t.noticeDays} days'];
                    return n.isEmpty ? '.' : ' (${n.join(', ')}).';
                  }()}',
                  style: AppTypography.helper,
                ),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Blackout periods',
                        style: AppTypography.cardTitle,
                      ),
                    ),
                    AppButton(
                      label: 'Add period',
                      icon: Icons.add,
                      size: AppButtonSize.small,
                      variant: AppButtonVariant.secondary,
                      onPressed: () => editBlackout(null),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                if (p.blackouts.isEmpty)
                  const Text(
                    'No blackout periods.',
                    style: AppTypography.small,
                  ),
                for (var i = 0; i < p.blackouts.length; i++)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: AppColors.divider),
                      ),
                    ),
                    child: Wrap(
                      spacing: AppSpacing.lg,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SizedBox(
                          width: 130,
                          child: Text(
                            leaveRange(p.blackouts[i].from, p.blackouts[i].to),
                            style: AppTypography.code,
                          ),
                        ),
                        SizedBox(
                          width: 200,
                          child: Text(
                            p.blackouts[i].name,
                            style: AppTypography.bodyStrong,
                          ),
                        ),
                        SizedBox(
                          width: 220,
                          child: Text(
                            [
                              p.blackouts[i].departments.isEmpty
                                  ? 'All departments'
                                  : p.blackouts[i].departments.join(', '),
                              if (p.blackouts[i].branchIds.isNotEmpty)
                                p.blackouts[i].branchIds
                                    .map(branchName)
                                    .join(', '),
                            ].join(' · '),
                            style: AppTypography.small,
                          ),
                        ),
                        SizedBox(
                          width: 200,
                          child: Text(
                            p.blackouts[i].blockedTypes.isEmpty
                                ? 'All leave blocked'
                                : '${p.blackouts[i].blockedTypes.map(typeName).join(', ')} blocked',
                            style: AppTypography.small,
                          ),
                        ),
                        TextButton(
                          onPressed: () => editBlackout(i),
                          child: const Text('Edit'),
                        ),
                        TextButton(
                          onPressed: () => edit(
                            (x) => x.copyWith(
                              blackouts: [...x.blackouts]..removeAt(i),
                            ),
                          ),
                          child: const Text('Remove'),
                        ),
                      ],
                    ),
                  ),
                if (errors['blackouts'] != null)
                  Text(
                    errors['blackouts']!,
                    style: AppTypography.small.copyWith(
                      color: AppColors.danger,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            header: const CardHeader(title: 'Balance treatment'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SwitchRow(
                  label: 'Reserve balance for pending requests',
                  description:
                      'Pending days are held so people can’t over-book.',
                  value: true,
                  onChanged: null,
                  lockedNote: ' · always on',
                ),
                SwitchRow(
                  label: 'Allow negative balance',
                  description:
                      'Lets employees go up to ${formatDays(p.negativeLimit)} days below zero, recovered from the next accrual.',
                  value: p.allowNegative,
                  onChanged: (v) => edit((x) => x.copyWith(allowNegative: v)),
                ),
                if (p.allowNegative)
                  SizedBox(
                    width: 220,
                    child: NumberField(
                      label: 'Down to',
                      unit: 'days below zero',
                      value: p.negativeLimit,
                      errorText: errors['negative'],
                      onChanged: (v) =>
                          edit((x) => x.copyWith(negativeLimit: v ?? -1)),
                    ),
                  ),
                SwitchRow(
                  label: 'Cancel approved leave that hasn’t started',
                  description:
                      'Employees can cancel; the approver is notified and days return.',
                  value: p.cancelApprovedNotStarted,
                  onChanged: (v) =>
                      edit((x) => x.copyWith(cancelApprovedNotStarted: v)),
                ),
                const SwitchRow(
                  label: 'Require approval again when dates change',
                  description:
                      'Editing a request sends it back to the first step.',
                  value: true,
                  onChanged: null,
                  lockedNote: ' · always on',
                ),
              ],
            ),
          ),
        ],
      );
    },
  );
}

class _RouteForm extends StatefulWidget {
  const _RouteForm({
    required this.route,
    required this.branches,
    required this.types,
  });

  final ApprovalRoute? route;
  final List<Branch> branches;
  final List<LeaveType> types;

  @override
  State<_RouteForm> createState() => _RouteFormState();
}

class _RouteFormState extends State<_RouteForm> {
  late String? _branch = widget.route?.branchId;
  late String? _type = widget.route?.typeKey;
  late SecondStep _second = widget.route?.second ?? SecondStep.hrIfDays;
  late double? _min = widget.route?.minDays ?? 3;

  bool get _isDefault =>
      widget.route != null &&
      widget.route!.branchId == null &&
      widget.route!.typeKey == null;

  @override
  Widget build(BuildContext context) {
    final needsDays =
        _second == SecondStep.hrIfDays ||
        _second == SecondStep.branchManagerIfDays;
    final ok = !needsDays || (_min != null && _min! >= 1 && _min! <= 90);
    return SidePanelFrame(
      title: widget.route == null ? 'Add route' : 'Edit route',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppDropdownField<String?>(
            label: 'Branch',
            value: _branch,
            options: [
              const AppDropdownOption(null, 'All branches'),
              for (final b in widget.branches)
                if (b.isActive) AppDropdownOption(b.id, b.name),
            ],
            onChanged: _isDefault ? null : (v) => setState(() => _branch = v),
          ),
          const SizedBox(height: AppSpacing.md),
          AppDropdownField<String?>(
            label: 'Leave type',
            value: _type,
            options: [
              const AppDropdownOption(null, 'All types'),
              for (final t in widget.types) AppDropdownOption(t.key, t.name),
            ],
            onChanged: _isDefault ? null : (v) => setState(() => _type = v),
          ),
          const SizedBox(height: AppSpacing.md),
          const InfoRow('Step 1', 'Reporting manager'),
          const SizedBox(height: AppSpacing.sm),
          AppDropdownField<SecondStep>(
            label: 'Step 2',
            value: _second,
            options: [
              for (final s in SecondStep.values) AppDropdownOption(s, s.label),
            ],
            onChanged: (v) => setState(() => _second = v ?? _second),
          ),
          if (needsDays) ...[
            const SizedBox(height: AppSpacing.md),
            NumberField(
              label: 'N',
              unit: 'days or more',
              value: _min ?? 0,
              errorText: ok ? null : 'Enter 1 to 90.',
              onChanged: (v) => setState(() => _min = v),
            ),
          ],
        ],
      ),
      footer: Wrap(
        alignment: WrapAlignment.end,
        spacing: AppSpacing.sm,
        children: [
          AppButton(
            label: 'Cancel',
            variant: AppButtonVariant.secondary,
            onPressed: () => Navigator.of(context).pop(),
          ),
          AppButton(
            label: 'Use route',
            onPressed: ok
                ? () => Navigator.of(context).pop(
                    ApprovalRoute(
                      id:
                          widget.route?.id ??
                          'route-${DateTime.now().microsecondsSinceEpoch}',
                      branchId: _branch,
                      typeKey: _type,
                      second: _second,
                      minDays: needsDays ? _min! : 0,
                    ),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}

class _BlackoutForm extends StatefulWidget {
  const _BlackoutForm({
    required this.blackout,
    required this.branches,
    required this.types,
    required this.today,
  });

  final Blackout? blackout;
  final List<Branch> branches;
  final List<LeaveType> types;
  final DateTime today;

  @override
  State<_BlackoutForm> createState() => _BlackoutFormState();
}

class _BlackoutFormState extends State<_BlackoutForm> {
  late final _name = TextEditingController(text: widget.blackout?.name ?? '');
  late DateTime? _from = widget.blackout?.from;
  late DateTime? _to = widget.blackout?.to;
  late List<String> _departments = widget.blackout?.departments ?? const [];
  late List<String> _branches = widget.blackout?.branchIds ?? const [];
  late List<String> _types = widget.blackout?.blockedTypes ?? const [];
  bool _tried = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nameError = _name.text.trim().isEmpty ? 'Name the period.' : null;
    final dateError = _from == null || _to == null
        ? 'Choose both dates.'
        : (_to!.isBefore(_from!) ? 'The end can’t be before the start.' : null);
    return SidePanelFrame(
      title: widget.blackout == null ? 'Add blackout period' : 'Edit period',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextField(
            label: 'Name',
            isRequired: true,
            controller: _name,
            errorText: _tried ? nameError : null,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.md),
          AppDateField(
            label: 'From',
            isRequired: true,
            value: _from,
            firstDate: widget.today,
            lastDate: DateTime(widget.today.year + 2, 12, 31),
            errorText: _tried ? dateError : null,
            onChanged: (d) => setState(() {
              _from = d;
              if (d != null && (_to == null || _to!.isBefore(d))) _to = d;
            }),
          ),
          const SizedBox(height: AppSpacing.md),
          AppDateField(
            label: 'To',
            isRequired: true,
            value: _to,
            firstDate: widget.today,
            lastDate: DateTime(widget.today.year + 2, 12, 31),
            onChanged: (d) => setState(() => _to = d),
          ),
          const SizedBox(height: AppSpacing.md),
          AllOrSome<String>(
            label: 'Departments',
            allLabel: 'All departments',
            options: [for (final d in departments) (d, d)],
            selected: _departments,
            onChanged: (v) => setState(() => _departments = v),
          ),
          const SizedBox(height: AppSpacing.md),
          AllOrSome<String>(
            label: 'Branches',
            allLabel: 'All branches',
            options: [
              for (final b in widget.branches)
                if (b.isActive) (b.id, b.name),
            ],
            selected: _branches,
            onChanged: (v) => setState(() => _branches = v),
          ),
          const SizedBox(height: AppSpacing.md),
          AllOrSome<String>(
            label: 'Blocked leave types',
            allLabel: 'All leave',
            options: [for (final t in widget.types) (t.key, t.name)],
            selected: _types,
            onChanged: (v) => setState(() => _types = v),
          ),
        ],
      ),
      footer: Wrap(
        alignment: WrapAlignment.end,
        spacing: AppSpacing.sm,
        children: [
          AppButton(
            label: 'Cancel',
            variant: AppButtonVariant.secondary,
            onPressed: () => Navigator.of(context).pop(),
          ),
          AppButton(
            label: 'Use period',
            onPressed: () {
              setState(() => _tried = true);
              if (nameError != null || dateError != null) return;
              Navigator.of(context).pop(
                Blackout(
                  name: _name.text.trim(),
                  from: _from!,
                  to: _to!,
                  departments: _departments,
                  branchIds: _branches,
                  blockedTypes: _types,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
