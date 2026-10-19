import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/initials.dart';
import '../../core/widgets/focus_ring.dart';
import '../../shared/models/app_session.dart';

class SideNavItem {
  const SideNavItem({
    required this.label,
    required this.icon,
    required this.path,
    required this.selected,
    this.section,
    this.trailing,
  });

  final String label;
  final IconData icon;
  final String path;
  final bool selected;

  /// Group heading shown above the first item of a group (board S34).
  final String? section;

  /// Short right-aligned note, e.g. a branch's setup percentage.
  final String? trailing;
}

/// Sidebar content: organization header, menu, user card.
///
/// [compact] renders the 72 px icon rail; labels move into tooltips.
class SideNav extends StatelessWidget {
  const SideNav({
    super.key,
    required this.session,
    required this.items,
    required this.onNavigate,
    this.devItems = const [],
    this.compact = false,
    this.onToggleCompact,
    this.width,
  });

  final AppSession session;
  final List<SideNavItem> items;
  final List<SideNavItem> devItems;
  final ValueChanged<String> onNavigate;
  final bool compact;

  /// Shown on the rail layout to expand or collapse it.
  final VoidCallback? onToggleCompact;

  /// Overrides the default 248 / 72 px width (e.g. inside a drawer).
  final double? width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width ?? (compact ? AppLayout.railWidth : AppLayout.sidebarWidth),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _OrganizationHeader(session: session, compact: compact),
          Expanded(
            child: Semantics(
              container: true,
              explicitChildNodes: true,
              label: 'Main navigation',
              child: ListView(
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? AppSpacing.md : AppSpacing.sm + 2,
                  vertical: AppSpacing.xs,
                ),
                children: [
                  for (var i = 0; i < items.length; i++) ...[
                    if (items[i].section != null &&
                        (i == 0 || items[i - 1].section != items[i].section))
                      compact
                          ? (i == 0
                                ? const SizedBox.shrink()
                                : const Divider(height: 24))
                          : _SectionHeading(items[i].section!),
                    _NavTile(
                      item: items[i],
                      compact: compact,
                      onTap: onNavigate,
                    ),
                  ],
                  if (devItems.isNotEmpty) ...[
                    if (!compact)
                      const _SectionHeading('DEMO TOOLS')
                    else
                      const Divider(height: 24),
                    for (final item in devItems)
                      _NavTile(item: item, compact: compact, onTap: onNavigate),
                  ],
                ],
              ),
            ),
          ),
          if (onToggleCompact != null)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Align(
                alignment: compact ? Alignment.center : Alignment.centerRight,
                child: IconButton(
                  tooltip: compact ? 'Expand menu' : 'Collapse menu',
                  onPressed: onToggleCompact,
                  icon: Icon(
                    compact ? Icons.chevron_right : Icons.chevron_left,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          const Divider(height: 1),
          _UserCard(session: session, compact: compact),
        ],
      ),
    );
  }
}

class _OrganizationHeader extends StatelessWidget {
  const _OrganizationHeader({required this.session, required this.compact});

  final AppSession session;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final mark = Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Text(
        initialsOf(session.organizationName),
        style: AppTypography.label.copyWith(
          color: AppColors.surface,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
    return SizedBox(
      height: AppLayout.headerHeight,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: compact ? 0 : AppSpacing.lg),
        child: compact
            ? Center(
                child: Tooltip(
                  message: '${session.organizationName} · ${session.roleName}',
                  child: mark,
                ),
              )
            : Row(
                children: [
                  mark,
                  const SizedBox(width: AppSpacing.sm + 2),
                  Expanded(
                    // The header has a fixed height; cap scaling so both lines fit.
                    child: MediaQuery.withClampedTextScaling(
                      maxScaleFactor: 1.5,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            session.organizationName,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.label.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            session.roleName,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.helper,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.item,
    required this.compact,
    required this.onTap,
  });

  final SideNavItem item;
  final bool compact;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final fg = item.selected ? AppColors.primaryHover : AppColors.textSecondary;
    final tile = Material(
      color: item.selected ? AppColors.primarySoft : Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: () => onTap(item.path),
        child: SizedBox(
          height: AppLayout.touchTarget,
          child: compact
              ? Icon(item.icon, size: 20, color: fg)
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    children: [
                      Icon(item.icon, size: 18, color: fg),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          item.label,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.body.copyWith(
                            color: item.selected
                                ? AppColors.primaryHover
                                : AppColors.textSecondary,
                            fontWeight: item.selected
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                      if (item.trailing != null)
                        Text(item.trailing!, style: AppTypography.code),
                    ],
                  ),
                ),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Semantics(
        selected: item.selected,
        label: compact ? item.label : null,
        child: FocusRing(
          child: compact ? Tooltip(message: item.label, child: tile) : tile,
        ),
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  const _UserCard({required this.session, required this.compact});

  final AppSession session;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final avatar = CircleAvatar(
      radius: 16,
      backgroundColor: AppColors.successSoft,
      child: Text(
        initialsOf(session.displayName),
        style: AppTypography.helper.copyWith(
          color: AppColors.successText,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    if (compact) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Center(
          child: Tooltip(message: session.displayName, child: avatar),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          avatar,
          const SizedBox(width: AppSpacing.sm + 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.displayName,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.label.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  session.email,
                  overflow: TextOverflow.ellipsis,
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

class _SectionHeading extends StatelessWidget {
  const _SectionHeading(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 16, 10, 6),
      child: Semantics(
        header: true,
        child: Text(label, style: AppTypography.tableHeader),
      ),
    );
  }
}
