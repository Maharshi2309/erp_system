import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/route_names.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/initials.dart';
import '../../../../core/widgets/focus_ring.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../domain/auth_models.dart';
import '../../domain/auth_state.dart';
import '../providers/auth_providers.dart';
import '../widgets/auth_layout.dart';
import '../widgets/auth_widgets.dart';

/// Board S10 — pick which organization to work in. Also reached from the
/// account menu to switch. Deactivated memberships are listed but can't be
/// opened (Q-14).
class ChooseOrganizationScreen extends ConsumerStatefulWidget {
  const ChooseOrganizationScreen({super.key});

  @override
  ConsumerState<ChooseOrganizationScreen> createState() =>
      _ChooseOrganizationScreenState();
}

class _ChooseOrganizationScreenState
    extends ConsumerState<ChooseOrganizationScreen> {
  String? _opening;
  String? _error;

  Future<void> _open(OrganizationMembership membership) async {
    if (_opening != null) return;
    setState(() {
      _opening = membership.organizationId;
      _error = null;
    });
    try {
      await ref
          .read(authControllerProvider.notifier)
          .chooseOrganization(membership.organizationId);
      // Switching while signed in keeps this page reachable; leave it.
      if (mounted) context.go(AppRoutes.root);
    } on Failure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _opening = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final (email, memberships) = switch (auth) {
      AwaitingOrganizationChoice(:final account, :final memberships) => (
        account.email,
        memberships,
      ),
      SignedIn(:final account, :final memberships) => (
        account.email,
        memberships,
      ),
      _ => ('', const <OrganizationMembership>[]),
    };

    return AuthLayout(
      plain: true,
      maxWidth: 480,
      trailing: TextLink(
        'Sign out',
        onTap: () => ref.read(authControllerProvider.notifier).signOut(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AuthHeading(
            title: 'Choose an organization',
            lead: Text(
              'Signed in as $email. You can switch later from the account '
              'menu.',
            ),
          ),
          const SizedBox(height: AppSpacing.lg + 2),
          if (_error != null) ...[
            AuthNotice(message: _error!, tone: NoticeTone.error),
            const SizedBox(height: AppSpacing.md),
          ],
          for (final membership in memberships) ...[
            _OrganizationCard(
              membership: membership,
              opening: _opening == membership.organizationId,
              onOpen: membership.isActive ? () => _open(membership) : null,
            ),
            const SizedBox(height: AppSpacing.sm + 2),
          ],
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: TextLink(
              '+ Set up another organization',
              onTap: () => context.go(AppRoutes.onboarding),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrganizationCard extends StatelessWidget {
  const _OrganizationCard({
    required this.membership,
    required this.opening,
    required this.onOpen,
  });

  final OrganizationMembership membership;
  final bool opening;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final active = membership.isActive;
    final roleLine = membership.scopeLabel.isEmpty
        ? membership.role.label
        : '${membership.role.label} · ${membership.scopeLabel}';
    return Semantics(
      button: active,
      enabled: active,
      label: [
        membership.organizationName,
        roleLine,
        membership.summary,
        if (membership.lastUsed) 'last used',
      ].join(', '),
      excludeSemantics: true,
      child: FocusRing(
        borderRadius: AppRadius.lg,
        child: Material(
          color: AppColors.surface,
          shape: RoundedRectangleBorder(
            side: BorderSide(
              color: membership.lastUsed ? AppColors.primary : AppColors.border,
              width: membership.lastUsed ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: InkWell(
            onTap: onOpen,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: active ? AppColors.ink : AppColors.textMuted,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Text(
                      initialsOf(membership.organizationName),
                      style: AppTypography.label.copyWith(
                        color: AppColors.surface,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md + 2),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: AppSpacing.sm,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              membership.organizationName,
                              style: AppTypography.bodyStrong.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (membership.lastUsed)
                              const StatusBadge(
                                label: 'Last used',
                                tone: StatusTone.info,
                              ),
                          ],
                        ),
                        Text(roleLine, style: AppTypography.small),
                        Text(
                          membership.summary,
                          style: AppTypography.helper.copyWith(
                            color: active
                                ? AppColors.textMuted
                                : AppColors.warning,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (opening)
                    const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else if (active)
                    const Icon(Icons.chevron_right, color: AppColors.textMuted),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
