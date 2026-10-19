import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// Placeholder block that mirrors the final layout while data loads.
/// The shimmer stops when the platform asks for reduced motion.
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({
    super.key,
    this.width,
    required this.height,
    this.radius = AppRadius.sm,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  static const _base = Color(0xFFEEF0F3);
  static const _highlight = Color(0xFFF6F7F9);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      unawaited(_controller.repeat());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value * 2 - 1;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(t - 1, 0),
              end: Alignment(t + 1, 0),
              colors: const [_base, _highlight, _base],
            ),
          ),
        );
      },
    );
  }
}

/// Wraps a skeleton layout: hidden for the first [delay] (so fast loads
/// don't flash) and announced once to screen readers as [label].
class LoadingSkeleton extends StatefulWidget {
  const LoadingSkeleton({
    super.key,
    required this.label,
    required this.child,
    this.delay = const Duration(milliseconds: 300),
  });

  /// e.g. "Loading employees".
  final String label;
  final Widget child;
  final Duration delay;

  @override
  State<LoadingSkeleton> createState() => _LoadingSkeletonState();
}

class _LoadingSkeletonState extends State<LoadingSkeleton> {
  Timer? _timer;
  late bool _visible = widget.delay == Duration.zero;

  @override
  void initState() {
    super.initState();
    if (!_visible) {
      _timer = Timer(widget.delay, () => setState(() => _visible = true));
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.label,
      liveRegion: true,
      child: ExcludeSemantics(
        child: _visible ? widget.child : const SizedBox.shrink(),
      ),
    );
  }
}

/// A list of skeleton rows (avatar, two lines, trailing value).
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.rows = 5});

  final int rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < rows; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm + 2),
            child: Row(
              children: [
                const SkeletonBox(width: 36, height: 36, radius: 18),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FractionallySizedBox(
                        widthFactor: 0.4 + (i % 3) * 0.1,
                        child: const SkeletonBox(height: 11),
                      ),
                      const SizedBox(height: 6),
                      FractionallySizedBox(
                        widthFactor: 0.25 + (i % 2) * 0.08,
                        child: const SkeletonBox(height: 9),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                const SkeletonBox(
                  width: 64,
                  height: 20,
                  radius: AppRadius.pill,
                ),
              ],
            ),
          ),
      ],
    );
  }
}
