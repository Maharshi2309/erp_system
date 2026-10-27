import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';

/// Chart colours for the platform pages (D-77). Validated with the data-viz
/// palette checker on white: categorical slots pass CVD and normal-vision
/// separation; the paler slots always come with visible labels.
abstract final class PlatformChartColors {
  /// Categorical order for identity (organizations); "Other" is neutral.
  static const categorical = [
    AppColors.primary,
    Color(0xFFEB6834),
    Color(0xFF1BAF7A),
    Color(0xFFEDA100),
  ];
  static const other = Color(0xFFB8BFCC);

  /// Status marks: active, setting up, quiet.
  static const active = Color(0xFF12A27A);
  static const settingUp = AppColors.primary;
  static const quiet = Color(0xFFE08A00);

  /// Sequential ramp (one hue, light → dark) for magnitude.
  static const ramp = [
    Color(0xFFEEF1FD),
    Color(0xFFC9D2F7),
    Color(0xFF8FA2EE),
    Color(0xFF5470DC),
    Color(0xFF2B4ACB),
  ];

  static Color step(double t) =>
      ramp[(t.clamp(0, 1) * (ramp.length - 1)).round()];

  static const track = AppColors.neutralSoft;
}

final _int = NumberFormat.decimalPattern('en_IN');

/// Line with a soft area for one series over time. Hover or tap shows the
/// day and value; the axis has 0, half and a rounded top.
class AreaTrendChart extends StatefulWidget {
  const AreaTrendChart({
    super.key,
    required this.days,
    required this.values,
    required this.semanticLabel,
    this.unit = 'people',
    this.height = 180,
  });

  final List<DateTime> days;
  final List<int> values;
  final String semanticLabel;
  final String unit;
  final double height;

  @override
  State<AreaTrendChart> createState() => _AreaTrendChartState();
}

class _AreaTrendChartState extends State<AreaTrendChart> {
  int? _hover;

  int get _top {
    final max = widget.values.fold(1, math.max);
    final mag = math.pow(10, (math.log(max) / math.ln10).floor()).toInt();
    for (final f in [1, 1.5, 2, 2.5, 3, 4, 5, 6, 8, 10]) {
      final top = (f * mag).ceil();
      if (top >= max) return top;
    }
    return max;
  }

  void _at(double dx, double width) {
    final n = widget.values.length;
    if (n < 2 || width <= 0) return;
    final i = (dx / width * (n - 1)).round().clamp(0, n - 1);
    if (i != _hover) setState(() => _hover = i);
  }

  @override
  Widget build(BuildContext context) {
    final top = _top;
    final h = _hover;
    return Semantics(
      label: widget.semanticLabel,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 20,
            child: h == null
                ? const SizedBox.shrink()
                : Text(
                    '${DateFormat('EEE d MMM').format(widget.days[h])} · ${_int.format(widget.values[h])} ${widget.unit}',
                    style: AppTypography.label,
                  ),
          ),
          const SizedBox(height: AppSpacing.xs),
          SizedBox(
            height: widget.height,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 36,
                  child: MediaQuery.withClampedTextScaling(
                    maxScaleFactor: 1.2,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final v in [top, top ~/ 2, 0])
                          Text(
                            _int.format(v),
                            style: AppTypography.code.copyWith(fontSize: 11),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, c) => MouseRegion(
                      onHover: (e) => _at(e.localPosition.dx, c.maxWidth),
                      onExit: (_) => setState(() => _hover = null),
                      child: GestureDetector(
                        onTapDown: (e) => _at(e.localPosition.dx, c.maxWidth),
                        onHorizontalDragUpdate: (e) =>
                            _at(e.localPosition.dx, c.maxWidth),
                        child: CustomPaint(
                          size: Size(c.maxWidth, c.maxHeight),
                          painter: _AreaPainter(
                            values: widget.values,
                            top: top,
                            hover: h,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 44),
            // Axis labels: capped scaling, like the other charts (D-65).
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.2,
              child: LayoutBuilder(
                builder: (context, c) => Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Very narrow: first and last day only.
                    for (final i in [
                      0,
                      if (c.maxWidth >= 260) widget.days.length ~/ 2,
                      widget.days.length - 1,
                    ])
                      if (i >= 0 && i < widget.days.length)
                        Text(
                          DateFormat('d MMM').format(widget.days[i]),
                          style: AppTypography.code.copyWith(fontSize: 10),
                        ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AreaPainter extends CustomPainter {
  _AreaPainter({required this.values, required this.top, required this.hover});

  final List<int> values;
  final int top;
  final int? hover;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = AppColors.divider
      ..strokeWidth = 1;
    for (final f in [0.0, 0.5]) {
      final y = size.height * f;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    canvas.drawLine(
      Offset(0, size.height - 0.5),
      Offset(size.width, size.height - 0.5),
      Paint()
        ..color = AppColors.borderStrong
        ..strokeWidth = 1,
    );
    if (values.length < 2) return;
    Offset at(int i) => Offset(
      size.width * i / (values.length - 1),
      size.height - size.height * values[i] / top,
    );
    final line = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < values.length; i++) {
      line.lineTo(at(i).dx, at(i).dy);
    }
    final area = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.primary.withValues(alpha: 0.22),
            AppColors.primary.withValues(alpha: 0.02),
          ],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = AppColors.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );
    final last = at(values.length - 1);
    canvas.drawCircle(last, 4, Paint()..color = AppColors.primary);
    if (hover case final h?) {
      final p = at(h);
      canvas.drawLine(
        Offset(p.dx, 0),
        Offset(p.dx, size.height),
        Paint()
          ..color = AppColors.textMuted
          ..strokeWidth = 1,
      );
      canvas.drawCircle(p, 6, Paint()..color = AppColors.surface);
      canvas.drawCircle(p, 4, Paint()..color = AppColors.primary);
    }
  }

  @override
  bool shouldRepaint(_AreaPainter old) =>
      old.values != values || old.hover != hover || old.top != top;
}

/// Part-to-whole in one horizontal bar (2 px gaps), with a legend that
/// names each part, its count and share — never colour alone.
class ShareBar extends StatelessWidget {
  const ShareBar({
    super.key,
    required this.parts,
    required this.unit,
    this.maxParts = 4,
  });

  /// (label, value), largest first.
  final List<(String, int)> parts;
  final String unit;

  /// Parts after this many fold into "Other".
  final int maxParts;

  @override
  Widget build(BuildContext context) {
    final shown = parts.take(maxParts).toList();
    final rest = parts.skip(maxParts).fold(0, (s, p) => s + p.$2);
    final all = [
      for (final (i, p) in shown.indexed)
        (p.$1, p.$2, PlatformChartColors.categorical[i]),
      if (rest > 0) ('Other', rest, PlatformChartColors.other),
    ];
    final total = all.fold(0, (s, p) => s + p.$2);
    if (total == 0) {
      return const Text('Nothing to show yet.', style: AppTypography.small);
    }
    return Semantics(
      label: 'Share of $unit: ${all.map((p) => '${p.$1} ${p.$2}').join(', ')}.',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 28,
              child: Row(
                children: [
                  for (final (i, (label, v, color)) in all.indexed)
                    if (v > 0)
                      Expanded(
                        flex: v,
                        child: Tooltip(
                          message:
                              '$label · ${_int.format(v)} $unit · ${(v * 100 / total).round()}%',
                          child: Container(
                            margin: EdgeInsets.only(
                              right: i == all.length - 1 ? 0 : 2,
                            ),
                            color: color,
                          ),
                        ),
                      ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          for (final (label, v, color) in all)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text(label, style: AppTypography.small)),
                  Text(_int.format(v), style: AppTypography.code),
                  SizedBox(
                    width: 48,
                    child: Text(
                      '${(v * 100 / total).round()}%',
                      textAlign: TextAlign.end,
                      style: AppTypography.helper,
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

/// A ring for a few parts of a whole (here: organization status), with the
/// total in the middle and a labelled legend.
class DonutChart extends StatelessWidget {
  const DonutChart({
    super.key,
    required this.parts,
    required this.centerLabel,
    this.size = 140,
  });

  /// (label, value, colour).
  final List<(String, int, Color)> parts;
  final String centerLabel;
  final double size;

  @override
  Widget build(BuildContext context) {
    final total = parts.fold(0, (s, p) => s + p.$2);
    final ring = SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _DonutPainter(parts: parts, total: total),
        child: Center(
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.3,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _int.format(total),
                  style: AppTypography.kpiValue.copyWith(
                    fontFamily: AppTypography.mono,
                  ),
                ),
                Text(centerLabel, style: AppTypography.helper),
              ],
            ),
          ),
        ),
      ),
    );
    final legend = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (label, v, color) in parts)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Flexible(child: Text(label, style: AppTypography.small)),
                const SizedBox(width: AppSpacing.sm),
                Text('$v', style: AppTypography.code),
              ],
            ),
          ),
      ],
    );
    return Semantics(
      label:
          '$total $centerLabel: ${parts.map((p) => '${p.$2} ${p.$1}').join(', ')}.',
      excludeSemantics: true,
      child: Wrap(
        spacing: AppSpacing.xl,
        runSpacing: AppSpacing.md,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [ring, legend],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({required this.parts, required this.total});

  final List<(String, int, Color)> parts;
  final int total;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 18.0;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final track = Paint()
      ..color = PlatformChartColors.track
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawArc(rect, 0, math.pi * 2, false, track);
    if (total == 0) return;
    // A small surface gap between segments.
    const gap = 0.03;
    var start = -math.pi / 2;
    for (final (_, v, color) in parts) {
      if (v == 0) continue;
      final sweep = math.pi * 2 * v / total;
      canvas.drawArc(
        rect,
        start + (sweep > gap * 2 ? gap / 2 : 0),
        sweep > gap * 2 ? sweep - gap : sweep,
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.parts != parts || old.total != total;
}

/// A ring gauge for one share against 100%.
class RingGauge extends StatelessWidget {
  const RingGauge({
    super.key,
    required this.percent,
    required this.label,
    this.size = 84,
  });

  final int percent;
  final String label;
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$label, $percent percent',
    excludeSemantics: true,
    child: SizedBox(
      width: math.max(size, 110),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: size,
            child: CustomPaint(
              painter: _GaugePainter(percent.clamp(0, 100) / 100),
              child: Center(
                child: MediaQuery.withClampedTextScaling(
                  maxScaleFactor: 1.2,
                  child: Text(
                    '$percent%',
                    style: AppTypography.label.copyWith(
                      fontFamily: AppTypography.mono,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(label, textAlign: TextAlign.center, style: AppTypography.small),
        ],
      ),
    ),
  );
}

class _GaugePainter extends CustomPainter {
  _GaugePainter(this.fraction);

  final double fraction;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 8.0;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    canvas.drawArc(
      rect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..color = PlatformChartColors.ramp[0]
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * fraction,
      false,
      Paint()
        ..color = AppColors.primary
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = stroke,
    );
  }

  @override
  bool shouldRepaint(_GaugePainter old) => old.fraction != fraction;
}

/// Dot plot: one dot per category on a thin stem, value at the end.
class LollipopChart extends StatelessWidget {
  const LollipopChart({super.key, required this.items, required this.unit});

  /// (label, value), largest first.
  final List<(String, int)> items;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final max = items.fold(1, (m, x) => math.max(m, x.$2));
    return Column(
      children: [
        for (final (label, v) in items)
          Semantics(
            label: '$label, $v $unit',
            excludeSemantics: true,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  SizedBox(
                    width: 140,
                    child: Text(
                      label,
                      style: AppTypography.small,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, c) {
                        final x = (c.maxWidth - 12) * v / max;
                        return SizedBox(
                          height: 14,
                          child: Stack(
                            alignment: Alignment.centerLeft,
                            children: [
                              Container(height: 1, color: AppColors.border),
                              Container(
                                width: x,
                                height: 2,
                                color: AppColors.primary,
                              ),
                              Positioned(
                                left: x,
                                child: Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: AppColors.primary,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: AppColors.surface,
                                      width: 2,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  SizedBox(
                    width: 28,
                    child: Text(
                      '$v',
                      textAlign: TextAlign.end,
                      style: AppTypography.code,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Tiles shaded light → dark by count (one hue), each labelled.
class HeatTiles extends StatelessWidget {
  const HeatTiles({super.key, required this.items, required this.unit});

  final List<(String, int)> items;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final max = items.fold(1, (m, x) => math.max(m, x.$2));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final (label, v) in items)
              () {
                final t = items.length == 1 ? 1.0 : (v / max);
                final bg = PlatformChartColors.step(0.25 + 0.75 * t);
                final dark = bg.computeLuminance() < 0.35;
                final fg = dark ? AppColors.surface : AppColors.textPrimary;
                return Semantics(
                  label: '$label, $v $unit',
                  excludeSemantics: true,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 120),
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$v',
                          style: AppTypography.kpiValue.copyWith(
                            color: fg,
                            fontFamily: AppTypography.mono,
                          ),
                        ),
                        Text(
                          label,
                          style: AppTypography.small.copyWith(color: fg),
                        ),
                      ],
                    ),
                  ),
                );
              }(),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        _RampLegend(unit: unit),
      ],
    );
  }
}

class _RampLegend extends StatelessWidget {
  const _RampLegend({required this.unit});

  final String unit;

  @override
  Widget build(BuildContext context) => Wrap(
    crossAxisAlignment: WrapCrossAlignment.center,
    runSpacing: 4,
    children: [
      Text('Fewer $unit', style: AppTypography.helper),
      const SizedBox(width: AppSpacing.sm),
      for (final c in PlatformChartColors.ramp.skip(1))
        Container(
          width: 18,
          height: 10,
          margin: const EdgeInsets.only(right: 2),
          decoration: BoxDecoration(
            color: c,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      const SizedBox(width: AppSpacing.sm - 2),
      const Text('More', style: AppTypography.helper),
    ],
  );
}

/// Calendar heatmap: the last days as weeks (Mon–Sun columns), each day
/// shaded by the share of people active. Days off show as empty cells.
class CalendarHeatmap extends StatelessWidget {
  const CalendarHeatmap({
    super.key,
    required this.days,
    required this.values,
    required this.total,
  });

  final List<DateTime> days;
  final List<int> values;

  /// People who could be active (employed), for the share.
  final int total;

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) return const SizedBox.shrink();
    final first = days.first.subtract(Duration(days: days.first.weekday - 1));
    final weeks = (days.last.difference(first).inDays ~/ 7) + 1;
    final byDay = {for (final (i, d) in days.indexed) d: values[i]};
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const SizedBox(width: 44),
            for (final n in names)
              Expanded(
                child: Text(
                  n,
                  textAlign: TextAlign.center,
                  style: AppTypography.helper,
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        for (var w = 0; w < weeks; w++)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 44,
                  child: Text(
                    DateFormat(
                      'd MMM',
                    ).format(first.add(Duration(days: w * 7))),
                    style: AppTypography.code.copyWith(fontSize: 10),
                  ),
                ),
                for (var d = 0; d < 7; d++)
                  Expanded(
                    child: () {
                      final day = first.add(Duration(days: w * 7 + d));
                      final v = byDay[DateTime(day.year, day.month, day.day)];
                      final share = v == null || total == 0 ? 0.0 : v / total;
                      final label = v == null
                          ? '${DateFormat('EEE d MMM').format(day)} · outside the range'
                          : '${DateFormat('EEE d MMM').format(day)} · $v of $total active (${(share * 100).round()}%)';
                      return Tooltip(
                        message: label,
                        child: Semantics(
                          label: label,
                          excludeSemantics: true,
                          child: Container(
                            height: 26,
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            decoration: BoxDecoration(
                              color: v == null
                                  ? Colors.transparent
                                  : (v == 0
                                        ? PlatformChartColors.track
                                        : PlatformChartColors.step(
                                            0.25 + 0.75 * share,
                                          )),
                              borderRadius: BorderRadius.circular(4),
                              border: v == null
                                  ? Border.all(color: AppColors.divider)
                                  : null,
                            ),
                          ),
                        ),
                      );
                    }(),
                  ),
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
        const _RampLegend(unit: 'active'),
      ],
    );
  }
}

/// Bullet bars: a track for the whole (employees) and a fill for the part
/// (active today), labelled "72 of 77".
class BulletBars extends StatelessWidget {
  const BulletBars({super.key, required this.rows});

  /// (label, part, whole).
  final List<(String, int, int)> rows;

  @override
  Widget build(BuildContext context) {
    final max = rows.fold(1, (m, r) => math.max(m, r.$3));
    return Column(
      children: [
        for (final (label, part, whole) in rows)
          Semantics(
            label: '$label, $part of $whole active today',
            excludeSemantics: true,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    spacing: AppSpacing.sm,
                    children: [
                      Text(
                        label,
                        style: AppTypography.small.copyWith(
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text('$part of $whole', style: AppTypography.code),
                    ],
                  ),
                  const SizedBox(height: 4),
                  LayoutBuilder(
                    builder: (context, c) => Stack(
                      children: [
                        Container(
                          width: c.maxWidth * whole / max,
                          height: 12,
                          decoration: BoxDecoration(
                            color: PlatformChartColors.ramp[1],
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        Container(
                          width: whole == 0 ? 0 : c.maxWidth * part / max,
                          height: 12,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: 4,
          children: [
            for (final (label, color) in [
              ('Active today', AppColors.primary),
              ('Employees', PlatformChartColors.ramp[1]),
            ]) ...[
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
              const SizedBox(width: AppSpacing.md),
            ],
          ],
        ),
      ],
    );
  }
}
