import '../domain/audit.dart';

/// DEMO ONLY — an append-only audit trail in memory, seeded with the
/// stories on boards S77–S78 relative to "now".
class DemoAuditRepository implements AuditRepository {
  DemoAuditRepository({
    this.latency = const Duration(milliseconds: 300),
    required this.now,
  });

  final Duration latency;
  final DateTime Function() now;

  /// Oldest first, so the checksum chain reads forwards.
  final _orgs = <String, List<AuditEvent>>{};
  int _next = 0x8f2200;

  Future<void> _delay() =>
      latency == Duration.zero ? Future.value() : Future.delayed(latency);

  String _id() => 'evt_${(_next++).toRadixString(16)}';

  List<AuditEvent> _org(String id) => _orgs.putIfAbsent(id, () {
    final list = <AuditEvent>[];
    for (final e in _seed()..sort((a, b) => a.at.compareTo(b.at))) {
      list.add(e.sealed(list.isEmpty ? '' : list.last.hash));
    }
    return list;
  });

  List<AuditEvent> _seed() {
    final t = now();
    DateTime at(int days, int h, int m, [int s = 0]) =>
        DateTime(t.year, t.month, t.day - days, h, m, s);
    String day(int days) {
      final d = at(days, 0, 0);
      const months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      return '${d.day} ${months[d.month - 1]}';
    }

    const ip = '103.21.58.14';
    final roleEdit = _id();
    final reauth = _id();
    final ended = _id();
    final earlier = _id();
    return [
      AuditEvent(
        id: _id(),
        at: at(13, 22, 47),
        actorName: 'Unknown',
        actorRole: '—',
        action: 'auth.signin_failed',
        entityType: 'Sign-in',
        entityLabel: 'Sign-in',
        scopeLabel: 'Organization',
        summary: '5 failed attempts for an employee account · locked 15 min',
        source: AuditSource.web,
        ip: '49.36.112.7',
      ),
      AuditEvent(
        id: earlier,
        at: at(12, 10, 3),
        actorName: 'Ankit Patel',
        actorRole: 'Owner',
        action: 'policy.update',
        entityType: 'Attendance policy',
        entityLabel: 'Attendance policy',
        scopeLabel: 'Factory floor',
        summary: 'Early departure threshold 15 → 30 min',
        reason: 'Shift handovers run long on the dyeing floor',
        ip: ip,
        changes: const [
          (
            field: 'Early departure threshold',
            before: '15 min',
            after: '30 min',
          ),
        ],
      ),
      AuditEvent(
        id: _id(),
        at: at(2, 16, 15),
        actorName: 'Hetal Shah',
        actorRole: 'HR Admin',
        action: 'import.commit',
        entityType: 'Import',
        entityLabel: 'vadodara_staff.xlsx',
        branchId: 'b-vad',
        scopeLabel: 'Vadodara',
        summary: '38 created · 0 updated · 4 failed',
        source: AuditSource.import,
        ip: ip,
      ),
      AuditEvent(
        id: _id(),
        at: at(3, 12, 4),
        actorName: 'Hetal Shah',
        actorRole: 'HR Admin',
        action: 'employee.update',
        entityType: 'Employee',
        entityId: 'e-13',
        entityLabel: 'Isha Rathod',
        entityRoute: '/employees/e-13',
        branchId: 'b-sur',
        scopeLabel: 'Surat',
        summary: 'Mobile number and personal email updated',
        reason: 'Employee asked by email',
        ip: ip,
        changes: const [
          (
            field: 'Mobile',
            before: '+91 98250 14417',
            after: '+91 98790 24417',
          ),
          (
            field: 'Personal email',
            before: 'isha.rathod@gmail.com',
            after: 'isha.r.surat@gmail.com',
          ),
        ],
      ),
      AuditEvent(
        id: _id(),
        at: at(1, 11, 40),
        actorName: 'Neha Iyer',
        actorRole: 'Branch Manager',
        action: 'leave.reject',
        entityType: 'Leave request',
        entityLabel: 'Leave #L-2287',
        branchId: 'b-vad',
        scopeLabel: 'Vadodara',
        summary: 'Rejected — “Peak dispatch week, please move by 3 days”',
        ip: ip,
      ),
      AuditEvent(
        id: reauth,
        at: at(1, 17, 1),
        actorName: 'Ankit Patel',
        actorRole: 'Owner',
        action: 'auth.reauth',
        entityType: 'Sign-in',
        entityLabel: 'Ankit Patel',
        scopeLabel: 'Organization',
        summary: 'Confirmed with password (re-authentication)',
        ip: ip,
      ),
      AuditEvent(
        id: roleEdit,
        at: at(1, 17, 2, 18),
        actorName: 'Ankit Patel',
        actorRole: 'Owner',
        action: 'role.update',
        entityType: 'Role',
        entityId: 'branchManager',
        entityLabel: 'Role: Branch Manager',
        entityRoute: '/roles/branchManager',
        scopeLabel: 'Organization',
        summary: 'Added Attendance · Correct; removed Employees · Deactivate',
        reason: 'Let branch managers fix punches',
        ip: ip,
        changes: const [
          (
            field: 'Attendance · Correct',
            before: 'Not allowed',
            after: 'Allowed',
          ),
          (
            field: 'Dashboard · Export',
            before: 'Not allowed',
            after: 'Allowed',
          ),
          (
            field: 'Employees · Deactivate',
            before: 'Allowed',
            after: 'Not allowed',
          ),
        ],
        affected: const [
          'Jignesh Parmar · Surat · signed out 1 session',
          'Kiran Dave · Ahmedabad HQ · signed out 2 sessions',
        ],
        relatedIds: [reauth, ended, earlier],
      ),
      AuditEvent(
        id: ended,
        at: at(1, 17, 2, 20),
        actorName: 'System',
        actorRole: '—',
        action: 'session.revoke',
        entityType: 'Session',
        entityLabel: 'Branch Manager sessions',
        scopeLabel: 'Organization',
        summary: '3 sessions ended because role permissions changed',
        source: AuditSource.system,
        relatedIds: [roleEdit],
      ),
      AuditEvent(
        id: _id(),
        at: at(1, 18, 20),
        actorName: 'Jignesh Parmar',
        actorRole: 'Branch Manager',
        action: 'leave.approve',
        entityType: 'Leave request',
        entityLabel: 'Aarav Bhatt · casual leave',
        branchId: 'b-sur',
        scopeLabel: 'Surat',
        summary: 'Approved 2 days casual for Aarav Bhatt',
        ip: ip,
      ),
      AuditEvent(
        id: _id(),
        at: at(0, 8, 52),
        actorName: 'Hetal Shah',
        actorRole: 'HR Admin',
        action: 'employee.update',
        entityType: 'Employee',
        entityLabel: 'Meera Rao',
        branchId: 'b-sur',
        scopeLabel: 'Ahmedabad HQ → Surat',
        summary: 'Branch transfer effective ${day(-1)}; manager changed',
        ip: ip,
        changes: const [
          (field: 'Branch', before: 'Ahmedabad HQ', after: 'Surat'),
          (field: 'Manager', before: 'Kiran Dave', after: 'Jignesh Parmar'),
        ],
      ),
      AuditEvent(
        id: _id(),
        at: at(0, 9, 5, 42),
        actorName: 'Mitesh Rana',
        actorRole: 'Attendance Manager',
        action: 'attendance.correct',
        entityType: 'Attendance',
        entityId: 'e-13',
        entityLabel: 'Isha Rathod · ${day(1)}',
        entityRoute: '/employees/e-13',
        branchId: 'b-sur',
        scopeLabel: 'Surat',
        summary: 'Punch-out added 18:34 — “Forgot to punch at gate”',
        reason:
            'Forgot to punch at gate. Verified with CCTV log and supervisor.',
        ip: ip,
        changes: const [
          (field: 'Punch-out', before: '—', after: '18:34'),
          (field: 'Status', before: 'Missing punch', after: 'Late'),
        ],
      ),
    ];
  }

  @override
  Future<List<AuditEvent>> events(String organizationId) async {
    await _delay();
    // Stored in the order things happened; newest first is the reverse
    // (timestamps can tie).
    return List.unmodifiable(_org(organizationId).reversed);
  }

  /// Oldest first, as stored (for checksum verification).
  List<AuditEvent> chain(String organizationId) =>
      List.unmodifiable(_org(organizationId));

  @override
  Future<AuditEvent> record(String organizationId, AuditEvent draft) async {
    await _delay();
    final list = _org(organizationId);
    final sealed = AuditEvent(
      id: draft.id.isEmpty ? _id() : draft.id,
      at: draft.at,
      actorName: draft.actorName,
      actorRole: draft.actorRole,
      action: draft.action,
      entityType: draft.entityType,
      entityId: draft.entityId,
      entityLabel: draft.entityLabel,
      entityRoute: draft.entityRoute,
      branchId: draft.branchId,
      scopeLabel: draft.scopeLabel,
      summary: draft.summary,
      reason: draft.reason,
      source: draft.source,
      ip: draft.ip,
      changes: draft.changes,
      affected: draft.affected,
      relatedIds: draft.relatedIds,
    ).sealed(list.isEmpty ? '' : list.last.hash);
    list.add(sealed);
    return sealed;
  }
}
