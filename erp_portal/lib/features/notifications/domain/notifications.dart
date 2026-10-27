import 'package:flutter/foundation.dart';

/// Inbox groups (board S76 chips).
enum NotificationCategory {
  approvals('Approvals'),
  attendance('Attendance'),
  people('People'),
  system('System');

  const NotificationCategory(this.label);

  final String label;
}

/// The look of an employee notification (board S95).
enum NotificationTone { ok, fix, no, info, user }

/// Who a preference row targets (board S82 columns).
enum Recipient {
  employee('Employee'),
  manager('Manager'),
  hr('HR Admin');

  const Recipient(this.label);

  final String label;
}

enum Channel {
  inApp('In-app'),
  email('Email');

  const Channel(this.label);

  final String label;
}

/// Events people can be told about (board S82 rows). [defaults] has six
/// characters — employee in-app, employee email, manager in-app, manager
/// email, HR in-app, HR email — each `1` on, `0` off, `L` always on (can't
/// be turned off) or `N` not applicable.
enum NotifyEvent {
  leaveSubmitted('Leave', 'New request needs approval', 'NN1100'),
  leaveDecided('Leave', 'Request approved or rejected', '11N000'),
  leaveWithdrawn('Leave', 'Request withdrawn or cancelled', '1N1000'),
  missingPunch('Attendance', 'Missing punch at end of day', '111000'),
  correctionDecided('Attendance', 'Correction approved or rejected', '11N0N0'),
  repeatedLateness('Attendance', 'Repeated lateness (3 in a month)', 'NN1110'),
  faceFlagged('Attendance', 'Punch selfie needs review', 'NN1010'),
  faceEnrolSubmitted(
    'Attendance',
    'Face set-up waiting for approval',
    'NNNN10',
  ),
  faceDecided('Attendance', 'Face set-up or selfie review decided', '10N0N0'),
  invitation('People & account', 'Invitation to join', 'LLNNNN'),
  profileChanged('People & account', 'Profile changed by HR', '11NNNN'),
  inviteBounced('People & account', 'Invitation not delivered', 'NNNN11'),
  holidaySoon('Calendar', 'Holiday in the next 7 days', '100000'),
  holidayAdded('Calendar', 'New holiday added', '101000');

  const NotifyEvent(this.group, this.label, this.defaults);

  final String group;
  final String label;
  final String defaults;

  static int _cell(Recipient r, Channel c) => r.index * 2 + c.index;

  bool applies(Recipient r, Channel c) => defaults[_cell(r, c)] != 'N';
  bool locked(Recipient r, Channel c) => defaults[_cell(r, c)] == 'L';
  bool onByDefault(Recipient r, Channel c) =>
      defaults[_cell(r, c)] == '1' || locked(r, c);
}

/// One switch of the preference matrix.
typedef PrefKey = ({NotifyEvent event, Recipient to, Channel channel});

/// Organization notification settings (board S82).
@immutable
class NotificationPrefs {
  const NotificationPrefs({
    this.overrides = const {},
    this.digest = false,
    this.digestAt = 18 * 60,
    this.updatedAt,
  });

  /// Only the switches changed from the defaults.
  final Map<PrefKey, bool> overrides;

  /// Managers get one daily email instead of each event.
  final bool digest;

  /// Minutes after midnight, branch local time.
  final int digestAt;
  final DateTime? updatedAt;

  bool isOn(NotifyEvent e, Recipient to, Channel c) {
    if (!e.applies(to, c)) return false;
    if (e.locked(to, c)) return true;
    return overrides[(event: e, to: to, channel: c)] ?? e.onByDefault(to, c);
  }

  /// Switches that are on, across all events (board S80 "14 events on").
  int get onCount => [
    for (final e in NotifyEvent.values)
      for (final r in Recipient.values)
        for (final c in Channel.values)
          if (isOn(e, r, c)) 1,
  ].length;

  NotificationPrefs toggled(NotifyEvent e, Recipient to, Channel c) {
    if (!e.applies(to, c) || e.locked(to, c)) return this;
    return copyWith(
      overrides: {
        ...overrides,
        (event: e, to: to, channel: c): !isOn(e, to, c),
      },
    );
  }

  NotificationPrefs copyWith({
    Map<PrefKey, bool>? overrides,
    bool? digest,
    int? digestAt,
    DateTime? updatedAt,
  }) => NotificationPrefs(
    overrides: overrides ?? this.overrides,
    digest: digest ?? this.digest,
    digestAt: digestAt ?? this.digestAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

/// A message in someone's inbox (boards S76, S95). Never carries
/// passwords, attachments or restricted fields.
@immutable
class AppNotification {
  const AppNotification({
    required this.id,
    required this.recipient,
    required this.category,
    required this.title,
    required this.short,
    required this.at,
    this.body = '',
    this.tone = NotificationTone.info,
    this.facts = const [],
    this.route,
    this.cta = '',
    this.read = false,
    this.event,
  });

  final String id;

  /// Employee code (EMP-0229), or the account id for members without an
  /// employee record (the owner).
  final String recipient;
  final NotificationCategory category;
  final NotificationTone tone;
  final String title;

  /// One line for the list.
  final String short;
  final String body;
  final List<(String, String)> facts;

  /// Floating time in the organization's zone.
  final DateTime at;

  /// Where the action button goes.
  final String? route;
  final String cta;
  final bool read;
  final NotifyEvent? event;

  AppNotification markRead() => AppNotification(
    id: id,
    recipient: recipient,
    category: category,
    tone: tone,
    title: title,
    short: short,
    body: body,
    facts: facts,
    at: at,
    route: route,
    cta: cta,
    read: true,
    event: event,
  );
}

/// A message that would be emailed (no mail is sent in the demo).
typedef OutgoingEmail = ({
  String to,
  String subject,
  DateTime at,
  NotifyEvent? event,
});

abstract interface class NotificationRepository {
  Future<List<AppNotification>> inbox(String organizationId, String recipient);
  Future<void> send(String organizationId, List<AppNotification> items);
  Future<void> markRead(String organizationId, String recipient, {String? id});
  Future<NotificationPrefs> prefs(String organizationId);
  Future<NotificationPrefs> savePrefs(
    String organizationId,
    NotificationPrefs prefs,
  );
  Future<void> queueEmail(String organizationId, OutgoingEmail email);
  Future<List<OutgoingEmail>> outbox(String organizationId);
}
