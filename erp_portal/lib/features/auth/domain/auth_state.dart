import 'package:flutter/foundation.dart';

import '../../../shared/models/app_session.dart';
import 'auth_models.dart';

/// Where the person is in the sign-in journey. The router guard reads this
/// to decide which pages are reachable (docs/navigation_flows.md §1–2).
@immutable
sealed class AuthState {
  const AuthState();
}

/// App start: checking for a saved "keep me signed in" session.
final class RestoringSession extends AuthState {
  const RestoringSession();
}

final class SignedOut extends AuthState {
  const SignedOut();
}

/// Registered, waiting for the 6-digit email code (S05).
final class AwaitingEmailVerification extends AuthState {
  const AwaitingEmailVerification(this.email);

  final String email;
}

/// Password accepted, waiting for the authenticator or backup code (S06).
final class AwaitingTwoStep extends AuthState {
  const AwaitingTwoStep(this.account);

  final UserAccount account;
}

/// Belongs to more than one organization; must pick one (S10).
final class AwaitingOrganizationChoice extends AuthState {
  const AwaitingOrganizationChoice(this.account, this.memberships);

  final UserAccount account;
  final List<OrganizationMembership> memberships;
}

/// Verified but not part of any organization yet: onboarding (S12).
final class NeedsOrganization extends AuthState {
  const NeedsOrganization(this.account);

  final UserAccount account;
}

final class SignedIn extends AuthState {
  const SignedIn(this.account, this.session, this.memberships);

  final UserAccount account;
  final AppSession session;
  final List<OrganizationMembership> memberships;
}

/// The platform super admin is signed in (D-75). There is no organization
/// session, so no organization page or record can be opened.
final class PlatformSignedIn extends AuthState {
  const PlatformSignedIn(this.account);

  final UserAccount account;
}
