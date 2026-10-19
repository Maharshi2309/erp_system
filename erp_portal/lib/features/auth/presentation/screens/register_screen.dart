import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/route_names.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/form_error_summary.dart';
import '../../domain/password_rules.dart';
import '../providers/auth_providers.dart';
import '../widgets/auth_layout.dart';
import '../widgets/auth_widgets.dart';

/// Board S04 — owner registration. Organization details come later
/// (onboarding), so only the account is created here.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _nameFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _phoneFocus = FocusNode();
  final _passwordFocus = FocusNode();
  bool _acceptedTerms = false;
  bool _busy = false;
  bool _submitted = false;
  Map<String, String> _errors = {};

  @override
  void dispose() {
    for (final c in [_name, _email, _phone, _password]) {
      c.dispose();
    }
    for (final f in [_nameFocus, _emailFocus, _phoneFocus, _passwordFocus]) {
      f.dispose();
    }
    super.dispose();
  }

  Map<String, String> _validate() {
    final phoneDigits = _phone.text.replaceAll(RegExp(r'\D'), '');
    return {
      if (_name.text.trim().isEmpty) 'name': 'Enter your full name.',
      if (_email.text.trim().isEmpty)
        'email': 'Enter your work email.'
      else if (!Validators.isEmail(_email.text))
        'email': 'Enter a valid work email, like name@company.com.',
      if (phoneDigits.isNotEmpty && phoneDigits.length != 10)
        'phone': 'Enter a 10-digit mobile number.',
      if (!isStrongPassword(
        _password.text,
        name: _name.text,
        email: _email.text,
      ))
        'password': 'Meet all the password rules below.',
      if (!_acceptedTerms) 'terms': 'Accept the terms to continue.',
    };
  }

  Future<void> _submit() async {
    if (_busy) return;
    final errors = _validate();
    setState(() {
      _submitted = true;
      _errors = errors;
    });
    if (errors.isNotEmpty) return;

    setState(() => _busy = true);
    try {
      await ref
          .read(authControllerProvider.notifier)
          .register(
            fullName: _name.text.trim(),
            email: _email.text.trim(),
            password: _password.text,
            phone: _phone.text.trim().isEmpty
                ? null
                : '+91 ${_phone.text.trim()}',
          );
      if (mounted) context.go(AppRoutes.verifyEmail);
    } on ValidationFailure catch (failure) {
      if (mounted) {
        setState(
          () => _errors = failure.fieldErrors.isEmpty
              ? {'form': failure.message}
              : {...failure.fieldErrors},
        );
      }
    } on Failure catch (failure) {
      if (mounted) setState(() => _errors = {'form': failure.message});
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _clear(String key) {
    if (_errors.containsKey(key)) setState(() => _errors.remove(key));
  }

  @override
  Widget build(BuildContext context) {
    final rules = passwordRules(
      _password.text,
      name: _name.text,
      email: _email.text,
    );
    final focusFor = {
      'name': _nameFocus,
      'email': _emailFocus,
      'phone': _phoneFocus,
      'password': _passwordFocus,
    };
    final fieldErrors = _errors.entries.where((e) => e.key != 'form').toList();

    return AuthLayout(
      trailing: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppSpacing.xs,
        children: [
          const Text('Have an account?', style: AppTypography.small),
          TextLink('Sign in', onTap: () => context.go(AppRoutes.welcome)),
        ],
      ),
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AuthHeading(
              title: 'Create your owner account',
              lead: Text(
                'You’ll set up your organization and first branch next. '
                'Takes about 10 minutes.',
              ),
            ),
            const SizedBox(height: AppSpacing.lg + 2),
            if (_errors['form'] case final message?) ...[
              AuthNotice(message: message, tone: NoticeTone.error),
              const SizedBox(height: AppSpacing.lg),
            ] else if (_submitted && fieldErrors.length > 1) ...[
              FormErrorSummary(
                title:
                    'Please fix ${fieldErrors.length} things. Nothing you '
                    'entered was lost.',
                items: [
                  for (final e in fieldErrors)
                    FormErrorItem(
                      e.value,
                      onTap: focusFor[e.key]?.requestFocus,
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
            AppTextField(
              label: 'Full name',
              isRequired: true,
              controller: _name,
              focusNode: _nameFocus,
              errorText: _errors['name'],
              autofillHints: const [AutofillHints.name],
              textInputAction: TextInputAction.next,
              onChanged: (_) => setState(() => _errors.remove('name')),
            ),
            const SizedBox(height: AppSpacing.lg + 2),
            AppTextField(
              label: 'Work email',
              isRequired: true,
              controller: _email,
              focusNode: _emailFocus,
              errorText: _errors['email'],
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              textInputAction: TextInputAction.next,
              onChanged: (_) => setState(() => _errors.remove('email')),
            ),
            const SizedBox(height: AppSpacing.lg + 2),
            AppTextField(
              label: 'Mobile number (+91)',
              isOptional: true,
              controller: _phone,
              focusNode: _phoneFocus,
              monospace: true,
              errorText: _errors['phone'],
              hintText: '98250 11204',
              keyboardType: TextInputType.phone,
              autofillHints: const [AutofillHints.telephoneNumberNational],
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d ]')),
              ],
              maxLength: 11,
              textInputAction: TextInputAction.next,
              onChanged: (_) => _clear('phone'),
            ),
            const SizedBox(height: AppSpacing.lg + 2),
            AppTextField(
              label: 'Password',
              isRequired: true,
              isPassword: true,
              controller: _password,
              focusNode: _passwordFocus,
              errorText: _errors['password'],
              autofillHints: const [AutofillHints.newPassword],
              onChanged: (_) => setState(() => _errors.remove('password')),
            ),
            const SizedBox(height: AppSpacing.sm),
            PasswordRulesList(rules: rules),
            const SizedBox(height: AppSpacing.md),
            LabeledCheckbox(
              value: _acceptedTerms,
              errorText: _errors['terms'],
              onChanged: (v) => setState(() {
                _acceptedTerms = v;
                _errors.remove('terms');
              }),
              label: const Text(
                'I agree to the Terms of Service and Privacy Policy. *',
              ),
            ),
            const SizedBox(height: AppSpacing.lg + 2),
            AppButton(
              label: 'Create account',
              busyLabel: 'Creating account…',
              busy: _busy,
              size: AppButtonSize.large,
              expand: true,
              onPressed: _submit,
            ),
            const SizedBox(height: AppSpacing.md),
            const Text(
              'We’ll email a 6-digit code to verify your address.',
              textAlign: TextAlign.center,
              style: AppTypography.helper,
            ),
          ],
        ),
      ),
    );
  }
}
