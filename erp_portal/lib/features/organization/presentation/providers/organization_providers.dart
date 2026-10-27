import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/config/app_config.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/utils/clock.dart';
import '../../../../core/utils/zoned_time.dart';
import '../../../audit/presentation/audit_providers.dart';
import '../../../auth/data/demo_auth_repository.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../employees/presentation/providers/employee_providers.dart';
import '../../data/demo_organization_repository.dart';
import '../../domain/branch.dart';
import '../../domain/organization.dart';
import '../../domain/organization_repository.dart';
import '../../domain/setup_progress.dart';

final organizationRepositoryProvider = Provider<OrganizationRepository>((ref) {
  final auth = ref.watch(authRepositoryProvider);
  final employees = ref.watch(employeeRepositoryProvider);
  return DemoOrganizationRepository(
    latency: ref.watch(demoLatencyProvider),
    countEmployees: employees.countInBranch,
    // The demo sign-in data learns about the new owner membership.
    onOrganizationCreated: auth is DemoAuthRepository
        ? (accountId, org) =>
              auth.addOwnerMembership(accountId, org.id, org.name)
        : null,
  );
});

String _organizationId(Ref ref) {
  final session = ref.watch(sessionProvider);
  if (session == null) throw const PermissionFailure();
  return session.organizationId;
}

/// The signed-in member's organization.
final organizationProvider =
    AsyncNotifierProvider<OrganizationNotifier, Organization>(
      OrganizationNotifier.new,
    );

class OrganizationNotifier extends AsyncNotifier<Organization> {
  @override
  Future<Organization> build() => ref
      .read(organizationRepositoryProvider)
      .organization(_organizationId(ref));

  /// Saves and publishes the new values. Throws a `Failure` on refusal.
  Future<void> save(Organization organization) async {
    final session = ref.read(sessionProvider);
    final saved = await ref
        .read(organizationRepositoryProvider)
        .updateOrganization(
          organization,
          updatedBy: session?.displayName ?? '',
        );
    final before = state.value;
    state = AsyncData(saved);
    await ref
        .read(auditRecorderProvider)
        .record(
          action: 'organization.update',
          entityType: 'Organization',
          entityLabel: saved.name,
          entityRoute: '/organization',
          summary: 'Organization profile saved',
          changes: [
            if (before != null && before.name != saved.name)
              (field: 'Name', before: before.name, after: saved.name),
            if (before != null && before.timeZone != saved.timeZone)
              (
                field: 'Time zone',
                before: before.timeZone,
                after: saved.timeZone,
              ),
          ],
        );
  }
}

/// The owner profile, or null before it is set up (board S15).
final ownerProfileProvider =
    AsyncNotifierProvider<OwnerProfileNotifier, OwnerProfile?>(
      OwnerProfileNotifier.new,
    );

class OwnerProfileNotifier extends AsyncNotifier<OwnerProfile?> {
  @override
  Future<OwnerProfile?> build() => ref
      .read(organizationRepositoryProvider)
      .ownerProfile(_organizationId(ref));

  Future<void> save(OwnerProfile profile) async {
    await ref
        .read(organizationRepositoryProvider)
        .saveOwnerProfile(_organizationId(ref), profile);
    state = AsyncData(profile);
  }
}

/// All branches of the organization, active and inactive.
final branchesProvider = AsyncNotifierProvider<BranchesNotifier, List<Branch>>(
  BranchesNotifier.new,
);

class BranchesNotifier extends AsyncNotifier<List<Branch>> {
  OrganizationRepository get _repo => ref.read(organizationRepositoryProvider);

  @override
  Future<List<Branch>> build() => _repo.branches(_organizationId(ref));

  List<Branch> get _current => state.value ?? const [];

  Future<void> _log(Branch b, String action, String summary) => ref
      .read(auditRecorderProvider)
      .record(
        action: action,
        entityType: 'Branch',
        entityId: b.id,
        entityLabel: b.name,
        entityRoute: '/branches/${b.id}',
        branchId: b.id,
        scopeLabel: b.name,
        summary: summary,
      );

  Future<Branch> create(Branch branch) async {
    final created = await _repo.createBranch(_organizationId(ref), branch);
    state = AsyncData([..._current, created]);
    await _log(created, 'branch.create', 'Created ${created.name}');
    return created;
  }

  /// Saves an edited branch or one setup step.
  Future<Branch> save(Branch branch) async {
    final saved = await _repo.updateBranch(_organizationId(ref), branch);
    _replace(saved);
    await _log(saved, 'branch.update', '${saved.name} settings saved');
    return saved;
  }

  Future<Branch> setStatus(String branchId, BranchStatus status) async {
    final saved = await _repo.setBranchStatus(
      _organizationId(ref),
      branchId,
      status,
    );
    _replace(saved);
    await _log(saved, 'branch.status', '${saved.name} is now ${status.name}');
    return saved;
  }

  void _replace(Branch branch) => state = AsyncData([
    for (final b in _current) b.id == branch.id ? branch : b,
  ]);
}

/// One branch by id, from [branchesProvider].
/// Branches the signed-in member may see: all of them, or only their
/// assigned branches for branch-scoped roles.
final visibleBranchesProvider = Provider<AsyncValue<List<Branch>>>((ref) {
  final scope = ref.watch(sessionProvider)?.branchIds ?? const <String>[];
  return ref
      .watch(branchesProvider)
      .whenData(
        (all) => scope.isEmpty
            ? all
            : [
                for (final b in all)
                  if (scope.contains(b.id)) b,
              ],
      );
});

final branchProvider = Provider.family<AsyncValue<Branch?>, String>(
  (ref, id) => ref
      .watch(visibleBranchesProvider)
      .whenData((list) => list.where((b) => b.id == id).firstOrNull),
);

/// Overall onboarding state for the setup home (boards S15–S24).
class SetupOverview {
  const SetupOverview({
    required this.organization,
    required this.owner,
    required this.branches,
  });

  final Organization organization;
  final OwnerProfile? owner;

  /// Active branches only; inactive ones don't need setup.
  final List<Branch> branches;

  int get stepsDone =>
      1 + (owner != null ? 1 : 0) + (branches.isNotEmpty ? 1 : 0);
  int get readyCount => branches.where((b) => SetupProgress(b).isReady).length;

  bool get isComplete =>
      owner != null && branches.isNotEmpty && readyCount == branches.length;
}

final setupOverviewProvider = FutureProvider<SetupOverview>((ref) async {
  final organization = await ref.watch(organizationProvider.future);
  final owner = await ref.watch(ownerProfileProvider.future);
  final branches = await ref.watch(branchesProvider.future);
  return SetupOverview(
    organization: organization,
    owner: owner,
    branches: [
      for (final b in branches)
        if (b.isActive) b,
    ],
  );
});

/// Last setup step opened, for "Continue where you left off" (board S24).
final setupBookmarkProvider =
    AsyncNotifierProvider<SetupBookmarkNotifier, SetupBookmark?>(
      SetupBookmarkNotifier.new,
    );

class SetupBookmarkNotifier extends AsyncNotifier<SetupBookmark?> {
  @override
  Future<SetupBookmark?> build() => ref
      .read(organizationRepositoryProvider)
      .setupBookmark(_organizationId(ref));

  Future<void> remember(String branchId, SetupStep step) async {
    final bookmark = SetupBookmark(branchId: branchId, step: step.name);
    state = AsyncData(bookmark);
    await ref
        .read(organizationRepositoryProvider)
        .saveSetupBookmark(_organizationId(ref), bookmark);
  }
}

/// True once the "Welcome back" banner was dismissed or used this session.
final returningBannerDismissedProvider = NotifierProvider<_FlagNotifier, bool>(
  _FlagNotifier.new,
);

class _FlagNotifier extends Notifier<bool> {
  @override
  bool build() {
    // A new sign-in shows the banner again.
    ref.watch(sessionProvider.select((s) => s?.organizationId));
    return false;
  }

  void set() => state = true;
}

/// Unsaved setup panels kept when closed ("Close · keep draft", board S21).
/// Keyed "branchId:step". In memory for the session.
final setupDraftsProvider =
    NotifierProvider<SetupDraftsNotifier, Map<String, Object>>(
      SetupDraftsNotifier.new,
    );

class SetupDraftsNotifier extends Notifier<Map<String, Object>> {
  @override
  Map<String, Object> build() => const {};

  static String key(String branchId, SetupStep step) =>
      '$branchId:${step.name}';

  T? draft<T>(String branchId, SetupStep step) =>
      state[key(branchId, step)] as T?;

  void keep(String branchId, SetupStep step, Object draft) =>
      state = {...state, key(branchId, step): draft};

  void discard(String branchId, SetupStep step) =>
      state = {...state}..remove(key(branchId, step));
}

/// "Now" as wall-clock time in the organization's time zone (floating
/// DateTime). Use it for dates, greetings and "this month".
final orgNowProvider = Provider<DateTime Function()>((ref) {
  final clock = ref.watch(clockProvider);
  final zone =
      ref.watch(organizationProvider).value?.timeZone ?? defaultTimeZone;
  return () => wallTime(clock(), zone);
});
