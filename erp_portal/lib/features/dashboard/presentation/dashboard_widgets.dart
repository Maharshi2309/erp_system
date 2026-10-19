import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/initials.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/status_badge.dart';
import '../../leave/domain/leave.dart';
import '../../leave/domain/leave_book.dart';
import '../domain/dashboard_metrics.dart';
import 'admin_dashboard_screen.dart';

/// A dashboard card with a title.
class DashboardPanel extends StatelessWidget {
  const DashboardPanel({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) => AppCard(
    header: CardHeader(title: title, subtitle: subtitle, trailing: trailing),
    child: child,
  );
}

/// Honest empty state inside a chart panel (PRD §12: no invented numbers).
class DashboardEmpty extends StatelessWidget {
  const DashboardEmpty({super.key, required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
    child: Row(
      children: [
        Icon(icon, color: AppColors.textDisabled),
        const SizedBox(width: AppSpacing.md),
        Expanded(child: Text(message, style: AppTypography.small)),
      ],
    ),
  );
}

class HeadcountBar extends StatelessWidget {
  const HeadcountBar({
    super.key,
    required this.label,
    required this.value,
    required this.max,
    this.onTap,
    this.unit = 'employees',
    this.valueText,
  });

  final String label;
  final num value;
  final num max;
  final VoidCallback? onTap;

  /// Spoken after the value ("employees", "days").
  final String unit;
  final String? valueText;

  @override
  Widget build(BuildContext context) {
    final text = valueText ?? '$value';
    return Semantics(
      button: onTap != null,
      label: '$label, $text $unit',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: AppTypography.small.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  Text(text, style: AppTypography.code),
                ],
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: max == 0 ? 0 : value / max,
                  minHeight: 8,
                  backgroundColor: AppColors.primarySoft,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AttentionRow extends StatelessWidget {
  const AttentionRow({super.key, required this.item, required this.onTap});

  final AttentionItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 110),
              child: StatusBadge(
                label: item.kind.label,
                tone: attentionTone(item.kind),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: AppTypography.small.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(item.subtitle, style: AppTypography.helper),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact labelled select used in dashboard filter rows.
class DashboardSelect<T> extends StatelessWidget {
  const DashboardSelect({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<(T, String)> options;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      child: InputDecorator(
        decoration: const InputDecoration(
          contentPadding: EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: 2,
          ),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            value: value,
            isExpanded: true,
            style: AppTypography.body.copyWith(color: AppColors.textPrimary),
            items: [
              for (final (v, text) in options)
                DropdownMenuItem(
                  value: v,
                  child: Text(text, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }
}

/// "Today, so far" as one stacked bar with counts (board S30).
class TodayBreakdown extends StatelessWidget {
  const TodayBreakdown({
    super.key,
    required this.items,
    required this.headline,
  });

  final List<(String, int, Color)> items;
  final String headline;

  @override
  Widget build(BuildContext context) {
    final total = items.fold(0, (s, x) => s + x.$2);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(headline, style: AppTypography.metric),
        const SizedBox(height: AppSpacing.sm),
        Semantics(
          label: items.map((x) => '${x.$1} ${x.$2}').join(', '),
          excludeSemantics: true,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 14,
              child: Row(
                children: [
                  for (final (_, v, c) in items)
                    if (v > 0)
                      Expanded(
                        flex: v,
                        child: Container(color: c),
                      ),
                  if (total == 0)
                    Expanded(child: Container(color: AppColors.neutralSoft)),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        for (final (label, v, c) in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: c,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text(label, style: AppTypography.small)),
                Text('$v', style: AppTypography.code),
              ],
            ),
          ),
      ],
    );
  }
}

/// Scheduled vs worked hours for a period (board S30).
class WorkedVsScheduled extends StatelessWidget {
  const WorkedVsScheduled({
    super.key,
    required this.scheduledMinutes,
    required this.workedMinutes,
    required this.missingDays,
  });

  final int scheduledMinutes;
  final int workedMinutes;
  final int missingDays;

  String _h(int m) =>
      '${NumberFormat.decimalPattern('en_IN').format(m ~/ 60)}h';

  @override
  Widget build(BuildContext context) {
    final pct = scheduledMinutes == 0
        ? 0.0
        : workedMinutes / scheduledMinutes * 100;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HeadcountBar(
          label: 'Scheduled',
          value: scheduledMinutes ~/ 60,
          max: scheduledMinutes ~/ 60,
        ),
        HeadcountBar(
          label: 'Worked',
          value: workedMinutes ~/ 60,
          max: scheduledMinutes ~/ 60,
        ),
        const SizedBox(height: 4),
        Text(
          '${_h(workedMinutes)} of ${_h(scheduledMinutes)} · ${pct.toStringAsFixed(1)}%'
          '${missingDays == 0 ? '' : ' · excludes $missingDays ${missingDays == 1 ? 'day' : 'days'} with missing punches until corrected'}',
          style: AppTypography.helper,
        ),
      ],
    );
  }
}

/// One waiting leave request (boards S30, S33).
class PendingLeaveRow extends StatelessWidget {
  const PendingLeaveRow({
    super.key,
    required this.book,
    required this.request,
    required this.now,
    this.onTap,
  });

  final LeaveBook book;
  final LeaveRequest request;
  final DateTime now;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final r = request;
    final e = book.person(r.employeeId);
    final type = (book.data.type(r.typeKey)?.name ?? r.typeKey).replaceAll(
      ' leave',
      '',
    );
    final days = book.daysOf(r);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            ExcludeSemantics(
              child: CircleAvatar(
                radius: 16,
                backgroundColor: AppColors.primarySoft,
                child: Text(
                  initialsOf(e?.fullName ?? '?'),
                  style: AppTypography.helper.copyWith(
                    color: AppColors.primaryHover,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e?.fullName ?? r.employeeId,
                    style: AppTypography.small.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    '$type · ${leaveRange(r.from, r.to)} · ${r.half == HalfDay.full ? '${formatDays(days)} ${days == 1 ? 'day' : 'days'}' : 'half day'}',
                    style: AppTypography.helper,
                  ),
                ],
              ),
            ),
            Text(
              _ago(r.createdAt, now),
              style: AppTypography.helper.copyWith(
                color: now.difference(r.createdAt).inHours >= 48
                    ? AppColors.warningText
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _ago(DateTime t, DateTime now) {
    final d = now.difference(t);
    if (d.inMinutes < 60) return '${d.inMinutes.clamp(1, 59)}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }
}
