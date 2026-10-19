import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/config/app_config.dart';
import '../../../core/errors/failure.dart';
import '../../../core/permissions/system_roles.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../../employees/domain/employee.dart';
import '../../employees/presentation/providers/employee_providers.dart';
import '../../organization/presentation/providers/organization_providers.dart';
import '../../roles/domain/access.dart';
import '../../roles/presentation/access_providers.dart';
import '../data/demo_notification_repository.dart';
import '../domain/notifications.dart';

final notificationRepositoryProvider = Provider<NotificationRepository>(
  (ref) => DemoNotificationRepository(
    latency: ref.watch(demoLatencyProvider),
    now: () => ref.read(orgNowProvider)(),
  ),
);

/// The signed-in member's inbox key: employee code, or account id.
String? inboxKey(Ref ref) {
  final s = ref.watch(sessionProvider);
  return s == null ? null : (s.employeeId ?? s.userId);
}

/// The signed-in member's notifications, newest first (boards S76, S95).
final inboxProvider =
    AsyncNotifierProvider<InboxNotifier, List<AppNotification>>(
      InboxNotifier.new,
    );

class InboxNotifier extends AsyncNotifier<List<AppNotification>> {
  NotificationRepository get _repo => ref.read(notificationRepositoryProvider);

  @override
  Future<List<AppNotification>> build() async {
    final key = inboxKey(ref);
    final session = ref.watch(sessionProvider);
    if (key == null || session == null) throw const PermissionFailure();
    return ref
        .watch(notificationRepositoryProvider)
        .inbox(session.organizationId, key);
  }

  Future<void> markRead({String? id}) async {
    final s = ref.read(sessionProvider)!;
    await _repo.markRead(s.organizationId, s.employeeId ?? s.userId, id: id);
    state = AsyncData(
      await _repo.inbox(s.organizationId, s.employeeId ?? s.userId),
    );
  }
}

final unreadCountProvider = Provider<int>(
  (ref) =>
      (ref.watch(inboxProvider).value ?? const []).where((n) => !n.read).length,
);

/// Organization notification settings (board S82).
final notificationPrefsProvider =
    AsyncNotifierProvider<NotificationPrefsNotifier, NotificationPrefs>(
      NotificationPrefsNotifier.new,
    );

class NotificationPrefsNotifier extends AsyncNotifier<NotificationPrefs> {
  @override
  Future<NotificationPrefs> build() async {
    final s = ref.watch(sessionProvider);
    if (s == null) throw const PermissionFailure();
    return ref.watch(notificationRepositoryProvider).prefs(s.organizationId);
  }

  Future<NotificationPrefs> save(NotificationPrefs prefs) async {
    final s = ref.read(sessionProvider)!;
    final saved = await ref
        .read(notificationRepositoryProvider)
        .savePrefs(s.organizationId, prefs);
    state = AsyncData(saved);
    return saved;
  }
}

/// Sends notifications for an event to the people the preferences name.
final notifierServiceProvider = Provider<NotificationService>(
  NotificationService.new,
);

class NotificationService {
  NotificationService(this.ref);

  final Ref ref;

  /// [employee] is the person the event is about; their manager and HR
  /// are told when the preferences say so. [approver] overrides "manager"
  /// (e.g. the step a leave request waits on).
  Future<int> send(
    NotifyEvent event, {
    required NotificationCategory category,
    required String title,
    required String short,
    Employee? employee,
    Employee? approver,
    List<Employee> employees = const [],
    bool includeHr = true,
    String body = '',
    List<(String, String)> facts = const [],
    String? employeeRoute,
    String? adminRoute,
    String cta = '',
    NotificationTone tone = NotificationTone.info,
  }) async {
    final session = ref.read(sessionProvider);
    if (session == null) return 0;
    final prefs =
        ref.read(notificationPrefsProvider).value ??
        await ref
            .read(notificationRepositoryProvider)
            .prefs(session.organizationId);
    final everyone =
        ref.read(employeesProvider).value ??
        await ref
            .read(employeeRepositoryProvider)
            .employees(session.organizationId);
    final manager =
        approver ??
        (employee?.managerId == null
            ? null
            : everyone.where((e) => e.id == employee!.managerId).firstOrNull);
    final targets = <(String, Recipient, String)>{};
    void add(Recipient r, String key, String? route) {
      // Nobody is notified about their own action.
      if (key == (session.employeeId ?? session.userId)) return;
      if (prefs.isOn(event, r, Channel.inApp)) {
        targets.add((key, r, route ?? ''));
      }
    }

    if (employee != null) add(Recipient.employee, employee.code, employeeRoute);
    for (final e in employees) {
      add(Recipient.employee, e.code, employeeRoute);
    }
    if (manager != null) add(Recipient.manager, manager.code, adminRoute);
    if (includeHr) {
      for (final e in everyone) {
        if (e.role == SystemRole.hrAdmin && e.status.isEmployed) {
          add(Recipient.hr, e.code, adminRoute);
        }
      }
      final access = ref.read(accessDataProvider).value;
      for (final m in access?.members ?? const <AccessMember>[]) {
        if (access!.assignments[m.key]?.roleId == SystemRole.owner.name) {
          add(Recipient.hr, m.key, adminRoute);
        }
      }
    }
    final now = ref.read(orgNowProvider)();
    final repo = ref.read(notificationRepositoryProvider);
    await repo.send(session.organizationId, [
      for (final (key, _, route) in targets)
        AppNotification(
          id: '',
          recipient: key,
          category: category,
          tone: tone,
          title: title,
          short: short,
          body: body,
          facts: facts,
          at: now,
          route: route.isEmpty ? null : route,
          cta: cta,
          event: event,
        ),
    ]);
    // Email is queued only (no mail is sent in the demo).
    for (final (key, r, _) in targets) {
      if (prefs.isOn(event, r, Channel.email)) {
        await repo.queueEmail(session.organizationId, (
          to: key,
          subject: title,
          at: now,
          event: event,
        ));
      }
    }
    ref.invalidate(inboxProvider);
    return targets.length;
  }
}
