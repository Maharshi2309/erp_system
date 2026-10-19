import 'leave.dart';

/// Leave types, policy, requests and adjustments. Implementations throw a
/// `Failure` when an operation is refused. The backend must apply the same
/// routing, validation and self-approval rules as `LeaveBook`.
abstract interface class LeaveRepository {
  Future<LeaveData> load(String organizationId);

  /// Saves a new request with the steps it was routed to.
  Future<LeaveRequest> submit(String organizationId, LeaveRequest draft);

  /// Decides the current step; a rejection needs a [note].
  Future<LeaveRequest> decide(
    String organizationId,
    String id, {
    required bool approve,
    required String by,
    required String byEmployeeId,
    String note = '',
  });

  Future<LeaveRequest> requestChanges(
    String organizationId,
    String id, {
    required String by,
    required String note,
  });

  /// The employee takes back a pending request.
  Future<LeaveRequest> withdraw(
    String organizationId,
    String id, {
    required String by,
  });

  /// The employee cancels approved leave that hasn't started.
  Future<LeaveRequest> cancel(
    String organizationId,
    String id, {
    required String by,
  });

  /// New dates or type; the request goes back for approval.
  Future<LeaveRequest> amend(
    String organizationId,
    LeaveRequest changed, {
    required String by,
  });

  Future<LeaveAdjustment> adjust(
    String organizationId,
    LeaveAdjustment adjustment,
  );

  Future<LeaveType> saveType(String organizationId, LeaveType type);

  Future<LeavePolicy> savePolicy(String organizationId, LeavePolicy policy);
}
