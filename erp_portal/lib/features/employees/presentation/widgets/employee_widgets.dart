import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/initials.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_date_field.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../domain/employee.dart';

final employeeDateFormat = DateFormat('dd MMM y');

/// Avatar palette from the design boards, picked by the person's ID so the
/// same person keeps the same colour.
const _palette = [
  (AppColors.primarySoft, AppColors.primaryHover),
  (AppColors.successSoft, AppColors.success),
  (AppColors.warningSoft, Color(0xFF8A4F00)),
  (AppColors.neutralSoft, Color(0xFF344054)),
];

class EmployeeAvatar extends StatelessWidget {
  const EmployeeAvatar({super.key, required this.employee, this.size = 36});

  final Employee employee;
  final double size;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = _palette[employee.code.hashCode.abs() % _palette.length];
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
        // Decorative initials in a fixed circle: cap scaling so both fit.
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.3,
          child: Text(
            initialsOf(employee.fullName),
            maxLines: 1,
            style: AppTypography.label.copyWith(
              color: fg,
              fontWeight: FontWeight.w600,
              fontSize: size >= 56 ? 20 : 12,
            ),
          ),
        ),
      ),
    );
  }
}

StatusTone employmentTone(EmploymentStatus s) => switch (s) {
  EmploymentStatus.active => StatusTone.success,
  EmploymentStatus.probation ||
  EmploymentStatus.noticePeriod => StatusTone.warning,
  EmploymentStatus.terminated => StatusTone.danger,
  EmploymentStatus.inactive => StatusTone.neutral,
};

StatusTone accountTone(AccountStatus s) => switch (s) {
  AccountStatus.invited => StatusTone.info,
  AccountStatus.inviteExpired => StatusTone.danger,
  AccountStatus.signedIn || AccountStatus.noAccount => StatusTone.neutral,
};

class EmploymentBadge extends StatelessWidget {
  const EmploymentBadge(this.status, {super.key});

  final EmploymentStatus status;

  @override
  Widget build(BuildContext context) =>
      StatusBadge(label: status.label, tone: employmentTone(status));
}

class AccountBadge extends StatelessWidget {
  const AccountBadge(this.status, {super.key});

  final AccountStatus status;

  @override
  Widget build(BuildContext context) =>
      StatusBadge(label: status.label, tone: accountTone(status));
}

/// Label above a value, used on profile and summary cards.
class FactTile extends StatelessWidget {
  const FactTile({
    super.key,
    required this.label,
    required this.value,
    this.mono = false,
    this.locked = false,
    this.trailing,
  });

  final String label;
  final String value;
  final bool mono;

  /// Masked or restricted (shows a lock).
  final bool locked;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: AppTypography.helper),
        const SizedBox(height: 2),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (locked) ...[
              const Icon(
                Icons.lock_outline,
                size: 13,
                color: AppColors.textMuted,
              ),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(
                value.isEmpty ? '—' : value,
                style: AppTypography.small.copyWith(
                  color: AppColors.textPrimary,
                  fontFamily: mono ? AppTypography.mono : null,
                ),
              ),
            ),
            ?trailing,
          ],
        ),
      ],
    );
  }
}

/// Result of a lifecycle dialog (deactivate, notice period, terminate).
typedef LifecycleInput = ({String reason, DateTime? date});

/// Asks for a reason (and optionally a date) before a lifecycle change
/// (PRD §6.3; terminate per Q-12 option b).
Future<LifecycleInput?> showLifecycleDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
  bool reasonRequired = true,
  String? dateLabel,
  DateTime? initialDate,
}) => showDialog<LifecycleInput>(
  context: context,
  builder: (context) => _LifecycleDialog(
    title: title,
    message: message,
    confirmLabel: confirmLabel,
    destructive: destructive,
    reasonRequired: reasonRequired,
    dateLabel: dateLabel,
    initialDate: initialDate,
  ),
);

class _LifecycleDialog extends StatefulWidget {
  const _LifecycleDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.destructive,
    required this.reasonRequired,
    required this.dateLabel,
    required this.initialDate,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final bool destructive;
  final bool reasonRequired;
  final String? dateLabel;
  final DateTime? initialDate;

  @override
  State<_LifecycleDialog> createState() => _LifecycleDialogState();
}

class _LifecycleDialogState extends State<_LifecycleDialog> {
  final _reason = TextEditingController();
  late DateTime? _date = widget.initialDate;
  String? _reasonError;
  String? _dateError;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _confirm() {
    setState(() {
      _reasonError = widget.reasonRequired && _reason.text.trim().isEmpty
          ? 'Enter a reason. It is kept in the history.'
          : null;
      _dateError = widget.dateLabel != null && _date == null
          ? 'Choose a date.'
          : null;
    });
    if (_reasonError != null || _dateError != null) return;
    Navigator.of(context).pop((reason: _reason.text.trim(), date: _date));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(AppSpacing.lg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(widget.title, style: AppTypography.sectionTitle),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(widget.message, style: AppTypography.bodySecondary),
              const SizedBox(height: AppSpacing.lg),
              if (widget.dateLabel != null) ...[
                AppDateField(
                  label: widget.dateLabel!,
                  value: _date,
                  isRequired: true,
                  errorText: _dateError,
                  onChanged: (d) => setState(() => _date = d),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              AppTextField(
                label: 'Reason',
                controller: _reason,
                isRequired: widget.reasonRequired,
                isOptional: !widget.reasonRequired,
                errorText: _reasonError,
                onSubmitted: (_) => _confirm(),
              ),
              const SizedBox(height: AppSpacing.xl),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  AppButton(
                    label: 'Cancel',
                    variant: AppButtonVariant.secondary,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  AppButton(
                    label: widget.confirmLabel,
                    variant: widget.destructive
                        ? AppButtonVariant.danger
                        : AppButtonVariant.primary,
                    onPressed: _confirm,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
