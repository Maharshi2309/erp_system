import 'auth_models.dart';

/// Everything sign-in needs from the server. Implementations throw a
/// `Failure` (core/errors) when an operation is refused.
///
/// The only implementation today is `DemoAuthRepository` (no backend, D-01).
abstract interface class AuthRepository {
  /// Checks the identifier (work email or employee ID) and password.
  /// Wrong details give one generic message that never reveals whether the
  /// account exists.
  Future<SignInResult> signIn({
    required String identifier,
    required String password,
  });

  /// Returns how many backup codes are left when [isBackupCode] is true.
  /// Wrong codes throw `ValidationFailure`; three in a row throw
  /// `LockedFailure` for 15 minutes.
  Future<int?> verifyTwoStep({
    required String accountId,
    required String code,
    required bool isBackupCode,
  });

  /// Creates an owner account and emails a 6-digit code.
  Future<void> register({
    required String fullName,
    required String email,
    required String password,
    String? phone,
  });

  Future<UserAccount> verifyEmail({
    required String email,
    required String code,
  });

  Future<void> resendVerificationCode(String email);

  /// Always completes normally, whether or not the account exists.
  Future<void> requestPasswordReset(String identifier);

  /// Throws `ExpiredFailure` for expired, used or unknown links.
  Future<ResetLink> openResetLink(String token);

  Future<void> resetPassword({
    required String token,
    required String newPassword,
  });

  /// Throws `ExpiredFailure` for expired or unknown invitations.
  Future<Invitation> openInvitation(String token);

  Future<UserAccount> acceptInvitation({
    required String token,
    required String password,
  });

  Future<UserAccount?> accountById(String accountId);

  Future<List<OrganizationMembership>> membershipsOf(String accountId);

  Future<void> rememberLastOrganization({
    required String accountId,
    required String organizationId,
  });

  /// Sends an access request to the organization owner; returns the
  /// owner's name for the confirmation message.
  Future<String> requestAccess({
    required String accountId,
    required String organizationId,
    required String path,
  });
}
