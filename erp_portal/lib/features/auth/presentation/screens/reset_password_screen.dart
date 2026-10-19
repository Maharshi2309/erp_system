import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/route_names.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_overlays.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/skeleton.dart';
import '../../domain/auth_models.dart';
import '../../domain/password_rules.dart';
import '../providers/auth_providers.dart';
import '../widgets/auth_layout.dart';
import '../widgets/auth_widgets.dart';

/// Opens the reset link [token] (null when the URL has none).
final _resetLinkProvider = FutureProvider.autoDispose
    .family<ResetLink, String?>((ref, token) {
      if (token == null || token.isEmpty) {
        throw const ExpiredFailure(
          'Open the link from your reset email. Links work once and expire '
          'after 30 minutes.',
        );
      }
      return ref.read(authRepositoryProvider).openResetLink(token);
    });

/// Board S08 — set a new password from the emailed link.
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key, required this.token});

  final String? token;

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _passwordError;
  String? _confirmError;
  String? _formError;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _passwordError = isStrongPassword(_password.text)
          ? null
          : 'Meet all the password rules below.';
      _confirmError = _confirm.text == _password.text
          ? null
          : 'Passwords don’t match. Re-type the new password.';
      _formError = null;
    });
    if (_passwordError != null || _confirmError != null) return;

    setState(() => _busy = true);
    try {
      await ref
          .read(authRepositoryProvider)
          .resetPassword(token: widget.token!, newPassword: _password.text);
      if (!mounted) return;
      showAppToast(
        context,
        'Password updated. Sign in with your new password.',
      );
      context.go(AppRoutes.welcome);
    } on Failure catch (failure) {
      if (mounted) setState(() => _formError = failure.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final link = ref.watch(_resetLinkProvider(widget.token));
    return AuthLayout(
      child: link.when(
        loading: () => const LoadingSkeleton(
          label: 'Checking your link',
          child: SkeletonList(rows: 3),
        ),
        error: (error, _) => _Expired(
          message: userMessageFor(error),
          onRequestNew: () => context.go(AppRoutes.forgotPassword),
        ),
        data: _form,
      ),
    );
  }

  Widget _form(ResetLink link) {
    final rules = passwordRules(_password.text);
    final allMet = rules.every((r) => r.isMet);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AuthHeading(
          title: 'Set a new password',
          lead: Text(
            'For ${link.maskedEmail}. You’ll be signed out on other devices.',
          ),
        ),
        const SizedBox(height: AppSpacing.lg + 2),
        if (_formError != null) ...[
          AuthNotice(message: _formError!, tone: NoticeTone.error),
          const SizedBox(height: AppSpacing.lg),
        ],
        AppTextField(
          label: 'New password',
          isPassword: true,
          controller: _password,
          errorText: _passwordError,
          helperText: allMet ? '✓ Meets all requirements' : null,
          autofillHints: const [AutofillHints.newPassword],
          onChanged: (_) => setState(() => _passwordError = null),
        ),
        if (!allMet) ...[
          const SizedBox(height: AppSpacing.sm),
          PasswordRulesList(rules: rules),
        ],
        const SizedBox(height: AppSpacing.lg),
        AppTextField(
          label: 'Confirm new password',
          isPassword: true,
          controller: _confirm,
          errorText: _confirmError,
          autofillHints: const [AutofillHints.newPassword],
          onChanged: (_) => setState(() => _confirmError = null),
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: AppSpacing.lg + 4),
        AppButton(
          label: 'Update password',
          busyLabel: 'Updating…',
          busy: _busy,
          size: AppButtonSize.large,
          expand: true,
          onPressed: _submit,
        ),
      ],
    );
  }
}

class _Expired extends StatelessWidget {
  const _Expired({required this.message, required this.onRequestNew});

  final String message;
  final VoidCallback onRequestNew;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AuthHeading(title: 'This reset link has expired', lead: Text(message)),
        const SizedBox(height: AppSpacing.lg + 2),
        AppButton(
          label: 'Request a new link',
          variant: AppButtonVariant.secondary,
          onPressed: onRequestNew,
        ),
      ],
    );
  }
}
