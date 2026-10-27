import 'package:flutter/foundation.dart';

enum PunchKind {
  punchIn('Punch in'),
  punchOut('Punch out'),
  breakStart('Break started'),
  breakEnd('Break ended');

  const PunchKind(this.label);

  final String label;
}

enum PunchSource {
  app('Mobile app'),
  kiosk('Gate kiosk'),
  web('Web'),
  correction('Manual · correction');

  const PunchSource(this.label);

  final String label;
}

/// One recorded event. Never edited or deleted: corrections add events
/// that replace it, so the original stays in the history (PRD §7.4).
@immutable
class Punch {
  const Punch({
    required this.id,
    required this.employeeId,
    required this.at,
    required this.kind,
    required this.source,
    this.correctionId,
    this.replaces,
    this.face,
  });

  final String id;
  final String employeeId;

  /// UTC instant.
  final DateTime at;
  final PunchKind kind;
  final PunchSource source;

  /// Set on events added by a correction.
  final String? correctionId;

  /// The original event this one replaces (a moved time).
  final String? replaces;

  /// The selfie check, when the branch asks for one (D-70).
  final FaceCheck? face;
}

/// What the server concluded from a punch selfie.
enum FaceResult {
  verified('Face verified'),
  notMatched('Face didn’t match'),
  noFace('No face found'),
  notEnrolled('Face not set up');

  const FaceResult(this.label);

  final String label;
}

/// A punch selfie and its result. Anything but [FaceResult.verified] is
/// saved and waits for a reviewer (D-70).
@immutable
class FaceCheck {
  const FaceCheck({required this.result, this.score, this.photo});

  final FaceResult result;

  /// Similarity 0–1 from the matcher, when a face was compared.
  final double? score;

  /// The selfie (JPEG). Shown only to reviewers and the employee.
  final Uint8List? photo;

  bool get needsReview => result != FaceResult.verified;
}

/// A reviewer's decision on a punch whose face wasn't verified. A rejected
/// punch no longer counts; the day then shows its missing punch.
@immutable
class FaceReview {
  const FaceReview({
    required this.punchId,
    required this.accepted,
    required this.by,
    required this.at,
    this.note = '',
  });

  final String punchId;
  final bool accepted;
  final String by;
  final DateTime at;
  final String note;
}

enum FaceEnrolStatus {
  pending('Waiting for HR approval'),
  approved('Set up'),
  rejected('Not approved');

  const FaceEnrolStatus(this.label);

  final String label;
}

/// An employee's reference face for selfie punches. Given with consent and
/// approved by HR; the employee can delete it at any time (D-71).
@immutable
class FaceProfile {
  const FaceProfile({
    required this.employeeId,
    required this.status,
    required this.photos,
    required this.consentAt,
    required this.submittedAt,
    this.decidedBy,
    this.decidedAt,
    this.rejectReason = '',
  });

  final String employeeId;
  final FaceEnrolStatus status;

  /// The enrolment selfies (JPEG): straight, slightly left, slightly right.
  final List<Uint8List> photos;
  final DateTime consentAt;
  final DateTime submittedAt;
  final String? decidedBy;
  final DateTime? decidedAt;
  final String rejectReason;
}

/// Someone in a selfie branch who punches without a selfie (e.g. no phone
/// camera). Set by HR with a reason.
@immutable
class FaceExemption {
  const FaceExemption({
    required this.employeeId,
    required this.reason,
    required this.by,
    required this.at,
  });

  final String employeeId;
  final String reason;
  final String by;
  final DateTime at;
}

enum CorrectionStatus {
  pending('Waiting for approval'),
  approved('Approved'),
  rejected('Rejected');

  const CorrectionStatus(this.label);

  final String label;
}

/// A change to one punch: add a missing one, or move one ([replaces]).
@immutable
class CorrectionChange {
  const CorrectionChange({required this.kind, required this.at, this.replaces});

  final PunchKind kind;

  /// UTC instant.
  final DateTime at;
  final String? replaces;
}

/// An authorised correction (board S55). It counts only once approved; the
/// record keeps its exception until then.
@immutable
class Correction {
  const Correction({
    required this.id,
    required this.employeeId,
    required this.workDate,
    required this.changes,
    required this.reason,
    required this.by,
    required this.createdAt,
    this.byEmployeeId,
    this.status = CorrectionStatus.approved,
    this.approverNote = '',
    this.decidedBy,
    this.decidedAt,
    this.requestId,
  });

  final String id;
  final String employeeId;

  /// Floating date of the work day.
  final DateTime workDate;
  final List<CorrectionChange> changes;
  final String reason;

  /// Name of the person who made the correction.
  final String by;
  final String? byEmployeeId;
  final DateTime createdAt;
  final CorrectionStatus status;

  /// Who must approve, e.g. "Hetal Shah (HR Admin)".
  final String approverNote;
  final String? decidedBy;
  final DateTime? decidedAt;

  /// The employee request this answers, if any.
  final String? requestId;

  Correction decide({
    required bool approve,
    required String by,
    required DateTime at,
  }) => Correction(
    id: id,
    employeeId: employeeId,
    workDate: workDate,
    changes: changes,
    reason: reason,
    by: this.by,
    byEmployeeId: byEmployeeId,
    createdAt: createdAt,
    status: approve ? CorrectionStatus.approved : CorrectionStatus.rejected,
    approverNote: approverNote,
    decidedBy: by,
    decidedAt: at,
    requestId: requestId,
  );
}

enum RequestStatus { open, resolved, rejected }

/// An employee's own correction request (Q-12 option b: proposed time and
/// reason). Answered by a correction or rejected with a reason.
@immutable
class CorrectionRequest {
  const CorrectionRequest({
    required this.id,
    required this.employeeId,
    required this.workDate,
    required this.kind,
    required this.proposedAt,
    required this.message,
    required this.createdAt,
    this.status = RequestStatus.open,
    this.rejectReason = '',
  });

  final String id;
  final String employeeId;
  final DateTime workDate;

  /// The punch the employee says is missing or wrong.
  final PunchKind kind;

  /// UTC instant they propose.
  final DateTime proposedAt;
  final String message;

  /// Floating local time it was sent.
  final DateTime createdAt;
  final RequestStatus status;
  final String rejectReason;

  CorrectionRequest close(RequestStatus status, {String reason = ''}) =>
      CorrectionRequest(
        id: id,
        employeeId: employeeId,
        workDate: workDate,
        kind: kind,
        proposedAt: proposedAt,
        message: message,
        createdAt: createdAt,
        status: status,
        rejectReason: reason,
      );
}

/// A reminder sent to an employee about one open day (board S54).
typedef PunchReminder = ({String employeeId, DateTime workDate, DateTime at});

/// Everything recorded for an organization.
@immutable
class AttendanceData {
  const AttendanceData({
    this.punches = const [],
    this.corrections = const [],
    this.requests = const [],
    this.reminders = const [],
    this.faceProfiles = const [],
    this.faceReviews = const [],
    this.faceExemptions = const [],
  });

  final List<Punch> punches;
  final List<Correction> corrections;
  final List<CorrectionRequest> requests;
  final List<PunchReminder> reminders;
  final List<FaceProfile> faceProfiles;
  final List<FaceReview> faceReviews;
  final List<FaceExemption> faceExemptions;

  FaceProfile? faceProfileOf(String employeeId) =>
      faceProfiles.where((f) => f.employeeId == employeeId).firstOrNull;

  FaceReview? reviewOf(String punchId) =>
      faceReviews.where((r) => r.punchId == punchId).firstOrNull;

  bool isFaceExempt(String employeeId) =>
      faceExemptions.any((x) => x.employeeId == employeeId);

  /// Selfie punches still waiting for a reviewer.
  List<Punch> get punchesToReview => [
    for (final p in punches)
      if (p.face?.needsReview == true && reviewOf(p.id) == null) p,
  ];
}
