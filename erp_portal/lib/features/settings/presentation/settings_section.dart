import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/route_names.dart';
import '../../../core/errors/failure.dart';
import '../../../core/permissions/permissions.dart';
import '../../../core/responsive/responsive_page.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/state_views.dart';
import '../../../shared/models/app_session.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../../dashboard/presentation/dashboard_widgets.dart';
import '../domain/settings.dart';
import 'settings_providers.dart';

/// One settings area (boards S80 cards and the S79–S85 side list).
typedef SettingsArea = ({
  String title,
  String hint,
  String route,
  IconData icon,
  String keywords,
  bool ownerOnly,
});

const settingsAreas = <SettingsArea>[
  (
    title: 'Organization',
    hint: 'Name, legal details, contact, default time zone.',
    route: AppRoutes.organization,
    icon: Icons.apartment_outlined,
    keywords: 'legal name time zone contact address',
    ownerOnly: false,
  ),
  (
    title: 'Branches',
    hint: 'Locations, codes, managers and branch calendars.',
    route: AppRoutes.branches,
    icon: Icons.location_on_outlined,
    keywords: 'location manager',
    ownerOnly: false,
  ),
  (
    title: 'Work schedules',
    hint: 'Shifts, breaks, expected hours, overnight shifts.',
    route: AppRoutes.settingsSchedules,
    icon: Icons.schedule_outlined,
    keywords: 'shift break night hours',
    ownerOnly: false,
  ),
  (
    title: 'Attendance policy',
    hint: 'Grace periods, late rules, early departures.',
    route: AppRoutes.settingsAttendance,
    icon: Icons.fact_check_outlined,
    keywords: 'grace late early punch half day',
    ownerOnly: false,
  ),
  (
    title: 'Leave policy',
    hint: 'Leave types, accrual, carry-forward and approvals.',
    route: AppRoutes.leavePolicy,
    icon: Icons.event_available_outlined,
    keywords: 'leave accrual approval balance',
    ownerOnly: false,
  ),
  (
    title: 'Employee fields',
    hint: 'Custom fields, required fields and who can see them.',
    route: AppRoutes.employeeFields,
    icon: Icons.dynamic_form_outlined,
    keywords: 'custom field',
    ownerOnly: false,
  ),
  (
    title: 'Notifications',
    hint: 'Which events send email or in-app messages.',
    route: AppRoutes.settingsNotifications,
    icon: Icons.notifications_none,
    keywords: 'email alert reminder digest',
    ownerOnly: false,
  ),
  (
    title: 'Security',
    hint: 'Passwords, two-step sign-in, sessions, invitations.',
    route: AppRoutes.settingsSecurity,
    icon: Icons.shield_outlined,
    keywords: 'password two-step mfa session invite',
    ownerOnly: true,
  ),
  (
    title: 'Data & export',
    hint: 'Export permissions, file formats, retention, audit access.',
    route: AppRoutes.settingsData,
    icon: Icons.storage_outlined,
    keywords: 'export retention audit format',
    ownerOnly: true,
  ),
  (
    title: 'Branding & localization',
    hint: 'Logo, colors, language, date, time and number formats.',
    route: AppRoutes.settingsBranding,
    icon: Icons.palette_outlined,
    keywords: 'logo color language date format',
    ownerOnly: false,
  ),
];

/// Security and data settings use the owner-only permission (D-58).
bool isOwnerLevel(AppSession s) =>
    s.permissions.can(PermissionModule.roles, PermissionAction.edit);

List<SettingsArea> areasFor(AppSession s) => [
  for (final a in settingsAreas)
    if (!a.ownerOnly || isOwnerLevel(s))
      if (a.route != AppRoutes.organization && a.route != AppRoutes.branches ||
          s.permissions.canView(PermissionModule.organization))
        a,
];

/// Page frame for a settings area: side list (wide) or a select (narrow),
/// title, and the unsaved / save bar.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({
    super.key,
    required this.route,
    required this.title,
    required this.body,
    this.subtitle,
    this.dirty = false,
    this.busy = false,
    this.savedNote,
    this.onSave,
    this.onDiscard,
    this.saveLabel = 'Save changes',
  });

  final String route;
  final String title;
  final String? subtitle;
  final Widget Function(OrgSettings settings) body;
  final bool dirty;
  final bool busy;
  final String? savedNote;
  final VoidCallback? onSave;
  final VoidCallback? onDiscard;
  final String saveLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final settings = ref.watch(orgSettingsProvider);
    if (session == null) return const SizedBox.shrink();
    if (settings.isLoading) {
      return const ResponsivePage(
        child: LoadingSkeleton(
          label: 'Loading settings',
          child: SkeletonList(rows: 6),
        ),
      );
    }
    if (settings.hasError) {
      return ErrorState(
        message: userMessageFor(settings.error!),
        onRetry: () => ref.invalidate(orgSettingsProvider),
      );
    }
    final areas = areasFor(session);
    final canEdit = session.permissions.can(
      PermissionModule.settings,
      PermissionAction.edit,
    );
    final head = Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.sm,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Settings / $title', style: AppTypography.helper),
            Semantics(
              header: true,
              child: Text(title, style: AppTypography.pageTitle),
            ),
            if (subtitle != null) Text(subtitle!, style: AppTypography.small),
          ],
        ),
        if (onSave != null && canEdit)
          Wrap(
            spacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (dirty)
                Text(
                  'Unsaved changes',
                  style: AppTypography.small.copyWith(
                    color: AppColors.warningText,
                  ),
                )
              else if (savedNote != null)
                Text(
                  savedNote!,
                  style: AppTypography.small.copyWith(
                    color: AppColors.successText,
                  ),
                ),
              if (onDiscard != null)
                AppButton(
                  label: 'Discard',
                  variant: AppButtonVariant.secondary,
                  onPressed: dirty ? onDiscard : null,
                ),
              AppButton(
                label: saveLabel,
                busy: busy,
                busyLabel: 'Saving…',
                onPressed: dirty ? onSave : null,
              ),
            ],
          ),
      ],
    );
    return ResponsivePage(
      child: LayoutBuilder(
        builder: (context, c) {
          final wide = c.maxWidth >= 1000;
          final content = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!wide) ...[
                DashboardSelect<String>(
                  label: 'Settings area',
                  value: route,
                  options: [
                    (AppRoutes.settings, 'All settings'),
                    for (final a in areas) (a.route, a.title),
                  ],
                  onChanged: (v) {
                    if (v != null && v != route) context.go(v);
                  },
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              head,
              const SizedBox(height: AppSpacing.lg),
              body(settings.value!),
            ],
          );
          if (!wide) return content;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 220,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final a in areas)
                      Semantics(
                        selected: a.route == route,
                        button: true,
                        child: InkWell(
                          onTap: () => context.go(a.route),
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: a.route == route
                                  ? AppColors.primarySoft
                                  : null,
                              borderRadius: BorderRadius.circular(AppRadius.md),
                            ),
                            child: Text(
                              a.title,
                              style: AppTypography.small.copyWith(
                                color: a.route == route
                                    ? AppColors.primaryHover
                                    : AppColors.textPrimary,
                                fontWeight: a.route == route
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xl),
              Expanded(child: content),
            ],
          );
        },
      ),
    );
  }
}
