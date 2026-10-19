import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../app/config/app_config.dart';
import '../../../../core/errors/failure.dart';
import '../../../../shared/models/app_session.dart';
import '../../../roles/domain/access.dart';
import '../../../roles/presentation/access_providers.dart';
import '../../../settings/presentation/settings_providers.dart';
import '../../data/demo_auth_repository.dart';
import '../../data/session_store.dart';
import '../../domain/auth_models.dart';
import '../../domain/auth_repository.dart';
import '../../domain/auth_state.dart';

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => DemoAuthRepository(latency: ref.watch(demoLatencyProvider)),
);

final sessionStoreProvider = FutureProvider<SessionStore>(
  (ref) async => SessionStore(await SharedPreferences.getInstance()),
);

final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

/// The signed-in member, or null.
///
/// The member's current role definition (Phase 7) is layered over the
/// session from sign-in, so a permission change reaches open sessions on
/// the next rebuild without signing in again (D-53).
final sessionProvider = Provider<AppSession?>((ref) {
  final auth = ref.watch(authControllerProvider);
  if (auth is! SignedIn) return null;
  final access = ref.watch(accessDataProvider).value;
  return access == null ? auth.session : applyAccess(auth.session, access);
});

/// The auth state the route guards see: [sessionProvider] in place of the
/// sign-in session.
AuthState effectiveAuth(Ref ref) {
  final auth = ref.read(authControllerProvider);
  if (auth is! SignedIn) return auth;
  final session = ref.read(sessionProvider) ?? auth.session;
  return SignedIn(auth.account, session, auth.memberships);
}

/// Drives the sign-in journey. Screens call these methods and show any
/// `Failure` they throw; the router reacts to the resulting [AuthState].
class AuthController extends Notifier<AuthState> {
  bool _keepSignedIn = false;

  AuthRepository get _repo => ref.read(authRepositoryProvider);
  Future<SessionStore> get _store => ref.read(sessionStoreProvider.future);

  @override
  AuthState build() {
    unawaited(_restore());
    return const RestoringSession();
  }

  Future<void> _restore() async {
    try {
      final store = await _store;
      final saved = store.read();
      if (saved == null) {
        state = const SignedOut();
        return;
      }
      final account = await _repo.accountById(saved.accountId);
      final memberships = await _repo.membershipsOf(saved.accountId);
      final membership = memberships
          .where((m) => m.isActive && m.organizationId == saved.organizationId)
          .firstOrNull;
      if (account == null || membership == null) {
        await store.clear();
        state = const SignedOut();
        return;
      }
      _keepSignedIn = true;
      state = SignedIn(
        account,
        _sessionFor(account, membership, memberships),
        memberships,
      );
    } on Object {
      // Storage unavailable or the saved account is gone: start signed out.
      state = const SignedOut();
    }
  }

  Future<void> signIn({
    required String identifier,
    required String password,
    required bool keepSignedIn,
  }) async {
    final result = await _repo.signIn(
      identifier: identifier,
      password: password,
    );
    _keepSignedIn = keepSignedIn;
    final store = await _store;
    // The organization's policy can require two-step for the role even
    // when the person hasn't turned it on (board S83).
    var requires = result.requiresTwoStep;
    if (!requires) {
      final settings = ref.read(settingsRepositoryProvider);
      for (final m in await _repo.membershipsOf(result.account.id)) {
        if (!m.isActive) continue;
        final policy = (await settings.load(m.organizationId)).security.twoStep;
        if (policy.requires(m.role)) requires = true;
      }
    }
    if (requires && !store.isTrusted(result.account.id)) {
      state = AwaitingTwoStep(result.account);
      return;
    }
    await _afterAuthentication(result.account);
  }

  /// Returns the number of backup codes left when one was used.
  Future<int?> verifyTwoStep({
    required String code,
    required bool isBackupCode,
    required bool trustDevice,
  }) async {
    final current = state;
    if (current is! AwaitingTwoStep) throw const UnexpectedFailure();
    final left = await _repo.verifyTwoStep(
      accountId: current.account.id,
      code: code,
      isBackupCode: isBackupCode,
    );
    if (trustDevice) await (await _store).trustDevice(current.account.id);
    await _afterAuthentication(current.account);
    return left;
  }

  Future<void> register({
    required String fullName,
    required String email,
    required String password,
    String? phone,
  }) async {
    await _repo.register(
      fullName: fullName,
      email: email,
      password: password,
      phone: phone,
    );
    state = AwaitingEmailVerification(email.trim().toLowerCase());
  }

  Future<void> verifyEmail(String code) async {
    final current = state;
    if (current is! AwaitingEmailVerification) {
      throw const UnexpectedFailure();
    }
    final account = await _repo.verifyEmail(email: current.email, code: code);
    state = NeedsOrganization(account);
  }

  Future<void> acceptInvitation({
    required String token,
    required String password,
  }) async {
    final account = await _repo.acceptInvitation(
      token: token,
      password: password,
    );
    _keepSignedIn = false;
    await _afterAuthentication(account);
  }

  /// From the organization selector, or to switch while signed in.
  Future<void> chooseOrganization(String organizationId) async {
    final current = state;
    final (account, memberships) = switch (current) {
      AwaitingOrganizationChoice(:final account, :final memberships) => (
        account,
        memberships,
      ),
      SignedIn(:final account, :final memberships) => (account, memberships),
      _ => throw const UnexpectedFailure(),
    };
    final membership = memberships
        .where((m) => m.isActive && m.organizationId == organizationId)
        .firstOrNull;
    if (membership == null) {
      throw const PermissionFailure(
        'This membership is deactivated. Ask that organization’s owner '
        'to restore it.',
      );
    }
    await _repo.rememberLastOrganization(
      accountId: account.id,
      organizationId: organizationId,
    );
    final updated = await _repo.membershipsOf(account.id);
    await _enter(account, membership, updated);
  }

  /// After the signed-in person creates an organization: re-read their
  /// memberships and enter the new organization as its owner.
  Future<void> enterNewOrganization(String organizationId) async {
    final account = switch (state) {
      NeedsOrganization(:final account) => account,
      AwaitingOrganizationChoice(:final account) => account,
      SignedIn(:final account) => account,
      _ => throw const UnexpectedFailure(),
    };
    final memberships = await _repo.membershipsOf(account.id);
    final membership = memberships.firstWhere(
      (m) => m.organizationId == organizationId,
      orElse: () => throw const NotFoundFailure(),
    );
    await _enter(account, membership, memberships);
  }

  /// The account behind any signed-in or onboarding state.
  UserAccount? get currentAccount => switch (state) {
    NeedsOrganization(:final account) => account,
    AwaitingOrganizationChoice(:final account) => account,
    SignedIn(:final account) => account,
    AwaitingTwoStep(:final account) => account,
    _ => null,
  };

  Future<String> requestAccess(String path) async {
    // Read our own state: sessionProvider depends on this notifier, so
    // reading it here would be a dependency cycle.
    final current = state;
    if (current is! SignedIn) throw const UnexpectedFailure();
    final session = current.session;
    return _repo.requestAccess(
      accountId: session.userId,
      organizationId: session.organizationId,
      path: path,
    );
  }

  Future<void> signOut() async {
    _keepSignedIn = false;
    try {
      await (await _store).clear();
    } on Object {
      // Nothing saved to clear.
    }
    state = const SignedOut();
  }

  Future<void> _afterAuthentication(UserAccount account) async {
    final memberships = await _repo.membershipsOf(account.id);
    if (memberships.isEmpty) {
      state = NeedsOrganization(account);
      return;
    }
    final active = memberships.where((m) => m.isActive).toList();
    if (memberships.length == 1 && active.length == 1) {
      await _enter(account, active.single, memberships);
      return;
    }
    state = AwaitingOrganizationChoice(account, memberships);
  }

  Future<void> _enter(
    UserAccount account,
    OrganizationMembership membership,
    List<OrganizationMembership> memberships,
  ) async {
    final store = await _store;
    if (_keepSignedIn) {
      await store.save(
        accountId: account.id,
        organizationId: membership.organizationId,
      );
    } else {
      await store.clear();
    }
    state = SignedIn(
      account,
      _sessionFor(account, membership, memberships),
      memberships,
    );
  }

  static AppSession _sessionFor(
    UserAccount account,
    OrganizationMembership membership,
    List<OrganizationMembership> memberships,
  ) => AppSession(
    userId: account.id,
    displayName: account.fullName,
    email: account.email,
    organizationId: membership.organizationId,
    organizationName: membership.organizationName,
    role: membership.role,
    scopeLabel: membership.scopeLabel,
    canSwitchOrganization: memberships.length > 1,
    branchIds: membership.branchIds,
    employeeId: account.employeeId,
  );
}
