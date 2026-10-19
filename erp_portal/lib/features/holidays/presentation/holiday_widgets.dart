import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../organization/domain/branch.dart';
import '../domain/company_holiday.dart';

/// How a holiday is drawn (boards S62, S93 legend).
enum HolidayLook {
  org(AppColors.primary, AppColors.surface, 'Organization-wide'),
  branch(AppColors.surface, Color(0xFF8A3A12), 'Branch-specific'),
  optional(AppColors.surface, Color(0xFF344054), 'Optional / floating');

  const HolidayLook(this.background, this.foreground, this.label);

  final Color background;
  final Color foreground;
  final String label;

  static HolidayLook of(CompanyHoliday h) =>
      h.optional ? optional : (h.orgWide ? org : branch);

  static HolidayLook ofItem(HolidayItem h) =>
      h.optional ? optional : (h.orgWide ? org : branch);

  BoxBorder? get border => switch (this) {
    org => null,
    branch => Border.all(color: const Color(0xFFB4471C), width: 2),
    optional => Border.all(color: AppColors.borderStrong),
  };
}

/// Diagonal stripes for optional holidays (never colour alone: the legend
/// and labels name them too).
class Stripes extends StatelessWidget {
  const Stripes({super.key, this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _StripePainter(), child: child);
}

class _StripePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFEDEFF3)
      ..strokeWidth = 4;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (var x = -size.height; x < size.width; x += 8) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        paint,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_StripePainter oldDelegate) => false;
}

/// A legend swatch.
class LegendSwatch extends StatelessWidget {
  const LegendSwatch({
    super.key,
    required this.label,
    this.color = AppColors.surface,
    this.border,
    this.striped = false,
  });

  final String label;
  final Color color;
  final BoxBorder? border;
  final bool striped;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: striped ? null : color,
        border: border,
        borderRadius: BorderRadius.circular(3),
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (striped)
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: Stripes(child: box),
          )
        else
          box,
        const SizedBox(width: 6),
        Flexible(child: Text(label, style: AppTypography.helper)),
      ],
    );
  }
}

/// One day cell's look.
class CalendarDay {
  const CalendarDay({
    this.background = AppColors.surface,
    this.foreground = AppColors.textPrimary,
    this.border,
    this.striped = false,
    this.bold = false,
    this.events = const [],
    required this.semantics,
  });

  final Color background;
  final Color foreground;
  final BoxBorder? border;
  final bool striped;
  final bool bold;

  /// Small labelled chips shown in tall cells: (text, look).
  final List<(String, HolidayLook)> events;
  final String semantics;
}

/// A Monday-first month grid (boards S62, S93).
class MonthCalendar extends StatelessWidget {
  const MonthCalendar({
    super.key,
    required this.month,
    required this.dayOf,
    this.tall = false,
    this.onTap,
  });

  final DateTime month;
  final CalendarDay Function(DateTime date) dayOf;

  /// Room for event chips (desktop calendar).
  final bool tall;
  final ValueChanged<DateTime>? onTap;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month);
    final days = DateTime(month.year, month.month + 1, 0).day;
    return LayoutBuilder(
      builder: (context, c) {
        const gap = 4.0;
        final cell = (c.maxWidth - 6 * gap) / 7;
        final showEvents = tall && cell >= 90;
        final height = showEvents ? 88.0 : cell.clamp(36.0, 56.0);
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final w in weekdayShort)
              SizedBox(
                width: cell,
                child: ExcludeSemantics(
                  child: Text(
                    cell < 44 ? w.substring(0, 1) : w,
                    textAlign: TextAlign.center,
                    style: AppTypography.helper,
                  ),
                ),
              ),
            for (var i = 0; i < first.weekday - 1; i++)
              SizedBox(width: cell, height: height),
            for (var d = 1; d <= days; d++)
              () {
                final date = DateTime(month.year, month.month, d);
                final look = dayOf(date);
                Widget body = Container(
                  width: cell,
                  height: height,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: look.striped ? null : look.background,
                    border: look.border ?? Border.all(color: AppColors.divider),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: showEvents
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$d',
                              style: AppTypography.helper.copyWith(
                                color: look.foreground,
                                fontWeight: look.bold
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                            for (final (text, kind) in look.events.take(2))
                              Container(
                                margin: const EdgeInsets.only(top: 2),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: kind.background,
                                  border: kind.border,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Text(
                                  text,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTypography.helper.copyWith(
                                    fontSize: 11,
                                    color: kind.foreground,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                          ],
                        )
                      : Center(
                          child: Text(
                            '$d',
                            style: AppTypography.small.copyWith(
                              color: look.foreground,
                              fontWeight: look.bold
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                );
                if (look.striped) {
                  body = ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    child: Stripes(child: body),
                  );
                }
                return Semantics(
                  label: look.semantics,
                  button: onTap != null,
                  excludeSemantics: true,
                  child: InkWell(
                    onTap: onTap == null ? null : () => onTap!(date),
                    child: body,
                  ),
                );
              }(),
          ],
        );
      },
    );
  }
}

/// "Tue 20 Oct" or "Mon 9 – Tue 10 Nov".
String holidayDates(CompanyHoliday h) {
  final f = DateFormat('EEE d MMM');
  if (!h.isRange) return f.format(h.date);
  if (h.date.month == h.endDate.month) {
    return '${DateFormat('EEE d').format(h.date)} – ${f.format(h.endDate)}';
  }
  return '${f.format(h.date)} – ${f.format(h.endDate)}';
}

/// "All branches", "Surat", "Employee picks · max 1".
String holidayScope(
  CompanyHoliday h,
  List<Branch> branches, {
  int optionalLimit = 1,
}) {
  if (h.optional) return 'Employee picks · max $optionalLimit';
  if (h.orgWide) return 'All branches';
  return [
    for (final id in h.branchIds)
      branches.where((b) => b.id == id).firstOrNull?.name ?? id,
  ].join(', ');
}

String categoryLabel(HolidayCategory c) => switch (c) {
  HolidayCategory.festival => 'Festival',
  HolidayCategory.national => 'National',
  HolidayCategory.regional => 'Regional',
  HolidayCategory.company => 'Company',
};
