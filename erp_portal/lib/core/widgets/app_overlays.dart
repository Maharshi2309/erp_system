import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'app_button.dart';
import 'app_text_field.dart';

/// Asks the user to confirm an action. Resolves to `true` only when the
/// confirm button is pressed; Esc, Cancel and tapping outside give `false`.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = 'Cancel',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => Dialog(
      insetPadding: const EdgeInsets.all(AppSpacing.lg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(title, style: AppTypography.sectionTitle),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(message, style: AppTypography.bodySecondary),
              const SizedBox(height: AppSpacing.xl),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  AppButton(
                    label: cancelLabel,
                    variant: AppButtonVariant.secondary,
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                  AppButton(
                    label: confirmLabel,
                    variant: destructive
                        ? AppButtonVariant.danger
                        : AppButtonVariant.primary,
                    onPressed: () => Navigator.of(context).pop(true),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
  return result ?? false;
}

/// Opens a side panel from the right for a quick view or a step form
/// without leaving the list (board S02). 440 px wide, full width below
/// 600 px. It is modal, so focus stays inside; Esc closes it.
Future<T?> showSidePanel<T>(
  BuildContext context, {
  required String title,
  String? subtitle,
  required WidgetBuilder body,
  List<Widget> Function(BuildContext context)? actions,
}) => showSidePanelRoute<T>(
  context,
  barrierLabel: 'Close $title',
  builder: (context) => SidePanelFrame(
    title: title,
    subtitle: subtitle,
    body: body(context),
    footer: actions == null
        ? null
        : Wrap(
            alignment: WrapAlignment.end,
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: actions(context),
          ),
  ),
);

/// Low-level side panel: slide-in, width and barrier. [builder] usually
/// returns a [SidePanelFrame]; use this when the panel content is stateful.
Future<T?> showSidePanelRoute<T>(
  BuildContext context, {
  required String barrierLabel,
  required WidgetBuilder builder,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: barrierLabel,
    barrierColor: AppColors.scrim,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, _, _) {
      final screenWidth = MediaQuery.sizeOf(context).width;
      final width = screenWidth < AppLayout.sidePanelFullWidthBelow
          ? screenWidth
          : AppLayout.sidePanelWidth;
      return Align(
        alignment: Alignment.centerRight,
        child: Material(
          color: AppColors.surface,
          elevation: 12,
          child: SizedBox(
            width: width,
            height: double.infinity,
            child: SafeArea(child: builder(context)),
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOut);
      return SlideTransition(
        position: Tween(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      );
    },
  );
}

/// Header, scrolling body and sticky footer of a side panel.
class SidePanelFrame extends StatelessWidget {
  const SidePanelFrame({
    super.key,
    required this.title,
    required this.body,
    this.subtitle,
    this.footer,
    this.onClose,
  });

  final String title;
  final String? subtitle;
  final Widget body;
  final Widget? footer;

  /// Defaults to closing the panel.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PanelHeader(title: title, subtitle: subtitle, onClose: onClose),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg + 2),
            child: body,
          ),
        ),
        if (footer != null) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg + 2,
              vertical: AppSpacing.md,
            ),
            child: footer,
          ),
        ],
      ],
    );
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({required this.title, this.subtitle, this.onClose});

  final String title;
  final String? subtitle;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg + 2,
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(title, style: AppTypography.cardTitle),
                ),
                if (subtitle != null)
                  Text(subtitle!, style: AppTypography.helper),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Close',
            iconSize: 20,
            constraints: const BoxConstraints.tightFor(width: 44, height: 44),
            onPressed: onClose ?? () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.close, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// Small confirmation at the bottom of the screen, e.g. "✓ Owner profile
/// saved". Shown only after the server confirmed the change.
void showAppToast(
  BuildContext context,
  String message, {
  IconData icon = Icons.check,
}) => showToastWith(
  ScaffoldMessenger.of(context),
  message,
  screenWidth: MediaQuery.sizeOf(context).width,
  icon: icon,
);

/// Same as [showAppToast] for callers that leave the page before the
/// toast appears (e.g. after sign-in): capture the app-level messenger
/// first, then call this after the `await`.
void showToastWith(
  ScaffoldMessengerState messenger,
  String message, {
  required double screenWidth,
  IconData icon = Icons.check,
}) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        width: screenWidth < 452 ? screenWidth - 32 : 420,
        duration: const Duration(milliseconds: 4500),
        content: Row(
          children: [
            Icon(icon, size: 16, color: AppColors.successSoft),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
}

/// Asks for a reason of at least 3 characters before a decision (e.g.
/// rejecting). Resolves to the trimmed reason, or null when cancelled.
Future<String?> showReasonDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String label = 'Reason',
  bool destructive = true,
}) => showDialog<String>(
  context: context,
  builder: (_) => _ReasonDialog(
    title: title,
    message: message,
    confirmLabel: confirmLabel,
    label: label,
    destructive: destructive,
  ),
);

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.label,
    required this.destructive,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final String label;
  final bool destructive;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _text = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _confirm() {
    final reason = _text.text.trim();
    if (reason.length < 3) {
      setState(() => _error = 'Enter at least 3 characters.');
      return;
    }
    Navigator.of(context).pop(reason);
  }

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(AppSpacing.lg),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
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
            AppTextField(
              label: widget.label,
              controller: _text,
              isRequired: true,
              maxLines: 3,
              errorText: _error,
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
