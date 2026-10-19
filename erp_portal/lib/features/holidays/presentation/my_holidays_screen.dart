import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/router/route_names.dart';
import '../../../core/responsive/responsive_page.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_card.dart';
import '../../leave/domain/leave.dart';
import '../../leave/presentation/leave_widgets.dart';
import 'holiday_widgets.dart';

/// Board S93 — the employee's holidays, leave and weekly offs by month.
class MyHolidaysScreen extends ConsumerStatefulWidget {
  const MyHolidaysScreen({super.key});

  @override
  ConsumerState<MyHolidaysScreen> createState() => _MyHolidaysScreenState();
}

class _MyHolidaysScreenState extends ConsumerState<MyHolidaysScreen> {
  int _offset = 0;

  @override
  Widget build(BuildContext context) => withLeaveSelf(ref, (book, self) {
    final today = book.today;
    final month = DateTime(today.year, today.month + _offset);
    final last = DateTime(month.year, month.month + 1, 0);
    final branch = book.branchOf(self);
    final optionalType = book.data.types
        .where((t) => t.optionalHolidaysOnly && t.active)
        .firstOrNull;
    final holidays = book.calendar.holidaysBetween(
      branch,
      month,
      last,
      includeOptional: true,
    );

    CalendarDay dayOf(DateTime d) {
      final h = book.holidayOn(self, d, includeOptional: true);
      final leave = book.leaveOn(self, d);
      final isToday = d == today;
      final parts = <String>[DateFormat('d MMMM').format(d)];
      var look = const CalendarDay(semantics: '');
      var bg = AppColors.surface;
      var fg = AppColors.textPrimary;
      var striped = false;
      BoxBorder? border;
      if (book.isWeeklyOff(self, d)) {
        bg = AppColors.surfaceMuted;
        fg = AppColors.textMuted;
        parts.add('weekly off');
      }
      if (leave != null) {
        bg = AppColors.successSoft;
        fg = const Color(0xFF0B5E4B);
        parts.add('your leave');
      }
      if (h != null) {
        if (h.optional) {
          striped = true;
          fg = AppColors.textPrimary;
          border = Border.all(color: AppColors.borderStrong);
          parts.add('${h.name}, optional');
        } else {
          bg = AppColors.primary;
          fg = AppColors.surface;
          parts.add(h.name);
        }
      }
      if (isToday) {
        border = Border.all(color: AppColors.textPrimary, width: 2);
        parts.add('today');
      }
      look = CalendarDay(
        background: bg,
        foreground: fg,
        border: border,
        striped: striped,
        bold: isToday || h != null,
        semantics: parts.join(', '),
      );
      return look;
    }

    return ResponsivePage(
      maxWidth: 720,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: const Text('Holidays', style: AppTypography.pageTitle),
          ),
          Text(branch?.name ?? '', style: AppTypography.small),
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Previous month',
                      onPressed: _offset <= -2
                          ? null
                          : () => setState(() => _offset--),
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Expanded(
                      child: Semantics(
                        header: true,
                        liveRegion: true,
                        child: Text(
                          DateFormat('MMMM y').format(month),
                          textAlign: TextAlign.center,
                          style: AppTypography.sectionTitle,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Next month',
                      onPressed: _offset >= 12
                          ? null
                          : () => setState(() => _offset++),
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                MonthCalendar(month: month, dayOf: dayOf),
                const SizedBox(height: AppSpacing.md),
                const Wrap(
                  spacing: AppSpacing.md,
                  runSpacing: 4,
                  children: [
                    LegendSwatch(label: 'Holiday', color: AppColors.primary),
                    LegendSwatch(
                      label: 'Optional',
                      striped: true,
                      border: Border.fromBorderSide(
                        BorderSide(color: AppColors.borderStrong),
                      ),
                    ),
                    LegendSwatch(
                      label: 'Your approved leave',
                      color: AppColors.successSoft,
                    ),
                    LegendSwatch(
                      label: 'Today',
                      border: Border.fromBorderSide(
                        BorderSide(color: AppColors.textPrimary, width: 2),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            padding: EdgeInsets.zero,
            child: holidays.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Text(
                      'No holidays in ${DateFormat('MMMM').format(month)}.',
                      style: AppTypography.small,
                    ),
                  )
                : Column(
                    children: [
                      for (final h in holidays)
                        _HolidayRow(
                          date: h.date,
                          name: h.name,
                          sub: h.optional
                              ? 'Optional · request to take it'
                              : [
                                  if (h.orgWide)
                                    'All branches'
                                  else
                                    branch?.name ?? '',
                                  if (book.isWeeklyOff(self, h.date))
                                    'falls on your weekly off',
                                ].join(' · '),
                          action:
                              h.optional &&
                                  optionalType != null &&
                                  !h.date.isBefore(today) &&
                                  !book
                                      .requestsOf(self)
                                      .any(
                                        (r) =>
                                            r.typeKey == optionalType.key &&
                                            r.status.holdsDays &&
                                            r.from == h.date,
                                      )
                              ? () => context.go(
                                  '${AppRoutes.applyLeave}?type=${optionalType.key}&from=${isoDate(h.date)}',
                                )
                              : null,
                          taken: book
                              .requestsOf(self)
                              .where(
                                (r) =>
                                    r.typeKey == optionalType?.key &&
                                    r.status.holdsDays &&
                                    r.from == h.date,
                              )
                              .firstOrNull
                              ?.status,
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Shows organization holidays and those for ${branch?.name ?? 'your branch'}. Optional holidays need a leave-style request.',
            textAlign: TextAlign.center,
            style: AppTypography.helper,
          ),
        ],
      ),
    );
  });
}

class _HolidayRow extends StatelessWidget {
  const _HolidayRow({
    required this.date,
    required this.name,
    required this.sub,
    this.action,
    this.taken,
  });

  final DateTime date;
  final String name;
  final String sub;
  final VoidCallback? action;
  final LeaveStatus? taken;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: 10,
      ),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Column(
              children: [
                Text(
                  DateFormat('EEE').format(date),
                  style: AppTypography.helper,
                ),
                Text(
                  '${date.day}',
                  style: AppTypography.code.copyWith(
                    fontSize: 17,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: MergeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: AppTypography.bodyStrong),
                  Text(sub, style: AppTypography.helper),
                ],
              ),
            ),
          ),
          if (taken != null)
            Flexible(child: LeaveStatusBadge(taken!))
          else if (action != null)
            TextButton(onPressed: action, child: const Text('Request')),
        ],
      ),
    );
  }
}
