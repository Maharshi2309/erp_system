import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// Circular percentage (boards S20–S23). Colour: green when complete,
/// orange when something needs attention, blue otherwise.
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    super.key,
    required this.percent,
    this.size = 56,
    this.attention = false,
    this.caption,
    this.showLabel = true,
  });

  final int percent;
  final double size;
  final bool attention;

  /// Small text under the number, e.g. "set up".
  final String? caption;
  final bool showLabel;

  Color get color => percent >= 100
      ? AppColors.success
      : (attention ? const Color(0xFFB4471C) : AppColors.primary);

  @override
  Widget build(BuildContext context) {
    final stroke = size >= 80 ? 8.0 : (size >= 40 ? 5.0 : 3.0);
    return Semantics(
      label: '$percent percent set up',
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _RingPainter(
            fraction: percent.clamp(0, 100) / 100,
            color: color,
            stroke: stroke,
          ),
          child: showLabel
              ? Padding(
                  padding: EdgeInsets.all(stroke + 2),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$percent%',
                          style: AppTypography.label.copyWith(
                            fontFamily: AppTypography.mono,
                            fontSize: size >= 80 ? 20 : (size >= 48 ? 13 : 10),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (caption != null && size >= 80)
                          Text(caption!, style: AppTypography.helper),
                      ],
                    ),
                  ),
                )
              : null,
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.fraction,
    required this.color,
    required this.stroke,
  });

  final double fraction;
  final Color color;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final track = Paint()
      ..color = AppColors.border
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawArc(rect, 0, 2 * math.pi, false, track);
    if (fraction <= 0) return;
    final arc = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke;
    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * fraction, false, arc);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fraction != fraction || old.color != color || old.stroke != stroke;
}
