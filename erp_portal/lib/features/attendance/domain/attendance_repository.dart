import 'attendance.dart';

/// Punches, corrections and requests. Implementations throw a `Failure`
/// when an operation is refused. A punch is only reported back once it is
/// saved (PRD §7.1: never show a punch the server hasn't confirmed).
abstract interface class AttendanceRepository {
  Future<AttendanceData> load(String organizationId);

  /// [requestId] makes retries safe: the same id returns the same punch.
  Future<Punch> punch(
    String organizationId, {
    required String employeeId,
    required PunchKind kind,
    required PunchSource source,
    required String requestId,
  });

  /// Saves a correction. With [needsSecondApproval] it waits as pending.
  Future<Correction> correct(
    String organizationId,
    Correction correction, {
    required bool needsSecondApproval,
  });

  Future<Correction> decide(
    String organizationId,
    String correctionId, {
    required bool approve,
    required String by,
  });

  Future<CorrectionRequest> request(
    String organizationId,
    CorrectionRequest request,
  );

  Future<CorrectionRequest> rejectRequest(
    String organizationId,
    String requestId, {
    required String reason,
  });

  /// Records reminders; returns how many were sent.
  Future<int> remind(
    String organizationId,
    List<({String employeeId, DateTime workDate})> items,
  );
}
