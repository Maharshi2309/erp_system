import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../app/router/route_names.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/permissions/permissions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_overlays.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../attendance/presentation/admin/attendance_section.dart';
import '../../../dashboard/presentation/dashboard_widgets.dart';
import '../../../employees/presentation/widgets/employee_widgets.dart';
import '../../../organization/presentation/providers/organization_providers.dart';
import '../../domain/leave.dart';
import '../../domain/leave_book.dart';
import '../leave_providers.dart';
import '../leave_widgets.dart';
import 'leave_section.dart';

enum _Filter { pending, decided, all }

/// Board S57 — the approvals inbox with a detail panel.
class LeaveApprovalsScreen extends ConsumerStatefulWidget {
  const LeaveApprovalsScreen({super.key, this.requestId});

  /// Opens with this request selected (links from Requests and dashboards).
  final String? requestId;

  @override
  ConsumerState<LeaveApprovalsScreen> createState() =>
      _LeaveApprovalsScreenState();
}

class _LeaveApprovalsScreenState extends ConsumerState<LeaveApprovalsScreen> {
  late _Filter _filter = widget.requestId == null
      ? _Filter.pending
      : _Filter.all;
  String _search = '';
  bool _byStart = false;
  late String? _selected = widget.requestId;

  /// Phones show the list or the detail, not both.
  late bool _detailOpen = widget.requestId != null;

  @override
  Widget build(BuildContext context) => LeaveSection(
    current: AppRoutes.leave,
    body: (context, scope) {
      final book = scope.book;
      final now = ref.watch(orgNowProvider)();
      final q = _search.trim().toLowerCase();
      final list =
          [
            for (final r in scope.requests)
              if (switch (_filter) {
                    _Filter.pending => r.status == LeaveStatus.pending,
                    _Filter.decided => r.status != LeaveStatus.pending,
                    _Filter.all => true,
                  } &&
                  (q.isEmpty ||
                      r.id.toLowerCase().contains(q) ||
                      (book.person(r.employeeId)?.fullName ?? '')
                          .toLowerCase()
                          .contains(q)))
                r,
          ]..sort(
            (a, b) => _byStart
                ? a.from.compareTo(b.from)
                : (_filter == _Filter.pending
                      ? a.createdAt.compareTo(b.createdAt)
                      : b.createdAt.compareTo(a.createdAt)),
          );
      final waiting = scope.requests
          .where(
            (r) => book.canDecide(
              r,
              role: scope.session.role,
              self: scope.self,
              branchIds: scope.session.branchIds,
            ),
          )
          .length;
      final selected =
          list.where((r) => r.id == _selected).firstOrNull ??
          scope.requests.where((r) => r.id == _selected).firstOrNull ??
          list.firstOrNull;
      final scopeLabel = scope.session.branchIds.isEmpty
          ? 'All branches'
          : scope.session.scopeLabel;

      final header = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: const Text(
              'Leave approvals',
              style: AppTypography.pageTitle,
            ),
          ),
          Text(
            '$waiting waiting for you · $scopeLabel',
            style: AppTypography.small,
          ),
        ],
      );
      final filters = Wrap(
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SegmentToggle<_Filter>(
            label: 'Show',
            options: const [
              (_Filter.pending, 'Pending'),
              (_Filter.decided, 'Decided'),
              (_Filter.all, 'All'),
            ],
            value: _filter,
            onChanged: (f) => setState(() => _filter = f),
          ),
          SizedBox(
            width: 240,
            child: SearchBox(
              label: 'Search requests',
              hint: 'Name or request ID',
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
          SizedBox(
            width: 170,
            child: DashboardSelect<bool>(
              label: 'Sort',
              value: _byStart,
              options: const [(false, 'Oldest first'), (true, 'Start date')],
              onChanged: (v) => setState(() => _byStart = v ?? false),
            ),
          ),
        ],
      );

      final listCard = AppCard(
        padding: EdgeInsets.zero,
        child: list.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: EmptyState(
                  icon: Icons.inbox_outlined,
                  title: _filter == _Filter.pending
                      ? 'Nothing waiting'
                      : 'No requests',
                  message: _filter == _Filter.pending
                      ? 'New leave requests appear here.'
                      : 'Nothing matches these filters.',
                ),
              )
            : Column(
                children: [
                  for (final r in list)
                    _ListItem(
                      book: book,
                      request: r,
                      now: now,
                      selected: r.id == selected?.id,
                      own: r.employeeId == scope.self?.id,
                      onTap: () => setState(() {
                        _selected = r.id;
                        _detailOpen = true;
                      }),
                    ),
                ],
              ),
      );

      return LayoutBuilder(
        builder: (context, c) {
          final wide = c.maxWidth >= 900;
          final detail = selected == null
              ? null
              : LeaveDecisionPanel(
                  key: ValueKey(selected.id),
                  scope: scope,
                  request: selected,
                  onBack: wide
                      ? null
                      : () => setState(() => _detailOpen = false),
                );
          if (!wide && _detailOpen && detail != null) return detail;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              const SizedBox(height: AppSpacing.md),
              filters,
              const SizedBox(height: AppSpacing.md),
              if (wide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 400, child: listCard),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(
                      child:
                          detail ??
                          const AppCard(
                            child: EmptyState(
                              icon: Icons.touch_app_outlined,
                              title: 'Choose a request',
                              message: 'Its details and actions show here.',
                            ),
                          ),
                    ),
                  ],
                )
              else
                listCard,
            ],
          );
        },
      );
    },
  );
}

/// "Routed to HR" for the viewer's own request, otherwise the status.
Widget statusFor(LeaveRequest r, {required bool own}) {
  if (own && r.status == LeaveStatus.pending) {
    return const StatusBadge(label: 'Routed to HR', tone: StatusTone.info);
  }
  return LeaveStatusBadge(r.status);
}

class _ListItem extends StatelessWidget {
  const _ListItem({
    required this.book,
    required this.request,
    required this.now,
    required this.selected,
    required this.own,
    required this.onTap,
  });

  final LeaveBook book;
  final LeaveRequest request;
  final DateTime now;
  final bool selected;
  final bool own;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final r = request;
    final e = book.person(r.employeeId);
    final old =
        r.status == LeaveStatus.pending &&
        now.difference(r.createdAt).inHours >= 36;
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFF7F8FE) : null,
            border: Border(
              left: BorderSide(
                color: selected ? AppColors.primary : Colors.transparent,
                width: 3,
              ),
              bottom: const BorderSide(color: AppColors.divider),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (e != null) EmployeeAvatar(employee: e, size: 32),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: AppSpacing.sm,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          e?.fullName ?? r.employeeId,
                          style: AppTypography.bodyStrong,
                        ),
                        Text(
                          sentAgo(r.createdAt, now),
                          style: AppTypography.helper.copyWith(
                            color: old ? AppColors.warningText : null,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      '${book.data.type(r.typeKey)?.name ?? r.typeKey} · ${leaveRange(r.from, r.to)}${r.half == HalfDay.full ? '' : ' (half)'}',
                      style: AppTypography.small,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    statusFor(r, own: own),
                    const SizedBox(height: 4),
                    Text(dayCount(book.daysOf(r)), style: AppTypography.code),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The detail of one request with its decision actions (board S57).
class LeaveDecisionPanel extends ConsumerWidget {
  const LeaveDecisionPanel({
    super.key,
    required this.scope,
    required this.request,
    this.onBack,
  });

  final LeaveScopeData scope;
  final LeaveRequest request;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final book = scope.book;
    final r = request;
    final e = book.person(r.employeeId);
    final type = book.data.type(r.typeKey);
    final days = book.daysOf(r);
    final own = r.employeeId == scope.self?.id;
    // Hidden when the role lost leave approval (D-53).
    final canDecide =
        scope.session.permissions.can(
          PermissionModule.leave,
          PermissionAction.approve,
        ) &&
        book.canDecide(
          r,
          role: scope.session.role,
          self: scope.self,
          branchIds: scope.session.branchIds,
        );
    final skipped = e == null || type == null
        ? const <LeaveDay>[]
        : book
              .countDays(e, type, r.from, r.to, r.half)
              .where((d) => d.counted == 0)
              .toList();
    final team = book.teamOff(r);
    final before = e == null || type == null || !type.tracksBalance
        ? null
        : book.balance(e, type.key, r.from.year, exceptRequest: r.id).available;
    final step = r.currentStep;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (onBack != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onBack,
                icon: const Icon(Icons.chevron_left),
                label: const Text('All requests'),
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (e != null) EmployeeAvatar(employee: e, size: 44),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        e?.fullName ?? r.employeeId,
                        style: AppTypography.sectionTitle,
                      ),
                    ),
                    Text(
                      [
                        if (e != null && e.designation.isNotEmpty)
                          e.designation,
                        if (e != null) e.code,
                        r.id,
                      ].join(' · '),
                      style: AppTypography.small,
                    ),
                  ],
                ),
              ),
              statusFor(r, own: own),
            ],
          ),
          const Divider(height: AppSpacing.xl),
          InfoRow('Leave type', type?.name ?? r.typeKey),
          InfoRow(
            'Dates',
            '${leaveRange(r.from, r.to)}${r.half == HalfDay.full ? '' : ' · ${r.half.label.toLowerCase()}'}',
          ),
          InfoRow('Duration', dayCount(days)),
          InfoRow('Submitted', DateFormat('d MMM, HH:mm').format(r.createdAt)),
          if (r.amendedFrom case (final f, final t))
            InfoRow('Originally', leaveRange(f, t)),
          if (r.reason.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Text(
                '“${r.reason}”',
                style: AppTypography.body.copyWith(fontStyle: FontStyle.italic),
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            children: [
              if (before != null)
                _Box(
                  title: 'Balance impact',
                  lines: [
                    ('Available now', dayCount(before), null),
                    (
                      r.status == LeaveStatus.approved
                          ? 'After this leave'
                          : 'After approval',
                      before - days < 0
                          ? 'Not enough · ${formatDays(before - days)}'
                          : dayCount(before - days),
                      before - days < 0 ? AppColors.danger : null,
                    ),
                  ],
                ),
              _Box(
                title: 'Team on these dates',
                lines: [
                  (
                    '${team.off} of ${team.team} in ${e?.department ?? 'the team'} already off',
                    '',
                    team.off > 0 ? AppColors.warningText : null,
                  ),
                ],
              ),
            ],
          ),
          if (skipped.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text(
                'Excludes ${_skippedText(skipped)}.',
                style: AppTypography.helper,
              ),
            ),
          const SizedBox(height: AppSpacing.md),
          if (own && r.status.isOpen)
            _Note(
              'This is your own request. It has been routed to ${step == null ? 'HR' : book.approverName(step)} — you can’t approve it yourself.',
            )
          else if (canDecide)
            DecisionActions(
              request: r,
              name: e?.fullName ?? 'The employee',
              days: days,
            )
          else if (r.status == LeaveStatus.pending && step != null)
            _Note('Waiting for ${book.approverName(step)}.')
          else if (r.status == LeaveStatus.changesRequested)
            _Note(
              'Changes requested: “${r.decisionNote}”. Waiting for ${e?.firstName ?? 'the employee'} to change or withdraw it.',
            ),
          const SizedBox(height: AppSpacing.lg),
          const Text('History', style: AppTypography.cardTitle),
          const SizedBox(height: AppSpacing.sm),
          for (final h in r.history.reversed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: MergeSemantics(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 104,
                      child: Text(
                        DateFormat('d MMM, HH:mm').format(h.at),
                        style: AppTypography.code.copyWith(fontSize: 12),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        h.by == 'System' ? h.text : '${h.text} · ${h.by}',
                        style: AppTypography.small.copyWith(
                          color: AppColors.textPrimary,
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

  static String _skippedText(List<LeaveDay> days) {
    final holidays = [
      for (final d in days)
        if (d.note.contains('holiday'))
          '${d.note.split(' — ').first} (${DateFormat('d MMM').format(d.date)})',
    ];
    final offs = days.where((d) => d.note.startsWith('Weekly off')).length;
    return [
      ...holidays,
      if (offs > 0) offs == 1 ? '1 weekly off' : '$offs weekly offs',
    ].join(' and ');
  }
}

class _Box extends StatelessWidget {
  const _Box({required this.title, required this.lines});

  final String title;
  final List<(String, String, Color?)> lines;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 320),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTypography.label),
          const SizedBox(height: 4),
          for (final (k, v, c) in lines)
            v.isEmpty
                ? Text(k, style: AppTypography.small.copyWith(color: c))
                : InfoRow(
                    k,
                    v,
                    valueStyle: AppTypography.small.copyWith(
                      color: c ?? AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Text(
        text,
        style: AppTypography.small.copyWith(color: AppColors.primaryHover),
      ),
    );
  }
}

enum _Mode { idle, rejecting, changes }

/// Approve, Request changes and Reject… with a required reason.
class DecisionActions extends ConsumerStatefulWidget {
  const DecisionActions({
    super.key,
    required this.request,
    required this.name,
    required this.days,
    this.allowChanges = true,
  });

  final LeaveRequest request;
  final String name;
  final double days;
  final bool allowChanges;

  @override
  ConsumerState<DecisionActions> createState() => _DecisionActionsState();
}

class _DecisionActionsState extends ConsumerState<DecisionActions> {
  _Mode _mode = _Mode.idle;
  final _note = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _run(Future<String> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final done = await action();
      if (mounted) showAppToast(context, done);
    } on Failure catch (f) {
      if (mounted) {
        setState(
          () => _error = f is ValidationFailure
              ? (f.fieldErrors['note'] ?? f.message)
              : f.message,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final notifier = ref.read(leaveDataProvider.notifier);
    final r = widget.request;
    final first = widget.name.split(' ').first;
    if (_mode != _Mode.idle) {
      final rejecting = _mode == _Mode.rejecting;
      final ok = _note.text.trim().length >= 3;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextField(
            label: rejecting ? 'Reason for rejection' : 'What should change?',
            isRequired: true,
            controller: _note,
            maxLines: 2,
            maxLength: 300,
            errorText: _error,
            helperText: 'Shown to $first.',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              AppButton(
                label: 'Cancel',
                variant: AppButtonVariant.secondary,
                onPressed: _busy
                    ? null
                    : () => setState(() {
                        _mode = _Mode.idle;
                        _note.clear();
                        _error = null;
                      }),
              ),
              AppButton(
                label: rejecting ? 'Reject request' : 'Send to $first',
                variant: rejecting
                    ? AppButtonVariant.danger
                    : AppButtonVariant.primary,
                busy: _busy,
                busyLabel: 'Saving…',
                onPressed: !ok
                    ? null
                    : () => _run(() async {
                        if (rejecting) {
                          await notifier.decide(
                            r,
                            approve: false,
                            note: _note.text,
                          );
                          return 'Rejected — ${widget.name} has been notified with your reason.';
                        }
                        await notifier.requestChanges(r, _note.text);
                        return 'Sent back to ${widget.name} for changes.';
                      }),
              ),
            ],
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(
              _error!,
              style: AppTypography.small.copyWith(color: AppColors.danger),
            ),
          ),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            AppButton(
              label: 'Reject…',
              variant: AppButtonVariant.secondary,
              onPressed: _busy
                  ? null
                  : () => setState(() => _mode = _Mode.rejecting),
            ),
            if (widget.allowChanges)
              AppButton(
                label: 'Request changes',
                variant: AppButtonVariant.secondary,
                onPressed: _busy
                    ? null
                    : () => setState(() => _mode = _Mode.changes),
              ),
            AppButton(
              label: 'Approve',
              busy: _busy,
              busyLabel: 'Saving…',
              onPressed: () => _run(() async {
                final saved = await notifier.decide(r, approve: true);
                return saved.status == LeaveStatus.approved
                    ? '✓ Approved — ${widget.name} has been notified. ${dayCount(widget.days)} deducted.'
                    : 'Approved — sent to the next approver.';
              }),
            ),
          ],
        ),
      ],
    );
  }
}
