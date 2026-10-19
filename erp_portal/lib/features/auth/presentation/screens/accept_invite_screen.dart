import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/config/app_config.dart';
import '../../../../app/router/route_names.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/initials.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/skeleton.dart';
import '../../data/demo_auth_repository.dart';
import '../../domain/auth_models.dart';
import '../../domain/password_rules.dart';
import '../providers/auth_providers.dart';
import '../widgets/auth_layout.dart';
import '../widgets/auth_widgets.dart';

final _invitationProvider = FutureProvider.autoDispose
    .family<Invitation, String?>((ref, token) {
      if (token == null || token.isEmpty) {
        throw const ExpiredFailure(
          'Open your invitation email and tap the link inside. Invitations '
          'expire after 7 days.',
        );
      }
      return ref.read(authRepositoryProvider).openInvitation(token);
    });

/// Board S09 — accept an invitation: confirm details, set a password.
/// No shared or default password is ever created (PRD §7.2).
class AcceptInviteScreen extends ConsumerStatefulWidget {
  const AcceptInviteScreen({super.key, required this.token});

  final String? token;

  @override
  ConsumerState<AcceptInviteScreen> createState() => _AcceptInviteScreenState();
}

class _AcceptInviteScreenState extends ConsumerState<AcceptInviteScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _agreed = false;
  bool _busy = false;
  Map<String, String> _errors = {};

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _accept(Invitation invitation) async {
    if (_busy) return;
    final errors = {
      if (!isStrongPassword(
        _password.text,
        name: invitation.fullName,
        email: invitation.email,
      ))
        'password': 'Meet all the password rules below.',
      if (_confirm.text != _password.text)
        'confirm': 'Passwords don’t match. Re-type the password.',
      if (!_agreed) 'terms': 'Agree to continue.',
    };
    setState(() => _errors = errors);
    if (errors.isNotEmpty) return;

    setState(() => _busy = true);
    try {
      await ref
          .read(authControllerProvider.notifier)
          .acceptInvitation(token: invitation.token, password: _password.text);
    } on Failure catch (failure) {
      if (mounted) setState(() => _errors = {'form': failure.message});
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final invitation = ref.watch(_invitationProvider(widget.token));
    final showDemo = ref.watch(appConfigProvider).showDevTools;
    return AuthLayout(
      child: invitation.when(
        loading: () => const LoadingSkeleton(
          label: 'Opening your invitation',
          child: SkeletonList(rows: 3),
        ),
        error: (error, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AuthHeading(
              title: 'This invitation can’t be used',
              lead: Text(userMessageFor(error)),
            ),
            const SizedBox(height: AppSpacing.lg + 2),
            AppButton(
              label: 'Back to sign in',
              variant: AppButtonVariant.secondary,
              onPressed: () => context.go(AppRoutes.welcome),
            ),
            if (showDemo) ...[
              const SizedBox(height: AppSpacing.md),
              TextLink(
                'Demo: open a sample invitation',
                onTap: () => context.go(
                  '${AppRoutes.acceptInvite}?token='
                  '${DemoAuthRepository.demoInviteToken}',
                ),
              ),
            ],
          ],
        ),
        data: _form,
      ),
    );
  }

  Widget _form(Invitation invitation) {
    final rules = passwordRules(
      _password.text,
      name: invitation.fullName,
      email: invitation.email,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _InviterBanner(invitation: invitation),
        const SizedBox(height: AppSpacing.xl),
        const AuthHeading(
          title: 'Confirm your details',
          lead: Text(
            'Your HR team filled these in. Tell them if anything is wrong.',
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _Details(invitation: invitation),
        const SizedBox(height: AppSpacing.lg + 4),
        if (_errors['form'] case final message?) ...[
          AuthNotice(message: message, tone: NoticeTone.error),
          const SizedBox(height: AppSpacing.lg),
        ],
        AppTextField(
          label: 'Create a password',
          isRequired: true,
          isPassword: true,
          controller: _password,
          hintText: 'At least 10 characters',
          errorText: _errors['password'],
          autofillHints: const [AutofillHints.newPassword],
          onChanged: (_) => setState(() => _errors.remove('password')),
        ),
        const SizedBox(height: AppSpacing.sm),
        PasswordRulesList(rules: rules),
        const SizedBox(height: AppSpacing.md),
        AppTextField(
          label: 'Confirm password',
          isRequired: true,
          isPassword: true,
          controller: _confirm,
          errorText: _errors['confirm'],
          autofillHints: const [AutofillHints.newPassword],
          onChanged: (_) => setState(() => _errors.remove('confirm')),
        ),
        const SizedBox(height: AppSpacing.md),
        LabeledCheckbox(
          value: _agreed,
          errorText: _errors['terms'],
          onChanged: (v) => setState(() {
            _agreed = v;
            _errors.remove('terms');
          }),
          label: Text(
            'I agree to the Terms and how ${invitation.organizationName} '
            'uses my work data (privacy notice).',
          ),
        ),
        const SizedBox(height: AppSpacing.lg + 2),
        AppButton(
          label: 'Accept and join',
          busyLabel: 'Joining…',
          busy: _busy,
          size: AppButtonSize.large,
          expand: true,
          onPressed: () => _accept(invitation),
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpacing.sm,
          children: [
            Text(
              'Invitation expires '
              '${DateFormat('d MMM, HH:mm').format(invitation.expiresAt)}',
              style: AppTypography.helper,
            ),
            TextLink('Not you?', onTap: () => context.go(AppRoutes.welcome)),
          ],
        ),
      ],
    );
  }
}

class _InviterBanner extends StatelessWidget {
  const _InviterBanner({required this.invitation});

  final Invitation invitation;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.ink,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Text(
              initialsOf(invitation.organizationName),
              style: AppTypography.label.copyWith(color: AppColors.surface),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${invitation.inviterName} invited you to join',
                  style: AppTypography.helper,
                ),
                Text(
                  invitation.organizationName,
                  style: AppTypography.cardTitle,
                ),
                Text(
                  'as ${invitation.role.label} · ${invitation.branchName} branch',
                  style: AppTypography.helper,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Details extends StatelessWidget {
  const _Details({required this.invitation});

  final Invitation invitation;

  @override
  Widget build(BuildContext context) {
    final items = [
      ('Name', invitation.fullName, false),
      ('Employee ID', invitation.employeeId, true),
      ('Email', invitation.email, false),
      ('Starts', DateFormat('EEE d MMM y').format(invitation.startDate), false),
    ];
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md + 2),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Wrap(
        runSpacing: AppSpacing.md,
        children: [
          for (final (label, value, mono) in items)
            FractionallySizedBox(
              widthFactor: 0.5,
              child: Padding(
                padding: const EdgeInsets.only(right: AppSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: AppTypography.helper),
                    Text(
                      value,
                      style: mono
                          ? AppTypography.code.copyWith(
                              color: AppColors.textPrimary,
                            )
                          : AppTypography.small.copyWith(
                              color: AppColors.textPrimary,
                            ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
