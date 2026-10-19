import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/config/app_config.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_overlays.dart';
import '../../data/demo_auth_repository.dart';
import '../../domain/auth_state.dart';
import '../providers/auth_providers.dart';
import '../widgets/auth_layout.dart';
import '../widgets/auth_widgets.dart';

/// Board S06 — second sign-in step: authenticator or one-time backup code.
/// Three wrong codes pause sign-in for 15 minutes.
class TwoStepScreen extends ConsumerStatefulWidget {
  const TwoStepScreen({super.key});

  @override
  ConsumerState<TwoStepScreen> createState() => _TwoStepScreenState();
}

class _TwoStepScreenState extends ConsumerState<TwoStepScreen> {
  final _code = TextEditingController();
  bool _backupMode = false;
  bool _trustDevice = false;
  bool _busy = false;
  String? _error;
  String? _lockedMessage;

  static final _backupPattern = RegExp(r'^[A-Z0-9]{4}-?[A-Z0-9]{4}$');

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  bool get _valid => _backupMode
      ? _backupPattern.hasMatch(_code.text)
      : RegExp(r'^\d{6}$').hasMatch(_code.text);

  Future<void> _verify() async {
    if (_busy || !_valid || _lockedMessage != null) return;
    setState(() => _busy = true);
    // Captured now: this page closes as soon as sign-in completes.
    final messenger = ScaffoldMessenger.of(context);
    final width = MediaQuery.sizeOf(context).width;
    try {
      final backupLeft = await ref
          .read(authControllerProvider.notifier)
          .verifyTwoStep(
            code: _code.text,
            isBackupCode: _backupMode,
            trustDevice: _trustDevice,
          );
      if (backupLeft != null) {
        showToastWith(
          messenger,
          'Backup code used — $backupLeft left. Generate new ones in My '
          'profile.',
          screenWidth: width,
        );
      }
    } on LockedFailure catch (failure) {
      if (mounted) setState(() => _lockedMessage = failure.message);
    } on Failure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _switchMode() => setState(() {
    _backupMode = !_backupMode;
    _code.clear();
    _error = null;
  });

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final email = auth is AwaitingTwoStep ? auth.account.email : '';
    final showDemo = ref.watch(appConfigProvider).showDevTools;
    final locked = _lockedMessage != null;

    return AuthLayout(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: const Icon(
                  Icons.verified_user_outlined,
                  size: 20,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Signing in as', style: AppTypography.helper),
                    Text(
                      email,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.label,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          AuthHeading(
            title: _backupMode
                ? 'Use a backup code'
                : 'Enter your sign-in code',
            lead: Text(
              _backupMode
                  ? 'Each of your 10 backup codes works once.'
                  : 'Open your authenticator app and enter the 6-digit code '
                        'for Staffline. Two-step sign-in is required for admin '
                        'roles.',
            ),
          ),
          const SizedBox(height: AppSpacing.lg + 4),
          if (locked) ...[
            AuthNotice(message: _lockedMessage!, tone: NoticeTone.error),
            const SizedBox(height: AppSpacing.lg),
          ],
          CodeField(
            key: ValueKey(_backupMode),
            label: _backupMode ? 'Backup code' : '6-digit code',
            controller: _code,
            isBackupCode: _backupMode,
            enabled: !locked,
            hasError: _error != null,
            message:
                _error ??
                (_backupMode
                    ? 'Letters and numbers, like 7KQ2-M9XD.'
                    : 'Codes change every 30 seconds.'),
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => _verify(),
          ),
          const SizedBox(height: AppSpacing.md),
          LabeledCheckbox(
            value: _trustDevice,
            onChanged: (v) => setState(() => _trustDevice = v),
            label: const Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'Don’t ask again on this device for 30 days\n',
                    style: TextStyle(color: AppColors.textPrimary),
                  ),
                  TextSpan(
                    text: 'Only on a computer you alone use.',
                    style: AppTypography.helper,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg + 4),
          AppButton(
            label: 'Verify and sign in',
            busyLabel: 'Checking…',
            busy: _busy,
            size: AppButtonSize.large,
            expand: true,
            onPressed: _valid && !locked ? _verify : null,
          ),
          const SizedBox(height: AppSpacing.lg + 4),
          const Divider(),
          const SizedBox(height: AppSpacing.lg),
          Align(
            alignment: Alignment.centerLeft,
            child: TextLink(
              _backupMode
                  ? 'Use authenticator app instead'
                  : 'Use a backup code instead',
              onTap: _switchMode,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          const Text(
            'Lost your phone and backup codes? Ask your organization owner to '
            'reset two-step sign-in for you.',
            style: AppTypography.small,
          ),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: TextLink(
              'Sign in as someone else',
              onTap: () => ref.read(authControllerProvider.notifier).signOut(),
            ),
          ),
          if (showDemo) ...[
            const SizedBox(height: AppSpacing.md),
            const Text(
              'Demo: code ${DemoAuthRepository.demoAuthenticatorCode} or backup '
              'code ${DemoAuthRepository.demoBackupCode}. Three wrong tries '
              'show the lockout.',
              style: AppTypography.helper,
            ),
          ],
        ],
      ),
    );
  }
}
