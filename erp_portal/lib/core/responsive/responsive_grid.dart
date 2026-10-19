import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../theme/app_spacing.dart';

/// Lays children out in equal-width columns: as many as fit at
/// [minItemWidth], at most [maxColumns]. Rows wrap; nothing overflows.
///
/// e.g. KPI cards: 2-up on phones, 3-up on tablets, 4–7 on desktops.
class ResponsiveGrid extends StatelessWidget {
  const ResponsiveGrid({
    super.key,
    required this.children,
    this.minItemWidth = 180,
    this.maxColumns = 6,
    this.spacing = AppSpacing.md,
  });

  final List<Widget> children;
  final double minItemWidth;
  final int maxColumns;
  final double spacing;

  static int columnsFor(
    double width, {
    required double minItemWidth,
    required int maxColumns,
    required double spacing,
  }) {
    final fit = ((width + spacing) / (minItemWidth + spacing)).floor();
    return math.max(1, math.min(maxColumns, fit));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = columnsFor(
          constraints.maxWidth,
          minItemWidth: minItemWidth,
          maxColumns: maxColumns,
          spacing: spacing,
        );
        // Floored so rounding can never push the last item onto a new row.
        final itemWidth =
            ((constraints.maxWidth - spacing * (columns - 1)) / columns)
                .floorToDouble();
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final child in children)
              SizedBox(width: itemWidth, child: child),
          ],
        );
      },
    );
  }
}
