import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/config/app_config.dart';
import '../../../core/errors/failure.dart';
import '../../../core/permissions/permissions.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../../organization/presentation/providers/organization_providers.dart';
import '../data/demo_audit_repository.dart';
import '../domain/audit.dart';

final auditRepositoryProvider = Provider<AuditRepository>(
  (ref) => DemoAuditRepository(
    latency: ref.watch(demoLatencyProvider),
    now: () => ref.read(orgNowProvider)(),
  ),
);

/// The audit trail, newest first, limited to what the member may see:
/// everything for organization-wide roles, their branches otherwise
/// (board S84 "Audit log access").
final auditEventsProvider = FutureProvider<List<AuditEvent>>((ref) async {
  final session = ref.watch(sessionProvider);
  if (session == null ||
      !session.permissions.canView(PermissionModule.auditLog)) {
    throw const PermissionFailure();
  }
  final all = await ref
      .watch(auditRepositoryProvider)
      .events(session.organizationId);
  return [
    for (final e in all)
      if (session.branchIds.isEmpty ||
          e.branchId == null ||
          session.branchIds.contains(e.branchId))
        e,
  ];
});

/// Records audit entries for the signed-in member's actions.
final auditRecorderProvider = Provider<AuditRecorder>(AuditRecorder.new);

/// DEMO source address; a backend records the real one.
const demoIp = '103.21.58.14';

class AuditRecorder {
  AuditRecorder(this.ref);

  final Ref ref;

  Future<AuditEvent?> record({
    required String action,
    required String entityType,
    required String entityLabel,
    required String summary,
    String? entityId,
    String? entityRoute,
    String? branchId,
    String scopeLabel = '',
    String reason = '',
    AuditSource source = AuditSource.web,
    List<AuditChange> changes = const [],
    List<String> affected = const [],
    List<String> relatedIds = const [],
    String? actorName,
    String? actorRole,
  }) async {
    final session = ref.read(sessionProvider);
    if (session == null && actorName == null) return null;
    final saved = await ref
        .read(auditRepositoryProvider)
        .record(
          session?.organizationId ?? '',
          AuditEvent(
            id: '',
            at: ref.read(orgNowProvider)(),
            actorName: actorName ?? session!.displayName,
            actorRole: actorRole ?? session!.roleName,
            action: action,
            entityType: entityType,
            entityId: entityId,
            entityLabel: entityLabel,
            entityRoute: entityRoute,
            branchId: branchId,
            scopeLabel: scopeLabel.isEmpty
                ? (branchId == null ? 'Organization' : '')
                : scopeLabel,
            summary: summary,
            reason: reason,
            source: source,
            ip: source == AuditSource.system ? '' : demoIp,
            changes: changes,
            affected: affected,
            relatedIds: relatedIds,
          ),
        );
    ref.invalidate(auditEventsProvider);
    return saved;
  }
}
