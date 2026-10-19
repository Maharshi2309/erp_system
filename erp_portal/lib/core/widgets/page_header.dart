import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

class BreadcrumbItem {
  const BreadcrumbItem(this.label, {this.onTap});

  final String label;

  /// Null for the current page (the last item).
  final VoidCallback? onTap;
}

/// "Employees / Priya Desai" trail; the last item is the current page.
class Breadcrumbs extends StatelessWidget {
  const Breadcrumbs({super.key, required this.items});

  final List<BreadcrumbItem> items;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: Text('/', style: AppTypography.small),
            ),
          if (items[i].onTap != null)
            InkWell(
              onTap: items[i].onTap,
              child: Text(items[i].label, style: AppTypography.small),
            )
          else
            Text(
              items[i].label,
              style: AppTypography.small.copyWith(color: AppColors.textPrimary),
            ),
        ],
      ],
    );
  }
}

/// Page title (24 px), optional subtitle and actions. Actions sit to the
/// right on wide screens and wrap below the title on narrow ones.
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          header: true,
          child: Text(title, style: AppTypography.pageTitle),
        ),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(subtitle!, style: AppTypography.small),
          ),
      ],
    );
    if (actions.isEmpty) return titleBlock;

    final actionRow = Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      alignment: WrapAlignment.end,
      children: actions,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 600) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              titleBlock,
              const SizedBox(height: AppSpacing.md),
              actionRow,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: titleBlock),
            const SizedBox(width: AppSpacing.lg),
            // Capped so many actions wrap instead of overflowing.
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.6),
              child: actionRow,
            ),
          ],
        );
      },
    );
  }
}
