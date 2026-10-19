import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/router/route_names.dart';
import '../../../core/errors/failure.dart';
import '../../../core/responsive/responsive_grid.dart';
import '../../../core/responsive/responsive_page.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_date_field.dart';
import '../../../core/widgets/app_dropdown_field.dart';
import '../../../core/widgets/app_overlays.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/selection_controls.dart';
import '../../../core/widgets/state_views.dart';
import '../../dashboard/presentation/dashboard_widgets.dart';
import '../../employees/domain/employee.dart';
import '../domain/leave.dart';
import '../domain/leave_book.dart';
import 'leave_providers.dart';
import 'leave_widgets.dart';

Widget _title(BuildContext context, String text, {String? back}) => Row(
  children: [
    if (back != null)
      IconButton(
        tooltip: 'Back',
        onPressed: () => context.go(back),
        icon: const Icon(Icons.chevron_left),
      ),
    Expanded(
      child: Semantics(
        header: true,
        child: Text(text, style: AppTypography.pageTitle),
      ),
    ),
  ],
);

/// Board S90 — balances, next leave and recent requests.
class MyLeaveScreen extends ConsumerWidget {
  const MyLeaveScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => withLeaveSelf(ref, (
    book,
    self,
  ) {
    final year = book.today.year;
    final balances = book.balances(self, year);
    final requests = book.requestsOf(self)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final next =
        requests
            .where(
              (r) =>
                  r.status == LeaveStatus.approved &&
                  !r.to.isBefore(book.today),
            )
            .toList()
          ..sort((a, b) => a.from.compareTo(b.from));

    return ResponsivePage(
      maxWidth: 960,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            children: [
              Semantics(
                header: true,
                child: const Text('My leave', style: AppTypography.pageTitle),
              ),
              Wrap(
                spacing: AppSpacing.sm,
                children: [
                  AppButton(
                    label: 'History',
                    variant: AppButtonVariant.secondary,
                    onPressed: () => context.go(AppRoutes.leaveHistory),
                  ),
                  AppButton(
                    label: 'Apply for leave',
                    icon: Icons.add,
                    onPressed: () => context.go(AppRoutes.applyLeave),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            header: CardHeader(title: 'Balances · $year', subtitle: 'in days'),
            child: balances.isEmpty
                ? const EmptyState(
                    icon: Icons.event_busy_outlined,
                    title: 'No leave balances',
                    message: 'Your branch doesn’t offer paid leave yet.',
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final b in balances) ...[
                        _BalanceRow(book: book, self: self, balance: b),
                        const SizedBox(height: AppSpacing.md),
                      ],
                      const BalanceLegend(),
                    ],
                  ),
          ),
          if (next.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            _NextLeave(book: book, request: next.first),
          ],
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            padding: EdgeInsets.zero,
            header: const CardHeader(title: 'Recent requests'),
            child: requests.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(AppSpacing.lg),
                    child: EmptyState(
                      icon: Icons.event_note_outlined,
                      title: 'No requests yet',
                      message:
                          'Requests you send appear here with their status.',
                    ),
                  )
                : Column(
                    children: [
                      for (final r in requests.take(5))
                        RequestRow(book: book, request: r),
                    ],
                  ),
          ),
        ],
      ),
    );
  });
}

class _BalanceRow extends StatelessWidget {
  const _BalanceRow({
    required this.book,
    required this.self,
    required this.balance,
  });

  final LeaveBook book;
  final Employee self;
  final LeaveBalance balance;

  @override
  Widget build(BuildContext context) {
    final b = balance;
    final sub = [
      b.type.method == AccrualMethod.monthly
          ? '${formatDays(b.granted)} accrued'
          : '${formatDays(b.granted)} granted',
      if (b.carried != 0) '${formatDays(b.carried)} carried',
      if (b.adjusted != 0)
        '${b.adjusted > 0 ? '+' : ''}${formatDays(b.adjusted)} adjusted',
      if (b.pending > 0) '${formatDays(b.pending)} pending',
      if (b.type.carryForwardMax == 0 && b.type.method == AccrualMethod.upfront)
        'lapses 31 Dec',
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: AppSpacing.sm,
          children: [
            Text(
              b.type.name.replaceAll(' leave', ''),
              style: AppTypography.bodyStrong,
            ),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: formatDays(b.available),
                    style: AppTypography.bodyStrong.copyWith(
                      fontFamily: AppTypography.mono,
                    ),
                  ),
                  const TextSpan(text: ' available'),
                ],
              ),
              style: AppTypography.small,
            ),
          ],
        ),
        const SizedBox(height: 6),
        BalanceBar(balance: b),
        const SizedBox(height: 4),
        Text(sub, style: AppTypography.helper),
      ],
    );
  }
}

class _NextLeave extends StatelessWidget {
  const _NextLeave({required this.book, required this.request});

  final LeaveBook book;
  final LeaveRequest request;

  @override
  Widget build(BuildContext context) {
    final r = request;
    final approver = r.steps
        .where((s) => s.approved == true)
        .lastOrNull
        ?.decidedBy;
    return AppCard(
      child: Row(
        children: [
          Container(
            width: 52,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.successSoft,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Column(
              children: [
                Text(
                  DateFormat('MMM').format(r.from).toUpperCase(),
                  style: AppTypography.helper.copyWith(
                    color: AppColors.successText,
                  ),
                ),
                Text(
                  '${r.from.day}',
                  style: AppTypography.sectionTitle.copyWith(
                    color: AppColors.successText,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Next approved leave', style: AppTypography.helper),
                Text(requestTitle(book, r), style: AppTypography.bodyStrong),
                if (approver != null)
                  Text(
                    '✓ Approved by $approver',
                    style: AppTypography.helper.copyWith(
                      color: AppColors.successText,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Open request',
            onPressed: () => context.go(AppRoutes.myLeaveRequest(r.id)),
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }
}

/// One request in a list (boards S90, S92).
class RequestRow extends StatelessWidget {
  const RequestRow({super.key, required this.book, required this.request});

  final LeaveBook book;
  final LeaveRequest request;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.go(AppRoutes.myLeaveRequest(request.id)),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: 12,
        ),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.divider)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    requestTitle(book, request),
                    style: AppTypography.bodyStrong,
                  ),
                  Text(
                    requestSubtitle(book, request),
                    style: AppTypography.helper,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Flexible(child: LeaveStatusBadge(request.status)),
          ],
        ),
      ),
    );
  }
}

/// Board S89 — apply, or change the dates of a request ([amendId]).
class ApplyLeaveScreen extends ConsumerStatefulWidget {
  const ApplyLeaveScreen({
    super.key,
    this.amendId,
    this.initialType,
    this.initialFrom,
    this.initialTo,
  });

  final String? amendId;

  /// Prefill from links such as an optional holiday (board S93).
  final String? initialType;
  final DateTime? initialFrom;
  final DateTime? initialTo;

  @override
  ConsumerState<ApplyLeaveScreen> createState() => _ApplyLeaveScreenState();
}

class _ApplyLeaveScreenState extends ConsumerState<ApplyLeaveScreen> {
  late String? _type = widget.initialType;
  late DateTime? _from = widget.initialFrom;
  late DateTime? _to = widget.initialTo ?? widget.initialFrom;
  HalfDay _half = HalfDay.full;
  final _reason = TextEditingController();
  bool _busy = false;
  bool _tried = false;
  bool _loaded = false;
  String? _failure;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _prefill(LeaveRequest r) {
    _loaded = true;
    _type = r.typeKey;
    _from = r.from;
    _to = r.to;
    _half = r.half;
    _reason.text = r.reason;
  }

  Future<void> _submit(
    LeaveBook book,
    Employee self,
    LeaveRequest? original,
  ) async {
    setState(() {
      _tried = true;
      _failure = null;
    });
    final errors = book.validate(
      e: self,
      typeKey: _type,
      from: _from,
      to: _to,
      half: _half,
      amending: original?.id,
    );
    if (errors.isNotEmpty) return;
    setState(() => _busy = true);
    final notifier = ref.read(leaveDataProvider.notifier);
    try {
      final saved = original == null
          ? await notifier.submit(
              typeKey: _type!,
              from: _from!,
              to: _to!,
              half: _half,
              reason: _reason.text,
            )
          : await notifier.amend(
              original,
              typeKey: _type!,
              from: _from!,
              to: _to!,
              half: _half,
              reason: _reason.text,
            );
      if (!mounted) return;
      final step = saved.currentStep;
      showAppToast(
        context,
        original == null
            ? 'Request sent${step == null ? '' : ' to ${book.approverName(step)}'}'
            : 'Changes sent for approval',
      );
      context.go(AppRoutes.myLeaveRequest(saved.id));
    } on Failure catch (f) {
      if (mounted) setState(() => _failure = f.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => withLeaveSelf(ref, (book, self) {
    final original = widget.amendId == null
        ? null
        : book
              .requestsOf(self)
              .where((r) => r.id == widget.amendId)
              .firstOrNull;
    if (widget.amendId != null && original == null) {
      return const ErrorState(
        headline: '404',
        title: 'Request not found',
        message: 'Open the request from My leave.',
      );
    }
    if (original != null && !_loaded) _prefill(original);

    final types = [
      for (final t in book.data.types)
        if (t.active && t.eligible(self) && book.offers(self, t)) t,
    ];
    _type ??= types.firstOrNull?.key;
    final type = _type == null ? null : book.data.type(_type!);
    final balance = type == null || !type.tracksBalance
        ? null
        : book.balance(
            self,
            type.key,
            (_from ?? book.today).year,
            exceptRequest: original?.id,
          );
    final days = type == null || _from == null || _to == null
        ? const <LeaveDay>[]
        : book.countDays(self, type, _from!, _to!, _half);
    final total = days.fold(0.0, (s, d) => s + d.counted);
    final errors = type == null || (_from == null && !_tried)
        ? const <String, String>{}
        : book.validate(
            e: self,
            typeKey: _type,
            from: _from,
            to: _to,
            half: _half,
            amending: original?.id,
          );
    final overlap = errors['overlap'];
    final steps = type == null
        ? const <ApprovalStep>[]
        : book.route(self, type, total);
    final overlapsOn = <DateTime>{
      if (overlap != null)
        for (final r in book.requestsOf(self))
          if (r.id != original?.id && r.status.holdsDays)
            for (final d in days)
              if (!d.date.isBefore(r.from) && !d.date.isAfter(r.to)) d.date,
    };

    return ResponsivePage(
      maxWidth: 640,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _title(
            context,
            original == null ? 'Apply for leave' : 'Change dates',
            back: original == null
                ? AppRoutes.myLeave
                : AppRoutes.myLeaveRequest(original.id),
          ),
          if (original != null)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'Changes send the request for approval again.',
                style: AppTypography.small,
              ),
            ),
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppDropdownField<String>(
                  label: 'Leave type',
                  isRequired: true,
                  value: _type,
                  errorText: _tried ? errors['type'] : null,
                  options: [
                    for (final t in types)
                      AppDropdownOption(
                        t.key,
                        t.tracksBalance
                            ? '${t.name} · ${dayCount(book.balance(self, t.key, (_from ?? book.today).year, exceptRequest: original?.id).available)} available'
                            : t.name,
                      ),
                  ],
                  onChanged: (v) => setState(() {
                    _type = v;
                    if (book.data.type(v ?? '')?.allowHalfDays == false) {
                      _half = HalfDay.full;
                    }
                  }),
                ),
                const SizedBox(height: AppSpacing.md),
                LayoutBuilder(
                  builder: (context, c) {
                    final fromField = AppDateField(
                      label: 'From',
                      isRequired: true,
                      value: _from,
                      firstDate: DateTime(book.today.year - 1),
                      lastDate: DateTime(book.today.year + 1, 12, 31),
                      errorText: errors['dates'],
                      onChanged: (d) => setState(() {
                        _from = d;
                        if (d != null && (_to == null || _to!.isBefore(d))) {
                          _to = d;
                        }
                      }),
                    );
                    final toField = AppDateField(
                      label: 'To',
                      isRequired: true,
                      value: _to,
                      firstDate: DateTime(book.today.year - 1),
                      lastDate: DateTime(book.today.year + 1, 12, 31),
                      onChanged: (d) => setState(() => _to = d),
                    );
                    if (c.maxWidth < 360) {
                      return Column(
                        children: [
                          fromField,
                          const SizedBox(height: AppSpacing.md),
                          toField,
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: fromField),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(child: toField),
                      ],
                    );
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                const Text('Duration', style: AppTypography.label),
                const SizedBox(height: 6),
                ChoiceChips<HalfDay>(
                  options: [
                    (HalfDay.full, HalfDay.full.label),
                    if (type?.allowHalfDays ?? true) ...[
                      (HalfDay.first, HalfDay.first.label),
                      (HalfDay.second, HalfDay.second.label),
                    ],
                  ],
                  selected: _half,
                  hasError: errors['half'] != null,
                  onSelected: (h) => setState(() => _half = h),
                ),
                if (errors['half'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      errors['half']!,
                      style: AppTypography.helper.copyWith(
                        color: AppColors.danger,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (days.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            AppCard(
              header: CardHeader(title: 'You’ll use ${dayCount(total)}'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final d in days.take(31))
                    _DayLine(day: d, overlaps: overlapsOn.contains(d.date)),
                  if (days.length > 31)
                    Text(
                      '…and ${days.length - 31} more days',
                      style: AppTypography.helper,
                    ),
                  if (balance != null) ...[
                    const Divider(height: AppSpacing.lg),
                    InfoRow(
                      '${type!.name.replaceAll(' leave', '')} balance after approval',
                      '${formatDays(balance.available)} → ${formatDays(balance.available - total)} days',
                      valueStyle: AppTypography.bodyStrong.copyWith(
                        fontFamily: AppTypography.mono,
                        color: balance.available - total < 0
                            ? AppColors.danger
                            : AppColors.textPrimary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
          for (final key in ['overlap', 'balance'])
            if (errors[key] != null) ...[
              const SizedBox(height: AppSpacing.md),
              _Notice(text: errors[key]!, danger: true),
            ],
          if (_failure != null) ...[
            const SizedBox(height: AppSpacing.md),
            _Notice(text: _failure!, danger: true),
          ],
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppTextField(
                  label: 'Reason',
                  isOptional: true,
                  controller: _reason,
                  maxLines: 3,
                  maxLength: 500,
                ),
                if (steps.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(text: 'Goes to '),
                        TextSpan(
                          text: book.approverName(steps.first),
                          style: AppTypography.helper.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (steps.length > 1)
                          TextSpan(
                            text:
                                ', then ${steps.skip(1).map(book.approverName).join(', then ')}',
                          ),
                        const TextSpan(
                          text:
                              '. You’ll get a notification when it’s decided.',
                        ),
                      ],
                    ),
                    style: AppTypography.helper,
                  ),
                  for (final s in steps.where((s) => s.note.isNotEmpty))
                    Text(
                      s.note,
                      style: AppTypography.helper.copyWith(
                        color: AppColors.primary,
                      ),
                    ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppButton(
            label: original == null ? 'Submit request' : 'Send changes',
            busy: _busy,
            busyLabel: 'Sending…',
            expand: true,
            onPressed: overlap != null
                ? null
                : () => _submit(book, self, original),
          ),
          if (overlap != null)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'Resolve the overlap to submit.',
                textAlign: TextAlign.center,
                style: AppTypography.helper,
              ),
            ),
        ],
      ),
    );
  });
}

class _DayLine extends StatelessWidget {
  const _DayLine({required this.day, required this.overlaps});

  final LeaveDay day;
  final bool overlaps;

  @override
  Widget build(BuildContext context) {
    final color = overlaps
        ? const Color(0xFF9A5B00)
        : (day.counted == 0 ? AppColors.textMuted : AppColors.textPrimary);
    final note = overlaps
        ? '${day.counted == 0 ? day.note : (day.counted == 1 ? 'Counted' : 'Half day')} · overlaps'
        : (day.counted == 0.5 ? 'Counted · half day' : day.note);
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 96,
              child: Text(
                DateFormat('EEE d MMM').format(day.date),
                style: AppTypography.code.copyWith(color: color),
              ),
            ),
            Expanded(
              child: Text(
                note,
                style: AppTypography.small.copyWith(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, this.danger = false});

  final String text;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: danger ? AppColors.dangerSoft : AppColors.warningSoft,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: danger ? AppColors.dangerBorder : AppColors.warning,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.error_outline,
              size: 18,
              color: danger ? AppColors.dangerText : AppColors.warningText,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                text,
                style: AppTypography.small.copyWith(
                  color: danger ? AppColors.dangerText : AppColors.warningText,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Board S91 — one request: status, progress, withdraw / cancel / change.
class LeaveRequestScreen extends ConsumerWidget {
  const LeaveRequestScreen({super.key, required this.requestId});

  final String requestId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => withLeaveSelf(ref, (
    book,
    self,
  ) {
    final r = book.requestsOf(self).where((x) => x.id == requestId).firstOrNull;
    if (r == null) {
      return const ErrorState(
        headline: '404',
        title: 'Request not found',
        message: 'Open the request from My leave.',
      );
    }
    final type = book.data.type(r.typeKey);
    final days = book.daysOf(r);
    final balance = type == null || !type.tracksBalance
        ? null
        : book.balance(self, r.typeKey, r.from.year);
    final startsLater = r.from.isAfter(book.today);
    final canCancel =
        r.status == LeaveStatus.approved &&
        startsLater &&
        book.policy.cancelApprovedNotStarted;
    final canChange =
        r.status.isOpen || (r.status == LeaveStatus.approved && startsLater);
    final approver = r.currentStep ?? r.steps.lastOrNull;

    return ResponsivePage(
      maxWidth: 640,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _title(context, 'Leave request', back: AppRoutes.myLeave),
          const SizedBox(height: AppSpacing.md),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            type?.name ?? r.typeKey,
                            style: AppTypography.small,
                          ),
                          Text(
                            r.isSingleDay
                                ? DateFormat('EEE d MMM y').format(r.from)
                                : leaveRange(r.from, r.to),
                            style: AppTypography.sectionTitle,
                          ),
                          Text(
                            '${r.half == HalfDay.full ? 'Full day' : r.half.label} · ${dayCount(days)}',
                            style: AppTypography.small,
                          ),
                        ],
                      ),
                    ),
                    LeaveStatusBadge(r.status),
                  ],
                ),
                if (r.amendedFrom case (final f, final t))
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Changed from ${leaveRange(f, t)}',
                      style: AppTypography.helper,
                    ),
                  ),
                const Divider(height: AppSpacing.xl),
                InfoRow(
                  'Submitted',
                  DateFormat('d MMM, HH:mm').format(r.createdAt),
                ),
                InfoRow(
                  'Request ID',
                  r.id,
                  valueStyle: AppTypography.code.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
                if (balance != null)
                  InfoRow(
                    'Balance after',
                    r.status.holdsDays
                        ? '${formatDays(balance.available)} days'
                        : '${formatDays(balance.available)} (unchanged)',
                  ),
                if (approver != null)
                  InfoRow('Approver', book.approverName(approver)),
                if (r.reason.isNotEmpty) InfoRow('Your reason', r.reason),
              ],
            ),
          ),
          if (r.status == LeaveStatus.changesRequested) ...[
            const SizedBox(height: AppSpacing.md),
            _Notice(
              text:
                  'Changes requested: “${r.decisionNote}”. Change the dates or withdraw the request.',
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            header: const CardHeader(title: 'Progress'),
            child: LeaveTimeline(
              entries: timelineOf(book, r, selfName: self.fullName),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (canChange) ...[
            AppButton(
              label: 'Change dates',
              variant: AppButtonVariant.secondary,
              expand: true,
              onPressed: () =>
                  context.go('${AppRoutes.applyLeave}?amend=${r.id}'),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 4, bottom: AppSpacing.md),
              child: Text(
                'Changes send the request for approval again.',
                textAlign: TextAlign.center,
                style: AppTypography.helper,
              ),
            ),
          ],
          if (r.status.isOpen)
            AppButton(
              label: 'Withdraw request',
              variant: AppButtonVariant.ghost,
              expand: true,
              onPressed: () => _confirm(context, ref, book, r, days, true),
            ),
          if (canCancel)
            AppButton(
              label: 'Cancel leave',
              variant: AppButtonVariant.ghost,
              expand: true,
              onPressed: () => _confirm(context, ref, book, r, days, false),
            ),
          if (r.status == LeaveStatus.approved &&
              !startsLater &&
              !r.to.isBefore(book.today))
            const Text(
              'This leave has started. Ask HR if it needs to change.',
              textAlign: TextAlign.center,
              style: AppTypography.helper,
            ),
        ],
      ),
    );
  });

  Future<void> _confirm(
    BuildContext context,
    WidgetRef ref,
    LeaveBook book,
    LeaveRequest r,
    double days,
    bool withdraw,
  ) async {
    final type = (book.data.type(r.typeKey)?.name ?? 'leave').toLowerCase();
    final approver = r.steps
        .map(
          (s) =>
              s.decidedBy ?? book.approverName(s).replaceAll(' (HR Admin)', ''),
        )
        .first
        .split(' ')
        .first;
    final done = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ConfirmSheet(
        title: withdraw ? 'Withdraw this request?' : 'Cancel this leave?',
        message:
            'Your ${dayCount(days)} of $type for ${leaveRange(r.from, r.to)} will be released. You can apply again later.',
        confirmLabel: withdraw ? 'Withdraw request' : 'Cancel leave',
        busyLabel: withdraw ? 'Withdrawing…' : 'Cancelling…',
        keepLabel: withdraw ? 'Keep request' : 'Keep leave',
        action: () => withdraw
            ? ref.read(leaveDataProvider.notifier).withdraw(r)
            : ref.read(leaveDataProvider.notifier).cancel(r),
      ),
    );
    if (done == true && context.mounted) {
      showAppToast(
        context,
        '${withdraw ? 'Request withdrawn' : 'Leave cancelled'}. ${dayCount(days)} ${days <= 1 ? 'is' : 'are'} back in your ${type.replaceAll(' leave', '')} balance and $approver has been told.',
      );
    }
  }
}

class _ConfirmSheet extends StatefulWidget {
  const _ConfirmSheet({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.busyLabel,
    required this.keepLabel,
    required this.action,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final String busyLabel;
  final String keepLabel;
  final Future<void> Function() action;

  @override
  State<_ConfirmSheet> createState() => _ConfirmSheetState();
}

class _ConfirmSheetState extends State<_ConfirmSheet> {
  bool _busy = false;
  String? _error;

  Future<void> _go() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.action();
      if (mounted) Navigator.of(context).pop(true);
    } on Failure catch (f) {
      if (mounted) setState(() => _error = f.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_busy,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(widget.title, style: AppTypography.sectionTitle),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(widget.message, style: AppTypography.body),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                _error!,
                style: AppTypography.small.copyWith(color: AppColors.danger),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            AppButton(
              label: widget.confirmLabel,
              variant: AppButtonVariant.danger,
              busy: _busy,
              busyLabel: widget.busyLabel,
              expand: true,
              onPressed: _go,
            ),
            const SizedBox(height: AppSpacing.sm),
            AppButton(
              label: widget.keepLabel,
              variant: AppButtonVariant.secondary,
              expand: true,
              onPressed: _busy ? null : () => Navigator.of(context).pop(false),
            ),
          ],
        ),
      ),
    );
  }
}

/// Board S92 — the ledger behind a balance.
class LeaveHistoryScreen extends ConsumerStatefulWidget {
  const LeaveHistoryScreen({super.key});

  @override
  ConsumerState<LeaveHistoryScreen> createState() => _LeaveHistoryScreenState();
}

class _LeaveHistoryScreenState extends ConsumerState<LeaveHistoryScreen> {
  String? _type;
  int? _year;
  LeaveStatus? _status;

  @override
  Widget build(BuildContext context) => withLeaveSelf(ref, (book, self) {
    final year = _year ?? book.today.year;
    final tracked = [
      for (final t in book.data.types)
        if (t.tracksBalance && book.offers(self, t)) t,
    ];
    final typeKey = _type ?? tracked.firstOrNull?.key ?? 'all';
    final type = book.data.type(typeKey);
    final requests =
        book
            .requestsOf(self)
            .where(
              (r) =>
                  r.from.year == year &&
                  (typeKey == 'all' || r.typeKey == typeKey) &&
                  (_status == null || r.status == _status),
            )
            .toList()
          ..sort((a, b) => b.from.compareTo(a.from));

    return ResponsivePage(
      maxWidth: 800,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _title(context, 'Leave history', back: AppRoutes.myLeave),
          const SizedBox(height: AppSpacing.md),
          ResponsiveGrid(
            minItemWidth: 150,
            maxColumns: 3,
            children: [
              DashboardSelect<String>(
                label: 'Leave type',
                value: typeKey,
                options: [
                  for (final t in tracked)
                    (t.key, t.name.replaceAll(' leave', '')),
                  ('all', 'All types'),
                ],
                onChanged: (v) => setState(() => _type = v),
              ),
              DashboardSelect<int>(
                label: 'Year',
                value: year,
                options: [
                  for (var y = book.today.year; y >= book.today.year - 1; y--)
                    (y, '$y'),
                ],
                onChanged: (v) => setState(() => _year = v),
              ),
              DashboardSelect<LeaveStatus?>(
                label: 'Status',
                value: _status,
                options: [
                  (null, 'Any status'),
                  for (final s in LeaveStatus.values) (s, s.label),
                ],
                onChanged: (v) => setState(() => _status = v),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          if (type != null && type.tracksBalance) ...[
            _Workings(book: book, self: self, type: type, year: year),
            const SizedBox(height: AppSpacing.lg),
            _Ledger(
              lines: [
                for (final l in book.ledger(self, type.key, year))
                  if (_status == null ||
                      l.what.startsWith(
                        _status == LeaveStatus.approved
                            ? 'Used'
                            : _status!.label,
                      ))
                    l,
              ],
            ),
          ] else
            AppCard(
              padding: EdgeInsets.zero,
              header: CardHeader(
                title: 'Requests',
                subtitle: '${requests.length} in $year',
              ),
              child: requests.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(AppSpacing.lg),
                      child: EmptyState(
                        icon: Icons.event_note_outlined,
                        title: 'Nothing here',
                        message: 'No requests match these filters.',
                      ),
                    )
                  : Column(
                      children: [
                        for (final r in requests)
                          RequestRow(book: book, request: r),
                      ],
                    ),
            ),
        ],
      ),
    );
  });
}

class _Workings extends StatelessWidget {
  const _Workings({
    required this.book,
    required this.self,
    required this.type,
    required this.year,
  });

  final LeaveBook book;
  final Employee self;
  final LeaveType type;
  final int year;

  @override
  Widget build(BuildContext context) {
    final b = book.balance(self, type.key, year);
    String signed(double v, String sign) =>
        v == 0 ? '0.00' : '$sign${v.abs().toStringAsFixed(2)}';
    final rows = <(String, String, Color)>[
      (
        type.method == AccrualMethod.monthly
            ? 'Accrued in $year'
            : 'Granted for $year',
        signed(b.granted, '+'),
        AppColors.textPrimary,
      ),
      if (b.carried != 0)
        (
          'Carried from ${year - 1}',
          signed(b.carried, '+'),
          AppColors.textPrimary,
        ),
      ('Used', signed(b.used, '−'), const Color(0xFF8A3A12)),
      (
        'Held for pending requests',
        signed(b.pending, '−'),
        AppColors.warningText,
      ),
      (
        'Adjustments by HR',
        signed(b.adjusted, b.adjusted < 0 ? '−' : '+'),
        AppColors.textMuted,
      ),
    ];
    return AppCard(
      header: CardHeader(
        title:
            '${type.name.replaceAll(' leave', '')} · how ${dayCount(b.available)} is worked out',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (k, v, c) in rows)
            InfoRow(k, v, valueStyle: AppTypography.code.copyWith(color: c)),
          const Divider(height: AppSpacing.md),
          InfoRow(
            'Available now',
            b.available.toStringAsFixed(2),
            valueStyle: AppTypography.code.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _Ledger extends StatelessWidget {
  const _Ledger({required this.lines});

  final List<LedgerLine> lines;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      header: const CardHeader(title: 'Transactions', subtitle: 'Newest first'),
      child: lines.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: EmptyState(
                icon: Icons.receipt_long_outlined,
                title: 'No transactions',
                message: 'Nothing matches these filters.',
              ),
            )
          : Column(
              children: [
                for (final l in lines)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: 10,
                    ),
                    decoration: const BoxDecoration(
                      border: Border(top: BorderSide(color: AppColors.divider)),
                    ),
                    child: MergeSemantics(
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(l.what, style: AppTypography.bodyStrong),
                                Text(l.note, style: AppTypography.helper),
                              ],
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                l.amount == 0
                                    ? '±0.00'
                                    : '${l.amount > 0 ? '+' : '−'}${l.amount.abs().toStringAsFixed(2)}',
                                style: AppTypography.code.copyWith(
                                  color: l.held
                                      ? AppColors.warningText
                                      : l.amount > 0
                                      ? AppColors.successText
                                      : l.amount < 0
                                      ? const Color(0xFF8A3A12)
                                      : AppColors.textMuted,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                'bal ${l.balance.toStringAsFixed(2)}',
                                style: AppTypography.helper,
                              ),
                            ],
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
