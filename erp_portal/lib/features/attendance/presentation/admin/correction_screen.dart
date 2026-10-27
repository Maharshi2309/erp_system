import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/router/route_names.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/permissions/permissions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/zoned_time.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/page_header.dart';
import '../../../../core/widgets/selection_controls.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../auth/presentation/widgets/auth_layout.dart';
import '../../../employees/domain/employee.dart';
import '../../../employees/presentation/providers/employee_providers.dart';
import '../../../employees/presentation/widgets/employee_widgets.dart';
import '../../../organization/presentation/providers/organization_providers.dart';
import '../../domain/attendance.dart';
import '../../domain/attendance_book.dart';
import '../attendance_providers.dart';
import '../attendance_widgets.dart';
import 'attendance_section.dart';

/// One editable row of the punches table.
class _Row {
  _Row({required this.session, required this.kind, this.punch});

  final int session;
  final PunchKind kind;

  /// The original event; null for a missing one.
  final Punch? punch;

  /// Local minutes after midnight of the work day (may exceed 24h for a
  /// night shift's morning punch-out).
  int? minutes;
  bool editing = false;

  bool get isMissing => punch == null;
}

/// Board S55 — correct one employee's day.
class CorrectionScreen extends ConsumerStatefulWidget {
  const CorrectionScreen({
    super.key,
    required this.employeeId,
    required this.date,
  });

  final String employeeId;
  final DateTime? date;

  @override
  ConsumerState<CorrectionScreen> createState() => _CorrectionScreenState();
}

class _CorrectionScreenState extends ConsumerState<CorrectionScreen> {
  List<_Row>? _rows;
  final _reason = TextEditingController();
  String? _reasonError;
  bool _busy = false;
  Correction? _saved;
  String? _formError;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  int _localMinutes(DateTime instant, DayRecord r) {
    final t = wallTime(instant, r.zone);
    return dateOnly(t).difference(r.date).inDays * 24 * 60 +
        t.hour * 60 +
        t.minute;
  }

  List<_Row> _initialRows(DayRecord r, CorrectionRequest? request) {
    final rows = <_Row>[];
    for (var i = 0; i < r.sessions.length; i++) {
      final s = r.sessions[i];
      rows.add(_Row(session: i + 1, kind: PunchKind.punchIn, punch: s.inPunch));
      rows.add(
        _Row(session: i + 1, kind: PunchKind.punchOut, punch: s.outPunch),
      );
    }
    if (r.sessions.isEmpty) {
      rows
        ..add(_Row(session: 1, kind: PunchKind.punchIn))
        ..add(_Row(session: 1, kind: PunchKind.punchOut));
    }
    for (final row in rows.where((x) => x.isMissing)) {
      final proposed = request != null && request.kind == row.kind
          ? request.proposedAt
          : null;
      final fallback = row.kind == PunchKind.punchIn
          ? r.shift?.start
          : r.shift?.end;
      final at = proposed ?? fallback;
      row
        ..minutes = at == null ? null : _localMinutes(at, r)
        ..editing = true;
    }
    for (final row in rows.where((x) => !x.isMissing)) {
      row.minutes = _localMinutes(row.punch!.at, r);
    }
    return rows;
  }

  DateTime _instant(DayRecord r, int minutes) =>
      instantOf(r.date.add(Duration(minutes: minutes)), r.zone);

  /// Changes for rows that are new or moved.
  List<CorrectionChange> _changes(DayRecord r) => [
    for (final row in _rows!)
      if (row.minutes != null &&
          (row.isMissing ||
              (row.editing && _instant(r, row.minutes!) != row.punch!.at)))
        CorrectionChange(
          kind: row.kind,
          at: _instant(r, row.minutes!),
          replaces: row.punch?.id,
        ),
  ];

  /// "Punch-out must be after the 14:02 punch-in." or null.
  String? _orderError(DayRecord r) {
    final bySession = <int, List<_Row>>{};
    for (final row in _rows!) {
      (bySession[row.session] ??= []).add(row);
    }
    for (final rows in bySession.values) {
      final inRow = rows.where((x) => x.kind == PunchKind.punchIn).firstOrNull;
      final outRow = rows
          .where((x) => x.kind == PunchKind.punchOut)
          .firstOrNull;
      if (inRow?.minutes == null || outRow?.minutes == null) continue;
      if (outRow!.minutes! <= inRow!.minutes!) {
        return outRow.isMissing || outRow.editing
            ? 'Punch-out must be after the ${_fmt(inRow.minutes!)} punch-in.'
            : 'Punch-in must be before the ${_fmt(outRow.minutes!)} punch-out.';
      }
    }
    return null;
  }

  static String _fmt(int m) =>
      '${((m ~/ 60) % 24).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

  Future<void> _submit(
    DayRecord r,
    bool second,
    String approver,
    CorrectionRequest? request,
  ) async {
    final changes = _changes(r);
    setState(() {
      _reasonError = _reason.text.trim().length < 5
          ? 'Give a reason of at least 5 characters.'
          : null;
      _formError = changes.isEmpty
          ? 'Change at least one punch, or cancel.'
          : (_rows!.any((x) => x.isMissing && x.minutes == null)
                ? 'Enter the missing time.'
                : _orderError(r));
    });
    if (_reasonError != null || _formError != null) return;
    final self = ref.read(selfEmployeeProvider);
    setState(() => _busy = true);
    try {
      final saved = await ref
          .read(attendanceDataProvider.notifier)
          .correct(
            Correction(
              id: '',
              employeeId: r.employee.id,
              workDate: r.date,
              changes: changes,
              reason: _reason.text.trim(),
              by: ref.read(sessionProvider)!.displayName,
              byEmployeeId: self?.id,
              createdAt: ref.read(orgNowProvider)(),
              approverNote: second ? approver : '',
              requestId: request?.id,
            ),
            needsSecondApproval: second,
          );
      if (mounted) setState(() => _saved = saved);
    } on ValidationFailure catch (f) {
      if (mounted) {
        setState(() => _reasonError = f.fieldErrors['reason'] ?? f.message);
      }
    } on Failure catch (f) {
      if (mounted) setState(() => _formError = f.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AttendanceSection(
      current: AppRoutes.missingPunches,
      body: (context, scope) {
        final book = scope.book;
        final employee = scope.people
            .where((e) => e.id == widget.employeeId)
            .firstOrNull;
        if (employee == null || widget.date == null) {
          return ErrorState(
            headline: '404',
            title: 'This record isn’t here',
            message:
                'The person may be outside the branches you can see, or the link is mistyped.',
            actions: [
              AppButton(
                label: 'Back to queue',
                onPressed: () => context.go(AppRoutes.missingPunches),
              ),
            ],
          );
        }
        if (!scope.session.permissions.can(
          PermissionModule.attendance,
          PermissionAction.correct,
        )) {
          return const ErrorState(
            title: 'You can’t correct attendance',
            message: 'Your role can view attendance only.',
          );
        }
        final r = book.day(employee, widget.date!);
        final request = book.openRequest(employee, r.date);
        _rows ??= _initialRows(r, request);
        final everyone =
            ref.watch(employeesProvider).value ?? const <Employee>[];
        final manager = everyone
            .where((e) => e.id == employee.managerId)
            .firstOrNull;
        final self = ref.watch(selfEmployeeProvider);
        final second = needsSecondApproval(scope.session, employee, self);
        final approver = approverFor(everyone);

        // Preview: the same day with this correction applied.
        final changes = _changes(r);
        final orderError = _orderError(r);
        final preview = changes.isEmpty || orderError != null
            ? null
            : AttendanceBook(
                data: AttendanceData(
                  punches: book.data.punches,
                  corrections: [
                    ...book.data.corrections,
                    Correction(
                      id: 'preview',
                      employeeId: employee.id,
                      workDate: r.date,
                      changes: changes,
                      reason: '',
                      by: '',
                      createdAt: r.date,
                    ),
                  ],
                ),
                employees: book.employees,
                branches: book.branches,
                orgZone: book.orgZone,
                now: book.now,
              ).day(employee, r.date);

        if (_saved case final saved?) {
          return AppCard(
            child: EmptyState(
              icon: Icons.check_circle_outline,
              iconTone: AppColors.success,
              title: saved.status == CorrectionStatus.pending
                  ? 'Sent for approval'
                  : 'Correction saved',
              message: saved.status == CorrectionStatus.pending
                  ? 'Original punches are kept. ${saved.approverNote} will review it; the record stays “Missing punch” until approved.'
                  : 'Original punches are kept alongside the correction in the history.',
              actions: [
                AppButton(
                  label: 'Back to queue',
                  onPressed: () => context.go(AppRoutes.missingPunches),
                ),
              ],
            ),
          );
        }

        final punches = AppCard(
          header: const CardHeader(title: 'Punches'),
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final row in _rows!) _punchRow(row, r),
              if (_formError ?? orderError case final e?)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Text(
                    e,
                    style: AppTypography.small.copyWith(
                      color: AppColors.danger,
                    ),
                  ),
                ),
              const Divider(height: AppSpacing.xl),
              Wrap(
                spacing: AppSpacing.xl,
                runSpacing: AppSpacing.md,
                children: [
                  _Stat(
                    'Worked',
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: formatMinutes(r.workedMinutes),
                            style: preview == null
                                ? null
                                : const TextStyle(
                                    decoration: TextDecoration.lineThrough,
                                    color: AppColors.textMuted,
                                  ),
                          ),
                          if (preview != null)
                            TextSpan(
                              text: '  ${formatMinutes(preview.workedMinutes)}',
                            ),
                        ],
                      ),
                      style: AppTypography.code.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  _Stat(
                    'Expected',
                    Text(
                      formatMinutes(r.expectedMinutes),
                      style: AppTypography.code.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  _Stat(
                    'Status after correction',
                    DayStatusBadge(preview?.status ?? r.status),
                  ),
                ],
              ),
            ],
          ),
        );

        final form = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            punches,
            const SizedBox(height: AppSpacing.lg),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppTextField(
                    label: 'Reason for correction',
                    controller: _reason,
                    isRequired: true,
                    errorText: _reasonError,
                    helperText:
                        'Saved in the history and shown to the employee.',
                    onChanged: (_) => setState(() => _reasonError = null),
                  ),
                  if (second) ...[
                    const SizedBox(height: AppSpacing.md),
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: AppColors.warningSoft,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                      child: Text(
                        'Corrections by an employee’s own manager need a second person to approve. '
                        'You’re ${employee.firstName}’s manager, so this goes to $approver. '
                        'The record stays “${r.status.label}” until approved.',
                        style: AppTypography.small.copyWith(
                          color: AppColors.warningText,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: AppSpacing.sm,
                    children: [
                      AppButton(
                        label: 'Cancel',
                        variant: AppButtonVariant.secondary,
                        onPressed: () => context.go(AppRoutes.missingPunches),
                      ),
                      AppButton(
                        label: second ? 'Send for approval' : 'Save correction',
                        busy: _busy,
                        busyLabel: second ? 'Sending…' : 'Saving…',
                        onPressed: () => _submit(r, second, approver, request),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );

        final side = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      EmployeeAvatar(employee: employee, size: 40),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // A link only for roles that may open profiles.
                            if (scope.session.permissions.canView(
                              PermissionModule.employees,
                            ))
                              TextLink(
                                employee.fullName,
                                onTap: () =>
                                    context.go(AppRoutes.employee(employee.id)),
                              )
                            else
                              Text(
                                employee.fullName,
                                style: AppTypography.bodyStrong,
                              ),
                            Text(
                              '${employee.code} · ${employee.designation}',
                              style: AppTypography.helper,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  FactTile(
                    label: 'Manager',
                    value: manager?.fullName ?? 'The owner',
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  FactTile(
                    label: 'This month',
                    value:
                        '${book.range(employee, DateTime(r.date.year, r.date.month), book.todayFor(employee)).where((d) => d.status == DayStatus.missingPunch).length} missing punches',
                  ),
                ],
              ),
            ),
            if (request != null) ...[
              const SizedBox(height: AppSpacing.lg),
              AppCard(
                header: const CardHeader(title: 'Employee’s request'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FactTile(
                      label:
                          'Proposed ${request.kind == PunchKind.punchIn ? 'punch-in' : 'punch-out'}',
                      value: clockTime(request.proposedAt, r.zone),
                      mono: true,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      '“${request.message}”',
                      style: AppTypography.small.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Submitted ${DateFormat('d MMM, HH:mm').format(request.createdAt)}',
                      style: AppTypography.helper,
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            AppCard(
              header: const CardHeader(title: 'Correction history'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (book.correctionsFor([employee]).isEmpty)
                    const Text(
                      'No earlier corrections.',
                      style: AppTypography.small,
                    ),
                  for (final c in book.correctionsFor([employee]).take(5))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        '${DateFormat('d MMM').format(c.workDate)} · ${c.changes.map((x) => '${x.kind == PunchKind.punchIn ? 'punch-in' : 'punch-out'} ${x.replaces == null ? 'added' : 'moved to'} ${clockTime(x.at, r.zone)}').join(', ')} by ${c.by} · ${c.status.label.toLowerCase()}',
                        style: AppTypography.small,
                      ),
                    ),
                ],
              ),
            ),
          ],
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Breadcrumbs(
              items: [
                BreadcrumbItem(
                  'Attendance',
                  onTap: () => context.go(AppRoutes.attendance),
                ),
                BreadcrumbItem(
                  'Missing punches',
                  onTap: () => context.go(AppRoutes.missingPunches),
                ),
                BreadcrumbItem(
                  '${employee.fullName} · ${DateFormat('d MMM').format(r.date)}',
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            AttendanceHeader(
              title: 'Correct attendance',
              subtitle:
                  '${DateFormat('EEEE, d MMMM y').format(r.date)} · shift ${r.shift?.label ?? '—'} · ${book.branchOf(employee)?.name ?? ''}',
            ),
            const SizedBox(height: AppSpacing.lg),
            LayoutBuilder(
              builder: (context, c) => c.maxWidth < 900
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        form,
                        const SizedBox(height: AppSpacing.lg),
                        side,
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: form),
                        const SizedBox(width: AppSpacing.lg),
                        SizedBox(width: 340, child: side),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _punchRow(_Row row, DayRecord r) {
    final label =
        'Session ${row.session} · ${row.kind == PunchKind.punchIn ? 'in' : 'out'}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.sm,
        children: [
          SizedBox(width: 130, child: Text(label, style: AppTypography.label)),
          SizedBox(
            width: 70,
            child: Text(
              row.isMissing ? 'missing' : clockTime(row.punch!.at, r.zone),
              style: AppTypography.code.copyWith(
                color: row.isMissing ? AppColors.danger : AppColors.textPrimary,
              ),
            ),
          ),
          if (row.editing)
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 170, maxWidth: 260),
              child: TimeField(
                minutes: (row.minutes ?? 0) % (24 * 60),
                hasError: _orderError(r) != null,
                semanticLabel:
                    'Corrected ${row.kind == PunchKind.punchIn ? 'punch-in' : 'punch-out'} time',
                onChanged: (m) => setState(() {
                  // Keep a night shift's morning punch on the next day.
                  final base = (row.minutes ?? 0) ~/ (24 * 60) * 24 * 60;
                  final inRow = _rows!
                      .where(
                        (x) =>
                            x.session == row.session &&
                            x.kind == PunchKind.punchIn,
                      )
                      .firstOrNull;
                  var value = base + m;
                  if (row.kind == PunchKind.punchOut &&
                      inRow?.minutes != null &&
                      value <= inRow!.minutes! &&
                      (r.shift?.label ?? '').startsWith('Night')) {
                    value += 24 * 60;
                  }
                  row.minutes = value;
                  _formError = null;
                }),
              ),
            )
          else
            const Text('unchanged', style: AppTypography.helper),
          Text(
            row.editing ? 'Manual · you' : (row.punch?.source.label ?? ''),
            style: AppTypography.helper,
          ),
          if (!row.isMissing)
            TextLink(
              row.editing ? 'Undo' : 'Change',
              onTap: () => setState(() {
                row.editing = !row.editing;
                row.minutes = _localMinutes(row.punch!.at, r);
              }),
            ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.child);

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: AppTypography.helper),
      const SizedBox(height: 2),
      child,
    ],
  );
}
