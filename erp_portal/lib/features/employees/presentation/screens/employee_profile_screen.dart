import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/router/route_names.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/permissions/permissions.dart';
import '../../../../core/responsive/responsive_grid.dart';
import '../../../../core/responsive/responsive_page.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_overlays.dart';
import '../../../../core/widgets/page_header.dart';
import '../../../../core/widgets/skeleton.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../../core/widgets/tab_strip.dart';
import '../../../../shared/models/app_session.dart';
import '../../../attendance/domain/attendance_book.dart';
import '../../../attendance/presentation/admin/monthly_summary_screen.dart'
    show cellStyle;
import '../../../attendance/presentation/attendance_providers.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../auth/presentation/widgets/auth_layout.dart';
import '../../../leave/presentation/admin/leave_records_screens.dart';
import '../../../leave/presentation/leave_providers.dart';
import '../../../leave/presentation/leave_widgets.dart';
import '../../../organization/domain/branch.dart';
import '../../../organization/presentation/providers/organization_providers.dart';
import '../../domain/custom_field.dart';
import '../../domain/employee.dart';
import '../../domain/employee_rules.dart';
import '../providers/employee_providers.dart';
import '../widgets/employee_widgets.dart';

/// "2h ago", "3 days ago".
String timeAgo(DateTime then, DateTime now) {
  final d = now.difference(then);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  if (d.inDays < 30) return '${d.inDays} ${d.inDays == 1 ? 'day' : 'days'} ago';
  return DateFormat('d MMM y').format(then);
}

/// Board S42 — one employee in tabs.
class EmployeeProfileScreen extends ConsumerStatefulWidget {
  const EmployeeProfileScreen({super.key, required this.employeeId});

  final String employeeId;

  @override
  ConsumerState<EmployeeProfileScreen> createState() =>
      _EmployeeProfileScreenState();
}

class _EmployeeProfileScreenState extends ConsumerState<EmployeeProfileScreen> {
  static const _tabs = [
    'Overview',
    'Personal & employment',
    'Attendance',
    'Leave & balances',
    'Schedule',
    'Account & access',
    'Custom fields',
    'Activity',
  ];
  int _tab = 0;
  bool _revealContact = false;

  Future<void> _run(Future<void> Function() action, String done) async {
    try {
      await action();
      if (mounted) showAppToast(context, done);
    } on Failure catch (f) {
      if (mounted) showAppToast(context, f.message, icon: Icons.error_outline);
    }
  }

  Future<void> _deactivate(Employee e) async {
    final input = await showLifecycleDialog(
      context,
      title: 'Deactivate ${e.fullName}?',
      message:
          'Removes sign-in access. Attendance, leave and audit history are '
          'kept, and you can reactivate them later.',
      confirmLabel: 'Deactivate',
      destructive: true,
    );
    if (input == null) return;
    await _run(
      () => ref
          .read(employeesProvider.notifier)
          .setStatus(e.id, EmploymentStatus.inactive, reason: input.reason),
      '${e.fullName} deactivated',
    );
  }

  Future<void> _reactivate(Employee e) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Reactivate ${e.fullName}?',
      message:
          'They appear in the directory and head counts again. Send a new '
          'invitation if they need to sign in.',
      confirmLabel: 'Reactivate',
    );
    if (!ok) return;
    await _run(
      () => ref
          .read(employeesProvider.notifier)
          .setStatus(e.id, EmploymentStatus.active),
      '${e.fullName} reactivated',
    );
  }

  Future<void> _notice(Employee e) async {
    final input = await showLifecycleDialog(
      context,
      title: 'Start notice period for ${e.fullName}?',
      message: 'They keep working and signing in until their last working day.',
      confirmLabel: 'Start notice period',
      reasonRequired: false,
      dateLabel: 'Last working day',
    );
    if (input == null) return;
    await _run(
      () => ref
          .read(employeesProvider.notifier)
          .setStatus(
            e.id,
            EmploymentStatus.noticePeriod,
            reason: input.reason,
            lastWorkingDay: input.date,
          ),
      'Notice period started',
    );
  }

  Future<void> _terminate(Employee e) async {
    final input = await showLifecycleDialog(
      context,
      title: 'Terminate and archive ${e.fullName}?',
      message:
          'They lose access on the effective date and leave the directory '
          '(filter by Terminated to find them). History is kept for audits '
          'and reports.',
      confirmLabel: 'Terminate',
      destructive: true,
      dateLabel: 'Effective date',
      initialDate: ref.read(orgNowProvider)(),
    );
    if (input == null) return;
    await _run(
      () => ref
          .read(employeesProvider.notifier)
          .setStatus(
            e.id,
            EmploymentStatus.terminated,
            reason: input.reason,
            lastWorkingDay: input.date,
          ),
      '${e.fullName} terminated and archived',
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final employee = ref.watch(employeeProvider(widget.employeeId));
    if (session == null) return const SizedBox.shrink();
    return ResponsivePage(
      child: employee.when(
        loading: () => const LoadingSkeleton(
          label: 'Loading employee',
          child: SkeletonList(rows: 6),
        ),
        error: (error, _) => ErrorState(
          message: userMessageFor(error),
          onRetry: () => ref.invalidate(employeesProvider),
        ),
        data: (e) => e == null
            ? ErrorState(
                headline: '404',
                title: 'This person isn’t here',
                message:
                    'They may be outside the branches you can see, or the link '
                    'is mistyped.',
                actions: [
                  AppButton(
                    label: 'Go to employees',
                    onPressed: () => context.go(AppRoutes.employees),
                  ),
                ],
              )
            : _body(context, session, e),
      ),
    );
  }

  Widget _body(BuildContext context, AppSession session, Employee e) {
    final everyone = ref.watch(employeesProvider).value ?? const <Employee>[];
    final branches = ref.watch(branchesProvider).value ?? const <Branch>[];
    final branch = branches.where((b) => b.id == e.branchId).firstOrNull;
    final manager = everyone.where((x) => x.id == e.managerId).firstOrNull;
    final now = ref.watch(orgNowProvider)();
    final p = session.permissions;
    final canEdit = p.can(PermissionModule.employees, PermissionAction.edit);
    final canDeactivate = p.can(
      PermissionModule.employees,
      PermissionAction.deactivate,
    );
    final seesPrivate = session.scope == DataScope.organization && canEdit;

    final account = switch (e.accountStatus) {
      AccountStatus.signedIn when e.lastSignInAt != null =>
        'Signed in · ${timeAgo(e.lastSignInAt!, now)}',
      AccountStatus.invited when e.invitedAt != null =>
        'Invited · ${timeAgo(e.invitedAt!, now)}',
      final s => s.label,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Breadcrumbs(
          items: [
            BreadcrumbItem(
              'Employees',
              onTap: () => context.go(AppRoutes.employees),
            ),
            BreadcrumbItem(e.fullName),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.start,
          spacing: AppSpacing.lg,
          runSpacing: AppSpacing.md,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  EmployeeAvatar(employee: e, size: 64),
                  const SizedBox(width: AppSpacing.lg),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.xs,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Semantics(
                              header: true,
                              child: Text(
                                e.fullName,
                                style: AppTypography.pageTitle,
                              ),
                            ),
                            EmploymentBadge(e.status),
                            Text(account, style: AppTypography.small),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${e.code} · ${e.designation} · ${e.department}',
                          style: AppTypography.small.copyWith(
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              '${branch?.name ?? '—'} · reports to ',
                              style: AppTypography.small,
                            ),
                            if (manager == null)
                              const Text(
                                'the owner',
                                style: AppTypography.small,
                              )
                            else
                              TextLink(
                                manager.fullName,
                                onTap: () =>
                                    context.go(AppRoutes.employee(manager.id)),
                              ),
                            Text(
                              ' · joined ${employeeDateFormat.format(e.joiningDate)} · ${e.type.label}',
                              style: AppTypography.small,
                            ),
                          ],
                        ),
                        if (!e.status.isEmployed && e.statusReason.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: AppSpacing.xs),
                            child: Text(
                              '${e.status.label} · reason: ${e.statusReason}',
                              style: AppTypography.helper,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (canEdit && e.accountStatus == AccountStatus.signedIn)
                  TextLink(
                    'Reset password link',
                    onTap: () => _run(
                      () => ref
                          .read(employeesProvider.notifier)
                          .sendPasswordReset(e.id),
                      'Reset link sent to ${e.workEmail}',
                    ),
                  ),
                if (canDeactivate && e.status.isEmployed)
                  AppButton(
                    label: 'Deactivate…',
                    variant: AppButtonVariant.dangerOutline,
                    onPressed: () => _deactivate(e),
                  ),
                if (canDeactivate && e.status == EmploymentStatus.inactive)
                  AppButton(
                    label: 'Reactivate…',
                    variant: AppButtonVariant.secondary,
                    onPressed: () => _reactivate(e),
                  ),
                if (canEdit && e.status != EmploymentStatus.terminated)
                  AppButton(
                    label: 'Edit',
                    onPressed: () => context.go(AppRoutes.employeeEdit(e.id)),
                  ),
                if (canDeactivate && e.status.isEmployed)
                  PopupMenuButton<String>(
                    tooltip: 'More actions for ${e.fullName}',
                    icon: const Icon(Icons.more_vert),
                    onSelected: (v) =>
                        v == 'notice' ? _notice(e) : _terminate(e),
                    itemBuilder: (_) => [
                      if (e.status != EmploymentStatus.noticePeriod)
                        const PopupMenuItem(
                          value: 'notice',
                          child: Text('Start notice period…'),
                        ),
                      const PopupMenuItem(
                        value: 'terminate',
                        child: Text('Terminate and archive…'),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        AppTabStrip(
          tabs: _tabs,
          selected: _tab,
          onSelected: (i) => setState(() => _tab = i),
        ),
        const SizedBox(height: AppSpacing.lg),
        switch (_tab) {
          0 => _overview(e, branch, seesPrivate),
          1 => _personal(e, seesPrivate),
          2 => _AttendanceTab(employee: e),
          3 => _LeaveTab(employee: e, branch: branch),
          4 => _schedule(e, branch),
          5 => _account(e, now, canEdit),
          6 => _CustomFieldsTab(employee: e, session: session),
          _ => _ActivityTab(employee: e),
        },
      ],
    );
  }

  Widget _section(
    String title,
    List<Widget> facts, {
    String? note,
    Widget? trailing,
  }) => AppCard(
    header: CardHeader(title: title, subtitle: note, trailing: trailing),
    child: ResponsiveGrid(
      minItemWidth: 200,
      maxColumns: 4,
      spacing: AppSpacing.lg,
      children: facts,
    ),
  );

  Widget _contact(Employee e, bool seesPrivate) {
    final showPhone = seesPrivate && _revealContact;
    return _section(
      'Contact',
      note: 'Visible to HR and managers',
      trailing:
          seesPrivate && (e.mobile.isNotEmpty || e.emergencyContact.isNotEmpty)
          ? TextLink(
              _revealContact ? 'Hide' : 'Show',
              onTap: () => setState(() => _revealContact = !_revealContact),
            )
          : null,
      [
        FactTile(label: 'Work email', value: e.workEmail),
        FactTile(
          label: 'Mobile',
          value: showPhone ? e.mobile : maskPhone(e.mobile),
          mono: true,
          locked: !showPhone && e.mobile.isNotEmpty,
        ),
        FactTile(
          label: 'Emergency contact',
          value: showPhone
              ? e.emergencyContact
              : (e.emergencyContact.isEmpty ? 'Not on file' : 'On file'),
          locked: !showPhone && e.emergencyContact.isNotEmpty,
        ),
        if (seesPrivate)
          FactTile(label: 'Personal email', value: e.personalEmail),
      ],
    );
  }

  Widget _overview(Employee e, Branch? branch, bool seesPrivate) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _AtAGlance(employee: e),
      const SizedBox(height: AppSpacing.lg),
      _section('Work', [
        FactTile(label: 'Branch', value: branch?.name ?? '—'),
        FactTile(label: 'Shift', value: describeShift(e, branch)),
        FactTile(label: 'Weekly off', value: _weeklyOff(e, branch)),
        FactTile(label: 'Work location', value: e.workLocation),
      ]),
      const SizedBox(height: AppSpacing.lg),
      _contact(e, seesPrivate),
    ],
  );

  Widget _personal(Employee e, bool seesPrivate) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _section('Identity', [
        FactTile(label: 'Full name', value: e.fullName),
        FactTile(label: 'Display name', value: e.displayName),
        FactTile(label: 'Employee ID', value: e.code, mono: true),
        FactTile(
          label: 'Date of birth',
          value: seesPrivate
              ? (e.dateOfBirth == null
                    ? ''
                    : employeeDateFormat.format(e.dateOfBirth!))
              : 'Restricted',
          locked: !seesPrivate,
        ),
      ]),
      const SizedBox(height: AppSpacing.lg),
      _section('Employment', [
        FactTile(label: 'Designation', value: e.designation),
        FactTile(label: 'Department', value: e.department),
        FactTile(label: 'Employment type', value: e.type.label),
        FactTile(label: 'Status', value: e.status.label),
        FactTile(
          label: 'Joining date',
          value: employeeDateFormat.format(e.joiningDate),
          mono: true,
        ),
        FactTile(
          label: e.status == EmploymentStatus.probation
              ? 'Probation ends'
              : 'Probation ended',
          value: e.probationEndsOn == null
              ? 'No probation'
              : employeeDateFormat.format(e.probationEndsOn!),
          mono: e.probationEndsOn != null,
        ),
        if (e.lastWorkingDay != null)
          FactTile(
            label: 'Last working day',
            value: employeeDateFormat.format(e.lastWorkingDay!),
            mono: true,
          ),
      ]),
    ],
  );

  String _weeklyOff(Employee e, Branch? branch) {
    if (e.weeklyOff != null) return weekdayNames[e.weeklyOff!];
    if (branch == null) return '—';
    final closed = [
      for (var i = 0; i < 7; i++)
        if (!branch.hours[i].open) weekdayNames[i],
    ];
    return closed.isEmpty ? 'None' : '${closed.join(', ')} (branch default)';
  }

  Widget _schedule(Employee e, Branch? branch) {
    final shift = branch == null
        ? null
        : shiftsFor(branch).where((s) => s.name == e.shift).firstOrNull;
    final minutes = shift == null
        ? 0
        : (shift.end - shift.start + 24 * 60) % (24 * 60);
    final days = branch == null
        ? '—'
        : [
            for (var i = 0; i < 7; i++)
              if (branch.hours[i].open && e.weeklyOff != i) weekdayShort[i],
          ].join(', ');
    return _section(
      'Assigned schedule',
      note: 'Effective ${employeeDateFormat.format(e.joiningDate)}',
      [
        FactTile(label: 'Shift', value: e.shift),
        FactTile(
          label: 'Hours',
          value: shift == null
              ? '—'
              : shiftLabel(shift).split('(').last.replaceAll(')', ''),
          mono: true,
        ),
        FactTile(
          label: 'Expected',
          value: minutes == 0
              ? '—'
              : '${minutes ~/ 60}h ${(minutes % 60).toString().padLeft(2, '0')}m / day',
          mono: true,
        ),
        FactTile(label: 'Working days', value: days),
        FactTile(label: 'Weekly off', value: _weeklyOff(e, branch)),
        FactTile(
          label: 'Source',
          value: 'Inherited from ${branch?.name ?? 'the'} branch',
        ),
      ],
    );
  }

  Widget _account(Employee e, DateTime now, bool canEdit) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _section(
        'Sign-in',
        trailing:
            canEdit &&
                e.status.isEmployed &&
                e.accountStatus != AccountStatus.signedIn &&
                e.workEmail.isNotEmpty
            ? AppButton(
                label: e.accountStatus == AccountStatus.noAccount
                    ? 'Send invite'
                    : 'Resend invite',
                size: AppButtonSize.small,
                variant: AppButtonVariant.secondary,
                onPressed: () => _run(
                  () => ref.read(employeesProvider.notifier).resendInvites([
                    e.id,
                  ]),
                  'Invitation sent to ${e.workEmail}',
                ),
              )
            : null,
        [
          FactTile(label: 'Account status', value: e.accountStatus.label),
          FactTile(
            label: 'Last sign-in',
            value: e.lastSignInAt == null
                ? 'Never'
                : DateFormat('d MMM y, HH:mm').format(e.lastSignInAt!),
            mono: e.lastSignInAt != null,
          ),
          const FactTile(label: 'Sign-in method', value: 'Email + password'),
          FactTile(
            label: 'Two-step verification',
            value: e.role.requiresTwoStep
                ? 'Required for this role'
                : 'Not enabled',
          ),
        ],
      ),
      const SizedBox(height: AppSpacing.lg),
      _section('Access', [
        FactTile(label: 'Role', value: e.role.label),
        FactTile(
          label: 'Scope',
          value: switch (e.role.scope) {
            DataScope.organization => 'All branches',
            DataScope.assignedBranches => 'Assigned branches',
            DataScope.ownTeam => 'Own team',
            DataScope.ownRecords => 'Own records',
          },
        ),
        FactTile(
          label: 'Invitation',
          value: switch (e.accountStatus) {
            AccountStatus.signedIn => 'Accepted',
            AccountStatus.invited =>
              e.invitedAt == null
                  ? 'Sent'
                  : 'Sent ${employeeDateFormat.format(e.invitedAt!)}',
            AccountStatus.inviteExpired => 'Expired — resend it',
            AccountStatus.noAccount => 'Not invited',
          },
        ),
        const FactTile(
          label: 'Password',
          value: 'Never displayed',
          locked: true,
        ),
      ]),
    ],
  );
}

class _AttendanceTab extends ConsumerWidget {
  const _AttendanceTab({required this.employee});

  final Employee employee;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final book = ref.watch(attendanceBookProvider).value;
    if (book == null) {
      return const LoadingSkeleton(
        label: 'Loading attendance',
        child: SkeletonList(rows: 4),
      );
    }
    final today = book.todayFor(employee);
    final first = DateTime(today.year, today.month);
    final days = DateTime(today.year, today.month + 1, 0).day;
    const legend = [
      DayStatus.present,
      DayStatus.late,
      DayStatus.halfDay,
      DayStatus.absent,
      DayStatus.onLeave,
      DayStatus.holiday,
      DayStatus.weeklyOff,
      DayStatus.missingPunch,
    ];
    final canSeeRecords =
        ref
            .watch(sessionProvider)
            ?.permissions
            .canView(PermissionModule.attendance) ??
        false;
    return AppCard(
      header: CardHeader(
        title: DateFormat('MMMM y').format(today),
        subtitle:
            'Holidays and weekly offs come from ${book.branchOf(employee)?.name ?? 'the branch'}.',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.xs,
            children: [
              for (final st in legend)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _CalendarCode(status: st, size: 22),
                    const SizedBox(width: 4),
                    Text(st.label, style: AppTypography.helper),
                  ],
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          LayoutBuilder(
            builder: (context, c) {
              final cell = ((c.maxWidth - 6 * 6) / 7).clamp(32.0, 96.0);
              final height = (cell * 0.7).clamp(40.0, 72.0);
              return Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final w in weekdayShort)
                    SizedBox(
                      width: cell,
                      child: Text(
                        w,
                        textAlign: TextAlign.center,
                        style: AppTypography.helper,
                      ),
                    ),
                  for (var i = 0; i < first.weekday - 1; i++)
                    SizedBox(width: cell, height: height),
                  for (var d = 1; d <= days; d++)
                    () {
                      final date = DateTime(today.year, today.month, d);
                      final r = book.day(employee, date);
                      final (bg, fg, border) = cellStyle(r.status);
                      final isToday = date == today;
                      return Semantics(
                        label:
                            '$d ${DateFormat('MMMM').format(date)}: ${r.holidayName ?? r.status.label}',
                        excludeSemantics: true,
                        child: InkWell(
                          onTap: canSeeRecords && !date.isAfter(today)
                              ? () => context.go(
                                  '${AppRoutes.attendanceRecords}?date=${isoDate(date)}&branch=${employee.branchId}',
                                )
                              : null,
                          child: Container(
                            width: cell,
                            height: height,
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: bg == Colors.transparent
                                  ? AppColors.surface
                                  : bg,
                              border: isToday
                                  ? Border.all(
                                      color: AppColors.primary,
                                      width: 2,
                                    )
                                  : (border ??
                                        Border.all(
                                          color: bg == Colors.transparent
                                              ? AppColors.border
                                              : Colors.transparent,
                                        )),
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                            ),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.topLeft,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '$d',
                                    style: AppTypography.helper.copyWith(
                                      fontSize: 11,
                                      color: fg == AppColors.surface
                                          ? fg
                                          : null,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    isToday && r.status.code.isEmpty
                                        ? 'Today'
                                        : r.status.code,
                                    style: AppTypography.helper.copyWith(
                                      color: isToday ? AppColors.primary : fg,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }(),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _CalendarCode extends StatelessWidget {
  const _CalendarCode({required this.status, required this.size});

  final DayStatus status;
  final double size;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, border) = cellStyle(status);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        border: border,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        status.code,
        style: AppTypography.helper.copyWith(
          color: fg,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// This month's attendance in four numbers (board S42 "At a glance").
class _AtAGlance extends ConsumerWidget {
  const _AtAGlance({required this.employee});

  final Employee employee;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final book = ref.watch(attendanceBookProvider).value;
    final today = book?.todayFor(employee);
    final days = book == null
        ? const <DayRecord>[]
        : book.range(employee, DateTime(today!.year, today.month), today);
    final scheduled = days
        .where((d) => d.scheduled && d.status != DayStatus.notYet)
        .length;
    final present = days.where((d) => d.status.attended).length;
    final late = days.where((d) => d.lateMinutes > 0).length;
    final worked = days.where((d) => d.workedMinutes > 0).toList();
    final avg = worked.isEmpty
        ? 0
        : worked.fold(0, (s, d) => s + d.workedMinutes) ~/ worked.length;
    return AppCard(
      header: CardHeader(
        title: 'At a glance',
        subtitle: today == null ? null : DateFormat('MMMM').format(today),
      ),
      child: ResponsiveGrid(
        minItemWidth: 140,
        maxColumns: 4,
        spacing: AppSpacing.lg,
        children: [
          FactTile(
            label: 'Present days',
            value: book == null ? '—' : '$present of $scheduled',
            mono: true,
          ),
          FactTile(
            label: 'Late arrivals',
            value: book == null ? '—' : '$late',
            mono: true,
          ),
          FactTile(
            label: 'Avg. worked',
            value: book == null || avg == 0 ? '—' : formatMinutes(avg),
            mono: true,
          ),
          FactTile(
            label: 'Leave taken',
            value: () {
              final leave = ref.watch(leaveBookProvider).value;
              if (leave == null || today == null) return '—';
              final d = leave
                  .takenByType(
                    [employee],
                    DateTime(today.year, today.month),
                    today,
                  )
                  .values
                  .fold(0.0, (s, v) => s + v);
              return dayCount(d);
            }(),
            mono: true,
          ),
        ],
      ),
    );
  }
}

class _LeaveTab extends ConsumerWidget {
  const _LeaveTab({required this.employee, required this.branch});

  final Employee employee;
  final Branch? branch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final book = ref.watch(leaveBookProvider).value;
    final session = ref.watch(sessionProvider);
    if (book == null) {
      return const LoadingSkeleton(
        label: 'Loading leave',
        child: SkeletonList(rows: 4),
      );
    }
    final year = book.today.year;
    final balances = book.balances(employee, year);
    if (balances.isEmpty) {
      return AppCard(
        child: EmptyState(
          icon: Icons.event_available_outlined,
          title: 'No leave balances',
          message:
              '${branch?.name ?? 'This branch'} offers no leave types with a balance.',
        ),
      );
    }
    final canAdjust =
        session?.permissions.can(
          PermissionModule.leave,
          PermissionAction.edit,
        ) ??
        false;
    final requests = book.requestsOf(employee);
    String n(double v) => v.toStringAsFixed(1);
    String signed(double v) => v > 0 ? '+${n(v)}' : n(v);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          header: CardHeader(
            title: 'Balances · $year',
            subtitle: 'Pending requests are already held.',
            trailing: canAdjust
                ? AppButton(
                    label: 'Adjust balance…',
                    size: AppButtonSize.small,
                    variant: AppButtonVariant.secondary,
                    onPressed: () => showSidePanel<void>(
                      context,
                      title: 'Adjust balance',
                      body: (_) => AdjustBalanceForm(
                        employee: employee,
                        types: [for (final b in balances) b.type],
                        year: year,
                      ),
                    ),
                  )
                : null,
          ),
          padding: EdgeInsets.zero,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('TYPE')),
                DataColumn(label: Text('GRANTED'), numeric: true),
                DataColumn(label: Text('USED'), numeric: true),
                DataColumn(label: Text('PENDING'), numeric: true),
                DataColumn(label: Text('ADJUSTED'), numeric: true),
                DataColumn(label: Text('AVAILABLE'), numeric: true),
              ],
              rows: [
                for (final b in balances)
                  DataRow(
                    cells: [
                      DataCell(Text(b.type.name)),
                      DataCell(Text(n(b.granted), style: AppTypography.code)),
                      DataCell(Text(n(b.used), style: AppTypography.code)),
                      DataCell(Text(n(b.pending), style: AppTypography.code)),
                      DataCell(
                        Text(
                          signed(b.adjusted + b.carried),
                          style: AppTypography.code,
                        ),
                      ),
                      DataCell(
                        Text(
                          n(b.available),
                          style: AppTypography.code.copyWith(
                            color: b.available < 0
                                ? AppColors.danger
                                : AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
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
          header: const CardHeader(title: 'Requests'),
          padding: EdgeInsets.zero,
          child: requests.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(AppSpacing.lg),
                  child: Text('No requests yet.', style: AppTypography.small),
                )
              : Column(
                  children: [
                    for (final r in requests.take(8))
                      InkWell(
                        onTap:
                            session?.permissions.canView(
                                  PermissionModule.leave,
                                ) ??
                                false
                            ? () => context.go(
                                '${AppRoutes.leave}?request=${r.id}',
                              )
                            : null,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.lg,
                            vertical: 10,
                          ),
                          decoration: const BoxDecoration(
                            border: Border(
                              top: BorderSide(color: AppColors.divider),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      requestTitle(book, r),
                                      style: AppTypography.bodyStrong,
                                    ),
                                    Text(
                                      '${r.id} · ${dayCount(book.daysOf(r))}',
                                      style: AppTypography.helper,
                                    ),
                                  ],
                                ),
                              ),
                              Flexible(child: LeaveStatusBadge(r.status)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _CustomFieldsTab extends ConsumerWidget {
  const _CustomFieldsTab({required this.employee, required this.session});

  final Employee employee;
  final AppSession session;

  String _value(Object? v) => switch (v) {
    null => 'Not provided',
    final DateTime d => employeeDateFormat.format(d),
    final List<Object?> l => l.isEmpty ? 'Not provided' : l.join(', '),
    final bool b => b ? 'Yes' : 'No',
    final String s when s.trim().isEmpty => 'Not provided',
    _ => '$v',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final self = session.employeeId == employee.code;
    final fields = [
      for (final f
          in ref.watch(customFieldsProvider).value ?? const <CustomField>[])
        if (f.appliesToEmployee(employee) &&
            f.canView(session.role, self: self))
          f,
    ];
    if (fields.isEmpty) {
      return const AppCard(
        child: EmptyState(
          icon: Icons.tune_outlined,
          title: 'No custom fields',
          message:
              'No organization fields apply to this person, or your role can’t see them.',
        ),
      );
    }
    return AppCard(
      header: CardHeader(
        title: 'Organization fields',
        subtitle:
            '${fields.length} ${fields.length == 1 ? 'field applies' : 'fields apply'} '
            'to ${employee.department}',
      ),
      child: ResponsiveGrid(
        minItemWidth: 220,
        maxColumns: 3,
        spacing: AppSpacing.lg,
        children: [
          for (final f in fields)
            FactTile(
              label: f.label,
              value: _value(employee.customValues[f.key]),
              locked: f.sensitive,
              mono:
                  f.type == CustomFieldType.shortText &&
                  f.key.contains('number'),
              trailing: f.required && isBlankValue(employee.customValues[f.key])
                  ? const Padding(
                      padding: EdgeInsets.only(left: AppSpacing.sm),
                      child: StatusBadge(
                        label: 'Incomplete',
                        tone: StatusTone.warning,
                      ),
                    )
                  : null,
            ),
        ],
      ),
    );
  }
}

class _ActivityTab extends StatelessWidget {
  const _ActivityTab({required this.employee});

  final Employee employee;

  @override
  Widget build(BuildContext context) {
    final format = DateFormat('d MMM y, HH:mm');
    return AppCard(
      header: const CardHeader(
        title: 'Activity',
        subtitle:
            'Changes to this record. The organisation-wide audit log arrives in Phase 7.',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final a in employee.activity)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          a.text,
                          style: AppTypography.small.copyWith(
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          '${a.by} · ${format.format(a.at)}',
                          style: AppTypography.helper,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
