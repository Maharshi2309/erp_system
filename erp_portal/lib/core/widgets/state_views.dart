import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'app_button.dart';

/// Empty state: says why the list is empty and offers the next step
/// (board S96 — "never a dead end").
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actions = const [],
    this.iconTone = AppColors.primary,
  });

  final IconData icon;
  final String title;
  final String message;
  final List<Widget> actions;
  final Color iconTone;

  @override
  Widget build(BuildContext context) {
    return _CenteredState(
      leading: _IconBubble(icon: icon, color: iconTone),
      title: title,
      message: message,
      actions: actions,
    );
  }
}

/// Error state with an optional retry and support reference.
class ErrorState extends StatelessWidget {
  const ErrorState({
    super.key,
    this.title = 'Couldn’t load this',
    required this.message,
    this.reference,
    this.onRetry,
    this.headline,
    this.actions = const [],
  });

  final String title;
  final String message;
  final String? reference;
  final VoidCallback? onRetry;

  /// Large text above the title, e.g. "404".
  final String? headline;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return _CenteredState(
      leading: headline != null
          ? Text(headline!, style: AppTypography.metric)
          : const _IconBubble(
              icon: Icons.warning_amber_rounded,
              color: AppColors.danger,
            ),
      title: title,
      message: message,
      actions: [
        if (onRetry != null) AppButton(label: 'Try again', onPressed: onRetry),
        ...actions,
      ],
      footnote: reference == null ? null : 'Reference · $reference',
    );
  }
}

class _CenteredState extends StatelessWidget {
  const _CenteredState({
    required this.leading,
    required this.title,
    required this.message,
    required this.actions,
    this.footnote,
  });

  final Widget leading;
  final String title;
  final String message;
  final List<Widget> actions;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.xxl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              leading,
              const SizedBox(height: AppSpacing.md),
              Semantics(
                header: true,
                child: Text(
                  title,
                  style: AppTypography.cardTitle,
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: AppSpacing.xs + 2),
              Text(
                message,
                style: AppTypography.small,
                textAlign: TextAlign.center,
              ),
              if (actions.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: actions,
                ),
              ],
              if (footnote != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  footnote!,
                  style: AppTypography.helper.copyWith(
                    fontFamily: AppTypography.mono,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _IconBubble extends StatelessWidget {
  const _IconBubble({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: color, size: 22),
    );
  }
}
