import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/selection_controls.dart';
import '../../domain/branch.dart';

/// Weekly opening hours (board S18): a switch per day, opening and closing
/// times, "Copy to…" other days, and quick-fill presets. Errors come from
/// `validateBranchDetails` (`hours.N` keys).
class WeeklyHoursEditor extends StatefulWidget {
  const WeeklyHoursEditor({
    super.key,
    required this.hours,
    required this.onChanged,
    this.errors = const {},
    this.onCopied,
  });

  final WeeklyHours hours;
  final ValueChanged<WeeklyHours> onChanged;
  final Map<String, String> errors;

  /// Called with a confirmation such as "Monday’s hours copied to 4 days".
  final ValueChanged<String>? onCopied;

  @override
  State<WeeklyHoursEditor> createState() => _WeeklyHoursEditorState();
}

class _WeeklyHoursEditorState extends State<WeeklyHoursEditor> {
  int? _copyFrom;
  Set<int> _copyTo = {};

  void _update(int day, DayHours hours) {
    final next = [...widget.hours];
    next[day] = hours;
    widget.onChanged(next);
  }

  void _applyCopy() {
    final from = widget.hours[_copyFrom!];
    final next = [
      for (var i = 0; i < 7; i++)
        _copyTo.contains(i)
            ? DayHours(
                open: true,
                opensAt: from.opensAt,
                closesAt: from.closesAt,
              )
            : widget.hours[i],
    ];
    final n = _copyTo.length;
    final message =
        '${weekdayNames[_copyFrom!]}’s hours copied to $n ${n == 1 ? 'day' : 'days'}';
    setState(() {
      _copyFrom = null;
      _copyTo = {};
    });
    widget.onChanged(next);
    widget.onCopied?.call(message);
  }

  @override
  Widget build(BuildContext context) {
    final presets = <(String, WeeklyHours)>[
      ('Mon–Sat · 9:30–18:30', HoursPresets.monSat930),
      ('Mon–Fri · 9:00–18:00', HoursPresets.monFri900),
      ('Every day · 10:00–20:00', HoursPresets.everyDay1000),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text('Quick fill:', style: AppTypography.helper),
            for (final (label, hours) in presets)
              ActionChip(
                label: Text(label, style: AppTypography.helper),
                onPressed: () => widget.onChanged([...hours]),
                side: const BorderSide(color: AppColors.borderStrong),
                backgroundColor: AppColors.surface,
              ),
          ],
        ),
        if (widget.errors['hours'] case final message?) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            message,
            style: AppTypography.helper.copyWith(color: AppColors.danger),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Column(
            children: [
              for (var day = 0; day < 7; day++) ...[
                if (day > 0) const Divider(height: 1),
                _DayRow(
                  day: day,
                  hours: widget.hours[day],
                  error: widget.errors['hours.$day'],
                  onChanged: (h) => _update(day, h),
                  copyOpen: _copyFrom == day,
                  onCopy: () => setState(() {
                    _copyFrom = _copyFrom == day ? null : day;
                    _copyTo = {};
                  }),
                ),
                if (_copyFrom == day)
                  _CopyPanel(
                    from: day,
                    selected: _copyTo,
                    onToggle: (target) => setState(() {
                      _copyTo = {..._copyTo};
                      if (!_copyTo.remove(target)) _copyTo.add(target);
                    }),
                    onSelectMonSat: () => setState(
                      () => _copyTo = {
                        for (var i = 0; i < 6; i++)
                          if (i != day) i,
                      },
                    ),
                    onCancel: () => setState(() {
                      _copyFrom = null;
                      _copyTo = {};
                    }),
                    onApply: _copyTo.isEmpty ? null : _applyCopy,
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _DayRow extends StatelessWidget {
  const _DayRow({
    required this.day,
    required this.hours,
    required this.onChanged,
    required this.copyOpen,
    required this.onCopy,
    this.error,
  });

  final int day;
  final DayHours hours;
  final ValueChanged<DayHours> onChanged;
  final bool copyOpen;
  final VoidCallback onCopy;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final name = weekdayNames[day];
    final m = hours.minutes;
    final length = m == 0
        ? '—'
        : '${m ~/ 60}h${m % 60 == 0 ? '' : ' ${m % 60}m'}';
    final toggle = Semantics(
      label: 'Open on $name',
      toggled: hours.open,
      excludeSemantics: true,
      child: Switch(
        value: hours.open,
        activeTrackColor: AppColors.primary,
        onChanged: (open) => onChanged(hours.copyWith(open: open)),
      ),
    );
    final times = hours.open
        ? Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TimeField(
                minutes: hours.opensAt,
                hasError: error != null,
                semanticLabel: '$name opening time',
                onChanged: (v) => onChanged(hours.copyWith(opensAt: v)),
              ),
              const Text('to', style: AppTypography.helper),
              TimeField(
                minutes: hours.closesAt,
                hasError: error != null,
                semanticLabel: '$name closing time',
                onChanged: (v) => onChanged(hours.copyWith(closesAt: v)),
              ),
              Text(length, style: AppTypography.helper),
            ],
          )
        : Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.neutralSoft,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: const Text('— Closed', style: AppTypography.helper),
          );
    final copy = hours.open
        ? AppButton(
            label: 'Copy to…',
            icon: Icons.copy_outlined,
            size: AppButtonSize.small,
            variant: AppButtonVariant.secondary,
            onPressed: onCopy,
          )
        : const SizedBox.shrink();

    return Container(
      color: hours.open ? AppColors.surface : AppColors.surfaceMuted,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked = constraints.maxWidth < 520;
          final label = SizedBox(
            width: 92,
            child: Text(name, style: AppTypography.label),
          );
          final errorText = error == null
              ? null
              : Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(
                    error!,
                    style: AppTypography.helper.copyWith(
                      color: AppColors.danger,
                    ),
                  ),
                );
          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    toggle,
                    Expanded(child: Text(name, style: AppTypography.label)),
                    if (hours.open)
                      IconButton(
                        tooltip: 'Copy $name’s hours to…',
                        icon: const Icon(Icons.copy_outlined, size: 18),
                        onPressed: onCopy,
                      ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(left: AppSpacing.xs),
                  child: times,
                ),
                ?errorText,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  toggle,
                  label,
                  Expanded(child: times),
                  copy,
                ],
              ),
              if (errorText != null)
                Padding(
                  padding: const EdgeInsets.only(left: 150),
                  child: errorText,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _CopyPanel extends StatelessWidget {
  const _CopyPanel({
    required this.from,
    required this.selected,
    required this.onToggle,
    required this.onSelectMonSat,
    required this.onCancel,
    required this.onApply,
  });

  final int from;
  final Set<int> selected;
  final ValueChanged<int> onToggle;
  final VoidCallback onSelectMonSat;
  final VoidCallback onCancel;
  final VoidCallback? onApply;

  @override
  Widget build(BuildContext context) {
    final n = selected.length;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.md,
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.primarySelected,
        border: Border.all(color: const Color(0xFFC9D2F6)),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Copy ${weekdayNames[from]} hours to:',
            style: AppTypography.helper.copyWith(color: AppColors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (var i = 0; i < 7; i++)
                if (i != from)
                  FilterChip(
                    label: Text(weekdayShort[i]),
                    selected: selected.contains(i),
                    onSelected: (_) => onToggle(i),
                    selectedColor: AppColors.primarySoft,
                    checkmarkColor: AppColors.primary,
                  ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              AppButton(
                label: 'Select Mon–Sat',
                variant: AppButtonVariant.ghost,
                size: AppButtonSize.small,
                onPressed: onSelectMonSat,
              ),
              Wrap(
                spacing: AppSpacing.sm,
                children: [
                  AppButton(
                    label: 'Cancel',
                    variant: AppButtonVariant.secondary,
                    size: AppButtonSize.small,
                    onPressed: onCancel,
                  ),
                  AppButton(
                    label: n == 0
                        ? 'Apply'
                        : 'Apply to $n ${n == 1 ? 'day' : 'days'}',
                    size: AppButtonSize.small,
                    onPressed: onApply,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
