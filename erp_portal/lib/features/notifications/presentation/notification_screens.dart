import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/router/route_names.dart';
import '../../../core/errors/failure.dart';
import '../../../core/permissions/permissions.dart';
import '../../../core/permissions/system_roles.dart';
import '../../../core/responsive/responsive_page.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../../organization/presentation/providers/organization_providers.dart';
import '../domain/notifications.dart';
import 'notification_providers.dart';

/// Where the bell leads for this member.
String inboxRouteFor(SystemRole role) =>
    role == SystemRole.employee || role == SystemRole.leaveApprover
    ? AppRoutes.myNotifications
    : AppRoutes.notifications;

/// The top-bar bell with the unread count.
class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    if (session == null) return const SizedBox.shrink();
    final unread = ref.watch(unreadCountProvider);
    return IconButton(
      tooltip: unread == 0 ? 'Notifications' : 'Notifications, $unread unread',
      onPressed: () => context.go(inboxRouteFor(session.role)),
      // The tooltip carries the count; the small badge stays its own size.
      icon: MediaQuery.withNoTextScaling(
        child: Badge(
          isLabelVisible: unread > 0,
          label: Text(unread > 9 ? '9+' : '$unread'),
          backgroundColor: AppColors.danger,
          child: const Icon(
            Icons.notifications_none,
            color: AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

/// "20 min ago", "08:00", "Yesterday", "2 Oct".
String whenText(DateTime at, DateTime now) {
  final d = now.difference(at);
  if (d.inMinutes < 60) return '${d.inMinutes.clamp(1, 59)} min ago';
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(at.year, at.month, at.day);
  if (day == today) return DateFormat('HH:mm').format(at);
  if (today.difference(day).inDays == 1) return 'Yesterday';
  return DateFormat('d MMM').format(at);
}

({Color bg, Color fg, IconData icon}) _lookOf(AppNotification n) =>
    switch (n.category) {
      NotificationCategory.approvals => (
        bg: AppColors.warningSoft,
        fg: AppColors.warningText,
        icon: Icons.schedule,
      ),
      NotificationCategory.attendance => (
        bg: AppColors.dangerSoft,
        fg: AppColors.dangerText,
        icon: Icons.priority_high,
      ),
      NotificationCategory.people => (
        bg: AppColors.primarySoft,
        fg: AppColors.primaryHover,
        icon: Icons.alternate_email,
      ),
      NotificationCategory.system => (
        bg: AppColors.neutralSoft,
        fg: AppColors.textSecondary,
        icon: Icons.info_outline,
      ),
    };

({Color bg, Color fg, IconData icon}) _toneOf(NotificationTone t) =>
    switch (t) {
      NotificationTone.ok => (
        bg: AppColors.successSoft,
        fg: AppColors.successText,
        icon: Icons.check,
      ),
      NotificationTone.fix => (
        bg: AppColors.primarySoft,
        fg: AppColors.primary,
        icon: Icons.edit_outlined,
      ),
      NotificationTone.no => (
        bg: AppColors.dangerSoft,
        fg: AppColors.dangerText,
        icon: Icons.close,
      ),
      NotificationTone.user => (
        bg: AppColors.warningSoft,
        fg: AppColors.warningText,
        icon: Icons.person_outline,
      ),
      NotificationTone.info => (
        bg: AppColors.neutralSoft,
        fg: AppColors.textSecondary,
        icon: Icons.info_outline,
      ),
    };

class _Glyph extends StatelessWidget {
  const _Glyph(this.look);

  final ({Color bg, Color fg, IconData icon}) look;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(color: look.bg, shape: BoxShape.circle),
      child: Icon(look.icon, size: 16, color: look.fg),
    ),
  );
}

Widget _loading(WidgetRef ref, AsyncValue<List<AppNotification>> inbox) {
  if (inbox.hasError) {
    return ErrorState(
      message: userMessageFor(inbox.error!),
      onRetry: () => ref.invalidate(inboxProvider),
    );
  }
  return const ResponsivePage(
    child: LoadingSkeleton(
      label: 'Loading notifications',
      child: SkeletonList(rows: 5),
    ),
  );
}

/// Board S76 — the admin inbox with a detail panel.
class AdminNotificationsScreen extends ConsumerStatefulWidget {
  const AdminNotificationsScreen({super.key});

  @override
  ConsumerState<AdminNotificationsScreen> createState() =>
      _AdminNotificationsScreenState();
}

class _AdminNotificationsScreenState
    extends ConsumerState<AdminNotificationsScreen> {
  NotificationCategory? _filter;
  String? _selected;
  bool _detailOpen = false;

  Future<void> _open(AppNotification n) async {
    setState(() {
      _selected = n.id;
      _detailOpen = true;
    });
    if (!n.read) await ref.read(inboxProvider.notifier).markRead(id: n.id);
  }

  @override
  Widget build(BuildContext context) {
    final inbox = ref.watch(inboxProvider);
    final session = ref.watch(sessionProvider);
    if (!inbox.hasValue || session == null) return _loading(ref, inbox);
    final now = ref.watch(orgNowProvider)();
    final all = inbox.value!;
    final shown = [
      for (final n in all)
        if (_filter == null || n.category == _filter) n,
    ];
    final selected =
        shown.where((n) => n.id == _selected).firstOrNull ?? shown.firstOrNull;
    final unread = all.where((n) => !n.read).length;
    final canSettings = session.permissions.can(
      PermissionModule.settings,
      PermissionAction.view,
    );

    final list = AppCard(
      padding: EdgeInsets.zero,
      child: shown.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: EmptyState(
                icon: Icons.notifications_off_outlined,
                title: 'You’re all caught up',
                message: 'New approvals and alerts will show here.',
              ),
            )
          : Column(
              children: [
                for (final n in shown)
                  Semantics(
                    selected: n.id == selected?.id,
                    button: true,
                    label: n.read ? null : 'Unread',
                    child: InkWell(
                      onTap: () => _open(n),
                      child: Container(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: n.id == selected?.id
                              ? const Color(0xFFF7F8FE)
                              : (n.read ? null : const Color(0xFFFBFCFF)),
                          border: Border(
                            left: BorderSide(
                              color: n.id == selected?.id
                                  ? AppColors.primary
                                  : Colors.transparent,
                              width: 3,
                            ),
                            bottom: const BorderSide(color: AppColors.divider),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _Glyph(_lookOf(n)),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    n.title,
                                    style: AppTypography.small.copyWith(
                                      color: AppColors.textPrimary,
                                      fontWeight: n.read
                                          ? FontWeight.w500
                                          : FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    n.short,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTypography.helper,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  whenText(n.at, now),
                                  style: AppTypography.helper,
                                ),
                                if (!n.read)
                                  Container(
                                    margin: const EdgeInsets.only(top: 4),
                                    width: 8,
                                    height: 8,
                                    decoration: const BoxDecoration(
                                      color: AppColors.primary,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );

    Widget? detail;
    if (selected != null) {
      final look = _lookOf(selected);
      detail = AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _Glyph(look),
                const SizedBox(width: AppSpacing.sm),
                Text(selected.category.label, style: AppTypography.small),
                const Spacer(),
                Text(whenText(selected.at, now), style: AppTypography.helper),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Semantics(
              header: true,
              child: Text(selected.title, style: AppTypography.sectionTitle),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              selected.body.isEmpty ? selected.short : selected.body,
              style: AppTypography.body,
            ),
            if (selected.facts.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              for (final (k, v) in selected.facts)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 120,
                        child: Text(k, style: AppTypography.small),
                      ),
                      Expanded(
                        child: Text(
                          v,
                          style: AppTypography.small.copyWith(
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            if (selected.route != null) ...[
              const SizedBox(height: AppSpacing.lg),
              Align(
                alignment: Alignment.centerLeft,
                child: AppButton(
                  label: selected.cta.isEmpty ? 'Open' : selected.cta,
                  onPressed: () => context.go(selected.route!),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            const Text(
              'Notifications never include passwords, attachments or restricted fields — open the record to see details you’re allowed to view.',
              style: AppTypography.helper,
            ),
          ],
        ),
      );
    }

    return ResponsivePage(
      child: LayoutBuilder(
        builder: (context, c) {
          final wide = c.maxWidth >= 900;
          if (!wide && _detailOpen && detail != null) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(() => _detailOpen = false),
                    icon: const Icon(Icons.chevron_left),
                    label: const Text('All notifications'),
                  ),
                ),
                detail,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.sm,
                children: [
                  Semantics(
                    header: true,
                    child: const Text(
                      'Notifications',
                      style: AppTypography.pageTitle,
                    ),
                  ),
                  Wrap(
                    spacing: AppSpacing.sm,
                    children: [
                      if (canSettings)
                        AppButton(
                          label: 'Notification settings',
                          variant: AppButtonVariant.ghost,
                          onPressed: () =>
                              context.go(AppRoutes.settingsNotifications),
                        ),
                      AppButton(
                        label: 'Mark all read',
                        variant: AppButtonVariant.secondary,
                        onPressed: unread == 0
                            ? null
                            : () => ref.read(inboxProvider.notifier).markRead(),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final c in <NotificationCategory?>[
                    null,
                    ...NotificationCategory.values,
                  ])
                    FilterChip(
                      label: Text(
                        '${c?.label ?? 'All'} ${c == null ? all.length : all.where((n) => n.category == c).length}',
                      ),
                      selected: _filter == c,
                      showCheckmark: false,
                      onSelected: (_) => setState(() => _filter = c),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              if (wide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 420, child: list),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(child: detail ?? const SizedBox.shrink()),
                  ],
                )
              else
                list,
            ],
          );
        },
      ),
    );
  }
}

/// Board S95 — the employee's notifications.
class MyNotificationsScreen extends ConsumerStatefulWidget {
  const MyNotificationsScreen({super.key});

  @override
  ConsumerState<MyNotificationsScreen> createState() =>
      _MyNotificationsScreenState();
}

class _MyNotificationsScreenState extends ConsumerState<MyNotificationsScreen> {
  bool _unreadOnly = false;

  @override
  Widget build(BuildContext context) {
    final inbox = ref.watch(inboxProvider);
    if (!inbox.hasValue) return _loading(ref, inbox);
    final now = ref.watch(orgNowProvider)();
    final all = inbox.value!;
    final unread = all.where((n) => !n.read).length;
    final shown = [
      for (final n in all)
        if (!_unreadOnly || !n.read) n,
    ];
    final today = DateTime(now.year, now.month, now.day);
    final groups = [
      (
        'Today',
        [
          for (final n in shown)
            if (!n.at.isBefore(today)) n,
        ],
      ),
      (
        'Earlier',
        [
          for (final n in shown)
            if (n.at.isBefore(today)) n,
        ],
      ),
    ];
    return ResponsivePage(
      maxWidth: 720,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Semantics(
                header: true,
                child: const Text(
                  'Notifications',
                  style: AppTypography.pageTitle,
                ),
              ),
              TextButton(
                onPressed: unread == 0
                    ? null
                    : () => ref.read(inboxProvider.notifier).markRead(),
                child: const Text('Mark all read'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              ChoiceChip(
                label: const Text('All'),
                selected: !_unreadOnly,
                onSelected: (_) => setState(() => _unreadOnly = false),
              ),
              ChoiceChip(
                label: Text('Unread ($unread)'),
                selected: _unreadOnly,
                onSelected: (_) => setState(() => _unreadOnly = true),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (shown.isEmpty)
            const AppCard(
              child: EmptyState(
                icon: Icons.notifications_none,
                title: 'You’re all caught up',
                message:
                    'New leave decisions and attendance updates will show here.',
              ),
            ),
          for (final (label, items) in groups)
            if (items.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Semantics(
                  header: true,
                  child: Text(label, style: AppTypography.cardTitle),
                ),
              ),
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (final n in items)
                      Semantics(
                        label: n.read ? null : 'Unread',
                        child: InkWell(
                          onTap: () async {
                            if (!n.read) {
                              await ref
                                  .read(inboxProvider.notifier)
                                  .markRead(id: n.id);
                            }
                            if (n.route != null && context.mounted) {
                              context.go(n.route!);
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.all(AppSpacing.md),
                            decoration: BoxDecoration(
                              color: n.read ? null : const Color(0xFFF7F8FE),
                              border: const Border(
                                bottom: BorderSide(color: AppColors.divider),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _Glyph(_toneOf(n.tone)),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        n.title,
                                        style: AppTypography.small.copyWith(
                                          color: AppColors.textPrimary,
                                          fontWeight: n.read
                                              ? FontWeight.w500
                                              : FontWeight.w700,
                                        ),
                                      ),
                                      Text(
                                        n.short,
                                        style: AppTypography.helper,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Text(
                                  whenText(n.at, now),
                                  style: AppTypography.helper,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
        ],
      ),
    );
  }
}
