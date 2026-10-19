import '../domain/notifications.dart';

/// DEMO ONLY — inboxes in memory, seeded with the stories on boards S76
/// (HR admin and owner) and S95 (Isha) relative to "now". Emails are only
/// queued in an outbox; nothing is sent.
class DemoNotificationRepository implements NotificationRepository {
  DemoNotificationRepository({
    this.latency = const Duration(milliseconds: 200),
    required this.now,
  });

  final Duration latency;
  final DateTime Function() now;
  final _orgs = <String, _Org>{};
  int _next = 1;

  Future<void> _delay() =>
      latency == Duration.zero ? Future.value() : Future.delayed(latency);

  _Org _org(String id) => _orgs.putIfAbsent(id, () => _seed(_Org()));

  _Org _seed(_Org o) {
    final t = now();
    DateTime at(int days, int h, int m) =>
        DateTime(t.year, t.month, t.day - days, h, m);
    AppNotification n(
      String to,
      NotificationCategory c,
      String title,
      String short,
      DateTime when, {
      String body = '',
      List<(String, String)> facts = const [],
      String? route,
      String cta = '',
      bool read = false,
      NotificationTone tone = NotificationTone.info,
    }) => AppNotification(
      id: 'n-${_next++}',
      recipient: to,
      category: c,
      title: title,
      short: short,
      at: when,
      body: body,
      facts: facts,
      route: route,
      cta: cta,
      read: read,
      tone: tone,
    );

    for (final admin in const ['EMP-0105', 'u-ankit']) {
      o.items.addAll([
        n(
          admin,
          NotificationCategory.approvals,
          'Earned leave needs HR approval',
          'Jignesh Parmar asked for 5 days of earned leave.',
          t.subtract(const Duration(minutes: 20)),
          body:
              'Jignesh Parmar (Branch Manager) requested 5 days of earned leave. Because he is the branch’s approver, it was routed to HR.',
          facts: const [('Type', 'Earned leave'), ('Days', '5')],
          route: '/leave',
          cta: 'Review request',
        ),
        n(
          admin,
          NotificationCategory.attendance,
          'Missing punches from yesterday',
          'Open sessions are waiting for a correction',
          at(0, 8, 0),
          body:
              'Some sessions from yesterday have no punch-out. Worked time for those days is held until corrected.',
          route: '/attendance/missing-punches',
          cta: 'Open queue',
        ),
        n(
          admin,
          NotificationCategory.people,
          'Invitation not delivered',
          'The mail server rejected an address',
          at(1, 11, 20),
          body:
              'An invitation couldn’t be delivered. Fix the address and send it again.',
          route: '/roles/invitations',
          cta: 'Fix email',
        ),
        n(
          admin,
          NotificationCategory.system,
          'Import finished with failed rows',
          'vadodara_staff.xlsx · 38 created',
          at(2, 16, 15),
          body:
              'Your import completed. 38 employees were created and 4 rows failed.',
          facts: const [('Created', '38'), ('Failed', '4')],
          route: '/employees',
          cta: 'See employees',
          read: true,
        ),
        n(
          admin,
          NotificationCategory.system,
          'Monthly report ready',
          'Monthly attendance summary',
          at(12, 9, 0),
          body: 'The report you requested is ready to download for 7 days.',
          route: '/reports/exports',
          cta: 'Open export history',
          read: true,
        ),
      ]);
    }
    o.items.addAll([
      n(
        'EMP-0229',
        NotificationCategory.attendance,
        'Attendance corrected',
        'Your punch-out yesterday was set to 18:34 by Mitesh Rana.',
        at(0, 9, 5),
        route: '/my/attendance',
        tone: NotificationTone.fix,
      ),
      n(
        'EMP-0229',
        NotificationCategory.system,
        'Holiday next week',
        'Dussehra on Tue 20 Oct — the Surat unit is closed.',
        at(0, 8, 0),
        route: '/my/holidays',
      ),
      n(
        'EMP-0229',
        NotificationCategory.people,
        'Profile updated',
        'HR changed your mobile number.',
        at(3, 12, 4),
        route: '/my/profile',
        read: true,
        tone: NotificationTone.user,
      ),
      n(
        'EMP-0229',
        NotificationCategory.approvals,
        'Leave not approved',
        'Casual leave: “Audit week, please move”',
        at(20, 10, 0),
        route: '/my/leave',
        read: true,
        tone: NotificationTone.no,
      ),
      n(
        'EMP-0229',
        NotificationCategory.system,
        'Announcement',
        'New canteen timings: lunch 13:00–14:00.',
        at(16, 9, 0),
        read: true,
      ),
    ]);
    return o;
  }

  @override
  Future<List<AppNotification>> inbox(
    String organizationId,
    String recipient,
  ) async {
    await _delay();
    final list = [
      for (final i in _org(organizationId).items)
        if (i.recipient == recipient) i,
    ]..sort((a, b) => b.at.compareTo(a.at));
    return List.unmodifiable(list);
  }

  @override
  Future<void> send(String organizationId, List<AppNotification> items) async {
    await _delay();
    final o = _org(organizationId);
    for (final i in items) {
      o.items.add(
        AppNotification(
          id: 'n-${_next++}',
          recipient: i.recipient,
          category: i.category,
          tone: i.tone,
          title: i.title,
          short: i.short,
          body: i.body,
          facts: i.facts,
          at: i.at,
          route: i.route,
          cta: i.cta,
          event: i.event,
        ),
      );
    }
  }

  @override
  Future<void> markRead(
    String organizationId,
    String recipient, {
    String? id,
  }) async {
    await _delay();
    final items = _org(organizationId).items;
    for (var i = 0; i < items.length; i++) {
      final x = items[i];
      if (x.recipient == recipient && (id == null || x.id == id) && !x.read) {
        items[i] = x.markRead();
      }
    }
  }

  @override
  Future<NotificationPrefs> prefs(String organizationId) async {
    await _delay();
    return _org(organizationId).prefs;
  }

  @override
  Future<NotificationPrefs> savePrefs(
    String organizationId,
    NotificationPrefs prefs,
  ) async {
    await _delay();
    final saved = prefs.copyWith(updatedAt: now());
    _org(organizationId).prefs = saved;
    return saved;
  }

  @override
  Future<void> queueEmail(String organizationId, OutgoingEmail email) async {
    _org(organizationId).outbox.add(email);
  }

  @override
  Future<List<OutgoingEmail>> outbox(String organizationId) async =>
      List.unmodifiable(_org(organizationId).outbox);
}

class _Org {
  final items = <AppNotification>[];
  final outbox = <OutgoingEmail>[];
  NotificationPrefs prefs = const NotificationPrefs();
}
