import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/router/route_names.dart';
import '../../../core/errors/failure.dart';
import '../../../core/permissions/permissions.dart';
import '../../../core/permissions/system_roles.dart';
import '../../../core/responsive/responsive_grid.dart';
import '../../../core/responsive/responsive_page.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_dropdown_field.dart';
import '../../../core/widgets/app_overlays.dart';
import '../../../core/widgets/selection_controls.dart';
import '../../audit/domain/audit.dart';
import '../../audit/presentation/audit_providers.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../../auth/presentation/widgets/confirm_password_dialog.dart';
import '../../employees/domain/employee.dart';
import '../../employees/domain/employee_rules.dart';
import '../../employees/presentation/providers/employee_providers.dart';
import '../../holidays/presentation/calendar_providers.dart';
import '../../leave/presentation/admin/leave_settings_screens.dart';
import '../../leave/presentation/leave_providers.dart';
import '../../notifications/domain/notifications.dart';
import '../../notifications/presentation/notification_providers.dart';
import '../../organization/domain/branch.dart';
import '../../organization/presentation/providers/organization_providers.dart';
import '../../roles/presentation/access_providers.dart';
import '../domain/settings.dart';
import 'settings_providers.dart';
import 'settings_section.dart';

/// Board S80 — every settings area, searchable.
class SettingsOverviewScreen extends ConsumerStatefulWidget {
  const SettingsOverviewScreen({super.key});

  @override
  ConsumerState<SettingsOverviewScreen> createState() =>
      _SettingsOverviewScreenState();
}

class _SettingsOverviewScreenState
    extends ConsumerState<SettingsOverviewScreen> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    if (session == null) return const SizedBox.shrink();
    final org = ref.watch(organizationProvider).value;
    final branches = ref.watch(branchesProvider).value ?? const <Branch>[];
    final leave = ref.watch(leaveDataProvider).value;
    final fields = ref.watch(customFieldsProvider).value;
    final prefs = ref.watch(notificationPrefsProvider).value;
    final settings = ref.watch(orgSettingsProvider).value;
    final holidays = ref.watch(companyHolidaysProvider).value;
    final now = ref.watch(orgNowProvider)();
    final active = branches.where((b) => b.isActive).length;
    final nextYear = holidays?.any((h) => h.date.year == now.year + 1) ?? true;
    final twoStepOff = settings?.security.twoStep == TwoStepPolicy.optional;
    final meta = <String, (String, bool)>{
      AppRoutes.organization: (org?.timeZone ?? '', false),
      AppRoutes.branches: (
        '$active active · ${branches.length - active} inactive',
        false,
      ),
      AppRoutes.settingsSchedules: ('General and night shifts', false),
      AppRoutes.settingsAttendance: (
        '${branches.where((b) => b.attendance != null).length} branches set up',
        false,
      ),
      AppRoutes.leavePolicy: (
        '${leave?.types.where((t) => t.active).length ?? '—'} active types',
        false,
      ),
      AppRoutes.employeeFields: ('${fields?.length ?? '—'} fields', false),
      AppRoutes.settingsNotifications: (
        '${prefs?.onCount ?? '—'} switches on',
        false,
      ),
      AppRoutes.settingsSecurity: (
        twoStepOff
            ? 'Two-step is optional for admins'
            : settings?.security.twoStep.label ?? '',
        twoStepOff,
      ),
      AppRoutes.settingsData: (
        'Audit kept ${DataSettings.auditYears} years',
        false,
      ),
      AppRoutes.settingsBranding: (
        settings?.branding.language ?? 'English (India)',
        false,
      ),
    };
    final warnings = [
      if (twoStepOff && isOwnerLevel(session))
        'two-step sign-in isn’t required for admins',
      if (!nextYear) '${now.year + 1} holidays aren’t set up yet',
    ];
    final q = _q.trim().toLowerCase();
    final cards = [
      for (final a in areasFor(session))
        if (q.isEmpty ||
            '${a.title} ${a.hint} ${a.keywords}'.toLowerCase().contains(q))
          a,
    ];
    return ResponsivePage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: const Text('Settings', style: AppTypography.pageTitle),
          ),
          Text(
            'Changes here affect everyone in ${session.organizationName}. Every change is logged.',
            style: AppTypography.small,
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: 360,
            child: Semantics(
              label: 'Search settings',
              textField: true,
              child: TextField(
                onChanged: (v) => setState(() => _q = v),
                decoration: const InputDecoration(
                  hintText: 'Search settings',
                  prefixIcon: Icon(Icons.search, size: 18),
                ),
              ),
            ),
          ),
          if (warnings.isNotEmpty && q.isEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.warningSoft,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Text(
                '${warnings.length} ${warnings.length == 1 ? 'thing needs' : 'things need'} attention: ${warnings.join(', and ')}.',
                style: AppTypography.small.copyWith(
                  color: AppColors.warningText,
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          if (cards.isEmpty)
            Text(
              'No settings match “$_q”. Try a broader word like “leave” or “attendance”.',
              style: AppTypography.small,
            )
          else
            ResponsiveGrid(
              minItemWidth: 260,
              maxColumns: 3,
              children: [
                for (final a in cards)
                  InkWell(
                    onTap: () => context.go(a.route),
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    child: AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(a.icon, color: AppColors.primary),
                          const SizedBox(height: AppSpacing.sm),
                          Text(a.title, style: AppTypography.cardTitle),
                          Text(a.hint, style: AppTypography.small),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            meta[a.route]?.$1 ?? '',
                            style: AppTypography.helper.copyWith(
                              color: meta[a.route]?.$2 ?? false
                                  ? AppColors.warningText
                                  : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Board S79 — late, half-day and early-departure rules per branch.
class AttendancePolicyScreen extends ConsumerStatefulWidget {
  const AttendancePolicyScreen({super.key});

  @override
  ConsumerState<AttendancePolicyScreen> createState() =>
      _AttendancePolicyScreenState();
}

class _AttendancePolicyScreenState
    extends ConsumerState<AttendancePolicyScreen> {
  String? _branchId;
  AttendanceRules? _draft;
  int _version = 0;
  bool _busy = false;
  String? _savedNote;
  Map<String, String> _errors = const {};

  static Map<String, String> _check(AttendanceRules r) => {
    if (r.graceMinutes < 0 || r.graceMinutes > 60)
      'grace': 'Use 0 to 60 minutes.',
    if (r.halfDayLateMinutes <= r.graceMinutes || r.halfDayLateMinutes > 300)
      'halfDay': 'More than the grace period, up to 300 minutes.',
    if (r.earlyLeaveMinutes < 0 || r.earlyLeaveMinutes > 240)
      'early': 'Use 0 to 240 minutes.',
  };

  @override
  Widget build(BuildContext context) {
    final branches = [
      for (final b in ref.watch(branchesProvider).value ?? const <Branch>[])
        if (b.isActive) b,
    ];
    final branch =
        branches.where((b) => b.id == _branchId).firstOrNull ??
        branches.firstOrNull;
    final saved = branch?.attendance ?? const AttendanceRules();
    final rules = _draft ?? saved;
    final dirty = _draft != null;
    final people = (ref.watch(employeesProvider).value ?? const <Employee>[])
        .where((e) => e.branchId == branch?.id && e.status.isEmployed)
        .length;
    final history = [
      for (final e
          in ref.watch(auditEventsProvider).value ?? const <AuditEvent>[])
        if (e.entityType == 'Attendance policy' &&
            (e.entityId == null || e.entityId == branch?.id))
          e,
    ];

    Future<void> save() async {
      final errors = _check(rules);
      setState(() => _errors = errors);
      if (errors.isNotEmpty || branch == null) return;
      setState(() => _busy = true);
      try {
        await ref
            .read(branchesProvider.notifier)
            .save(branch.copyWith(attendance: rules));
        await ref
            .read(auditRecorderProvider)
            .record(
              action: 'policy.update',
              entityType: 'Attendance policy',
              entityId: branch.id,
              entityLabel: 'Attendance policy',
              entityRoute: AppRoutes.settingsAttendance,
              branchId: branch.id,
              scopeLabel: branch.name,
              summary: 'Attendance rules for ${branch.name} updated',
              changes: [
                if (saved.graceMinutes != rules.graceMinutes)
                  (
                    field: 'Grace period',
                    before: '${saved.graceMinutes} min',
                    after: '${rules.graceMinutes} min',
                  ),
                if (saved.halfDayLateMinutes != rules.halfDayLateMinutes)
                  (
                    field: 'Half day if late by',
                    before: '${saved.halfDayLateMinutes} min',
                    after: '${rules.halfDayLateMinutes} min',
                  ),
                if (saved.earlyLeaveMinutes != rules.earlyLeaveMinutes)
                  (
                    field: 'Early departure threshold',
                    before: '${saved.earlyLeaveMinutes} min',
                    after: '${rules.earlyLeaveMinutes} min',
                  ),
              ],
            );
        if (!mounted) return;
        setState(() {
          _draft = null;
          _version++;
          _savedNote = '✓ Saved · logged in the audit trail';
        });
      } on Failure catch (f) {
        if (mounted) {
          showAppToast(this.context, f.message, icon: Icons.error_outline);
        }
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }

    return SettingsPage(
      key: ValueKey('${branch?.id}-$_version'),
      route: AppRoutes.settingsAttendance,
      title: 'Attendance policy',
      subtitle: branch == null
          ? null
          : '${branch.name} · $people employees · measured against each employee’s assigned shift',
      dirty: dirty,
      busy: _busy,
      savedNote: _savedNote,
      onSave: save,
      onDiscard: () => setState(() {
        _draft = null;
        _version++;
      }),
      body: (_) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 280,
            child: AppDropdownField<String>(
              label: 'Branch',
              value: branch?.id,
              options: [
                for (final b in branches) AppDropdownOption(b.id, b.name),
              ],
              onChanged: (v) => setState(() {
                _branchId = v;
                _draft = null;
                _savedNote = null;
                _version++;
              }),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            header: const CardHeader(
              title: 'Late arrival & early departure',
              subtitle: 'Measured against each employee’s assigned shift.',
            ),
            child: ResponsiveGrid(
              minItemWidth: 220,
              maxColumns: 3,
              children: [
                NumberField(
                  label: 'Grace period',
                  unit: 'minutes',
                  value: rules.graceMinutes.toDouble(),
                  errorText: _errors['grace'],
                  helperText: dirty && saved.graceMinutes != rules.graceMinutes
                      ? 'Changed from ${saved.graceMinutes} min'
                      : null,
                  onChanged: (v) => setState(
                    () =>
                        _draft = rules.copyWith(graceMinutes: v?.round() ?? -1),
                  ),
                ),
                NumberField(
                  label: 'Mark as half day if late by',
                  unit: 'minutes',
                  value: rules.halfDayLateMinutes.toDouble(),
                  errorText: _errors['halfDay'],
                  onChanged: (v) => setState(
                    () => _draft = rules.copyWith(
                      halfDayLateMinutes: v?.round() ?? -1,
                    ),
                  ),
                ),
                NumberField(
                  label: 'Early departure threshold',
                  unit: 'minutes',
                  value: rules.earlyLeaveMinutes.toDouble(),
                  errorText: _errors['early'],
                  onChanged: (v) => setState(
                    () => _draft = rules.copyWith(
                      earlyLeaveMinutes: v?.round() ?? -1,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const AppCard(
            header: CardHeader(title: 'Missing punches & corrections'),
            child: Text(
              'Open sessions stay open and appear in the missing-punch queue; worked time excludes them until corrected. Employees can request a correction within 3 days, and a reason is always required.',
              style: AppTypography.small,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            header: CardHeader(
              title: 'Change history',
              trailing: TextButton(
                onPressed: () => context.go(AppRoutes.auditLog),
                child: const Text('Open audit log'),
              ),
            ),
            child: history.isEmpty
                ? const Text('No changes yet.', style: AppTypography.small)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final h in history.take(5))
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text(
                            '${DateFormat('d MMM y').format(h.at)} · ${h.changes.isEmpty ? h.summary : h.changes.map((c) => '${c.field} ${c.before} → ${c.after}').join('; ')} · ${h.actorName}',
                            style: AppTypography.small,
                          ),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: AppSpacing.sm),
          const Text(
            'New rules apply from the next calculation, including days already recorded this month.',
            style: AppTypography.helper,
          ),
        ],
      ),
    );
  }
}

/// Board S81 — the shift templates attendance uses.
class SchedulesSettingsScreen extends ConsumerWidget {
  const SchedulesSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branches = [
      for (final b in ref.watch(branchesProvider).value ?? const <Branch>[])
        if (b.isActive) b,
    ];
    final people = ref.watch(employeesProvider).value ?? const <Employee>[];
    String hm(int m) =>
        '${(m % 1440 ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
    final canEdit =
        ref
            .watch(sessionProvider)
            ?.permissions
            .can(PermissionModule.organization, PermissionAction.edit) ??
        false;
    return SettingsPage(
      route: AppRoutes.settingsSchedules,
      title: 'Work schedules',
      subtitle:
          'Shift templates used by attendance. Assign them to people in Holidays & Calendar › Schedules.',
      body: (_) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final b in branches)
            for (final s in shiftsFor(b))
              () {
                final length = (s.end - s.start) % 1440;
                final expected = length > 360 ? length - 60 : length;
                final users = people
                    .where(
                      (e) =>
                          e.branchId == b.id &&
                          e.shift == s.name &&
                          e.status.isEmployed,
                    )
                    .length;
                final night = s.end <= s.start;
                return Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: AppCard(
                    header: CardHeader(
                      title: '${s.name} · ${b.name}',
                      subtitle:
                          '${hm(s.start)}–${hm(s.end)}${night ? ' (next day)' : ''} · $users people',
                      trailing: canEdit && s.name == 'General'
                          ? TextButton(
                              onPressed: () =>
                                  context.go(AppRoutes.branchEdit(b.id)),
                              child: Text(
                                'Edit hours',
                                semanticsLabel: 'Edit hours of ${b.name}',
                              ),
                            )
                          : null,
                    ),
                    child: Wrap(
                      spacing: AppSpacing.xl,
                      runSpacing: AppSpacing.sm,
                      children: [
                        _Fact(
                          'Expected hours',
                          '${expected ~/ 60}h ${(expected % 60).toString().padLeft(2, '0')}m',
                        ),
                        _Fact(
                          'Breaks',
                          length > 360
                              ? '60 min unpaid, taken any time'
                              : 'None',
                        ),
                        _Fact(
                          'Times come from',
                          s.name == 'General'
                              ? 'Branch opening hours'
                              : 'Fixed overnight shift',
                        ),
                        if (night)
                          const _Fact(
                            'Overnight hours count on',
                            'The day the shift starts',
                          ),
                      ],
                    ),
                  ),
                );
              }(),
          Align(
            alignment: Alignment.centerLeft,
            child: AppButton(
              label: 'Assign schedules',
              variant: AppButtonVariant.secondary,
              onPressed: () => context.go(AppRoutes.schedules),
            ),
          ),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTypography.helper),
        Text(
          value,
          style: AppTypography.small.copyWith(color: AppColors.textPrimary),
        ),
      ],
    ),
  );
}

/// Board S82 — who hears about what.
class NotificationSettingsScreen extends ConsumerStatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  ConsumerState<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends ConsumerState<NotificationSettingsScreen> {
  NotificationPrefs? _draft;
  bool _busy = false;
  String? _savedNote;

  @override
  Widget build(BuildContext context) {
    final saved = ref.watch(notificationPrefsProvider).value;
    final prefs = _draft ?? saved ?? const NotificationPrefs();
    final queued = ref.watch(_outboxCountProvider).value ?? 0;
    final canEdit =
        ref
            .watch(sessionProvider)
            ?.permissions
            .can(PermissionModule.settings, PermissionAction.edit) ??
        false;

    Future<void> save() async {
      setState(() => _busy = true);
      try {
        final before = saved ?? const NotificationPrefs();
        await ref.read(notificationPrefsProvider.notifier).save(prefs);
        await ref
            .read(auditRecorderProvider)
            .record(
              action: 'settings.update',
              entityType: 'Settings',
              entityLabel: 'Notifications',
              entityRoute: AppRoutes.settingsNotifications,
              summary: 'Notification settings saved',
              changes: [
                for (final e in NotifyEvent.values)
                  for (final r in Recipient.values)
                    for (final c in Channel.values)
                      if (before.isOn(e, r, c) != prefs.isOn(e, r, c))
                        (
                          field: '${e.label} · ${r.label} ${c.label}',
                          before: before.isOn(e, r, c) ? 'On' : 'Off',
                          after: prefs.isOn(e, r, c) ? 'On' : 'Off',
                        ),
                if (before.digest != prefs.digest)
                  (
                    field: 'Daily digest',
                    before: before.digest ? 'On' : 'Off',
                    after: prefs.digest ? 'On' : 'Off',
                  ),
              ],
            );
        if (mounted) {
          setState(() {
            _draft = null;
            _savedNote = '✓ All changes saved';
          });
        }
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }

    final groups = <String>{for (final e in NotifyEvent.values) e.group};
    return SettingsPage(
      route: AppRoutes.settingsNotifications,
      title: 'Notifications',
      subtitle:
          'Who hears about what. Security emails (password resets, sign-in alerts) are always sent and can’t be turned off.',
      dirty: _draft != null,
      busy: _busy,
      savedNote: _savedNote,
      onSave: save,
      onDiscard: () => setState(() => _draft = null),
      body: (_) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppCard(
            padding: EdgeInsets.zero,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Table(
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                columnWidths: {
                  0: const FixedColumnWidth(260),
                  for (var i = 1; i <= 6; i++) i: const FixedColumnWidth(76),
                },
                border: const TableBorder(
                  horizontalInside: BorderSide(color: AppColors.divider),
                ),
                children: [
                  TableRow(
                    children: [
                      const Padding(
                        padding: EdgeInsets.all(AppSpacing.md),
                        child: Text('Event', style: AppTypography.tableHeader),
                      ),
                      for (final r in Recipient.values)
                        for (final c in Channel.values)
                          Text(
                            '${r.label}\n${c.label}',
                            textAlign: TextAlign.center,
                            style: AppTypography.tableHeader,
                          ),
                    ],
                  ),
                  for (final g in groups) ...[
                    TableRow(
                      decoration: const BoxDecoration(
                        color: AppColors.surfaceMuted,
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: 6,
                          ),
                          child: Text(g, style: AppTypography.label),
                        ),
                        for (var i = 0; i < 6; i++) const SizedBox.shrink(),
                      ],
                    ),
                    for (final e in NotifyEvent.values.where(
                      (e) => e.group == g,
                    ))
                      TableRow(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(AppSpacing.md),
                            child: Text(e.label, style: AppTypography.small),
                          ),
                          for (final r in Recipient.values)
                            for (final c in Channel.values)
                              !e.applies(r, c)
                                  ? const ExcludeSemantics(
                                      child: Text(
                                        '—',
                                        textAlign: TextAlign.center,
                                        style: AppTypography.helper,
                                      ),
                                    )
                                  : Center(
                                      child: Checkbox(
                                        value: prefs.isOn(e, r, c),
                                        semanticLabel:
                                            '${e.label}: ${r.label} ${c.label}',
                                        onChanged: e.locked(r, c) || !canEdit
                                            ? null
                                            : (_) => setState(
                                                () => _draft = prefs.toggled(
                                                  e,
                                                  r,
                                                  c,
                                                ),
                                              ),
                                      ),
                                    ),
                        ],
                      ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            header: const CardHeader(title: 'Daily digest for managers'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SwitchRow(
                  label: 'Send one summary email instead of each event',
                  value: prefs.digest,
                  onChanged: canEdit
                      ? (v) =>
                            setState(() => _draft = prefs.copyWith(digest: v))
                      : null,
                ),
                if (prefs.digest)
                  SizedBox(
                    width: 220,
                    child: AppDropdownField<int>(
                      label: 'Send at',
                      helperText: 'Each branch’s local time',
                      value: prefs.digestAt,
                      options: [
                        for (final h in const [8, 12, 17, 18, 20])
                          AppDropdownOption(
                            h * 60,
                            '${h.toString().padLeft(2, '0')}:00',
                          ),
                      ],
                      onChanged: (v) =>
                          setState(() => _draft = prefs.copyWith(digestAt: v)),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            header: const CardHeader(title: 'Email preview · leave approved'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Your leave is approved',
                  style: AppTypography.bodyStrong,
                ),
                const Text(
                  'Hi Isha, Aarav Bhatt approved your casual leave. Open Staffline to see your balance.',
                  style: AppTypography.small,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'In this demo emails are queued, not sent ($queued queued so far).',
                  style: AppTypography.helper,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

final _outboxCountProvider = FutureProvider<int>((ref) async {
  final s = ref.watch(sessionProvider);
  if (s == null) return 0;
  ref.watch(inboxProvider);
  return (await ref
          .watch(notificationRepositoryProvider)
          .outbox(s.organizationId))
      .length;
});

/// Board S83 — sign-in rules. Saving asks for the password again.
class SecuritySettingsScreen extends ConsumerStatefulWidget {
  const SecuritySettingsScreen({super.key});

  @override
  ConsumerState<SecuritySettingsScreen> createState() =>
      _SecuritySettingsScreenState();
}

class _SecuritySettingsScreenState
    extends ConsumerState<SecuritySettingsScreen> {
  SecuritySettings? _draft;
  int _version = 0;
  bool _busy = false;
  String? _savedNote;

  @override
  Widget build(BuildContext context) {
    final settings =
        ref.watch(orgSettingsProvider).value ?? const OrgSettings();
    final saved = settings.security;
    final s = _draft ?? saved;
    final access = ref.watch(accessDataProvider).value;
    final admins = access == null
        ? 0
        : access.assignments.values
              .where(
                (a) => access.role(a.roleId)?.base.requiresTwoStep ?? false,
              )
              .length;
    final everyone = (ref.watch(employeesProvider).value ?? const <Employee>[])
        .where((e) => e.status.isEmployed)
        .length;
    final errors = validateSecurity(s);

    Future<void> save() async {
      if (errors.isNotEmpty) return;
      if (!await confirmItsYou(context, why: 'change security settings')) {
        return;
      }
      setState(() => _busy = true);
      try {
        await ref
            .read(orgSettingsProvider.notifier)
            .save(
              settings.copyWith(security: s),
              area: 'Security',
              changes: [
                if (saved.twoStep != s.twoStep)
                  (
                    field: 'Two-step sign-in',
                    before: saved.twoStep.label,
                    after: s.twoStep.label,
                  ),
                if (saved.minPasswordLength != s.minPasswordLength)
                  (
                    field: 'Minimum password length',
                    before: '${saved.minPasswordLength}',
                    after: '${s.minPasswordLength}',
                  ),
                if (saved.inviteDays != s.inviteDays)
                  (
                    field: 'Invitation links expire after',
                    before: '${saved.inviteDays} days',
                    after: '${s.inviteDays} days',
                  ),
                if (saved.lockAfterAttempts != s.lockAfterAttempts)
                  (
                    field: 'Lock after failed attempts',
                    before: '${saved.lockAfterAttempts}',
                    after: '${s.lockAfterAttempts}',
                  ),
              ],
            );
        if (mounted) {
          setState(() {
            _draft = null;
            _version++;
            _savedNote = '✓ Saved · logged in the audit trail';
          });
        }
      } on Failure catch (f) {
        if (mounted) {
          showAppToast(this.context, f.message, icon: Icons.error_outline);
        }
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }

    void edit(SecuritySettings Function(SecuritySettings) f) => setState(() {
      _draft = f(s);
      _savedNote = null;
    });

    return SettingsPage(
      key: ValueKey(_version),
      route: AppRoutes.settingsSecurity,
      title: 'Security',
      dirty: _draft != null,
      busy: _busy,
      savedNote: _savedNote,
      onSave: errors.isEmpty ? save : null,
      onDiscard: () => setState(() {
        _draft = null;
        _version++;
      }),
      body: (_) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppCard(
            header: const CardHeader(
              title: 'Two-step sign-in',
              subtitle: 'A code from an authenticator app after the password.',
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final p in TwoStepPolicy.values)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: OptionCard(
                      title: p.label,
                      description: p.hint,
                      selected: s.twoStep == p,
                      onTap: () => edit((x) => x.copyWith(twoStep: p)),
                    ),
                  ),
                Text(
                  switch (s.twoStep) {
                    TwoStepPolicy.optional =>
                      'Two-step becomes optional for everyone.',
                    TwoStepPolicy.admins =>
                      '$admins people with admin access are asked for a code at their next sign-in.',
                    TwoStepPolicy.everyone =>
                      '$everyone people are asked for a code at their next sign-in.',
                  },
                  style: AppTypography.small.copyWith(
                    color: AppColors.warningText,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            header: const CardHeader(title: 'Passwords & sessions'),
            child: ResponsiveGrid(
              minItemWidth: 240,
              maxColumns: 2,
              children: [
                NumberField(
                  label: 'Minimum length',
                  unit: 'characters',
                  value: s.minPasswordLength.toDouble(),
                  errorText: errors['minLength'],
                  helperText: 'Applies when people next set a password.',
                  onChanged: (v) => edit(
                    (x) => x.copyWith(minPasswordLength: v?.round() ?? 0),
                  ),
                ),
                AppDropdownField<int>(
                  label: 'Lock after failed attempts',
                  value: s.lockAfterAttempts,
                  options: const [
                    AppDropdownOption(3, '3 attempts · 15 minutes'),
                    AppDropdownOption(5, '5 attempts · 15 minutes'),
                    AppDropdownOption(10, '10 attempts · 15 minutes'),
                  ],
                  onChanged: (v) =>
                      edit((x) => x.copyWith(lockAfterAttempts: v)),
                ),
                AppDropdownField<int>(
                  label: 'Sign out inactive admins after',
                  value: s.adminIdleMinutes,
                  options: const [
                    AppDropdownOption(15, '15 minutes'),
                    AppDropdownOption(30, '30 minutes'),
                    AppDropdownOption(60, '1 hour'),
                  ],
                  onChanged: (v) =>
                      edit((x) => x.copyWith(adminIdleMinutes: v)),
                ),
                AppDropdownField<int>(
                  label: 'Invitation links expire after',
                  value: s.inviteDays,
                  options: const [
                    AppDropdownOption(3, '3 days'),
                    AppDropdownOption(7, '7 days'),
                    AppDropdownOption(14, '14 days'),
                  ],
                  onChanged: (v) => edit((x) => x.copyWith(inviteDays: v)),
                ),
                AppDropdownField<int>(
                  label: 'Password reset links expire after',
                  value: s.resetMinutes,
                  options: const [
                    AppDropdownOption(15, '15 minutes'),
                    AppDropdownOption(30, '30 minutes'),
                    AppDropdownOption(60, '1 hour'),
                  ],
                  onChanged: (v) => edit((x) => x.copyWith(resetMinutes: v)),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          const Text(
            'Security changes need your password again and are logged.',
            style: AppTypography.helper,
          ),
        ],
      ),
    );
  }
}

/// Board S84 — export rights, file formats, retention, audit access.
class DataSettingsScreen extends ConsumerStatefulWidget {
  const DataSettingsScreen({super.key});

  @override
  ConsumerState<DataSettingsScreen> createState() => _DataSettingsScreenState();
}

class _DataSettingsScreenState extends ConsumerState<DataSettingsScreen> {
  DataSettings? _draft;
  int _version = 0;
  bool _busy = false;
  String? _savedNote;

  @override
  Widget build(BuildContext context) {
    final settings =
        ref.watch(orgSettingsProvider).value ?? const OrgSettings();
    final saved = settings.data;
    final d = _draft ?? saved;
    final roles = ref.watch(accessDataProvider).value?.roles ?? const [];
    bool auditFor(String id) =>
        roles
            .where((r) => r.id == id)
            .firstOrNull
            ?.grants
            .canView(PermissionModule.auditLog) ??
        false;

    Future<void> save() async {
      setState(() => _busy = true);
      try {
        await ref
            .read(orgSettingsProvider.notifier)
            .save(
              settings.copyWith(data: d),
              area: 'Data & export',
              changes: [
                for (final r in DataSettings.defaultExportRights.keys)
                  for (final a in ExportArea.values)
                    if (saved.canExport(r, a) != d.canExport(r, a))
                      (
                        field: '${r.label} can export ${a.label}',
                        before: saved.canExport(r, a) ? 'Yes' : 'No',
                        after: d.canExport(r, a) ? 'Yes' : 'No',
                      ),
                if (saved.dateFormat != d.dateFormat)
                  (
                    field: 'Date format in files',
                    before: saved.dateFormat.label,
                    after: d.dateFormat.label,
                  ),
                if (saved.durations != d.durations)
                  (
                    field: 'Durations',
                    before: saved.durations.label,
                    after: d.durations.label,
                  ),
              ],
            );
        if (mounted) {
          setState(() {
            _draft = null;
            _version++;
            _savedNote = '✓ All changes saved';
          });
        }
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }

    void edit(DataSettings Function(DataSettings) f) => setState(() {
      _draft = f(d);
      _savedNote = null;
    });

    return SettingsPage(
      key: ValueKey(_version),
      route: AppRoutes.settingsData,
      title: 'Data & export',
      dirty: _draft != null,
      busy: _busy,
      savedNote: _savedNote,
      onSave: save,
      onDiscard: () => setState(() {
        _draft = null;
        _version++;
      }),
      body: (_) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppCard(
            header: const CardHeader(
              title: 'Who can export',
              subtitle:
                  'Exports never include more than the person can see on screen.',
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Table(
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                columnWidths: {
                  0: const FixedColumnWidth(200),
                  for (var i = 1; i <= ExportArea.values.length; i++)
                    i: const FixedColumnWidth(120),
                },
                border: const TableBorder(
                  horizontalInside: BorderSide(color: AppColors.divider),
                ),
                children: [
                  TableRow(
                    children: [
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('Role', style: AppTypography.tableHeader),
                      ),
                      for (final a in ExportArea.values)
                        Text(
                          a.label,
                          textAlign: TextAlign.center,
                          style: AppTypography.tableHeader,
                        ),
                    ],
                  ),
                  for (final r in [
                    SystemRole.owner,
                    ...DataSettings.defaultExportRights.keys,
                  ])
                    TableRow(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(r.label, style: AppTypography.small),
                        ),
                        for (final a in ExportArea.values)
                          Center(
                            child: Checkbox(
                              value: d.canExport(r, a),
                              semanticLabel: '${r.label} can export ${a.label}',
                              onChanged: r == SystemRole.owner
                                  ? null
                                  : (on) => edit(
                                      (x) => x.copyWith(
                                        exportRights: {
                                          ...x.exportRights,
                                          r: {...?x.exportRights[r], if (on!) a}
                                            ..removeWhere((y) => !on && y == a),
                                        },
                                      ),
                                    ),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            header: const CardHeader(title: 'Export format'),
            child: ResponsiveGrid(
              minItemWidth: 220,
              maxColumns: 2,
              children: [
                AppDropdownField<FileDateFormat>(
                  label: 'Date format in files',
                  value: d.dateFormat,
                  options: [
                    for (final f in FileDateFormat.values)
                      AppDropdownOption(f, f.label),
                  ],
                  onChanged: (v) => edit((x) => x.copyWith(dateFormat: v)),
                ),
                AppDropdownField<DurationStyle>(
                  label: 'Durations',
                  value: d.durations,
                  options: [
                    for (final f in DurationStyle.values)
                      AppDropdownOption(f, f.label),
                  ],
                  onChanged: (v) => edit((x) => x.copyWith(durations: v)),
                ),
                AppDropdownField<String>(
                  label: 'CSV separator',
                  value: d.csvSeparator,
                  options: const [
                    AppDropdownOption(',', 'Comma ,'),
                    AppDropdownOption(';', 'Semicolon ;'),
                  ],
                  onChanged: (v) => edit((x) => x.copyWith(csvSeparator: v)),
                ),
                AppDropdownField<int>(
                  label: 'Download links expire',
                  value: d.linkDays,
                  options: const [
                    AppDropdownOption(1, 'After 1 day'),
                    AppDropdownOption(7, 'After 7 days'),
                    AppDropdownOption(30, 'After 30 days'),
                  ],
                  onChanged: (v) => edit((x) => x.copyWith(linkDays: v)),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            header: const CardHeader(title: 'Retention'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Retention(
                  'Attendance punches',
                  'Raw punches and corrections',
                  d.punchYears,
                  const [3, 5, 7, 10],
                  'years',
                  (v) => edit((x) => x.copyWith(punchYears: v)),
                ),
                _Retention(
                  'Deactivated employees',
                  'Profile kept for reports, then anonymized',
                  d.leaverYears,
                  const [1, 3, 5],
                  'years after leaving',
                  (v) => edit((x) => x.copyWith(leaverYears: v)),
                ),
                _Retention(
                  'Generated export files',
                  'Files on the export history page',
                  d.exportFileDays,
                  const [7, 30, 90],
                  'days',
                  (v) => edit((x) => x.copyWith(exportFileDays: v)),
                ),
                const _Retention(
                  'Audit log',
                  'Minimum required; can’t be shortened',
                  DataSettings.auditYears,
                  [DataSettings.auditYears],
                  'years',
                  null,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            header: CardHeader(
              title: 'Audit log access',
              trailing: TextButton(
                onPressed: () => context.go(AppRoutes.roles),
                child: const Text('Change in Roles'),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('✓ Owner — always', style: AppTypography.small),
                Text(
                  '${auditFor('hrAdmin') ? '✓' : '✗'} HR Admin',
                  style: AppTypography.small,
                ),
                Text(
                  '${auditFor('branchManager') ? '✓' : '✗'} Branch Managers — their branches only',
                  style: AppTypography.small,
                ),
                const SizedBox(height: AppSpacing.sm),
                const Text(
                  'Nobody can edit or delete audit entries, including the owner.',
                  style: AppTypography.helper,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Retention extends StatelessWidget {
  const _Retention(
    this.title,
    this.hint,
    this.value,
    this.options,
    this.unit,
    this.onChanged,
  );

  final String title;
  final String hint;
  final int value;
  final List<int> options;
  final String unit;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpacing.md,
      runSpacing: 4,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTypography.bodyStrong),
              Text(hint, style: AppTypography.helper),
            ],
          ),
        ),
        SizedBox(
          width: 220,
          child: onChanged == null
              ? Text('$value $unit · locked', style: AppTypography.small)
              : DropdownButton<int>(
                  value: value,
                  isExpanded: true,
                  items: [
                    for (final o in options)
                      DropdownMenuItem(value: o, child: Text('$o $unit')),
                  ],
                  onChanged: (v) => onChanged!(v ?? value),
                ),
        ),
      ],
    ),
  );
}

/// Board S85 — brand color and formats, with a live preview.
class BrandingSettingsScreen extends ConsumerStatefulWidget {
  const BrandingSettingsScreen({super.key});

  @override
  ConsumerState<BrandingSettingsScreen> createState() =>
      _BrandingSettingsScreenState();
}

class _BrandingSettingsScreenState
    extends ConsumerState<BrandingSettingsScreen> {
  BrandingSettings? _draft;
  bool _busy = false;
  String? _savedNote;
  final _hex = TextEditingController();

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings =
        ref.watch(orgSettingsProvider).value ?? const OrgSettings();
    final saved = settings.branding;
    final b = _draft ?? saved;
    final contrast = contrastWithWhite(b.color);
    void edit(BrandingSettings Function(BrandingSettings) f) => setState(() {
      _draft = f(b);
      _savedNote = null;
    });

    Future<void> save() async {
      setState(() => _busy = true);
      try {
        await ref
            .read(orgSettingsProvider.notifier)
            .save(
              settings.copyWith(branding: b),
              area: 'Branding & localization',
              changes: [
                if (saved.color != b.color)
                  (
                    field: 'Brand color',
                    before:
                        '#${saved.color.toRadixString(16).substring(2).toUpperCase()}',
                    after:
                        '#${b.color.toRadixString(16).substring(2).toUpperCase()}',
                  ),
                if (saved.language != b.language)
                  (
                    field: 'Default language',
                    before: saved.language,
                    after: b.language,
                  ),
              ],
            );
        if (mounted) {
          setState(() {
            _draft = null;
            _savedNote = '✓ Saved';
          });
        }
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }

    final previewDate = DateTime(2026, 10, 14, 18, 30);
    final dateText = b.longDates
        ? DateFormat('EEE d MMM y').format(previewDate)
        : DateFormat('dd/MM/yyyy').format(previewDate);
    final timeText = b.clock24
        ? DateFormat('HH:mm').format(previewDate)
        : DateFormat('h:mm a').format(previewDate).toLowerCase();
    final amount = b.indianNumbers ? '₹ 1,25,000' : '₹ 125,000';
    final buttonText = contrast < 3 ? AppColors.textPrimary : AppColors.surface;

    return SettingsPage(
      route: AppRoutes.settingsBranding,
      title: 'Branding & localization',
      dirty: _draft != null,
      busy: _busy,
      savedNote: _savedNote,
      onSave: save,
      saveLabel: 'Save',
      onDiscard: () => setState(() => _draft = null),
      body: (_) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppCard(
            header: CardHeader(
              title: 'Logo',
              trailing: TextButton(
                onPressed: () => context.go(AppRoutes.organization),
                child: const Text('Change in Organization'),
              ),
            ),
            child: const Text(
              'SVG or PNG, square, at least 256 × 256. Shown in the sidebar, sign-in page and emails.',
              style: AppTypography.small,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            header: const CardHeader(title: 'Brand color'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final (hex, label) in BrandingSettings.swatches)
                      Semantics(
                        button: true,
                        selected: b.color == hex,
                        label: label,
                        child: InkWell(
                          onTap: () => edit((x) => x.copyWith(color: hex)),
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: Color(hex),
                              borderRadius: BorderRadius.circular(AppRadius.md),
                              border: Border.all(
                                color: b.color == hex
                                    ? AppColors.textPrimary
                                    : AppColors.border,
                                width: b.color == hex ? 3 : 1,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                SizedBox(
                  width: 240,
                  child: Semantics(
                    label: 'Custom color, hex',
                    textField: true,
                    child: TextField(
                      controller: _hex,
                      decoration: const InputDecoration(hintText: '#F2B84B'),
                      onSubmitted: (v) {
                        final m = RegExp(
                          r'^#?([0-9a-fA-F]{6})$',
                        ).firstMatch(v.trim());
                        if (m != null) {
                          edit(
                            (x) => x.copyWith(
                              color: int.parse('FF${m.group(1)}', radix: 16),
                            ),
                          );
                        }
                      },
                    ),
                  ),
                ),
                if (contrast < 4.5) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'White text on this color is hard to read (${contrast.toStringAsFixed(1)}:1). We’ll use dark text on buttons and the sidebar badge automatically.',
                    style: AppTypography.small.copyWith(
                      color: AppColors.warningText,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            header: const CardHeader(title: 'Language & formats'),
            child: ResponsiveGrid(
              minItemWidth: 220,
              maxColumns: 2,
              children: [
                AppDropdownField<String>(
                  label: 'Default language',
                  helperText: 'Employees can pick their own in My profile.',
                  value: b.language,
                  options: [
                    for (final l in BrandingSettings.languages)
                      AppDropdownOption(l, l),
                  ],
                  onChanged: (v) => edit((x) => x.copyWith(language: v)),
                ),
                AppDropdownField<bool>(
                  label: 'Date format',
                  value: b.longDates,
                  options: const [
                    AppDropdownOption(true, '14 Oct 2026'),
                    AppDropdownOption(false, '14/10/2026'),
                  ],
                  onChanged: (v) => edit((x) => x.copyWith(longDates: v)),
                ),
                AppDropdownField<bool>(
                  label: 'Time format',
                  value: b.clock24,
                  options: const [
                    AppDropdownOption(true, '24-hour (18:30)'),
                    AppDropdownOption(false, '12-hour (6:30 pm)'),
                  ],
                  onChanged: (v) => edit((x) => x.copyWith(clock24: v)),
                ),
                AppDropdownField<bool>(
                  label: 'Numbers',
                  value: b.indianNumbers,
                  options: const [
                    AppDropdownOption(true, 'Indian (1,00,000)'),
                    AppDropdownOption(false, 'International (100,000)'),
                  ],
                  onChanged: (v) => edit((x) => x.copyWith(indianNumbers: v)),
                ),
                AppDropdownField<bool>(
                  label: 'Week starts on',
                  value: b.weekStartsMonday,
                  options: const [
                    AppDropdownOption(true, 'Monday'),
                    AppDropdownOption(false, 'Sunday'),
                  ],
                  onChanged: (v) =>
                      edit((x) => x.copyWith(weekStartsMonday: v)),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            header: const CardHeader(title: 'Preview'),
            child: Wrap(
              spacing: AppSpacing.lg,
              runSpacing: AppSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ExcludeSemantics(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Color(b.color),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Text(
                      'Approve',
                      style: AppTypography.button.copyWith(color: buttonText),
                    ),
                  ),
                ),
                Text('$dateText · $timeText', style: AppTypography.code),
                Text(amount, style: AppTypography.code),
                const Text('8h 04m', style: AppTypography.code),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          const Text(
            'Saved for the organization. The app itself keeps the Staffline theme and English in this version.',
            style: AppTypography.helper,
          ),
        ],
      ),
    );
  }
}
