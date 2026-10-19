import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../audit/presentation/audit_providers.dart';
import '../providers/auth_providers.dart';

/// "Confirm it’s you" before a high-impact change (boards S68, S83). True
/// when the password matched; the re-authentication is logged.
Future<bool> confirmItsYou(BuildContext context, {required String why}) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) => _ConfirmDialog(why: why),
    ) ??
    false;

class _ConfirmDialog extends ConsumerStatefulWidget {
  const _ConfirmDialog({required this.why});

  final String why;

  @override
  ConsumerState<_ConfirmDialog> createState() => _ConfirmDialogState();
}

class _ConfirmDialogState extends ConsumerState<_ConfirmDialog> {
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(authRepositoryProvider)
          .signIn(identifier: session.email, password: _password.text);
      await ref
          .read(auditRecorderProvider)
          .record(
            action: 'auth.reauth',
            entityType: 'Sign-in',
            entityLabel: session.displayName,
            summary: 'Confirmed with password · ${widget.why}',
          );
      if (mounted) Navigator.of(context).pop(true);
    } on Failure {
      if (mounted) {
        setState(() => _error = 'That password isn’t right. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(AppSpacing.lg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: const Text(
                  'Confirm it’s you',
                  style: AppTypography.sectionTitle,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Enter your password to ${widget.why}.',
                style: AppTypography.body,
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                label: 'Password',
                isRequired: true,
                isPassword: true,
                controller: _password,
                errorText: _error,
                autofillHints: const [AutofillHints.password],
                onSubmitted: (_) => _confirm(),
              ),
              const SizedBox(height: AppSpacing.lg),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: AppSpacing.sm,
                children: [
                  AppButton(
                    label: 'Cancel',
                    variant: AppButtonVariant.secondary,
                    onPressed: _busy
                        ? null
                        : () => Navigator.of(context).pop(false),
                  ),
                  AppButton(
                    label: 'Confirm',
                    busy: _busy,
                    busyLabel: 'Checking…',
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
