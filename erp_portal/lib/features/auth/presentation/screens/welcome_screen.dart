import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/config/app_config.dart';
import '../../../../app/router/route_names.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../data/demo_auth_repository.dart';
import '../providers/auth_providers.dart';
import '../widgets/auth_layout.dart';
import '../widgets/auth_widgets.dart';

/// Board S03 — welcome and sign-in.
///
/// The "Set up an organization" card is navigation only; it grants
/// nothing. Access comes from the signed-in account's membership (PRD §3).
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  final _identifier = TextEditingController();
  final _password = TextEditingController();
  bool _keepSignedIn = false;
  bool _busy = false;
  String? _formError;
  String? _identifierError;
  String? _passwordError;

  @override
  void dispose() {
    _identifier.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (_busy) return;
    setState(() {
      _formError = null;
      _identifierError = _identifier.text.trim().isEmpty
          ? 'Enter your work email or employee ID.'
          : null;
      _passwordError = _password.text.isEmpty ? 'Enter your password.' : null;
    });
    if (_identifierError != null || _passwordError != null) return;

    setState(() => _busy = true);
    try {
      await ref
          .read(authControllerProvider.notifier)
          .signIn(
            identifier: _identifier.text,
            password: _password.text,
            keepSignedIn: _keepSignedIn,
          );
      // The router moves on from here once the auth state changes.
    } on Failure catch (failure) {
      if (mounted) setState(() => _formError = failure.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _useDemoAccount(String identifier) {
    _identifier.text = identifier;
    _password.text = DemoAuthRepository.demoPassword;
    setState(() {
      _identifierError = null;
      _passwordError = null;
      _formError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final showDemo = ref.watch(appConfigProvider).showDevTools;
    final form = _SignInForm(
      identifier: _identifier,
      password: _password,
      keepSignedIn: _keepSignedIn,
      onKeepSignedIn: (v) => setState(() => _keepSignedIn = v),
      busy: _busy,
      formError: _formError,
      identifierError: _identifierError,
      passwordError: _passwordError,
      onSubmit: _signIn,
      onIdentifierChanged: () => setState(() => _identifierError = null),
      onPasswordChanged: () => setState(() => _passwordError = null),
    );

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 940;
          final main = Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: wide ? AppSpacing.xxxl : AppSpacing.xl,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    form,
                    if (showDemo) ...[
                      const SizedBox(height: AppSpacing.lg),
                      _DemoAccounts(onPick: _useDemoAccount),
                    ],
                  ],
                ),
              ),
            ),
          );
          if (wide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(width: 460, child: _BrandPane()),
                Expanded(child: SingleChildScrollView(child: main)),
              ],
            );
          }
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [const _BrandPane(compact: true), main],
            ),
          );
        },
      ),
    );
  }
}

class _SignInForm extends StatelessWidget {
  const _SignInForm({
    required this.identifier,
    required this.password,
    required this.keepSignedIn,
    required this.onKeepSignedIn,
    required this.busy,
    required this.formError,
    required this.identifierError,
    required this.passwordError,
    required this.onSubmit,
    required this.onIdentifierChanged,
    required this.onPasswordChanged,
  });

  final TextEditingController identifier;
  final TextEditingController password;
  final bool keepSignedIn;
  final ValueChanged<bool> onKeepSignedIn;
  final bool busy;
  final String? formError;
  final String? identifierError;
  final String? passwordError;
  final VoidCallback onSubmit;
  final VoidCallback onIdentifierChanged;
  final VoidCallback onPasswordChanged;

  @override
  Widget build(BuildContext context) {
    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: const Text('Welcome', style: AppTypography.pageTitle),
          ),
          const SizedBox(height: AppSpacing.sm),
          const Text(
            'Choose how you want to continue.',
            style: AppTypography.bodySecondary,
          ),
          const SizedBox(height: AppSpacing.xl + 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _ChoiceCard(
                  icon: Icons.apartment_outlined,
                  title: 'Set up an organization',
                  subtitle: 'For owners creating a new workspace',
                  selected: false,
                  onTap: () => context.go(AppRoutes.register),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              const Expanded(
                child: _ChoiceCard(
                  icon: Icons.person_outline,
                  title: 'Employee sign in',
                  subtitle: 'For staff, managers and admins',
                  selected: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl + 4),
          Container(
            padding: const EdgeInsets.all(AppSpacing.xl),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (formError != null) ...[
                  AuthNotice(message: formError!, tone: NoticeTone.error),
                  const SizedBox(height: AppSpacing.lg + 2),
                ],
                AppTextField(
                  label: 'Work email or employee ID',
                  controller: identifier,
                  errorText: identifierError,
                  autofillHints: const [AutofillHints.username],
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => onIdentifierChanged(),
                ),
                const SizedBox(height: AppSpacing.lg + 2),
                // The link sits on the label row; Tab still visits the
                // password field first.
                FocusTraversalGroup(
                  policy: OrderedTraversalPolicy(),
                  child: Stack(
                    children: [
                      FocusTraversalOrder(
                        order: const NumericFocusOrder(1),
                        child: AppTextField(
                          label: 'Password',
                          controller: password,
                          isPassword: true,
                          errorText: passwordError,
                          autofillHints: const [AutofillHints.password],
                          textInputAction: TextInputAction.done,
                          onChanged: (_) => onPasswordChanged(),
                          onSubmitted: (_) => onSubmit(),
                        ),
                      ),
                      Positioned(
                        right: 0,
                        top: 0,
                        child: FocusTraversalOrder(
                          order: const NumericFocusOrder(2),
                          child: TextLink(
                            'Forgot password?',
                            onTap: () => context.go(AppRoutes.forgotPassword),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                LabeledCheckbox(
                  value: keepSignedIn,
                  onChanged: onKeepSignedIn,
                  label: const Text('Keep me signed in on this device'),
                ),
                const SizedBox(height: AppSpacing.lg + 2),
                AppButton(
                  label: 'Sign in',
                  busyLabel: 'Signing in…',
                  busy: busy,
                  size: AppButtonSize.large,
                  expand: true,
                  onPressed: onSubmit,
                ),
                const SizedBox(height: AppSpacing.lg),
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: AppSpacing.xs,
                  children: [
                    const Text(
                      'Got an invitation email?',
                      style: AppTypography.small,
                    ),
                    TextLink(
                      'Accept invitation',
                      onTap: () => context.go(AppRoutes.acceptInvite),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onTap != null,
      selected: selected,
      child: Material(
        color: selected ? AppColors.primarySoft : AppColors.surface,
        shape: RoundedRectangleBorder(
          side: BorderSide(
            color: selected ? AppColors.primary : AppColors.borderStrong,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg - 1),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  icon,
                  size: 22,
                  color: selected ? AppColors.primary : AppColors.textSecondary,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  title,
                  style: AppTypography.bodyStrong.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(subtitle, style: AppTypography.helper),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BrandPane extends StatelessWidget {
  const _BrandPane({this.compact = false});

  final bool compact;

  static const _benefits = [
    'Branch-level schedules, holidays and shifts',
    'Leave balances with approval routing',
    'Role-based access with a full audit trail',
  ];

  @override
  Widget build(BuildContext context) {
    final headline = Text(
      'Attendance, leave and people records for every branch — in one place.',
      style: AppTypography.pageTitle.copyWith(
        color: AppColors.surface,
        fontSize: compact ? 26 : 36,
        height: 1.2,
      ),
    );
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const StafflineLogo(onDark: true),
        SizedBox(height: compact ? AppSpacing.xl : AppSpacing.xxxl),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            headline,
            if (!compact) ...[
              const SizedBox(height: AppSpacing.lg + 4),
              Text(
                'Owners set up branches and policies. Managers approve '
                'what’s in their scope. Employees punch in and request '
                'leave from their phone.',
                style: AppTypography.body.copyWith(
                  color: const Color(0xFFB8C0CC),
                  fontSize: 16,
                  height: 26 / 16,
                ),
              ),
              const SizedBox(height: AppSpacing.lg + 4),
              for (final benefit in _benefits)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.check,
                        size: 18,
                        color: Color(0xFF5FD3B4),
                      ),
                      const SizedBox(width: AppSpacing.sm + 2),
                      Expanded(
                        child: Text(
                          benefit,
                          style: AppTypography.body.copyWith(
                            color: const Color(0xFFDCE1E8),
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
        if (!compact) ...[
          const SizedBox(height: AppSpacing.xxxl),
          Text(
            '© Staffline · Privacy · Terms',
            style: AppTypography.small.copyWith(color: const Color(0xFFB8C0CC)),
          ),
        ],
      ],
    );

    if (compact) {
      return Container(
        color: AppColors.ink,
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: SafeArea(bottom: false, child: content),
      );
    }
    // Full-height pane: logo at the top, footer at the bottom; scrolls
    // instead of overflowing on short screens or with large text.
    return ColoredBox(
      color: AppColors.ink,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          padding: const EdgeInsets.all(56),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: (constraints.maxHeight - 112).clamp(
                0,
                double.infinity,
              ),
            ),
            child: IntrinsicHeight(child: content),
          ),
        ),
      ),
    );
  }
}

/// Demo builds only: sample accounts to try every role (no backend, D-01).
class _DemoAccounts extends StatelessWidget {
  const _DemoAccounts({required this.onPick});

  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.warningSoft,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Demo accounts',
            style: AppTypography.label.copyWith(color: AppColors.warningText),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Password ${DemoAuthRepository.demoPassword} · sign-in code '
            '${DemoAuthRepository.demoAuthenticatorCode} · backup code '
            '${DemoAuthRepository.demoBackupCode}. Tap one to fill the form.',
            style: AppTypography.helper.copyWith(color: AppColors.warningText),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final (identifier, role) in DemoAuthRepository.demoAccounts)
            InkWell(
              onTap: () => onPick(identifier),
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        identifier,
                        style: AppTypography.code.copyWith(
                          color: AppColors.warningText,
                        ),
                      ),
                    ),
                    Flexible(
                      child: Text(
                        role,
                        textAlign: TextAlign.end,
                        style: AppTypography.helper.copyWith(
                          color: AppColors.warningText,
                        ),
                      ),
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
