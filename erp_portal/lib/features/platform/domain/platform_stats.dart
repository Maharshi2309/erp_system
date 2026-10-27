import 'package:flutter/foundation.dart';

/// Statistics the platform super admin sees (D-75). Everything here is a
/// count, a percentage or a business detail of the organization itself —
/// never a person's name, contact details or records.

enum OrgStatus {
  active('Active'),
  settingUp('Setting up'),
  quiet('No activity in 7 days');

  const OrgStatus(this.label);

  final String label;
}

@immutable
class BranchStats {
  const BranchStats({
    required this.id,
    required this.name,
    required this.code,
    required this.city,
    required this.active,
    required this.employees,
    required this.setupPercent,
    required this.activeToday,
    required this.selfieCheck,
  });

  final String id;
  final String name;
  final String code;
  final String city;
  final bool active;

  /// Employed people (active, probation, notice period).
  final int employees;
  final int setupPercent;

  /// People with at least one punch today.
  final int activeToday;
  final bool selfieCheck;
}

@immutable
class OrgStats {
  const OrgStats({
    required this.id,
    required this.name,
    required this.industry,
    required this.city,
    required this.state,
    required this.sizeRange,
    required this.createdAt,
    required this.branches,
    required this.employees,
    required this.inactiveEmployees,
    required this.accountsSignedIn,
    required this.accountsInvited,
    required this.dailyActive,
    required this.punches30,
    required this.leaveRequests30,
    required this.leavePending,
    required this.customFields,
    required this.imports,
    required this.faceEnrolled,
    required this.lastActivity,
  });

  final String id;
  final String name;
  final String industry;
  final String city;
  final String state;

  /// Size the owner chose at sign-up, e.g. "51–200".
  final String sizeRange;
  final DateTime? createdAt;
  final List<BranchStats> branches;
  final int employees;
  final int inactiveEmployees;

  /// People who have signed in at least once.
  final int accountsSignedIn;

  /// Invitations not yet accepted.
  final int accountsInvited;

  /// People with a punch on each of the last 30 days, oldest first.
  final List<int> dailyActive;
  final int punches30;
  final int leaveRequests30;
  final int leavePending;
  final int customFields;
  final int imports;

  /// People whose face set-up for selfie punches is approved.
  final int faceEnrolled;
  final DateTime? lastActivity;

  int get activeToday => dailyActive.isEmpty ? 0 : dailyActive.last;
  int get activeBranches => branches.where((b) => b.active).length;
  int get selfieBranches =>
      branches.where((b) => b.active && b.selfieCheck).length;

  /// Share of employed people who use their account, 0–100.
  int get adoption =>
      employees == 0 ? 0 : (accountsSignedIn * 100 / employees).round();

  OrgStatus statusAt(DateTime now) {
    final ready = branches.any((b) => b.active && b.setupPercent == 100);
    if (employees == 0 || !ready) return OrgStatus.settingUp;
    final last = lastActivity;
    if (last == null || now.difference(last).inDays >= 7) {
      return OrgStatus.quiet;
    }
    return OrgStatus.active;
  }
}

/// All organizations on the platform at one moment.
@immutable
class PlatformSnapshot {
  const PlatformSnapshot({
    required this.generatedAt,
    required this.days,
    required this.orgs,
  });

  /// UTC instant the figures were calculated.
  final DateTime generatedAt;

  /// The last 30 calendar days, oldest first (matches [OrgStats.dailyActive]).
  final List<DateTime> days;
  final List<OrgStats> orgs;

  int get branches => orgs.fold(0, (s, o) => s + o.activeBranches);
  int get employees => orgs.fold(0, (s, o) => s + o.employees);
  int get accountsSignedIn => orgs.fold(0, (s, o) => s + o.accountsSignedIn);
  int get activeToday => orgs.fold(0, (s, o) => s + o.activeToday);
  int get leaveRequests30 => orgs.fold(0, (s, o) => s + o.leaveRequests30);
  int get punches30 => orgs.fold(0, (s, o) => s + o.punches30);

  int countWith(OrgStatus status) =>
      orgs.where((o) => o.statusAt(generatedAt) == status).length;

  /// Platform-wide people with a punch per day.
  List<int> get dailyActive => [
    for (var i = 0; i < days.length; i++)
      orgs.fold(0, (s, o) => s + (o.dailyActive.elementAtOrNull(i) ?? 0)),
  ];

  /// New organizations per month for the last [months] months, oldest
  /// first, as (first day of month, count).
  List<(DateTime, int)> registrations({int months = 12}) {
    final now = generatedAt;
    return [
      for (var i = months - 1; i >= 0; i--)
        () {
          final month = DateTime(now.year, now.month - i);
          final n = orgs.where((o) {
            final c = o.createdAt;
            return c != null && c.year == month.year && c.month == month.month;
          }).length;
          return (month, n);
        }(),
    ];
  }

  /// Organizations counted by a property, largest first.
  List<(String, int)> countBy(String Function(OrgStats o) key) {
    final counts = <String, int>{};
    for (final o in orgs) {
      final k = key(o).trim().isEmpty ? 'Not given' : key(o);
      counts[k] = (counts[k] ?? 0) + 1;
    }
    return counts.entries.map((e) => (e.key, e.value)).toList()
      ..sort((a, b) => b.$2.compareTo(a.$2));
  }

  /// Share of organizations using each feature, 0–100.
  List<(String, int)> get featureUse {
    int pct(bool Function(OrgStats o) uses) => orgs.isEmpty
        ? 0
        : (orgs.where(uses).length * 100 / orgs.length).round();
    return [
      ('Attendance punches', pct((o) => o.punches30 > 0)),
      ('Leave management', pct((o) => o.leaveRequests30 > 0)),
      ('Selfie punches', pct((o) => o.selfieBranches > 0)),
      ('Employee import', pct((o) => o.imports > 0)),
      ('Custom fields', pct((o) => o.customFields > 0)),
    ];
  }
}

/// Platform statistics. A backend computes these server-side from all
/// organizations and returns only aggregates (no personal data).
abstract interface class PlatformRepository {
  Future<PlatformSnapshot> snapshot();
}
