import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/route_names.dart';
import '../../../../core/permissions/system_roles.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/initials.dart';
import '../../../../core/widgets/app_button.dart';
import '../providers/auth_providers.dart';

enum _AccountAction { profile, switchOrganization, signOut }

/// Avatar in the top bar; opens the account menu (switch organization,
/// sign out).
class AccountMenu extends ConsumerWidget {
  const AccountMenu({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    if (session == null) return const SizedBox.shrink();
    return PopupMenuButton<_AccountAction>(
      tooltip: '${session.displayName}, account menu',
      position: PopupMenuPosition.under,
      onSelected: (action) {
        switch (action) {
          case _AccountAction.profile:
            context.go(AppRoutes.myProfile);
          case _AccountAction.switchOrganization:
            context.go(AppRoutes.chooseOrganization);
          case _AccountAction.signOut:
            ref.read(authControllerProvider.notifier).signOut();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<_AccountAction>(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(session.displayName, style: AppTypography.label),
              Text(session.email, style: AppTypography.helper),
              Text(
                '${session.roleName} · ${session.organizationName}',
                style: AppTypography.helper,
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        if (session.role == SystemRole.employee ||
            session.role == SystemRole.leaveApprover)
          const PopupMenuItem(
            value: _AccountAction.profile,
            child: Text('My profile'),
          ),
        if (session.canSwitchOrganization)
          const PopupMenuItem(
            value: _AccountAction.switchOrganization,
            child: Text('Switch organization…'),
          ),
        const PopupMenuItem(
          value: _AccountAction.signOut,
          child: Text('Sign out'),
        ),
      ],
      child: CircleAvatar(
        radius: 16,
        backgroundColor: AppColors.primarySoft,
        child: Text(
          initialsOf(session.displayName),
          style: AppTypography.helper.copyWith(
            color: AppColors.primaryHover,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// Plain "Sign out" button for pages outside the shell.
class SignOutButton extends ConsumerWidget {
  const SignOutButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => AppButton(
    label: 'Sign out',
    variant: AppButtonVariant.secondary,
    onPressed: () => ref.read(authControllerProvider.notifier).signOut(),
  );
}
