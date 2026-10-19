import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_overlays.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/selection_controls.dart';
import '../../../auth/presentation/widgets/auth_widgets.dart';
import '../../../organization/domain/branch.dart';
import '../../../organization/domain/setup_progress.dart';
import '../../../organization/presentation/providers/organization_providers.dart';
import '../../../organization/presentation/setup_text.dart';

/// What a closed step panel asks the checklist to do next.
sealed class StepPanelResult {
  const StepPanelResult();
}

/// Saved; show [message] as a toast.
final class StepSaved extends StepPanelResult {
  const StepSaved(this.message);

  final String message;
}

/// From the final review: open another step instead.
final class OpenStep extends StepPanelResult {
  const OpenStep(this.step);

  final SetupStep step;
}

/// Opens the side panel for one setup step of [branch] (board S21).
Future<StepPanelResult?> showSetupStepPanel(
  BuildContext context, {
  required Branch branch,
  required SetupStep step,
}) => showSidePanelRoute<StepPanelResult>(
  context,
  barrierLabel: 'Close ${step.title}',
  builder: (context) => SetupStepPanel(branch: branch, step: step),
);

/// One step's settings. Unsaved changes are kept as a draft when the panel
/// closes ("Close · keep draft") and offered again next time.
class SetupStepPanel extends ConsumerStatefulWidget {
  const SetupStepPanel({super.key, required this.branch, required this.step});

  final Branch branch;
  final SetupStep step;

  @override
  ConsumerState<SetupStepPanel> createState() => _SetupStepPanelState();
}

class _SetupStepPanelState extends ConsumerState<SetupStepPanel> {
  late AttendanceRules _attendance;
  late HolidaySetup _holidays;
  late LeaveSetup _leave;
  late RolesSetup _roles;
  late ReminderSettings _reminders;

  final _grace = TextEditingController();
  final _early = TextEditingController();
  final _halfDay = TextEditingController();
  final _managerEmail = TextEditingController();
  final _holidayName = TextEditingController();
  DateTime? _holidayDate;
  bool _holidayEveryYear = false;
  final _leaveDays = <String, TextEditingController>{};

  bool _dirty = false;
  bool _fromDraft = false;
  bool _busy = false;
  bool _saved = false;
  String? _notice;
  Map<String, String> _errors = {};

  Branch get branch => widget.branch;
  SetupStep get step => widget.step;

  @override
  void initState() {
    super.initState();
    final draft = ref
        .read(setupDraftsProvider.notifier)
        .draft<Branch>(branch.id, step);
    _fromDraft = draft != null;
    _dirty = _fromDraft;
    _load(draft ?? branch);
  }

  void _load(Branch source) {
    _attendance = source.attendance ?? const AttendanceRules();
    _holidays = source.holidays ?? HolidaySetup.from(HolidaySource.gujarat);
    _leave = source.leave ?? LeaveSetup.defaults;
    _roles = source.roles ?? const RolesSetup();
    _reminders = source.reminders ?? const ReminderSettings();
    _grace.text = '${_attendance.graceMinutes}';
    _early.text = '${_attendance.earlyLeaveMinutes}';
    _halfDay.text = '${_attendance.halfDayLateMinutes}';
    _managerEmail.text = _roles.managerEmail;
    for (final t in _leave.types) {
      (_leaveDays[t.key] ??= TextEditingController()).text = t.tracksBalance
          ? '${t.daysPerYear}'
          : '';
    }
  }

  @override
  void dispose() {
    for (final c in [
      _grace,
      _early,
      _halfDay,
      _managerEmail,
      _holidayName,
      ..._leaveDays.values,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _change(VoidCallback update) => setState(() {
    update();
    _dirty = true;
    _errors = {};
    _notice = null;
  });

  /// The branch as it would be saved from the panel's current values.
  Branch _draftBranch() {
    int n(TextEditingController c) => int.tryParse(c.text) ?? -1;
    return switch (step) {
      SetupStep.attendance => branch.copyWith(
        attendance: AttendanceRules(
          method: _attendance.method,
          shiftMode: _attendance.shiftMode,
          graceMinutes: n(_grace),
          earlyLeaveMinutes: n(_early),
          halfDayLateMinutes: n(_halfDay),
        ),
      ),
      SetupStep.holidays => branch.copyWith(holidays: _holidays),
      SetupStep.leave => branch.copyWith(
        leave: LeaveSetup(
          approval: _leave.approval,
          types: [
            for (final t in _leave.types)
              t.tracksBalance
                  ? t.copyWith(
                      daysPerYear: int.tryParse(_leaveDays[t.key]!.text) ?? 0,
                    )
                  : t,
          ],
        ),
      ),
      SetupStep.roles => branch.copyWith(
        roles: RolesSetup(
          manager: _roles.manager,
          managerEmail: _managerEmail.text.trim(),
          managerCanApproveLeave: _roles.managerCanApproveLeave,
          managerCanCorrectAttendance: _roles.managerCanCorrectAttendance,
          managerCanSeeReports: _roles.managerCanSeeReports,
          managerCanEditPeople: _roles.managerCanEditPeople,
          employeesCanRequestLeave: _roles.employeesCanRequestLeave,
          employeesCanSeeTeamOff: _roles.employeesCanSeeTeamOff,
        ),
      ),
      SetupStep.reminders => branch.copyWith(reminders: _reminders),
      SetupStep.review => branch.copyWith(reviewed: true),
      SetupStep.basics => branch,
    };
  }

  Map<String, String> _validate() {
    final errors = <String, String>{};
    if (step == SetupStep.attendance) {
      for (final (key, controller, max) in [
        ('grace', _grace, AttendanceRules.maxGrace),
        ('early', _early, AttendanceRules.maxEarlyLeave),
        ('half', _halfDay, AttendanceRules.maxHalfDayLate),
      ]) {
        final v = int.tryParse(controller.text);
        if (v == null || v < 0 || v > max) {
          errors[key] = 'Enter 0 to $max minutes.';
        }
      }
      if (errors.isNotEmpty) errors['panel'] = 'Check the highlighted values.';
    }
    if (step == SetupStep.roles &&
        _roles.manager == BranchManagerChoice.invite &&
        !_draftBranch().roles!.isComplete) {
      errors['email'] =
          'Enter a valid work email, or choose “I’ll manage it for now”.';
      errors['panel'] = 'Add the manager’s email to send the invitation.';
    }
    return errors;
  }

  Future<void> _save() async {
    if (_busy) return;
    final errors = _validate();
    setState(() => _errors = errors);
    if (errors.isNotEmpty) return;

    final before = SetupProgress(branch).percent;
    setState(() => _busy = true);
    try {
      final saved = await ref
          .read(branchesProvider.notifier)
          .save(_draftBranch());
      ref.read(setupDraftsProvider.notifier).discard(branch.id, step);
      final progress = SetupProgress(saved);
      final next = progress.attention.firstOrNull ?? progress.next;
      if (next != null) {
        await ref.read(setupBookmarkProvider.notifier).remember(saved.id, next);
      }
      final after = progress.percent;
      final message = step == SetupStep.review
          ? '${saved.name} is ready · Branch Setup Completed'
          : after == 100
          ? '${step.title} saved · ${saved.name} is 100% set up'
          : after < before
          ? '${step.title} saved · progress is now $after% — this step needs attention'
          : '${step.title} saved · ${saved.name} is $after% set up';
      _saved = true;
      if (mounted) Navigator.of(context).pop(StepSaved(message));
    } on Failure catch (failure) {
      if (mounted) setState(() => _errors = {'panel': failure.message});
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _discardDraft() {
    ref.read(setupDraftsProvider.notifier).discard(branch.id, step);
    setState(() {
      _load(branch);
      _dirty = false;
      _fromDraft = false;
      _errors = {};
    });
  }

  void _copyFrom(Branch source) {
    final copy = switch (step) {
      // A manager invitation is specific to its branch.
      SetupStep.roles => branch.copyWith(
        roles: RolesSetup(
          managerCanApproveLeave: source.roles!.managerCanApproveLeave,
          managerCanCorrectAttendance:
              source.roles!.managerCanCorrectAttendance,
          managerCanSeeReports: source.roles!.managerCanSeeReports,
          managerCanEditPeople: source.roles!.managerCanEditPeople,
          employeesCanRequestLeave: source.roles!.employeesCanRequestLeave,
          employeesCanSeeTeamOff: source.roles!.employeesCanSeeTeamOff,
        ),
      ),
      _ => branch.copyWith(
        attendance: source.attendance,
        holidays: source.holidays,
        leave: source.leave,
      ),
    };
    setState(() {
      _load(copy);
      _dirty = true;
      _errors = {};
      _notice = 'Copied from ${source.name} — review, then save.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final others = (ref.watch(branchesProvider).value ?? const <Branch>[])
        .where(
          (b) =>
              b.id != branch.id &&
              step != SetupStep.review &&
              step != SetupStep.reminders &&
              SetupProgress(b).isComplete(step),
        )
        .take(2)
        .toList();
    final reviewBlocked =
        step == SetupStep.review && !SetupProgress(branch).canReview;

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && _dirty && !_saved && step != SetupStep.review) {
          ref
              .read(setupDraftsProvider.notifier)
              .keep(branch.id, step, _draftBranch());
        }
      },
      child: SidePanelFrame(
        title: step.title,
        subtitle:
            '${branch.name} · ${step.isOptional ? 'optional' : 'worth ${step.weight}% of setup'}',
        footer: Wrap(
          alignment: WrapAlignment.end,
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            AppButton(
              label: _dirty && step != SetupStep.review
                  ? 'Close · keep draft'
                  : 'Close',
              variant: AppButtonVariant.secondary,
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            AppButton(
              label: step == SetupStep.review ? 'Mark branch ready' : 'Save',
              busyLabel: 'Saving…',
              busy: _busy,
              onPressed: reviewBlocked ? null : _save,
            ),
          ],
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_fromDraft) ...[
              _DraftNotice(onDiscard: _discardDraft),
              const SizedBox(height: AppSpacing.md),
            ],
            if (others.isNotEmpty) ...[
              _CopyFrom(branches: others, onCopy: _copyFrom),
              const SizedBox(height: AppSpacing.md),
            ],
            if (_notice != null) ...[
              AuthNotice(message: _notice!, tone: NoticeTone.info),
              const SizedBox(height: AppSpacing.md),
            ],
            if (_errors['panel'] case final message?) ...[
              AuthNotice(message: message, tone: NoticeTone.error),
              const SizedBox(height: AppSpacing.md),
            ],
            switch (step) {
              SetupStep.attendance => _attendanceEditor(),
              SetupStep.holidays => _holidaysEditor(),
              SetupStep.leave => _leaveEditor(),
              SetupStep.roles => _rolesEditor(),
              SetupStep.reminders => _remindersEditor(),
              SetupStep.review => _reviewList(),
              SetupStep.basics => const SizedBox.shrink(),
            },
          ],
        ),
      ),
    );
  }

  // ---------- Attendance ----------

  Widget _attendanceEditor() {
    final methods = [
      (
        PunchMethod.app,
        'Mobile app',
        'Employees punch on their phone at the branch location.',
      ),
      (
        PunchMethod.kiosk,
        'Shared kiosk',
        'A tablet at the entrance; people punch with their employee ID and PIN.',
      ),
      (
        PunchMethod.both,
        'App and kiosk',
        'Either works — useful when some staff have no smartphone.',
      ),
    ];
    Widget minutes(
      String key,
      String label,
      TextEditingController c,
      String help,
    ) => Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AppTextField(
        label: '$label (minutes)',
        controller: c,
        monospace: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        maxLength: 3,
        errorText: _errors[key],
        helperText: help,
        onChanged: (_) => _change(() {}),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Heading('How people punch in'),
        for (final (method, title, description) in methods) ...[
          OptionCard(
            title: title,
            description: description,
            selected: _attendance.method == method,
            onTap: () => _change(
              () => _attendance = AttendanceRules(
                method: method,
                shiftMode: _attendance.shiftMode,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        const SizedBox(height: AppSpacing.md),
        minutes(
          'grace',
          'Late-arrival grace period',
          _grace,
          'Punches within this many minutes after opening count as on time.',
        ),
        minutes(
          'early',
          'Early-departure threshold',
          _early,
          'Leaving more than this before closing is marked as early.',
        ),
        minutes(
          'half',
          'Half day if late by more than',
          _halfDay,
          'Late beyond this counts as a half day.',
        ),
        const _Heading('Shifts'),
        OptionCard(
          title: 'Use this branch’s working hours',
          description:
              '${hoursSummary(branch.hours)} — one shift for everyone.',
          selected: _attendance.shiftMode == ShiftMode.branchHours,
          onTap: () => _change(
            () => _attendance = AttendanceRules(method: _attendance.method),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        OptionCard(
          title: 'Several shifts',
          description:
              'Day/night or rotating shifts. Define them in Work schedules once '
              'setup is done.',
          selected: _attendance.shiftMode == ShiftMode.several,
          onTap: () => _change(
            () => _attendance = AttendanceRules(
              method: _attendance.method,
              shiftMode: ShiftMode.several,
            ),
          ),
        ),
      ],
    );
  }

  // ---------- Holidays ----------

  Widget _holidaysEditor() {
    final sources = [
      (
        HolidaySource.gujarat,
        'Gujarat public holidays',
        '7 holidays from Dussehra to Republic Day',
      ),
      (
        HolidaySource.national,
        'National holidays only',
        'Republic Day, Independence Day, Gandhi Jayanti',
      ),
      (HolidaySource.none, 'Start empty', 'Add your own dates below'),
    ];
    final items = [..._holidays.items]
      ..sort((a, b) => a.date.compareTo(b.date));
    final format = DateFormat('EEE, d MMM y');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Heading('Start from'),
        for (final (source, title, description) in sources) ...[
          OptionCard(
            title: title,
            description: description,
            selected: _holidays.source == source,
            onTap: () => _change(
              () => _holidays = HolidaySetup(
                source: source,
                items: [
                  ...HolidayLists.of(source),
                  ..._holidays.items.where((h) => h.custom),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        const SizedBox(height: AppSpacing.md),
        _Heading('Holidays · ${_holidays.observedCount} observed'),
        if (items.isEmpty)
          const Text(
            'No holidays yet. Add your own below.',
            style: AppTypography.helper,
          )
        else
          for (final h in items)
            Row(
              children: [
                Checkbox(
                  value: h.observed,
                  semanticLabel: 'Observe ${h.name} at this branch',
                  onChanged: (v) => _change(
                    () => _holidays = HolidaySetup(
                      source: _holidays.source,
                      items: [
                        for (final i in _holidays.items)
                          identical(i, h)
                              ? i.copyWith(observed: v ?? false)
                              : i,
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(h.name, style: AppTypography.label),
                      Text(
                        [
                          format.format(h.date),
                          if (h.custom) 'custom',
                          if (h.everyYear) 'every year',
                          if (!h.observed) 'branch stays open',
                        ].join(' · '),
                        style: AppTypography.helper,
                      ),
                    ],
                  ),
                ),
                if (h.custom)
                  IconButton(
                    tooltip: 'Remove ${h.name}',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => _change(
                      () => _holidays = HolidaySetup(
                        source: _holidays.source,
                        items: _holidays.items
                            .where((i) => !identical(i, h))
                            .toList(),
                      ),
                    ),
                  ),
              ],
            ),
        const SizedBox(height: AppSpacing.md),
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surfaceMuted,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Add a custom holiday', style: AppTypography.label),
              const SizedBox(height: AppSpacing.sm),
              AppTextField(
                label: 'Name',
                controller: _holidayName,
                errorText: _errors['holiday'],
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  AppButton(
                    label: _holidayDate == null
                        ? 'Choose date'
                        : format.format(_holidayDate!),
                    icon: Icons.calendar_today_outlined,
                    size: AppButtonSize.small,
                    variant: AppButtonVariant.secondary,
                    onPressed: () async {
                      final now = DateTime.now();
                      final picked = await showDatePicker(
                        context: context,
                        firstDate: DateTime(now.year - 1),
                        lastDate: DateTime(now.year + 3),
                        initialDate: _holidayDate ?? now,
                      );
                      if (picked != null) setState(() => _holidayDate = picked);
                    },
                  ),
                  FilterChip(
                    label: const Text('Every year'),
                    selected: _holidayEveryYear,
                    onSelected: (v) => setState(() => _holidayEveryYear = v),
                  ),
                  AppButton(
                    label: 'Add holiday',
                    size: AppButtonSize.small,
                    onPressed: _addHoliday,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _addHoliday() {
    final name = _holidayName.text.trim();
    final date = _holidayDate;
    if (name.isEmpty || date == null) {
      setState(() => _errors = {'holiday': 'Add a name and a date.'});
      return;
    }
    final duplicate = _holidays.items.any(
      (h) =>
          h.name.toLowerCase() == name.toLowerCase() &&
          DateUtils.isSameDay(h.date, date),
    );
    if (duplicate) {
      setState(
        () => _errors = {'holiday': 'That holiday is already on the list.'},
      );
      return;
    }
    _change(() {
      _holidays = HolidaySetup(
        source: _holidays.source,
        items: [
          ..._holidays.items,
          HolidayItem(
            name: name,
            date: date,
            custom: true,
            everyYear: _holidayEveryYear,
          ),
        ],
      );
      _holidayName.clear();
      _holidayDate = null;
      _holidayEveryYear = false;
    });
  }

  // ---------- Leave ----------

  Widget _leaveEditor() {
    final flows = [
      (
        LeaveApproval.manager,
        'Reporting manager',
        'Fastest. Managers can’t approve their own requests — those go to you.',
      ),
      (
        LeaveApproval.managerThenHr,
        'Reporting manager, then HR',
        'Two steps, for teams that want HR to see every request.',
      ),
      (
        LeaveApproval.owner,
        'Only me (owner)',
        'Simple for small teams; you can change it later.',
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Heading('Leave types'),
        if (!_leave.types.any((t) => t.enabled))
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(
              'Switch on at least one leave type to complete this step.',
              style: AppTypography.helper.copyWith(color: AppColors.warning),
            ),
          ),
        for (var i = 0; i < _leave.types.length; i++)
          _LeaveTypeRow(
            type: _leave.types[i],
            days: _leaveDays[_leave.types[i].key]!,
            onToggle: (on) => _change(
              () => _leave = LeaveSetup(
                approval: _leave.approval,
                types: [
                  for (var j = 0; j < _leave.types.length; j++)
                    j == i
                        ? _leave.types[j].copyWith(enabled: on)
                        : _leave.types[j],
                ],
              ),
            ),
            onDaysChanged: () => _change(() {}),
          ),
        const SizedBox(height: AppSpacing.md),
        const _Heading('Who approves leave'),
        for (final (approval, title, description) in flows) ...[
          OptionCard(
            title: title,
            description: description,
            selected: _leave.approval == approval,
            onTap: () => _change(
              () =>
                  _leave = LeaveSetup(types: _leave.types, approval: approval),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }

  // ---------- Roles ----------

  Widget _rolesEditor() {
    RolesSetup with_({
      BranchManagerChoice? manager,
      bool? leave,
      bool? attendance,
      bool? reports,
      bool? people,
      bool? requestLeave,
      bool? teamOff,
    }) => RolesSetup(
      manager: manager ?? _roles.manager,
      managerEmail: _managerEmail.text,
      managerCanApproveLeave: leave ?? _roles.managerCanApproveLeave,
      managerCanCorrectAttendance:
          attendance ?? _roles.managerCanCorrectAttendance,
      managerCanSeeReports: reports ?? _roles.managerCanSeeReports,
      managerCanEditPeople: people ?? _roles.managerCanEditPeople,
      employeesCanRequestLeave: requestLeave ?? _roles.employeesCanRequestLeave,
      employeesCanSeeTeamOff: teamOff ?? _roles.employeesCanSeeTeamOff,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Heading('Who manages this branch'),
        OptionCard(
          title: 'I’ll manage it for now',
          description:
              'You approve and correct everything here until you invite someone.',
          selected: _roles.manager == BranchManagerChoice.owner,
          onTap: () =>
              _change(() => _roles = with_(manager: BranchManagerChoice.owner)),
        ),
        const SizedBox(height: AppSpacing.sm),
        OptionCard(
          title: 'Invite a branch manager',
          description: 'They get an email and manage only this branch.',
          selected: _roles.manager == BranchManagerChoice.invite,
          onTap: () => _change(
            () => _roles = with_(manager: BranchManagerChoice.invite),
          ),
        ),
        if (_roles.manager == BranchManagerChoice.invite) ...[
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            label: 'Manager’s work email',
            controller: _managerEmail,
            keyboardType: TextInputType.emailAddress,
            errorText: _errors['email'],
            helperText: 'The invitation is sent when you save.',
            onChanged: (_) => _change(() {}),
          ),
          const SizedBox(height: AppSpacing.md),
          const _Heading('The branch manager can'),
          SwitchRow(
            label: 'Approve leave for this branch',
            value: _roles.managerCanApproveLeave,
            onChanged: (v) => _change(() => _roles = with_(leave: v)),
          ),
          SwitchRow(
            label: 'Correct attendance and missing punches',
            value: _roles.managerCanCorrectAttendance,
            onChanged: (v) => _change(() => _roles = with_(attendance: v)),
          ),
          SwitchRow(
            label: 'See and export branch reports',
            value: _roles.managerCanSeeReports,
            onChanged: (v) => _change(() => _roles = with_(reports: v)),
          ),
          SwitchRow(
            label: 'Add and edit employees',
            value: _roles.managerCanEditPeople,
            onChanged: (v) => _change(() => _roles = with_(people: v)),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        const _Heading('Employees can'),
        const SwitchRow(
          label: 'Punch in and out',
          lockedNote: ' · always on',
          value: true,
          onChanged: null,
        ),
        SwitchRow(
          label: 'Request leave and see balances',
          value: _roles.employeesCanRequestLeave,
          onChanged: (v) => _change(() => _roles = with_(requestLeave: v)),
        ),
        SwitchRow(
          label: 'See who’s off on their team',
          value: _roles.employeesCanSeeTeamOff,
          onChanged: (v) => _change(() => _roles = with_(teamOff: v)),
        ),
      ],
    );
  }

  // ---------- Reminders ----------

  Widget _remindersEditor() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'Optional. These never block setup.',
        style: AppTypography.helper,
      ),
      const SizedBox(height: AppSpacing.sm),
      SwitchRow(
        label: 'Punch-in reminder',
        description:
            'Remind employees 15 minutes after opening if they haven’t punched in.',
        value: _reminders.punchInReminder,
        onChanged: (v) => _change(
          () => _reminders = ReminderSettings(
            punchInReminder: v,
            missingPunchSummary: _reminders.missingPunchSummary,
            weeklyLeaveDigest: _reminders.weeklyLeaveDigest,
          ),
        ),
      ),
      SwitchRow(
        label: 'Daily missing-punch summary',
        description: 'Sent to the branch manager at 10:00 each morning.',
        value: _reminders.missingPunchSummary,
        onChanged: (v) => _change(
          () => _reminders = ReminderSettings(
            punchInReminder: _reminders.punchInReminder,
            missingPunchSummary: v,
            weeklyLeaveDigest: _reminders.weeklyLeaveDigest,
          ),
        ),
      ),
      SwitchRow(
        label: 'Weekly leave digest',
        description: 'Monday email to you listing who’s off this week.',
        value: _reminders.weeklyLeaveDigest,
        onChanged: (v) => _change(
          () => _reminders = ReminderSettings(
            punchInReminder: _reminders.punchInReminder,
            missingPunchSummary: _reminders.missingPunchSummary,
            weeklyLeaveDigest: v,
          ),
        ),
      ),
    ],
  );

  // ---------- Final review ----------

  Widget _reviewList() {
    final progress = SetupProgress(branch);
    final missing = SetupStep.required
        .where((s) => !progress.isComplete(s))
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          missing > 0
              ? 'Finish $missing ${missing == 1 ? 'step' : 'steps'} before marking '
                    '${branch.name} ready.'
              : 'Everything required is set. Mark ${branch.name} ready so '
                    'attendance starts counting from its next working day.',
          style: AppTypography.small,
        ),
        const SizedBox(height: AppSpacing.md),
        for (final s in [...SetupStep.required, SetupStep.reminders]) ...[
          _ReviewRow(
            step: s,
            ok: progress.isComplete(s),
            note: stepNote(branch, s),
            onFix: () => Navigator.of(context).pop(OpenStep(s)),
          ),
          const Divider(height: 1),
        ],
      ],
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Semantics(
      header: true,
      child: Text(text, style: AppTypography.label),
    ),
  );
}

class _DraftNotice extends StatelessWidget {
  const _DraftNotice({required this.onDiscard});

  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.warningSoft,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'You have unsaved changes from earlier.',
              style: AppTypography.small.copyWith(color: AppColors.warningText),
            ),
          ),
          AppButton(
            label: 'Discard',
            size: AppButtonSize.small,
            variant: AppButtonVariant.ghost,
            onPressed: onDiscard,
          ),
        ],
      ),
    );
  }
}

class _CopyFrom extends StatelessWidget {
  const _CopyFrom({required this.branches, required this.onCopy});

  final List<Branch> branches;
  final ValueChanged<Branch> onCopy;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.primarySelected,
        border: Border.all(color: const Color(0xFFC9D2F6)),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Same as another branch? Start from its settings, then adjust.',
            style: AppTypography.helper,
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final b in branches)
                AppButton(
                  label: 'Copy from ${b.name}',
                  size: AppButtonSize.small,
                  variant: AppButtonVariant.secondary,
                  onPressed: () => onCopy(b),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LeaveTypeRow extends StatelessWidget {
  const _LeaveTypeRow({
    required this.type,
    required this.days,
    required this.onToggle,
    required this.onDaysChanged,
  });

  final LeaveTypeSetup type;
  final TextEditingController days;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDaysChanged;

  @override
  Widget build(BuildContext context) {
    final invalid =
        type.enabled &&
        type.tracksBalance &&
        (int.tryParse(days.text) ?? 0) <= 0;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.sm + 2),
      decoration: BoxDecoration(
        color: type.enabled ? const Color(0xFFFAFBFF) : AppColors.surface,
        border: Border.all(
          color: type.enabled ? const Color(0xFFC9D2F6) : AppColors.border,
        ),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Semantics(
            label: type.name,
            toggled: type.enabled,
            excludeSemantics: true,
            child: Switch(
              value: type.enabled,
              activeTrackColor: AppColors.primary,
              onChanged: onToggle,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(type.name, style: AppTypography.label),
                Text(type.accrual, style: AppTypography.helper),
              ],
            ),
          ),
          if (type.tracksBalance)
            SizedBox(
              width: 92,
              child: Semantics(
                label: '${type.name} days per year',
                child: TextField(
                  controller: days,
                  enabled: type.enabled,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(2),
                  ],
                  style: AppTypography.body.copyWith(
                    fontFamily: AppTypography.mono,
                  ),
                  decoration: InputDecoration(
                    suffixText: 'days',
                    enabledBorder: invalid
                        ? OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            borderSide: const BorderSide(
                              color: AppColors.danger,
                            ),
                          )
                        : null,
                  ),
                  onChanged: (_) => onDaysChanged(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({
    required this.step,
    required this.ok,
    required this.note,
    required this.onFix,
  });

  final SetupStep step;
  final bool ok;
  final String note;
  final VoidCallback onFix;

  @override
  Widget build(BuildContext context) {
    final optional = step.isOptional;
    final (mark, bg, fg) = ok
        ? ('✓', AppColors.successSoft, AppColors.successText)
        : optional
        ? ('–', AppColors.neutralSoft, AppColors.textSecondary)
        : ('!', AppColors.warningSoft, AppColors.warningText);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm + 2),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
            child: Text(mark, style: AppTypography.label.copyWith(color: fg)),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${step.title}${optional ? ' (optional)' : ''}',
                  style: AppTypography.label,
                ),
                Text(note, style: AppTypography.helper),
              ],
            ),
          ),
          if (!ok)
            AppButton(
              label: optional ? 'Set up' : 'Fix',
              size: AppButtonSize.small,
              variant: AppButtonVariant.secondary,
              onPressed: onFix,
            ),
        ],
      ),
    );
  }
}
