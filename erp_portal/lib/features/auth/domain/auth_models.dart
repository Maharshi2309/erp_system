import 'package:flutter/foundation.dart';

import '../../../core/permissions/system_roles.dart';

@immutable
class UserAccount {
  const UserAccount({
    required this.id,
    required this.fullName,
    required this.email,
    this.employeeId,
    this.isPlatformAdmin = false,
  });

  final String id;
  final String fullName;
  final String email;
  final String? employeeId;

  /// Staffline's own super admin: sees platform statistics only, never an
  /// organization's records (D-75). Has no memberships.
  final bool isPlatformAdmin;
}

enum MembershipStatus { active, deactivated }

/// The account's place in one organization (board S10 rows).
@immutable
class OrganizationMembership {
  const OrganizationMembership({
    required this.organizationId,
    required this.organizationName,
    required this.role,
    required this.scopeLabel,
    required this.summary,
    this.status = MembershipStatus.active,
    this.lastUsed = false,
    this.branchIds = const [],
  });

  final String organizationId;
  final String organizationName;
  final SystemRole role;

  /// Branches a branch-scoped role covers; empty means every branch.
  final List<String> branchIds;

  /// e.g. "all branches", "Surat".
  final String scopeLabel;

  /// e.g. "3 branches · 248 employees".
  final String summary;
  final MembershipStatus status;
  final bool lastUsed;

  bool get isActive => status == MembershipStatus.active;
}

@immutable
class SignInResult {
  const SignInResult({required this.account, required this.requiresTwoStep});

  final UserAccount account;
  final bool requiresTwoStep;
}

/// Invitation details shown on board S09. Filled in by HR beforehand.
@immutable
class Invitation {
  const Invitation({
    required this.token,
    required this.inviterName,
    required this.organizationName,
    required this.role,
    required this.branchName,
    required this.fullName,
    required this.employeeId,
    required this.email,
    required this.startDate,
    required this.expiresAt,
  });

  final String token;
  final String inviterName;
  final String organizationName;
  final SystemRole role;
  final String branchName;
  final String fullName;
  final String employeeId;
  final String email;
  final DateTime startDate;
  final DateTime expiresAt;
}

/// A password-reset link opened from email (board S08).
@immutable
class ResetLink {
  const ResetLink({required this.maskedEmail});

  final String maskedEmail;
}
