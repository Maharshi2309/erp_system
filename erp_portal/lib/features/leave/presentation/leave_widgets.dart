import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/failure.dart';
import '../../../core/responsive/responsive_page.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_badge.dart';
import '../../employees/domain/employee.dart';
import '../../employees/presentation/providers/employee_providers.dart';
import '../domain/leave.dart';
import '../domain/leave_book.dart';
import 'leave_providers.dart';

StatusTone toneOf(LeaveStatus s) => switch (s) {
  LeaveStatus.pending => StatusTone.warning,
  LeaveStatus.changesRequested => StatusTone.info,
  LeaveStatus.approved => StatusTone.success,
  LeaveStatus.rejected => StatusTone.danger,
  LeaveStatus.withdrawn || LeaveStatus.cancelled => StatusTone.neutral,
};

class LeaveStatusBadge extends StatelessWidget {
  const LeaveStatusBadge(this.status, {super.key});

  final LeaveStatus status;

  @override
  Widget build(BuildContext context) =>
      StatusBadge(label: status.label, tone: toneOf(status));
}

/// "1 day", "0.5 day", "5 days".
String dayCount(double d) => '${formatDays(d)} ${d <= 1 ? 'day' : 'days'}';

/// "Casual · Mon 19 Oct" / "Sick · 15 Sep (half)" (board S90).
String requestTitle(LeaveBook book, LeaveRequest r) {
  final name = (book.data.type(r.typeKey)?.name ?? r.typeKey).replaceAll(
    ' leave',
    '',
  );
  return '$name · ${leaveRange(r.from, r.to)}${r.half == HalfDay.full ? '' : ' (half)'}';
}

/// The line under a request: days and what happened last.
String requestSubtitle(LeaveBook book, LeaveRequest r) {
  final days = dayCount(book.daysOf(r));
  final last = r.history.isEmpty ? null : r.history.last;
  final when = DateFormat('d MMM').format(last?.at ?? r.createdAt);
  return switch (r.status) {
    LeaveStatus.pending =>
      '$days · sent ${DateFormat('d MMM').format(r.createdAt)}',
    LeaveStatus.changesRequested => '$days · “${r.decisionNote}”',
    LeaveStatus.approved => '$days · approved $when',
    LeaveStatus.rejected =>
      '$days · ${r.decisionNote.isEmpty ? 'rejected $when' : '“${r.decisionNote}”'}',
    LeaveStatus.withdrawn => '$days · you withdrew',
    LeaveStatus.cancelled => '$days · you cancelled',
  };
}

/// Used / pending / available in one bar (board S90).
class BalanceBar extends StatelessWidget {
  const BalanceBar({super.key, required this.balance});

  final LeaveBalance balance;

  @override
  Widget build(BuildContext context) {
    final b = balance;
    final total = b.total <= 0 ? 1.0 : b.total;
    final parts = [
      (b.used, const Color(0xFF8A3A12)),
      (b.pending, AppColors.warning),
      (b.available < 0 ? 0.0 : b.available, AppColors.success),
    ];
    return Semantics(
      label:
          '${b.type.name}: ${formatDays(b.used)} used, ${formatDays(b.pending)} pending, ${formatDays(b.available)} available of ${formatDays(b.total)}',
      child: ExcludeSemantics(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: SizedBox(
            height: 8,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (v, c) in parts)
                  if (v > 0)
                    Expanded(
                      flex: (v / total * 1000).round().clamp(1, 1000),
                      child: ColoredBox(color: c),
                    ),
                if (b.used + b.pending + b.available <= 0)
                  const Expanded(child: ColoredBox(color: AppColors.divider)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class BalanceLegend extends StatelessWidget {
  const BalanceLegend({super.key});

  @override
  Widget build(BuildContext context) {
    Widget item(String label, Color c) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: c,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: AppTypography.helper),
      ],
    );
    return ExcludeSemantics(
      child: Wrap(
        spacing: AppSpacing.md,
        runSpacing: 4,
        children: [
          item('Used', const Color(0xFF8A3A12)),
          item('Pending', AppColors.warning),
          item('Available', AppColors.success),
        ],
      ),
    );
  }
}

/// Shared loading/error/no-record handling for the employee leave pages.
Widget withLeaveSelf(
  WidgetRef ref,
  Widget Function(LeaveBook book, Employee self) build,
) {
  final self = ref.watch(selfEmployeeProvider);
  final book = ref.watch(leaveBookProvider);
  if (book.isLoading) {
    return const ResponsivePage(
      child: LoadingSkeleton(label: 'Loading', child: SkeletonList(rows: 6)),
    );
  }
  if (book.hasError) {
    return ErrorState(
      message: userMessageFor(book.error!),
      onRetry: () => ref.invalidate(leaveDataProvider),
    );
  }
  if (self == null) {
    return const ResponsivePage(
      child: AppCard(
        child: EmptyState(
          icon: Icons.badge_outlined,
          title: 'No employee record',
          message: 'Your account isn’t linked to an employee record yet.',
        ),
      ),
    );
  }
  return build(book.value!, self);
}

/// A label/value row in a details card.
class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {super.key, this.valueStyle});

  final String label;
  final String value;
  final TextStyle? valueStyle;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: AppSpacing.md,
          children: [
            Text(label, style: AppTypography.small),
            Text(
              value,
              style:
                  valueStyle ??
                  AppTypography.small.copyWith(color: AppColors.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}

/// A vertical progress list (boards S57, S91).
typedef TimelineEntry = ({
  String title,
  String sub,
  Color dot,
  bool hollow,
  bool muted,
});

class LeaveTimeline extends StatelessWidget {
  const LeaveTimeline({super.key, required this.entries});

  final List<TimelineEntry> entries;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < entries.length; i++)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 20,
                  child: Column(
                    children: [
                      const SizedBox(height: 4),
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: entries[i].hollow
                              ? AppColors.surface
                              : entries[i].dot,
                          shape: BoxShape.circle,
                          border: Border.all(color: entries[i].dot, width: 2),
                        ),
                      ),
                      if (i < entries.length - 1)
                        Expanded(
                          child: Container(width: 2, color: AppColors.divider),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: MergeSemantics(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entries[i].title,
                            style: AppTypography.bodyStrong.copyWith(
                              color: entries[i].muted
                                  ? AppColors.textMuted
                                  : AppColors.textPrimary,
                            ),
                          ),
                          if (entries[i].sub.isNotEmpty)
                            Text(entries[i].sub, style: AppTypography.helper),
                        ],
                      ),
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

/// The request's progress: what happened, then the steps still to come.
List<TimelineEntry> timelineOf(
  LeaveBook book,
  LeaveRequest r, {
  required String selfName,
}) {
  String stamp(DateTime t) => DateFormat('d MMM, HH:mm').format(t);
  Color colorOf(String text) {
    if (text.startsWith('Rejected')) return AppColors.danger;
    if (text.startsWith('Withdrawn') || text.startsWith('Cancelled')) {
      return AppColors.textSecondary;
    }
    if (text.startsWith('Changes')) return AppColors.primary;
    if (text.startsWith('Routed') || text.startsWith('No reporting')) {
      return AppColors.primary;
    }
    return AppColors.success;
  }

  final entries = <TimelineEntry>[
    for (final h in r.history)
      (
        title: h.text,
        sub:
            '${stamp(h.at)} · ${h.by == selfName ? 'by you' : (h.by == 'System' ? 'automatic' : 'by ${h.by}')}',
        dot: colorOf(h.text),
        hollow: false,
        muted: false,
      ),
  ];
  if (r.status == LeaveStatus.pending) {
    final open = r.steps.where((s) => !s.isDone).toList();
    for (var i = 0; i < open.length; i++) {
      final s = open[i];
      entries.add((
        title: i == 0
            ? 'Waiting for ${book.approverName(s)}'
            : 'Then ${book.approverName(s)}',
        sub: switch (s.kind) {
          ApproverKind.manager => 'Reporting manager',
          ApproverKind.branchManager => 'Branch manager',
          ApproverKind.hr => 'HR approval',
        },
        dot: i == 0 ? AppColors.warning : AppColors.borderStrong,
        hollow: true,
        muted: i > 0,
      ));
    }
    entries.add((
      title: 'Decision',
      sub: 'A notification is sent when it’s decided',
      dot: AppColors.borderStrong,
      hollow: true,
      muted: true,
    ));
  }
  return entries;
}

/// A search box with a magnifier and an accessible name.
class SearchBox extends StatelessWidget {
  const SearchBox({
    super.key,
    required this.label,
    required this.hint,
    required this.onChanged,
  });

  final String label;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      textField: true,
      child: TextField(
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: const Icon(Icons.search, size: 18),
        ),
      ),
    );
  }
}

/// "40 min ago", "3 hours ago", "yesterday", "2 days ago".
String sentAgo(DateTime sent, DateTime now) {
  final d = now.difference(sent);
  if (d.inMinutes < 60) return '${d.inMinutes.clamp(1, 59)} min ago';
  if (d.inHours < 24) {
    return '${d.inHours} ${d.inHours == 1 ? 'hour' : 'hours'} ago';
  }
  final days = DateTime(
    now.year,
    now.month,
    now.day,
  ).difference(DateTime(sent.year, sent.month, sent.day)).inDays;
  return days <= 1 ? 'yesterday' : '$days days ago';
}
