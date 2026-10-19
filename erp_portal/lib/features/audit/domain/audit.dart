import 'package:flutter/foundation.dart';

/// One changed field of an audit event (boards S77–S78 "Before / After").
typedef AuditChange = ({String field, String before, String after});

/// Where an event came from.
enum AuditSource {
  web('Web'),
  import('Import'),
  system('System'),
  kiosk('Kiosk');

  const AuditSource(this.label);

  final String label;
}

/// A sealed, append-only audit entry (boards S77, S78; PRD §12).
@immutable
class AuditEvent {
  const AuditEvent({
    required this.id,
    required this.at,
    required this.actorName,
    required this.actorRole,
    required this.action,
    required this.entityType,
    required this.entityLabel,
    required this.summary,
    this.entityId,
    this.entityRoute,
    this.branchId,
    this.scopeLabel = '',
    this.reason = '',
    this.source = AuditSource.web,
    this.ip = '',
    this.changes = const [],
    this.affected = const [],
    this.relatedIds = const [],
    this.previousHash = '',
    this.hash = '',
  });

  /// "evt_8f21c4".
  final String id;

  /// Floating time in the organization's zone.
  final DateTime at;
  final String actorName;
  final String actorRole;

  /// Dotted code, e.g. `leave.approve`, `role.update`.
  final String action;

  /// "Leave request", "Employee", "Role" …
  final String entityType;
  final String? entityId;

  /// "Leave #L-2291", "Isha Rathod · 13 Oct".
  final String entityLabel;

  /// Where the record opens in the app, if anywhere.
  final String? entityRoute;

  /// For branch-scoped viewers; null = organization.
  final String? branchId;
  final String scopeLabel;
  final String summary;
  final String reason;
  final AuditSource source;

  /// Stored in full; shown masked (see [maskValue]).
  final String ip;
  final List<AuditChange> changes;

  /// People affected, e.g. "Jignesh Parmar · Surat · signed out 1 session".
  final List<String> affected;
  final List<String> relatedIds;

  /// Checksum chain: each entry includes the previous entry's hash.
  final String previousHash;
  final String hash;

  /// "attendance" from `attendance.correct`.
  String get area => action.split('.').first;

  /// The fields that make up the checksum.
  String get canonical => [
    id,
    at.toIso8601String(),
    actorName,
    action,
    entityType,
    entityId ?? '',
    entityLabel,
    summary,
    reason,
    ip,
    for (final c in changes) '${c.field}=${c.before}>${c.after}',
    previousHash,
  ].join('|');

  AuditEvent sealed(String previous) {
    final draft = AuditEvent(
      id: id,
      at: at,
      actorName: actorName,
      actorRole: actorRole,
      action: action,
      entityType: entityType,
      entityId: entityId,
      entityLabel: entityLabel,
      entityRoute: entityRoute,
      branchId: branchId,
      scopeLabel: scopeLabel,
      summary: summary,
      reason: reason,
      source: source,
      ip: ip,
      changes: changes,
      affected: affected,
      relatedIds: relatedIds,
      previousHash: previous,
    );
    return AuditEvent(
      id: id,
      at: at,
      actorName: actorName,
      actorRole: actorRole,
      action: action,
      entityType: entityType,
      entityId: entityId,
      entityLabel: entityLabel,
      entityRoute: entityRoute,
      branchId: branchId,
      scopeLabel: scopeLabel,
      summary: summary,
      reason: reason,
      source: source,
      ip: ip,
      changes: changes,
      affected: affected,
      relatedIds: relatedIds,
      previousHash: previous,
      hash: auditChecksum(draft.canonical),
    );
  }
}

/// DEMO checksum (64-bit FNV-1a, hex). A backend would use SHA-256 over the
/// same canonical text.
String auditChecksum(String text) {
  var h = BigInt.parse('cbf29ce484222325', radix: 16);
  final prime = BigInt.parse('100000001b3', radix: 16);
  final mask = (BigInt.one << 64) - BigInt.one;
  for (final c in text.codeUnits) {
    h = ((h ^ BigInt.from(c)) * prime) & mask;
  }
  return h.toRadixString(16).padLeft(16, '0');
}

/// True when every entry's hash matches its content and links to the one
/// before it (oldest first).
bool verifyAuditChain(List<AuditEvent> oldestFirst) {
  var previous = '';
  for (final e in oldestFirst) {
    if (e.previousHash != previous) return false;
    if (auditChecksum(e.canonical) != e.hash) return false;
    previous = e.hash;
  }
  return true;
}

/// Fields whose values are never shown in full (board S77).
const sensitiveFields = {
  'Personal email',
  'Work email',
  'Mobile',
  'Date of birth',
  'Emergency contact',
  'IP address',
  'Password',
};

/// Masks a sensitive value: emails keep two letters and the domain,
/// numbers the first and last digits, IPs the first two parts.
String maskValue(String field, String value) {
  if (value.isEmpty || value == '—') return value;
  if (field == 'Password') return '••••••••';
  if (field == 'Date of birth') return 'Restricted';
  if (field == 'IP address' ||
      RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(value)) {
    final p = value.split('.');
    return p.length == 4 ? '${p[0]}.${p[1]}.••.••' : '••••';
  }
  if (value.contains('@')) {
    final at = value.indexOf('@');
    final name = value.substring(0, at);
    final keep = name.length <= 2 ? name.substring(0, 1) : name.substring(0, 2);
    return '$keep••••${value.substring(at)}';
  }
  final digits = value.replaceAll(RegExp(r'\D'), '');
  if (digits.length >= 6) {
    final last = digits.substring(digits.length - 4);
    final lead = value.trimLeft().startsWith('+')
        ? '+${digits.substring(0, 2)} ${digits.substring(2, 4)}•• ••'
        : '${digits.substring(0, 2)}•• ••';
    return '$lead$last';
  }
  return '••••';
}

/// A value as shown: masked when the field is sensitive.
String shownValue(String field, String value) =>
    sensitiveFields.contains(field) ? maskValue(field, value) : value;

/// Filters on the audit log (board S77).
@immutable
class AuditQuery {
  const AuditQuery({
    this.days = 7,
    this.actor,
    this.areas = const {},
    this.entityType,
    this.branchId,
    this.search = '',
  });

  /// 0 = all time.
  final int days;
  final String? actor;

  /// Action areas, e.g. {"leave", "attendance"}; empty = all.
  final Set<String> areas;
  final String? entityType;
  final String? branchId;
  final String search;

  bool matches(AuditEvent e, DateTime now) {
    if (days > 0 && e.at.isBefore(now.subtract(Duration(days: days)))) {
      return false;
    }
    if (actor != null && e.actorName != actor) return false;
    if (areas.isNotEmpty && !areas.contains(e.area)) return false;
    if (entityType != null && e.entityType != entityType) return false;
    if (branchId != null && e.branchId != branchId) return false;
    final q = search.trim().toLowerCase();
    if (q.isNotEmpty &&
        !'${e.summary} ${e.entityLabel} ${e.actorName} ${e.action} ${e.id}'
            .toLowerCase()
            .contains(q)) {
      return false;
    }
    return true;
  }

  AuditQuery copyWith({
    int? days,
    Object? actor = _keep,
    Set<String>? areas,
    Object? entityType = _keep,
    Object? branchId = _keep,
    String? search,
  }) => AuditQuery(
    days: days ?? this.days,
    actor: identical(actor, _keep) ? this.actor : actor as String?,
    areas: areas ?? this.areas,
    entityType: identical(entityType, _keep)
        ? this.entityType
        : entityType as String?,
    branchId: identical(branchId, _keep) ? this.branchId : branchId as String?,
    search: search ?? this.search,
  );
}

const _keep = Object();

/// Append-only. There is deliberately no update or delete.
abstract interface class AuditRepository {
  /// Newest first.
  Future<List<AuditEvent>> events(String organizationId);

  /// Seals and appends; returns the stored entry.
  Future<AuditEvent> record(String organizationId, AuditEvent draft);
}
