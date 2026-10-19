import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../features/auth/presentation/widgets/account_menu.dart';
import '../../features/notifications/presentation/notification_screens.dart';

/// 64 px header above the page: menu button (drawer layout), page title,
/// account menu.
///
/// The notifications bell shows the unread count (boards S76, S95).
class TopBar extends StatelessWidget {
  const TopBar({super.key, required this.title, this.onOpenMenu});

  final String title;

  /// Set in the drawer layout.
  final VoidCallback? onOpenMenu;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: AppLayout.headerHeight,
      padding: EdgeInsets.only(
        left: onOpenMenu == null ? AppSpacing.xl : AppSpacing.xs,
        right: AppSpacing.lg,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          if (onOpenMenu != null)
            IconButton(
              tooltip: 'Open navigation',
              onPressed: onOpenMenu,
              icon: const Icon(Icons.menu, color: AppColors.textPrimary),
            ),
          Expanded(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.small.copyWith(color: AppColors.textPrimary),
            ),
          ),
          const NotificationBell(),
          const AccountMenu(),
        ],
      ),
    );
  }
}
