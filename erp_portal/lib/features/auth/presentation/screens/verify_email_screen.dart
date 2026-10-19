import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/config/app_config.dart';
import '../../../../app/router/route_names.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/app_button.dart';
import '../../data/demo_auth_repository.dart';
import '../../domain/auth_state.dart';
import '../providers/auth_providers.dart';
import '../widgets/auth_layout.dart';
import '../widgets/auth_widgets.dart';

/// Board S05 — email verification with a 6-digit code and resend timer.
class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  static const _resendAfter = 45;

  final _code = TextEditingController();
  Timer? _timer;
  int _secondsLeft = _resendAfter;
  bool _busy = false;
  bool _resent = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    _secondsLeft = _resendAfter;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsLeft <= 1) timer.cancel();
      setState(() => _secondsLeft--);
    });
  }

  Future<void> _verify() async {
    if (_busy || _code.text.length != 6) return;
    setState(() => _busy = true);
    try {
      await ref.read(authControllerProvider.notifier).verifyEmail(_code.text);
    } on Failure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend(String email) async {
    await ref.read(authRepositoryProvider).resendVerificationCode(email);
    if (!mounted) return;
    setState(() {
      _resent = true;
      _error = null;
      _code.clear();
    });
    _startTimer();
  }

  Future<void> _useDifferentEmail() async {
    await ref.read(authControllerProvider.notifier).signOut();
    if (mounted) context.go(AppRoutes.register);
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final showDemo = ref.watch(appConfigProvider).showDevTools;
    final verified = auth is NeedsOrganization;
    final email = switch (auth) {
      AwaitingEmailVerification(:final email) => email,
      NeedsOrganization(:final account) => account.email,
      _ => '',
    };

    return AuthLayout(
      child: verified
          ? _Verified(onContinue: () => context.go(AppRoutes.onboarding))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _IconTile(icon: Icons.mail_outline),
                const SizedBox(height: AppSpacing.lg + 4),
                AuthHeading(
                  title: 'Check your email',
                  lead: Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(text: 'We sent a 6-digit code to '),
                        TextSpan(
                          text: maskEmail(email),
                          style: AppTypography.bodyStrong,
                        ),
                        const TextSpan(text: '. It expires in 10 minutes.'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg + 4),
                CodeField(
                  label: 'Verification code',
                  controller: _code,
                  hasError: _error != null,
                  message:
                      _error ??
                      (_resent
                          ? 'New code sent. Earlier codes no longer work.'
                          : 'Enter all 6 digits.'),
                  onChanged: (_) => setState(() {
                    _error = null;
                    _resent = false;
                  }),
                  onSubmitted: (_) => _verify(),
                ),
                const SizedBox(height: AppSpacing.lg + 4),
                AppButton(
                  label: 'Verify email',
                  busyLabel: 'Verifying…',
                  busy: _busy,
                  size: AppButtonSize.large,
                  expand: true,
                  onPressed: _code.text.length == 6 ? _verify : null,
                ),
                const SizedBox(height: AppSpacing.lg),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    const Text(
                      'Didn’t get it? Check spam.',
                      style: AppTypography.small,
                    ),
                    if (_secondsLeft > 0)
                      Text(
                        'Resend in 0:${_secondsLeft.toString().padLeft(2, '0')}',
                        style: AppTypography.code,
                      )
                    else
                      TextLink('Resend code', onTap: () => _resend(email)),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextLink(
                    'Use a different email',
                    onTap: _useDifferentEmail,
                  ),
                ),
                if (showDemo) ...[
                  const SizedBox(height: AppSpacing.md),
                  const Text(
                    'Demo: use code ${DemoAuthRepository.demoEmailCode}.',
                    style: AppTypography.helper,
                  ),
                ],
              ],
            ),
    );
  }
}

class _Verified extends StatelessWidget {
  const _Verified({required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _IconTile(icon: Icons.check, success: true),
        const SizedBox(height: AppSpacing.lg + 4),
        const AuthHeading(
          title: 'Email verified',
          lead: Text('Next, tell us about your organization.'),
        ),
        const SizedBox(height: AppSpacing.xl),
        AppButton(
          label: 'Set up organization',
          size: AppButtonSize.large,
          expand: true,
          onPressed: onContinue,
        ),
      ],
    );
  }
}

class _IconTile extends StatelessWidget {
  const _IconTile({required this.icon, this.success = false});

  final IconData icon;
  final bool success;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: success ? AppColors.successSoft : AppColors.primarySoft,
          borderRadius: BorderRadius.circular(success ? 24 : AppRadius.lg),
        ),
        child: Icon(
          icon,
          color: success ? AppColors.success : AppColors.primary,
        ),
      ),
    );
  }
}
