import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'app_button.dart';

/// Data table inside a bordered box. When the table is wider than the box it
/// scrolls sideways inside the box instead of widening the page.
class AppDataTable extends StatelessWidget {
  const AppDataTable({
    super.key,
    required this.columns,
    required this.rows,
    this.minWidth = 720,
    this.sortColumnIndex,
    this.sortAscending = true,
    this.footer,
    this.showCheckboxColumn = true,
  });

  final List<DataColumn> columns;
  final List<DataRow> rows;

  /// Width below which the table starts to scroll horizontally.
  final double minWidth;
  final int? sortColumnIndex;
  final bool sortAscending;

  /// Usually a [PaginationBar].
  final Widget? footer;

  /// Off when tapping a row selects it for a detail panel.
  final bool showCheckboxColumn;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) => Scrollbar(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minWidth: math.max(constraints.maxWidth, minWidth),
                    ),
                    child: DataTable(
                      columns: columns,
                      rows: rows,
                      sortColumnIndex: sortColumnIndex,
                      sortAscending: sortAscending,
                      showCheckboxColumn: showCheckboxColumn,
                      border: const TableBorder(
                        horizontalInside: BorderSide(color: AppColors.divider),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (footer != null) ...[const Divider(height: 1), footer!],
          ],
        ),
      ),
    );
  }
}

/// "Showing 1–10 of 78 · Rows [10] · Previous · Next".
class PaginationBar extends StatelessWidget {
  const PaginationBar({
    super.key,
    required this.firstIndex,
    required this.pageSize,
    required this.totalCount,
    required this.onPageChanged,
    this.pageSizeOptions = const [10, 25, 50],
    this.onPageSizeChanged,
    this.itemLabel,
  });

  /// Zero-based index of the first row on this page.
  final int firstIndex;
  final int pageSize;
  final int totalCount;

  /// Receives the new zero-based first index.
  final ValueChanged<int> onPageChanged;
  final List<int> pageSizeOptions;
  final ValueChanged<int>? onPageSizeChanged;

  /// Appended to the range, e.g. "in Surat".
  final String? itemLabel;

  @override
  Widget build(BuildContext context) {
    final start = totalCount == 0 ? 0 : firstIndex + 1;
    final end = math.min(firstIndex + pageSize, totalCount);
    final hasPrevious = firstIndex > 0;
    final hasNext = end < totalCount;
    final range =
        'Showing $start–$end of $totalCount'
        '${itemLabel == null ? '' : ' $itemLabel'}';

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm + 2,
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.sm,
        children: [
          Text(range, style: AppTypography.small),
          // A Wrap, not a Row: on phones the rows selector drops onto its
          // own line instead of overflowing.
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              if (onPageSizeChanged != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Rows', style: AppTypography.small),
                    const SizedBox(width: AppSpacing.xs + 2),
                    DropdownButton<int>(
                      value: pageSize,
                      underline: const SizedBox.shrink(),
                      style: AppTypography.small.copyWith(
                        color: AppColors.textPrimary,
                      ),
                      items: [
                        for (final size in pageSizeOptions)
                          DropdownMenuItem(value: size, child: Text('$size')),
                      ],
                      onChanged: (size) {
                        if (size != null) onPageSizeChanged!(size);
                      },
                    ),
                  ],
                ),
              AppButton(
                label: 'Previous',
                variant: AppButtonVariant.secondary,
                size: AppButtonSize.small,
                onPressed: hasPrevious
                    ? () => onPageChanged(math.max(0, firstIndex - pageSize))
                    : null,
              ),
              AppButton(
                label: 'Next',
                variant: AppButtonVariant.secondary,
                size: AppButtonSize.small,
                onPressed: hasNext
                    ? () => onPageChanged(firstIndex + pageSize)
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
