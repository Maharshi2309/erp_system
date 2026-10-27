import 'dart:typed_data';

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
    Uint8List? selfie,
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

  /// Saves the employee's consent and enrolment selfies; waits for HR.
  /// Replaces an earlier enrolment.
  Future<FaceProfile> enrolFace(
    String organizationId, {
    required String employeeId,
    required List<Uint8List> photos,
  });

  /// HR approves or rejects an enrolment (a rejection needs a reason).
  Future<FaceProfile> decideFace(
    String organizationId,
    String employeeId, {
    required bool approve,
    required String by,
    String reason = '',
  });

  /// The employee withdraws consent: their face data is deleted.
  Future<void> deleteFace(String organizationId, String employeeId);

  /// Lets someone punch without a selfie, or ends that (null reason).
  Future<void> setFaceExemption(
    String organizationId,
    String employeeId, {
    required String? reason,
    required String by,
  });

  /// Accepts or rejects a punch whose face wasn't verified.
  Future<FaceReview> reviewFacePunch(
    String organizationId,
    String punchId, {
    required bool accept,
    required String by,
    String note = '',
  });

  /// Records reminders; returns how many were sent.
  Future<int> remind(
    String organizationId,
    List<({String employeeId, DateTime workDate})> items,
  );
}
