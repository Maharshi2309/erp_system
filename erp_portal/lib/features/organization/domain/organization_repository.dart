import 'dart:typed_data';

import 'branch.dart';
import 'organization.dart';

/// Organization, owner profile and branch data. Implementations throw a
/// `Failure` when an operation is refused.
abstract interface class OrganizationRepository {
  /// Creates the organization and makes [ownerAccountId] its owner.
  Future<Organization> createOrganization({
    required String ownerAccountId,
    required String ownerName,
    required String ownerEmail,
    required String name,
    required String employeeRange,
    Uint8List? logo,
  });

  Future<Organization> organization(String organizationId);

  Future<Organization> updateOrganization(
    Organization organization, {
    required String updatedBy,
  });

  /// Null until the owner saves it (board S15 → S16).
  Future<OwnerProfile?> ownerProfile(String organizationId);

  Future<void> saveOwnerProfile(String organizationId, OwnerProfile profile);

  Future<List<Branch>> branches(String organizationId);

  Future<Branch> createBranch(String organizationId, Branch branch);

  /// Saves any change to an existing branch, including one setup step.
  Future<Branch> updateBranch(String organizationId, Branch branch);

  /// Refused while employees are still assigned (board S37).
  Future<Branch> setBranchStatus(
    String organizationId,
    String branchId,
    BranchStatus status,
  );

  Future<SetupBookmark?> setupBookmark(String organizationId);

  Future<void> saveSetupBookmark(String organizationId, SetupBookmark bookmark);
}
