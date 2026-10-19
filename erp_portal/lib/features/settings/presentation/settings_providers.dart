import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/config/app_config.dart';
import '../../../core/errors/failure.dart';
import '../../audit/domain/audit.dart';
import '../../audit/presentation/audit_providers.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../data/demo_settings_repository.dart';
import '../domain/settings.dart';

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => DemoSettingsRepository(latency: ref.watch(demoLatencyProvider)),
);

final orgSettingsProvider =
    AsyncNotifierProvider<OrgSettingsNotifier, OrgSettings>(
      OrgSettingsNotifier.new,
    );

class OrgSettingsNotifier extends AsyncNotifier<OrgSettings> {
  @override
  Future<OrgSettings> build() async {
    final s = ref.watch(sessionProvider);
    if (s == null) throw const PermissionFailure();
    return ref.watch(settingsRepositoryProvider).load(s.organizationId);
  }

  /// Saves and logs one area of settings with its changes.
  Future<OrgSettings> save(
    OrgSettings next, {
    required String area,
    List<AuditChange> changes = const [],
  }) async {
    final s = ref.read(sessionProvider)!;
    final saved = await ref
        .read(settingsRepositoryProvider)
        .save(s.organizationId, next);
    state = AsyncData(saved);
    await ref
        .read(auditRecorderProvider)
        .record(
          action: 'settings.update',
          entityType: 'Settings',
          entityLabel: area,
          entityRoute: '/settings',
          summary: changes.isEmpty
              ? '$area saved'
              : changes
                    .map((c) => '${c.field} ${c.before} → ${c.after}')
                    .join('; '),
          changes: changes,
        );
    return saved;
  }
}
