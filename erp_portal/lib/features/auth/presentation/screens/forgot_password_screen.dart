import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/config/app_config.dart';
import '../../../../app/router/route_names.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../data/demo_auth_repository.dart';
import '../providers/auth_providers.dart';
import '../widgets/auth_layout.dart';
import '../widgets/auth_widgets.dart';

/// Board S07 — request a reset link. The confirmation never reveals
/// whether an account exists.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _identifier = TextEditingController();
  bool _busy = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _identifier.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_busy) return;
    if (_identifier.text.trim().isEmpty) {
      setState(() => _error = 'Enter your work email or employee ID.');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(authRepositoryProvider)
          .requestPasswordReset(_identifier.text.trim());
      if (mounted) setState(() => _sent = true);
    } on Failure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final showDemo = ref.watch(appConfigProvider).showDevTools;
    return AuthLayout(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AuthHeading(
            title: 'Reset your password',
            lead: Text('Enter the work email or employee ID you sign in with.'),
          ),
          const SizedBox(height: AppSpacing.lg + 2),
          AppTextField(
            label: 'Work email or employee ID',
            controller: _identifier,
            errorText: _error,
            autofillHints: const [AutofillHints.username],
            onChanged: (_) => setState(() {
              _error = null;
              _sent = false;
            }),
            onSubmitted: (_) => _send(),
          ),
          const SizedBox(height: AppSpacing.lg + 2),
          if (_sent) ...[
            const AuthNotice(
              tone: NoticeTone.success,
              message:
                  'If an account matches, we’ve sent a reset link to its '
                  'email. The link works once and expires in 30 minutes.',
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          AppButton(
            label: _sent ? 'Send again' : 'Send reset link',
            busyLabel: 'Sending…',
            busy: _busy,
            variant: _sent
                ? AppButtonVariant.secondary
                : AppButtonVariant.primary,
            size: AppButtonSize.large,
            expand: true,
            onPressed: _send,
          ),
          const SizedBox(height: AppSpacing.lg),
          const Divider(),
          const SizedBox(height: AppSpacing.md),
          const Text(
            'No work email on file? Ask your HR admin to send a reset link '
            'from your profile.',
            style: AppTypography.small,
          ),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: TextLink(
              'Back to sign in',
              onTap: () => context.go(AppRoutes.welcome),
            ),
          ),
          if (showDemo && _sent) ...[
            const SizedBox(height: AppSpacing.md),
            Align(
              alignment: Alignment.centerLeft,
              child: TextLink(
                'Demo: open the emailed reset link',
                onTap: () => context.go(
                  '${AppRoutes.resetPassword}?token='
                  '${DemoAuthRepository.demoResetToken}',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
