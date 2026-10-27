import '../../../core/errors/failure.dart';
import '../../../core/permissions/system_roles.dart';
import '../../../core/utils/validators.dart';
import '../domain/auth_models.dart';
import '../domain/auth_repository.dart';
import '../domain/password_rules.dart';

/// In-memory stand-in for the auth backend (no backend yet, D-01).
///
/// Accounts, organizations and codes come from the design boards.
/// **Not secure**: passwords are compared in plain text and everything
/// resets when the app reloads, except what `SessionStore` keeps.
class DemoAuthRepository implements AuthRepository {
  DemoAuthRepository({
    this.latency = const Duration(milliseconds: 600),
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now {
    _seed();
  }

  /// Simulated network delay, so busy states are visible.
  final Duration latency;
  final DateTime Function() _now;

  static const demoPassword = 'Staffline@2026';
  static const demoAuthenticatorCode = '482913';
  static const demoBackupCode = '7KQ2-M9XD';
  static const demoEmailCode = '482913';
  static const demoInviteToken = 'demo-invite';
  static const demoExpiredInviteToken = 'demo-invite-expired';
  static const demoResetToken = 'demo-reset';
  static const demoExpiredResetToken = 'demo-reset-expired';

  static const _maxCodeTries = 3;
  static const _lockout = Duration(minutes: 15);

  final _accounts = <String, _DemoAccount>{};
  final _memberships = <String, List<OrganizationMembership>>{};
  final _pendingRegistrations = <String, _DemoAccount>{};
  final _invitations = <String, Invitation>{};
  final _usedResetTokens = <String>{};

  /// Accounts listed on the sign-in screen in demo builds.
  static const demoAccounts = <(String, String)>[
    ('ankit@meridiantex.in', 'Owner · 3 organizations'),
    ('hetal.s@meridiantex.in', 'HR Admin'),
    ('jignesh.p@meridiantex.in', 'Branch Manager · Surat'),
    ('mitesh.r@meridiantex.in', 'Attendance Manager'),
    ('aarav.b@meridiantex.in', 'Leave Approver'),
    ('EMP-0229', 'Employee · Isha Rathod'),
    (platformAdminEmail, 'Platform super admin · statistics only'),
  ];

  static const platformAdminEmail = 'admin@staffline.app';

  void _seed() {
    void add(
      String id,
      String name,
      String email,
      SystemRole role, {
      String? employeeId,
      String scope = 'all branches',
      List<String> branchIds = const [],
    }) {
      _accounts[id] = _DemoAccount(
        UserAccount(
          id: id,
          fullName: name,
          email: email,
          employeeId: employeeId,
        ),
        password: demoPassword,
        twoStep: role.requiresTwoStep,
      );
      _memberships[id] = [
        _meridian(role, scope, lastUsed: true, branchIds: branchIds),
      ];
    }

    add('u-ankit', 'Ankit Patel', 'ankit@meridiantex.in', SystemRole.owner);
    _memberships['u-ankit'] = [
      _meridian(SystemRole.owner, 'all branches', lastUsed: true),
      const OrganizationMembership(
        organizationId: 'org_pateldyes',
        organizationName: 'Patel Dyes & Chemicals',
        role: SystemRole.hrAdmin,
        scopeLabel: 'Vapi',
        summary: '1 branch · 42 employees',
      ),
      const OrganizationMembership(
        organizationId: 'org_sabarmati',
        organizationName: 'Sabarmati Retail',
        role: SystemRole.employee,
        scopeLabel: '',
        summary: 'Membership deactivated · history kept',
        status: MembershipStatus.deactivated,
      ),
    ];
    add(
      'u-hetal',
      'Hetal Shah',
      'hetal.s@meridiantex.in',
      SystemRole.hrAdmin,
      employeeId: 'EMP-0105',
    );
    add(
      'u-jignesh',
      'Jignesh Parmar',
      'jignesh.p@meridiantex.in',
      SystemRole.branchManager,
      employeeId: 'EMP-0102',
      scope: 'Surat',
      branchIds: const ['b-sur'],
    );
    add(
      'u-mitesh',
      'Mitesh Rana',
      'mitesh.r@meridiantex.in',
      SystemRole.attendanceManager,
      employeeId: 'EMP-0110',
      scope: 'Surat, Vadodara',
      branchIds: const ['b-sur', 'b-vad'],
    );
    add(
      'u-aarav',
      'Aarav Bhatt',
      'aarav.b@meridiantex.in',
      SystemRole.leaveApprover,
      employeeId: 'EMP-0201',
      scope: 'Own team (24)',
    );
    add(
      'u-isha',
      'Isha Rathod',
      'isha.r@meridiantex.in',
      SystemRole.employee,
      employeeId: 'EMP-0229',
      scope: 'Surat',
      branchIds: const ['b-sur'],
    );
    // Platform super admin: always two-step, no organization (D-75).
    _accounts['u-platform'] = _DemoAccount(
      const UserAccount(
        id: 'u-platform',
        fullName: 'Staffline Platform Admin',
        email: platformAdminEmail,
        isPlatformAdmin: true,
      ),
      password: demoPassword,
      twoStep: true,
    );
    _memberships['u-platform'] = const [];

    final now = _now();
    _invitations[demoInviteToken] = Invitation(
      token: demoInviteToken,
      inviterName: 'Hetal Shah',
      organizationName: 'Meridian Textiles',
      role: SystemRole.employee,
      branchName: 'Surat',
      fullName: 'Pooja Chauhan',
      employeeId: 'EMP-0244',
      email: 'pooja.c@meridiantex.in',
      startDate: now.add(const Duration(days: 3)),
      expiresAt: now.add(const Duration(days: 6)),
    );
    _invitations[demoExpiredInviteToken] = Invitation(
      token: demoExpiredInviteToken,
      inviterName: 'Hetal Shah',
      organizationName: 'Meridian Textiles',
      role: SystemRole.employee,
      branchName: 'Surat',
      fullName: 'Chirag Vaghela',
      employeeId: 'EMP-0233',
      email: 'chirag.v@meridiantex.in',
      startDate: now.subtract(const Duration(days: 10)),
      expiresAt: now.subtract(const Duration(days: 8)),
    );
  }

  static OrganizationMembership _meridian(
    SystemRole role,
    String scope, {
    bool lastUsed = false,
    List<String> branchIds = const [],
  }) => OrganizationMembership(
    organizationId: 'org_meridian-tex',
    organizationName: 'Meridian Textiles',
    role: role,
    scopeLabel: scope,
    summary: '3 branches · 248 employees',
    lastUsed: lastUsed,
    branchIds: branchIds,
  );

  Future<void> _delay() =>
      latency == Duration.zero ? Future.value() : Future.delayed(latency);

  _DemoAccount? _find(String identifier) {
    final key = identifier.trim().toLowerCase();
    for (final account in _accounts.values) {
      if (account.user.email.toLowerCase() == key ||
          account.user.employeeId?.toLowerCase() == key) {
        return account;
      }
    }
    return null;
  }

  _DemoAccount _byId(String accountId) {
    final account = _accounts[accountId];
    if (account == null) throw const NotFoundFailure();
    return account;
  }

  @override
  Future<SignInResult> signIn({
    required String identifier,
    required String password,
  }) async {
    await _delay();
    final account = _find(identifier);
    if (account == null || account.password != password) {
      throw const ValidationFailure(
        'That email or employee ID and password don’t match. '
        'Check both and try again.',
      );
    }
    return SignInResult(
      account: account.user,
      requiresTwoStep: account.twoStep,
    );
  }

  @override
  Future<int?> verifyTwoStep({
    required String accountId,
    required String code,
    required bool isBackupCode,
  }) async {
    await _delay();
    final account = _byId(accountId);
    final lockedUntil = account.lockedUntil;
    if (lockedUntil != null && _now().isBefore(lockedUntil)) {
      throw LockedFailure(_lockedMessage, until: lockedUntil);
    }

    final normalized = code.replaceAll('-', '').toUpperCase();
    final ok = isBackupCode
        ? account.backupCodes.remove(normalized)
        : normalized == demoAuthenticatorCode;
    if (ok) {
      account.wrongCodes = 0;
      account.lockedUntil = null;
      return isBackupCode ? account.backupCodes.length : null;
    }

    account.wrongCodes++;
    final left = _maxCodeTries - account.wrongCodes;
    if (left <= 0) {
      account.wrongCodes = 0;
      final until = _now().add(_lockout);
      account.lockedUntil = until;
      throw LockedFailure(_lockedMessage, until: until);
    }
    throw ValidationFailure(
      'That code didn’t work. $left ${left == 1 ? 'try' : 'tries'} left '
      'before a 15-minute pause.',
    );
  }

  static const _lockedMessage =
      'Too many wrong codes. Sign-in is paused for 15 minutes. If this '
      'wasn’t you, tell your owner — the attempts are in the audit log.';

  @override
  Future<void> register({
    required String fullName,
    required String email,
    required String password,
    String? phone,
  }) async {
    await _delay();
    final key = email.trim().toLowerCase();
    if (!Validators.isEmail(key)) {
      throw const ValidationFailure(
        'Check the email address.',
        fieldErrors: {'email': 'Enter a valid work email.'},
      );
    }
    if (!isStrongPassword(password, name: fullName, email: key)) {
      throw const ValidationFailure(
        'The password doesn’t meet the rules.',
        fieldErrors: {'password': 'Meet all the password rules.'},
      );
    }
    if (_find(key) != null) {
      throw const ValidationFailure(
        'An account already uses this email.',
        fieldErrors: {
          'email': 'An account already uses this email. Sign in instead.',
        },
      );
    }
    final id = 'u-${_accounts.length + _pendingRegistrations.length + 1}';
    _pendingRegistrations[key] = _DemoAccount(
      UserAccount(id: id, fullName: fullName.trim(), email: key),
      password: password,
      // New owners set up two-step later, from Security settings.
      twoStep: false,
    );
  }

  @override
  Future<UserAccount> verifyEmail({
    required String email,
    required String code,
  }) async {
    await _delay();
    final pending = _pendingRegistrations[email.trim().toLowerCase()];
    if (pending == null) {
      throw const ExpiredFailure('Start again from sign-up.');
    }
    if (code != demoEmailCode) {
      throw const ValidationFailure(
        'That code isn’t right. Check the latest email and try again.',
      );
    }
    _pendingRegistrations.remove(pending.user.email);
    _accounts[pending.user.id] = pending;
    _memberships[pending.user.id] = [];
    return pending.user;
  }

  @override
  Future<void> resendVerificationCode(String email) => _delay();

  @override
  Future<void> requestPasswordReset(String identifier) => _delay();

  @override
  Future<ResetLink> openResetLink(String token) async {
    await _delay();
    if (token != demoResetToken || _usedResetTokens.contains(token)) {
      throw const ExpiredFailure(
        'Links work once and expire after 30 minutes. '
        'Your password hasn’t changed.',
      );
    }
    return ResetLink(maskedEmail: maskEmail(_accounts['u-isha']!.user.email));
  }

  @override
  Future<void> resetPassword({
    required String token,
    required String newPassword,
  }) async {
    await openResetLink(token);
    final account = _accounts['u-isha']!;
    if (!isStrongPassword(
      newPassword,
      name: account.user.fullName,
      email: account.user.email,
    )) {
      throw const ValidationFailure('Meet all the password rules.');
    }
    account.password = newPassword;
    _usedResetTokens.add(token);
  }

  @override
  Future<Invitation> openInvitation(String token) async {
    await _delay();
    final invitation = _invitations[token];
    if (invitation == null || _now().isAfter(invitation.expiresAt)) {
      throw const ExpiredFailure(
        'This invitation has expired or was already used. '
        'Ask your HR team to send a new one.',
      );
    }
    return invitation;
  }

  @override
  Future<UserAccount> acceptInvitation({
    required String token,
    required String password,
  }) async {
    final invitation = await openInvitation(token);
    if (!isStrongPassword(
      password,
      name: invitation.fullName,
      email: invitation.email,
    )) {
      throw const ValidationFailure('Meet all the password rules.');
    }
    final id = 'u-${invitation.employeeId.toLowerCase()}';
    final user = UserAccount(
      id: id,
      fullName: invitation.fullName,
      email: invitation.email,
      employeeId: invitation.employeeId,
    );
    _accounts[id] = _DemoAccount(
      user,
      password: password,
      twoStep: invitation.role.requiresTwoStep,
    );
    _memberships[id] = [
      _meridian(invitation.role, invitation.branchName, lastUsed: true),
    ];
    _invitations.remove(token);
    return user;
  }

  @override
  Future<UserAccount?> accountById(String accountId) async {
    await _delay();
    return _accounts[accountId]?.user;
  }

  @override
  Future<List<OrganizationMembership>> membershipsOf(String accountId) async {
    await _delay();
    return List.unmodifiable(_memberships[accountId] ?? const []);
  }

  @override
  Future<void> rememberLastOrganization({
    required String accountId,
    required String organizationId,
  }) async {
    final list = _memberships[accountId];
    if (list == null) return;
    _memberships[accountId] = [
      for (final m in list)
        OrganizationMembership(
          organizationId: m.organizationId,
          organizationName: m.organizationName,
          role: m.role,
          scopeLabel: m.scopeLabel,
          summary: m.summary,
          status: m.status,
          lastUsed: m.organizationId == organizationId,
          branchIds: m.branchIds,
        ),
    ];
  }

  /// Demo only: the owner membership a real backend adds when someone
  /// creates an organization. Becomes the last-used organization.
  void addOwnerMembership(
    String accountId,
    String organizationId,
    String name,
  ) {
    final existing = _memberships[accountId] ?? const [];
    _memberships[accountId] = [
      for (final m in existing)
        OrganizationMembership(
          organizationId: m.organizationId,
          organizationName: m.organizationName,
          role: m.role,
          scopeLabel: m.scopeLabel,
          summary: m.summary,
          status: m.status,
          branchIds: m.branchIds,
        ),
      OrganizationMembership(
        organizationId: organizationId,
        organizationName: name,
        role: SystemRole.owner,
        scopeLabel: 'all branches',
        summary: 'New organization',
        lastUsed: true,
      ),
    ];
  }

  @override
  Future<String> requestAccess({
    required String accountId,
    required String organizationId,
    required String path,
  }) async {
    await _delay();
    return 'Ankit Patel';
  }
}

class _DemoAccount {
  _DemoAccount(this.user, {required this.password, required this.twoStep});

  final UserAccount user;
  String password;
  final bool twoStep;
  final backupCodes = <String>{
    DemoAuthRepository.demoBackupCode.replaceAll('-', ''),
    '4HJT8WQ2',
    'P9DM3ZK7',
    'R2XC6VN4',
    'T8LB5QH1',
    'W3FG7JY6',
    'Z6KP2MS9',
    'B4NQ8RT3',
  };
  int wrongCodes = 0;
  DateTime? lockedUntil;
}
