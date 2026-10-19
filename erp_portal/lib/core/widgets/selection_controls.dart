import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'focus_ring.dart';

/// One choice in a vertical list of cards with a title and description
/// (e.g. "Mobile app — Employees punch on their phone…", board S21).
class OptionCard extends StatelessWidget {
  const OptionCard({
    super.key,
    required this.title,
    required this.selected,
    required this.onTap,
    this.description,
  });

  final String title;
  final String? description;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
      label: [title, ?description].join('. '),
      excludeSemantics: true,
      child: FocusRing(
        child: Material(
          color: selected ? AppColors.primarySelected : AppColors.surface,
          shape: RoundedRectangleBorder(
            side: BorderSide(
              color: selected ? AppColors.primary : AppColors.border,
              width: selected ? 1.5 : 1,
            ),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(
                      selected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      size: 18,
                      color: selected ? AppColors.primary : AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm + 2),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: AppTypography.label),
                        if (description != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              description!,
                              style: AppTypography.helper,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Row of pill choices (employee range, designation suggestions).
class ChoiceChips<T> extends StatelessWidget {
  const ChoiceChips({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.hasError = false,
    this.minWidth = 0,
  });

  final List<(T, String)> options;
  final T? selected;
  final ValueChanged<T> onSelected;
  final bool hasError;
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final (value, label) in options)
          Semantics(
            inMutuallyExclusiveGroup: true,
            checked: value == selected,
            button: true,
            label: label,
            excludeSemantics: true,
            child: FocusRing(
              child: Material(
                color: value == selected
                    ? AppColors.primarySoft
                    : AppColors.surface,
                shape: RoundedRectangleBorder(
                  side: BorderSide(
                    color: value == selected
                        ? AppColors.primary
                        : (hasError
                              ? const Color(0xFFE8A39C)
                              : AppColors.borderStrong),
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: InkWell(
                  onTap: () => onSelected(value),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: Container(
                    constraints: BoxConstraints(
                      minWidth: minWidth,
                      minHeight: 40,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md + 2,
                    ),
                    // Sized to the label, centred within minWidth/minHeight.
                    child: Align(
                      widthFactor: 1,
                      child: Text(
                        label,
                        style: AppTypography.small.copyWith(
                          color: value == selected
                              ? AppColors.primaryHover
                              : AppColors.textPrimary,
                          fontWeight: value == selected
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// A switch with a label and optional description, the whole row tappable.
class SwitchRow extends StatelessWidget {
  const SwitchRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.description,
    this.lockedNote,
  });

  final String label;
  final String? description;
  final bool value;

  /// Null makes the switch read-only (e.g. "Punch in and out · always on").
  final ValueChanged<bool>? onChanged;
  final String? lockedNote;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: InkWell(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs + 2),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        text: label,
                        children: [
                          if (lockedNote != null)
                            TextSpan(
                              text: lockedNote,
                              style: AppTypography.helper,
                            ),
                        ],
                      ),
                      style: AppTypography.body,
                    ),
                    if (description != null)
                      Text(description!, style: AppTypography.helper),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Switch(
                value: value,
                onChanged: onChanged,
                activeTrackColor: AppColors.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "09:30 AM" button that opens the time picker. Value in minutes after
/// midnight.
class TimeField extends StatelessWidget {
  const TimeField({
    super.key,
    required this.minutes,
    required this.onChanged,
    required this.semanticLabel,
    this.hasError = false,
    this.enabled = true,
  });

  final int minutes;
  final ValueChanged<int> onChanged;
  final String semanticLabel;
  final bool hasError;
  final bool enabled;

  static String format(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    final period = h < 12 ? 'AM' : 'PM';
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '${h12.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')} $period';
  }

  Future<void> _pick(BuildContext context) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
    );
    if (picked != null) onChanged(picked.hour * 60 + picked.minute);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$semanticLabel, ${format(minutes)}',
      excludeSemantics: true,
      child: FocusRing(
        child: Material(
          color: enabled ? AppColors.surface : AppColors.surfaceMuted,
          shape: RoundedRectangleBorder(
            side: BorderSide(
              color: hasError ? AppColors.danger : AppColors.borderStrong,
            ),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: InkWell(
            onTap: enabled ? () => _pick(context) : null,
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm + 2,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    format(minutes),
                    style: AppTypography.small.copyWith(
                      fontFamily: AppTypography.mono,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  const Icon(
                    Icons.schedule,
                    size: 16,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
