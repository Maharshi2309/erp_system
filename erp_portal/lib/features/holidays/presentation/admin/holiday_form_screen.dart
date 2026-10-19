import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/router/route_names.dart';
import '../../../../core/errors/failure.dart';
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
import '../../../../core/widgets/state_views.dart';
import '../../../employees/presentation/providers/employee_providers.dart';
import '../../../leave/domain/leave.dart';
import '../../../leave/domain/leave_book.dart';
import '../../../leave/presentation/leave_providers.dart';
import '../../../organization/domain/branch.dart';
import '../../../organization/presentation/providers/organization_providers.dart';
import '../../domain/company_holiday.dart';
import '../../domain/holiday_import.dart';
import '../calendar_providers.dart';
import '../holiday_widgets.dart';

/// What saving a holiday changes (board S64 "What this changes").
typedef HolidayImpact = ({
  int people,
  List<String> branches,
  int working,
  int leaveRequests,
  double leaveDaysReturned,
});

HolidayImpact holidayImpact(
  CompanyHoliday h,
  LeaveBook book,
  List<Branch> branches,
) {
  final reached = [
    for (final b in branches)
      if (b.isActive && h.appliesTo(b.id)) b,
  ];
  final people = [
    for (final e in book.employees)
      if (e.status.isEmployed && h.appliesTo(e.branchId)) e,
  ];
  final days = h.days;
  var working = 0;
  for (final e in people) {
    if (days.any((d) => !book.isWeeklyOff(e, d))) working++;
  }
  var requests = 0;
  var returned = 0.0;
  if (!h.optional) {
    for (final r in book.data.requests) {
      if (r.status != LeaveStatus.approved) continue;
      final e = book.person(r.employeeId);
      final type = book.data.type(r.typeKey);
      if (e == null || type == null || !h.appliesTo(e.branchId)) continue;
      if (type.countHolidays) continue;
      final overlap = book
          .countDays(e, type, r.from, r.to, r.half)
          .where((d) => d.counted > 0 && h.covers(d.date))
          .fold(0.0, (s, d) => s + d.counted);
      if (overlap > 0) {
        requests++;
        returned += overlap;
      }
    }
  }
  return (
    people: people.length,
    branches: [for (final b in reached) b.name],
    working: working,
    leaveRequests: requests,
    leaveDaysReturned: returned,
  );
}

/// Board S64 — add, edit or (past) view a holiday.
class HolidayFormScreen extends ConsumerStatefulWidget {
  const HolidayFormScreen({super.key, this.holidayId});

  final String? holidayId;

  @override
  ConsumerState<HolidayFormScreen> createState() => _HolidayFormScreenState();
}

class _HolidayFormScreenState extends ConsumerState<HolidayFormScreen> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  bool _range = false;
  DateTime? _date;
  DateTime? _end;
  HolidayCategory _category = HolidayCategory.festival;
  bool _whole = true;
  List<String> _branches = const [];
  bool _optional = false;
  bool _loaded = false;
  bool _tried = false;
  bool _busy = false;
  Map<String, String> _errors = const {};

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  void _load(CompanyHoliday h) {
    _loaded = true;
    _name.text = h.name;
    _description.text = h.description;
    _range = h.isRange;
    _date = h.date;
    _end = h.endDate;
    _category = h.category;
    _whole = h.orgWide;
    _branches = h.branchIds;
    _optional = h.optional;
  }

  CompanyHoliday _draft(String id) => CompanyHoliday(
    id: id,
    name: _name.text.trim(),
    date: _date ?? DateTime(2000),
    endDate: _range ? (_end ?? _date) : _date,
    category: _category,
    branchIds: _whole ? const [] : _branches,
    optional: _optional,
    description: _description.text.trim(),
  );

  Map<String, String> _check() => {
    if (_name.text.trim().length < 2) 'name': 'Enter the holiday name.',
    if (_date == null) 'date': 'Choose a date.',
    if (_range && _end != null && _date != null && _end!.isBefore(_date!))
      'date': 'The last day can’t be before the first.',
    if (!_whole && _branches.isEmpty) 'branches': 'Choose at least one branch.',
  };

  void _close() => context.go(AppRoutes.holidayList);

  Future<void> _save(String id) async {
    setState(() {
      _tried = true;
      _errors = _check();
    });
    if (_errors.isNotEmpty) return;
    setState(() => _busy = true);
    try {
      final saved = await ref
          .read(companyHolidaysProvider.notifier)
          .save(_draft(id));
      if (!mounted) return;
      showAppToast(context, '${saved.name} saved');
      _close();
    } on Failure catch (f) {
      if (mounted) {
        setState(
          () => _errors = f is ValidationFailure && f.fieldErrors.isNotEmpty
              ? f.fieldErrors
              : {'form': f.message},
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(CompanyHoliday h) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Delete ${h.name}?',
      message:
          'The day becomes a normal working day again. Approved leave on it counts again.',
      confirmLabel: 'Delete holiday',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(companyHolidaysProvider.notifier).delete(h.id);
      if (!mounted) return;
      showAppToast(context, '${h.name} deleted');
      _close();
    } on Failure catch (f) {
      if (mounted) setState(() => _errors = {'form': f.message});
    }
  }

  @override
  Widget build(BuildContext context) {
    final holidays = ref.watch(companyHolidaysProvider);
    final branches = ref.watch(branchesProvider).value;
    final book = ref.watch(leaveBookProvider).value;
    ref.watch(employeesProvider);
    if (!holidays.hasValue || branches == null || book == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final existing = widget.holidayId == null
        ? null
        : holidays.value!.where((h) => h.id == widget.holidayId).firstOrNull;
    if (widget.holidayId != null && existing == null) {
      return Scaffold(
        body: ErrorState(
          headline: '404',
          title: 'Holiday not found',
          message: 'It may have been deleted.',
          onRetry: _close,
        ),
      );
    }
    if (existing != null && !_loaded) _load(existing);
    final today = book.today;
    final past = existing != null && existing.date.isBefore(today);
    final active = [
      for (final b in branches)
        if (b.isActive) b,
    ];
    final draft = _date == null ? null : _draft(existing?.id ?? '');
    final clashes = draft == null
        ? const <CompanyHoliday>[]
        : overlapping(holidays.value!, draft);
    final impact = draft == null ? null : holidayImpact(draft, book, branches);
    final errors = _tried ? _check() : const <String, String>{};
    final shown = {..._errors, ...errors};

    final actions = <Widget>[
      AppButton(
        label: past ? 'Back' : 'Cancel',
        variant: AppButtonVariant.secondary,
        onPressed: _close,
      ),
      if (!past)
        AppButton(
          label: 'Save holiday',
          busy: _busy,
          busyLabel: 'Saving…',
          onPressed: () => _save(existing?.id ?? ''),
        ),
    ];

    final form = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (past)
          Container(
            margin: const EdgeInsets.only(bottom: AppSpacing.lg),
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.neutralSoft,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: const Text(
              'This holiday has passed. It can’t be edited because attendance already used it.',
              style: AppTypography.small,
            ),
          ),
        if (shown['form'] != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Text(
              shown['form']!,
              style: AppTypography.small.copyWith(color: AppColors.danger),
            ),
          ),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppTextField(
                label: 'Holiday name',
                isRequired: true,
                controller: _name,
                readOnly: past,
                maxLength: 60,
                errorText: shown['name'],
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: AppSpacing.md),
              const Text('Length', style: AppTypography.label),
              const SizedBox(height: 6),
              ChoiceChips<bool>(
                options: const [(false, 'Single day'), (true, 'Date range')],
                selected: _range,
                onSelected: past ? (_) {} : (v) => setState(() => _range = v),
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                children: [
                  SizedBox(
                    width: 260,
                    child: AppDateField(
                      label: _range ? 'First day' : 'Date',
                      isRequired: true,
                      value: _date,
                      firstDate: past ? DateTime(2000) : today,
                      lastDate: DateTime(today.year + 2, 12, 31),
                      errorText: shown['date'],
                      onChanged: past
                          ? null
                          : (d) => setState(() {
                              _date = d;
                              if (d != null &&
                                  (_end == null || _end!.isBefore(d))) {
                                _end = d;
                              }
                            }),
                    ),
                  ),
                  if (_range)
                    SizedBox(
                      width: 260,
                      child: AppDateField(
                        label: 'Last day',
                        isRequired: true,
                        value: _end,
                        firstDate: past ? DateTime(2000) : (_date ?? today),
                        lastDate: DateTime(today.year + 2, 12, 31),
                        onChanged: past
                            ? null
                            : (d) => setState(() => _end = d),
                      ),
                    ),
                ],
              ),
              for (final c in clashes)
                Container(
                  margin: const EdgeInsets.only(top: AppSpacing.sm),
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.warningSoft,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Text(
                    '${DateFormat('EEE d MMM').format(c.date.isBefore(draft!.date) ? draft.date : c.date)} is already “${c.name}” for ${c.orgWide ? 'all branches' : c.branchIds.map((id) => branches.where((b) => b.id == id).firstOrNull?.name ?? id).join(', ')}. Save anyway only if this replaces it.',
                    style: AppTypography.small.copyWith(
                      color: AppColors.warningText,
                    ),
                  ),
                ),
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                width: 260,
                child: AppDropdownField<HolidayCategory>(
                  label: 'Category',
                  value: _category,
                  options: [
                    for (final c in HolidayCategory.values)
                      AppDropdownOption(c, categoryLabel(c)),
                  ],
                  onChanged: past
                      ? null
                      : (v) => setState(() => _category = v ?? _category),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                label: 'Description',
                isOptional: true,
                controller: _description,
                readOnly: past,
                maxLines: 2,
                maxLength: 200,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        AppCard(
          header: const CardHeader(title: 'Who gets this holiday'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OptionCard(
                title: 'Whole organization',
                description: 'All current and future branches',
                selected: _whole,
                onTap: () {
                  if (!past) setState(() => _whole = true);
                },
              ),
              const SizedBox(height: AppSpacing.sm),
              OptionCard(
                title: 'Selected branches',
                description: 'New branches won’t get it automatically',
                selected: !_whole,
                onTap: () {
                  if (!past) setState(() => _whole = false);
                },
              ),
              if (!_whole) ...[
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final b in active)
                      FilterChip(
                        label: Text(b.name),
                        selected: _branches.contains(b.id),
                        onSelected: past
                            ? null
                            : (on) => setState(
                                () => _branches = on
                                    ? [..._branches, b.id]
                                    : [
                                        for (final x in _branches)
                                          if (x != b.id) x,
                                      ],
                              ),
                      ),
                  ],
                ),
                if (shown['branches'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      shown['branches']!,
                      style: AppTypography.helper.copyWith(
                        color: AppColors.danger,
                      ),
                    ),
                  ),
              ],
              const SizedBox(height: AppSpacing.md),
              SwitchRow(
                label: 'Optional holiday',
                description:
                    'Employees choose to take it, up to the yearly limit in Leave policy.',
                value: _optional,
                onChanged: past ? null : (v) => setState(() => _optional = v),
              ),
            ],
          ),
        ),
        if (existing != null && !past) ...[
          const SizedBox(height: AppSpacing.lg),
          Align(
            alignment: Alignment.centerLeft,
            child: AppButton(
              label: 'Delete holiday',
              variant: AppButtonVariant.ghost,
              onPressed: () => _delete(existing),
            ),
          ),
        ],
      ],
    );

    final impactCard = AppCard(
      header: const CardHeader(title: 'What this changes'),
      child: impact == null
          ? const Text(
              'Choose a date to see who is affected.',
              style: AppTypography.small,
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final line in [
                  if (_optional)
                    'Optional: ${impact.people} employees in ${impact.branches.join(', ')} can choose to take it.'
                  else
                    '${impact.people} employees in ${impact.branches.isEmpty ? 'no branch' : impact.branches.join(', ')} get the day off.',
                  if (!_optional)
                    impact.leaveRequests == 0
                        ? 'No approved leave on ${draft!.isRange ? 'these dates' : 'this date'}.'
                        : 'Leave already approved on ${draft!.isRange ? 'these dates' : 'this date'}: ${impact.leaveRequests} ${impact.leaveRequests == 1 ? 'request' : 'requests'} — ${formatDays(impact.leaveDaysReturned)} ${impact.leaveDaysReturned == 1 ? 'day is' : 'days are'} returned.',
                  if (!_optional)
                    impact.working == 0
                        ? 'No one was scheduled to work that day.'
                        : '${impact.working} of them were scheduled to work.',
                  'It shows on everyone’s holiday calendar once saved.',
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Text(line, style: AppTypography.small),
                  ),
              ],
            ),
    );

    final width = MediaQuery.sizeOf(context).width;
    final phone = width < 600;
    final wide = width >= 1100;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: Column(
          children: [
            Container(
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
                    tooltip: 'Back to holidays',
                    onPressed: _close,
                    icon: const Icon(Icons.arrow_back),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        existing == null
                            ? 'Add holiday'
                            : (past ? existing.name : 'Edit holiday'),
                        style: AppTypography.sectionTitle,
                      ),
                    ),
                  ),
                  if (!phone) Wrap(spacing: AppSpacing.sm, children: actions),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(phone ? AppSpacing.lg : AppSpacing.xl),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1120),
                    child: wide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: form),
                              const SizedBox(width: AppSpacing.xl),
                              SizedBox(width: 340, child: impactCard),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              form,
                              const SizedBox(height: AppSpacing.lg),
                              impactCard,
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
                  children: actions,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
