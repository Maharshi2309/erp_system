import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/status_badge.dart';
import '../domain/attendance.dart';
import '../domain/attendance_book.dart';

StatusTone dayTone(DayStatus s) => switch (s) {
  DayStatus.present => StatusTone.success,
  DayStatus.late ||
  DayStatus.leftEarly ||
  DayStatus.shortShift => StatusTone.warning,
  DayStatus.halfDay ||
  DayStatus.holiday ||
  DayStatus.working => StatusTone.info,
  DayStatus.missingPunch => StatusTone.danger,
  _ => StatusTone.neutral,
};

class DayStatusBadge extends StatelessWidget {
  const DayStatusBadge(this.status, {super.key});

  final DayStatus status;

  @override
  Widget build(BuildContext context) =>
      StatusBadge(label: status.label, tone: dayTone(status));
}

/// Colours of the stacked charts (boards S30, S52).
abstract final class AttendanceColors {
  static const onTime = AppColors.primary;
  static const late = Color(0xFFF2B84B);
  static const absent = Color(0xFFB4471C);
  static const working = AppColors.success;
}

/// A vertical stacked bar chart. Each bar lists its segments bottom-up.
class StackedBarChart extends StatelessWidget {
  const StackedBarChart({
    super.key,
    required this.bars,
    required this.semanticLabel,
    this.height = 180,
    this.sparseLabels = false,
  });

  final List<({String label, List<(int, Color)> segments, bool muted})> bars;
  final String semanticLabel;
  final double height;

  /// Only some bars are labelled, so a label may run past its own bar
  /// instead of being clipped on narrow screens.
  final bool sparseLabels;

  @override
  Widget build(BuildContext context) {
    final max = bars
        .map((b) => b.segments.fold(0, (s, x) => s + x.$1))
        .fold(1, (a, b) => a > b ? a : b);
    final top = _niceTop(max);
    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 32,
            height: height,
            // Axis labels sit in a fixed box; cap scaling so they stay inside.
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.2,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$top',
                    style: AppTypography.code.copyWith(fontSize: 11),
                  ),
                  Text(
                    '${top ~/ 2}',
                    style: AppTypography.code.copyWith(fontSize: 11),
                  ),
                  Text('0', style: AppTypography.code.copyWith(fontSize: 11)),
                ],
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              children: [
                Container(
                  height: height,
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: AppColors.borderStrong),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final b in bars)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 3),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                if (b.muted)
                                  Container(
                                    height: (height - 1) * 0.9,
                                    decoration: BoxDecoration(
                                      color: AppColors.neutralSoft,
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                  ),
                                for (final (v, c) in b.segments.reversed)
                                  if (v > 0)
                                    Container(
                                      // The chart's 1 px baseline takes one pixel.
                                      height: (height - 1) * v / top,
                                      decoration: BoxDecoration(
                                        color: c,
                                        border: const Border(
                                          top: BorderSide(
                                            color: AppColors.surface,
                                          ),
                                        ),
                                      ),
                                    ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    for (final b in bars)
                      Expanded(
                        child: Text(
                          b.label,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          softWrap: !sparseLabels,
                          overflow: sparseLabels
                              ? TextOverflow.visible
                              : TextOverflow.clip,
                          style: AppTypography.code.copyWith(fontSize: 10),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static int _niceTop(int max) {
    for (final step in [10, 20, 25, 50, 100, 250, 500, 1000, 2500, 5000]) {
      final top = ((max + step - 1) ~/ step) * step;
      if (top / step <= 5) return top;
    }
    return max;
  }
}

class ChartLegend extends StatelessWidget {
  const ChartLegend({super.key, required this.items});

  final List<(String, Color)> items;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: AppSpacing.md,
    runSpacing: 4,
    children: [
      for (final (label, color) in items)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 6),
            Text(label, style: AppTypography.helper),
          ],
        ),
    ],
  );
}

/// Punch timeline (boards S53 detail, S88).
class PunchTimeline extends StatelessWidget {
  const PunchTimeline({
    super.key,
    required this.record,
    this.missingNote = true,
  });

  final DayRecord record;
  final bool missingNote;

  @override
  Widget build(BuildContext context) {
    final entries = record.timeline;
    final missingOut =
        record.sessions.lastOrNull?.isOpen == true &&
        record.status == DayStatus.missingPunch;
    final missingIn = record.sessions.any((s) => s.isOrphanOut);
    final rows = <Widget>[];
    if (missingIn) {
      rows.add(
        _row(
          time: '— —',
          title: 'No punch-in recorded',
          sub: '',
          missing: true,
          last: false,
        ),
      );
    }
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      final isBreak =
          e.kind == PunchKind.breakStart || e.kind == PunchKind.breakEnd;
      rows.add(
        _row(
          time: clockTime(e.at, record.zone),
          title: e.kind.label,
          sub: [
            if (e.corrected)
              'Added by correction · original: none'
            else if (e.source.isNotEmpty)
              e.source,
            if (e.lateMinutes != null) '${e.lateMinutes} min late',
          ].join(' · '),
          fixed: e.corrected,
          hollow: isBreak,
          last: i == entries.length - 1 && !missingOut,
        ),
      );
    }
    if (missingOut && missingNote) {
      rows.add(
        _row(
          time: '— —',
          title: 'No punch-out recorded',
          sub: '',
          missing: true,
          last: true,
        ),
      );
    }
    if (rows.isEmpty) {
      return const Text('No punches recorded.', style: AppTypography.small);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }

  Widget _row({
    required String time,
    required String title,
    required String sub,
    bool missing = false,
    bool fixed = false,
    bool hollow = false,
    required bool last,
  }) {
    final color = missing ? AppColors.danger : AppColors.primary;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 16,
            child: Column(
              children: [
                const SizedBox(height: 4),
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: missing || hollow || fixed
                        ? AppColors.surface
                        : color,
                    border: Border.all(
                      color: hollow ? AppColors.textDisabled : color,
                      width: 2,
                    ),
                  ),
                ),
                if (!last)
                  Expanded(child: Container(width: 2, color: AppColors.border)),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    time,
                    style: AppTypography.code.copyWith(
                      color: fixed ? AppColors.primary : AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    sub.isEmpty ? title : '$title · $sub',
                    style: AppTypography.small.copyWith(
                      color: missing
                          ? AppColors.danger
                          : (fixed
                                ? AppColors.primary
                                : AppColors.textSecondary),
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
}

/// Rebuilds once a second, but only when [text] changes, so a fixed clock
/// (tests, screenshots) never schedules frames.
class LiveText extends StatefulWidget {
  const LiveText({super.key, required this.text, this.style});

  final String Function() text;
  final TextStyle? style;

  @override
  State<LiveText> createState() => _LiveTextState();
}

class _LiveTextState extends State<LiveText> {
  Timer? _timer;
  late String _value = widget.text();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final next = widget.text();
      if (next != _value && mounted) setState(() => _value = next);
    });
  }

  @override
  void didUpdateWidget(LiveText oldWidget) {
    super.didUpdateWidget(oldWidget);
    _value = widget.text();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(_value, style: widget.style);
}

/// "02:41:07".
String hms(Duration d) {
  final s = d.inSeconds < 0 ? 0 : d.inSeconds;
  return '${(s ~/ 3600).toString().padLeft(2, '0')}:'
      '${(s % 3600 ~/ 60).toString().padLeft(2, '0')}:'
      '${(s % 60).toString().padLeft(2, '0')}';
}
