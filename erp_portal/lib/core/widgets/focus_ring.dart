import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Draws the design system's focus ring (2 px primary, 2 px outside the
/// control) while a descendant has keyboard focus.
///
/// Like CSS `:focus-visible`, the ring shows only when the user navigates by
/// keyboard, not after a tap or click.
class FocusRing extends StatefulWidget {
  const FocusRing({
    super.key,
    required this.child,
    this.borderRadius = AppRadius.md,
  });

  final Widget child;
  final double borderRadius;

  @override
  State<FocusRing> createState() => _FocusRingState();
}

class _FocusRingState extends State<FocusRing> {
  bool _hasFocus = false;
  late FocusHighlightMode _mode = FocusManager.instance.highlightMode;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addHighlightModeListener(_onModeChanged);
  }

  @override
  void dispose() {
    FocusManager.instance.removeHighlightModeListener(_onModeChanged);
    super.dispose();
  }

  void _onModeChanged(FocusHighlightMode mode) => setState(() => _mode = mode);

  @override
  Widget build(BuildContext context) {
    final visible = _hasFocus && _mode == FocusHighlightMode.traditional;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (focused) => setState(() => _hasFocus = focused),
      child: CustomPaint(
        foregroundPainter: _RingPainter(
          visible: visible,
          radius: widget.borderRadius,
        ),
        child: widget.child,
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({required this.visible, required this.radius});

  final bool visible;
  final double radius;

  static const double _offset = 2;
  static const double _width = 2;

  @override
  void paint(Canvas canvas, Size size) {
    if (!visible) return;
    final rect = (Offset.zero & size).inflate(_offset + _width / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(radius + _offset)),
      Paint()
        ..color = AppColors.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = _width,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.visible != visible || old.radius != radius;
}
