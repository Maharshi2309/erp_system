import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/permissions/system_roles.dart';
import '../../core/responsive/breakpoints.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../features/auth/presentation/providers/auth_providers.dart';
import '../../features/organization/domain/branch.dart';
import '../../features/organization/domain/setup_progress.dart';
import '../../features/organization/presentation/providers/organization_providers.dart';
import '../config/app_config.dart';
import '../router/app_destinations.dart';
import '../router/route_names.dart';
import 'side_nav.dart';
import 'top_bar.dart';

/// Frame around every signed-in page, with the signed-in role's menu.
///
/// ≥ 1024 px: 248 px sidebar · 768–1023 px: 72 px icon rail that can expand ·
/// < 768 px: menu drawer, or bottom tabs for employees (board S86).
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  bool _railExpanded = false;

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    // Signed out: the router guard is already redirecting.
    if (session == null) return const SizedBox.shrink();
    final config = ref.watch(appConfigProvider);

    final destinations = visibleDestinations(session.role, session.permissions);
    final branchItems = _setupBranchItems(session.role);
    final inBranchItem = branchItems.any((i) => i.selected);
    final current = bestMatch(widget.location, destinations);
    final items = [
      for (final d in destinations)
        SideNavItem(
          label: d.label,
          icon: d.icon,
          path: d.path,
          section: d.section,
          selected: !inBranchItem && identical(d, current),
        ),
      ...branchItems,
    ];
    final devItems = [
      if (config.showDevTools)
        SideNavItem(
          label: 'Design system',
          icon: Icons.palette_outlined,
          path: AppRoutes.designSystem,
          selected: widget.location == AppRoutes.designSystem,
        ),
    ];
    final title = switch (widget.location) {
      AppRoutes.designSystem => 'Design system',
      AppRoutes.accessDenied => 'Access denied',
      _ => current?.label ?? '',
    };

    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = NavLayout.fromWidth(constraints.maxWidth);

        if (layout == NavLayout.drawer &&
            (session.role == SystemRole.employee ||
                session.role == SystemRole.leaveApprover)) {
          return _PhoneTabsLayout(
            title: title,
            items: items,
            child: widget.child,
          );
        }

        if (layout == NavLayout.drawer) {
          return Scaffold(
            drawer: Drawer(
              width: math.min(320, constraints.maxWidth * 0.86),
              child: Builder(
                builder: (drawerContext) => SafeArea(
                  child: SideNav(
                    session: session,
                    items: items,
                    devItems: devItems,
                    width: double.infinity,
                    onNavigate: (path) {
                      Navigator.of(drawerContext).pop();
                      context.go(path);
                    },
                  ),
                ),
              ),
            ),
            body: Builder(
              builder: (scaffoldContext) => SafeArea(
                child: Column(
                  children: [
                    TopBar(
                      title: title,
                      onOpenMenu: () =>
                          Scaffold.of(scaffoldContext).openDrawer(),
                    ),
                    Expanded(child: widget.child),
                  ],
                ),
              ),
            ),
          );
        }

        final isRail = layout == NavLayout.rail;
        return Scaffold(
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SideNav(
                session: session,
                items: items,
                devItems: devItems,
                compact: isRail && !_railExpanded,
                onToggleCompact: isRail
                    ? () => setState(() => _railExpanded = !_railExpanded)
                    : null,
                onNavigate: context.go,
              ),
              Expanded(
                child: Column(
                  children: [
                    TopBar(title: title),
                    Expanded(child: widget.child),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Phone layout for self-service: top bar plus bottom tabs (board S86).
/// The leave approver's "Approvals" is the fifth tab instead of Profile,
/// which stays reachable from the account menu.
extension on _AppShellState {
  /// Owner sidebar "BRANCHES" group with each branch's setup percentage,
  /// shown until every active branch is fully set up (boards S15–S25).
  List<SideNavItem> _setupBranchItems(SystemRole role) {
    if (role != SystemRole.owner) return const [];
    final branches = ref.watch(branchesProvider).value ?? const <Branch>[];
    final active = branches.where((b) => b.isActive).toList();
    if (active.isEmpty || active.every((b) => SetupProgress(b).isReady)) {
      return const [];
    }
    bool under(String path) =>
        widget.location == path || widget.location.startsWith('$path/');
    return [
      for (final b in active)
        SideNavItem(
          label: b.name,
          icon: Icons.location_on_outlined,
          path: AppRoutes.branchSetup(b.id),
          section: 'BRANCHES',
          trailing: '${SetupProgress(b).percent}%',
          selected: under(AppRoutes.branch(b.id)),
        ),
      const SideNavItem(
        label: 'Add branch',
        icon: Icons.add,
        path: AppRoutes.newBranch,
        section: 'BRANCHES',
        selected: false,
      ),
    ];
  }
}

class _PhoneTabsLayout extends StatelessWidget {
  const _PhoneTabsLayout({
    required this.title,
    required this.items,
    required this.child,
  });

  final String title;
  final List<SideNavItem> items;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tabs = items.length > 5 ? [...items.take(4), items.last] : items;
    final selected = tabs.indexWhere((t) => t.selected);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            TopBar(title: title),
            Expanded(child: child),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          backgroundColor: AppColors.surface,
          indicatorColor: AppColors.primarySoft,
          height: 64,
          labelTextStyle: WidgetStateProperty.resolveWith(
            (states) => AppTypography.helper.copyWith(
              fontSize: 11,
              color: states.contains(WidgetState.selected)
                  ? AppColors.primary
                  : AppColors.textMuted,
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w600
                  : FontWeight.w400,
            ),
          ),
        ),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: NavigationBar(
            selectedIndex: selected < 0 ? 0 : selected,
            onDestinationSelected: (i) => context.go(tabs[i].path),
            destinations: [
              for (final tab in tabs)
                NavigationDestination(
                  icon: Icon(tab.icon, color: AppColors.textMuted),
                  selectedIcon: Icon(tab.icon, color: AppColors.primary),
                  label: tab.label,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
