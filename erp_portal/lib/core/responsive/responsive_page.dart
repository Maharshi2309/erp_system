import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import 'breakpoints.dart';

/// Standard page body: centred, capped at the content width, with gutters
/// that grow with the screen (16 px on phones, 24 on tablets, 32 wider).
///
/// Wide content such as tables must scroll inside its own box rather than
/// widen the page; see AppDataTable.
class ResponsivePage extends StatelessWidget {
  const ResponsivePage({
    super.key,
    required this.child,
    this.scrollable = true,
    this.maxWidth = AppLayout.contentMaxWidth,
  });

  final Widget child;
  final bool scrollable;
  final double maxWidth;

  static double gutterFor(double width) {
    final size = ScreenSize.fromWidth(width);
    if (size.isPhone) return AppSpacing.lg;
    if (!size.isLaptopOrWider) return AppSpacing.xl;
    return AppSpacing.xxl;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final gutter = gutterFor(constraints.maxWidth);
        final body = Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                gutter,
                AppSpacing.xl,
                gutter,
                AppSpacing.xxl,
              ),
              child: child,
            ),
          ),
        );
        if (!scrollable) return body;
        return SingleChildScrollView(child: body);
      },
    );
  }
}
