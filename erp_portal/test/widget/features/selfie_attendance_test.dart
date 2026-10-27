// D-70/D-71: self attendance with a selfie matched to an enrolled face.
import 'dart:typed_data';

import 'package:erp_portal/app/router/route_names.dart';
import 'package:erp_portal/features/attendance/domain/attendance.dart';
import 'package:erp_portal/features/attendance/presentation/attendance_providers.dart';
import 'package:erp_portal/features/attendance/presentation/selfie_capture.dart';
import 'package:erp_portal/features/audit/presentation/audit_providers.dart';
import 'package:erp_portal/features/notifications/domain/notifications.dart';
import 'package:erp_portal/features/organization/domain/branch.dart';
import 'package:erp_portal/features/organization/presentation/providers/organization_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_helpers/pump_app.dart';
import 'attendance_screens_test.dart' show byCode, go;

/// A 1×1 PNG, so photos decode in tests.
final _png = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0xF8, 0xCF, 0xC0, 0xF0,
  0x1F, 0x00, 0x05, 0x00, 0x01, 0xFF, 0x89, 0x99, 0x3D, 0x1D, 0x00, 0x00,
  0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

class FakeCamera implements SelfieCapture {
  int taken = 0;
  bool cancel = false;
  final instructions = <String>[];

  @override
  Future<Uint8List?> capture(
    BuildContext context, {
    required String title,
    required String instruction,
  }) async {
    instructions.add(instruction);
    if (cancel) return null;
    taken++;
    return _png;
  }
}

/// Turns selfie punches on for Surat (Isha's and Jignesh's branch).
Future<void> selfieOnInSurat(WidgetTester tester, ProviderContainer c) async {
  final surat = c
      .read(branchesProvider)
      .value!
      .firstWhere((b) => b.id == 'b-sur');
  await c
      .read(branchesProvider.notifier)
      .save(
        surat.copyWith(
          attendance: (surat.attendance ?? const AttendanceRules()).copyWith(
            selfieCheck: true,
          ),
        ),
      );
  await tester.pumpAndSettle();
}

Future<(ProviderContainer, FakeCamera)> start(WidgetTester tester) async {
  final camera = FakeCamera();
  final c = await pumpStafflineApp(
    tester,
    size: const Size(1280, 1600),
    overrides: [selfieCaptureProvider.overrideWithValue(camera)],
  );
  await selfieOnInSurat(tester, c);
  return (c, camera);
}

List<Punch> ishaPunches(ProviderContainer c) => [
  for (final p in c.read(attendanceDataProvider).value!.punches)
    if (p.employeeId == byCode(c, employee).id) p,
];

void main() {
  testWidgets('the owner turns selfie punches on per branch; it is audited', (
    tester,
  ) async {
    final c = await pumpStafflineApp(
      tester,
      size: const Size(1280, 1600),
      location: AppRoutes.settingsAttendance,
    );
    final selfie = find.text('Selfie with each punch');
    await tester.ensureVisible(selfie);
    await tester.tap(selfie);
    await tester.pumpAndSettle();
    expect(find.text('Changed from off'), findsOneWidget);
    await tapText(tester, 'Save changes');
    final ahmedabad = c
        .read(branchesProvider)
        .value!
        .firstWhere((b) => b.id == 'b-ahm');
    expect(ahmedabad.attendance!.selfieCheck, isTrue);
    final event = c.read(auditEventsProvider).value!.first;
    expect(event.changes.single.field, 'Selfie with each punch');
    expect(event.changes.single.after, 'On');
  });

  testWidgets('without a set-up face the punch is saved and flagged; the '
      'branch manager accepts it', (tester) async {
    final (c, camera) = await start(tester);
    await switchTo(tester, c, employee, location: AppRoutes.home);
    expect(find.textContaining('Surat uses selfie punches'), findsOneWidget);

    await tapText(tester, 'Punch out');
    expect(camera.taken, 1);
    expect(find.textContaining('Face not set up.'), findsOneWidget);
    expect(find.text('Punched out'), findsOneWidget);
    final p = ishaPunches(c).last;
    expect(p.face!.result, FaceResult.notEnrolled);

    await switchTo(tester, c, branchManager, location: AppRoutes.faceCheck);
    expect(find.text('Isha Rathod'), findsWidgets);
    expect(find.textContaining('Punch out ·'), findsOneWidget);
    // Branch managers review punches but don't approve set-ups.
    expect(find.text('Set-ups waiting for approval'), findsNothing);
    await tapText(tester, 'Accept');
    expect(find.text('Nothing to review.'), findsOneWidget);
    final review = c.read(attendanceDataProvider).value!.reviewOf(p.id)!;
    expect(review.accepted, isTrue);
    expect(review.by, 'Jignesh Parmar');
  });

  testWidgets('enrol with consent, HR approves, then the punch is verified', (
    tester,
  ) async {
    final (c, camera) = await start(tester);
    await switchTo(tester, c, employee, location: AppRoutes.myProfile);
    expect(find.text('Not set up'), findsOneWidget);
    await tapText(tester, 'Set up');
    expect(currentPath(c), AppRoutes.myFace);

    // Nothing starts before consent.
    await tapText(tester, 'Start');
    expect(camera.taken, 0);
    await tapText(
      tester,
      'I agree to my face being used to check my attendance, as described above.',
    );
    await tapText(tester, 'Start');
    expect(camera.taken, 3);
    expect(camera.instructions, [
      'Look straight at the camera.',
      'Turn your head slightly to the left.',
      'Turn your head slightly to the right.',
    ]);
    await tapText(tester, 'Send for approval');
    expect(find.text('Waiting for HR approval'), findsOneWidget);

    await switchTo(tester, c, hrAdmin, location: AppRoutes.faceCheck);
    expect(find.text('Set-ups waiting for approval'), findsOneWidget);
    await tapText(tester, 'Approve');
    expect(find.text('No set-ups waiting.'), findsOneWidget);

    await switchTo(tester, c, employee, location: AppRoutes.home);
    expect(find.textContaining('uses selfie punches'), findsNothing);
    await tapText(tester, 'Punch out');
    expect(find.text('Face verified.'), findsOneWidget);
    expect(ishaPunches(c).last.face!.result, FaceResult.verified);
    expect(c.read(attendanceDataProvider).value!.punchesToReview, isEmpty);
  });

  testWidgets('a mismatch that the reviewer rejects no longer counts, and '
      'the employee is told why', (tester) async {
    final (c, _) = await start(tester);
    final isha = byCode(c, employee);
    final notifier = c.read(attendanceDataProvider.notifier);
    // Isha is set up and approved.
    await switchTo(tester, c, employee);
    await notifier.enrolFace([_png, _png, _png]);
    await switchTo(tester, c, hrAdmin);
    await notifier.decideFace(isha, approve: true);

    await switchTo(tester, c, employee, location: AppRoutes.home);
    await tapText(tester, 'No match');
    await tapText(tester, 'Punch out');
    expect(find.textContaining('Face didn’t match.'), findsOneWidget);
    expect(find.text('Punched out'), findsOneWidget);

    await switchTo(tester, c, branchManager, location: AppRoutes.faceCheck);
    expect(find.textContaining('41% similar'), findsOneWidget);
    await tapText(tester, 'Don’t accept…');
    await tapText(tester, 'Don’t accept');
    expect(find.text('Enter at least 3 characters.'), findsOneWidget);
    await enter(tester, 'Reason the employee will see', 'Not Isha in photo');
    await tapText(tester, 'Don’t accept');

    await switchTo(tester, c, employee, location: AppRoutes.home);
    // The rejected punch-out doesn't count: still punched in since 09:24.
    expect(find.text('Punched in'), findsOneWidget);
    expect(find.text('since 09:24'), findsOneWidget);
    await go(tester, c, AppRoutes.myNotifications);
    expect(find.text('Punch not accepted'), findsWidgets);
    final audit = await c
        .read(auditRepositoryProvider)
        .events('org_meridian-tex');
    expect(
      audit.map((e) => e.action),
      containsAll(['face.flag', 'face.review.reject']),
    );
    expect(
      audit.firstWhere((e) => e.action == 'face.review.reject').reason,
      'Not Isha in photo',
    );
  });

  testWidgets('HR lets someone punch without a selfie', (tester) async {
    final (c, camera) = await start(tester);
    await switchTo(tester, c, hrAdmin, location: AppRoutes.faceCheck);
    final options = find.byTooltip('Selfie options for Isha Rathod');
    await tester.ensureVisible(options);
    await tester.pumpAndSettle();
    await tester.tap(options);
    await tester.pumpAndSettle();
    await tapText(tester, 'Punch without a selfie…');
    await enter(tester, 'Reason', 'Phone camera broken');
    await tapText(tester, 'Allow');

    await switchTo(tester, c, employee, location: AppRoutes.home);
    await tapText(tester, 'Punch out');
    expect(camera.taken, 0);
    expect(ishaPunches(c).last.face, isNull);
  });

  testWidgets('cancelling the camera records nothing', (tester) async {
    final (c, camera) = await start(tester);
    camera.cancel = true;
    await switchTo(tester, c, employee, location: AppRoutes.home);
    final before = ishaPunches(c).length;
    await tapText(tester, 'Punch out');
    expect(ishaPunches(c).length, before);
    expect(find.text('Punched in'), findsOneWidget);
  });

  testWidgets('the employee deletes their face data', (tester) async {
    final (c, _) = await start(tester);
    await switchTo(tester, c, employee, location: AppRoutes.myFace);
    await c.read(attendanceDataProvider.notifier).enrolFace([_png, _png, _png]);
    await tester.pumpAndSettle();
    await tapText(tester, 'Delete my face data');
    await tapText(tester, 'Delete');
    expect(
      c
          .read(attendanceDataProvider)
          .value!
          .faceProfileOf(byCode(c, employee).id),
      isNull,
    );
    expect(find.text('Before you start'), findsOneWidget);
  });

  testWidgets('without the branch switch, punching needs no selfie', (
    tester,
  ) async {
    final camera = FakeCamera();
    await pumpStafflineApp(
      tester,
      size: const Size(390, 1400),
      signInAs: employee,
      location: AppRoutes.home,
      overrides: [selfieCaptureProvider.overrideWithValue(camera)],
    );
    await tapText(tester, 'Punch out');
    expect(camera.taken, 0);
    expect(find.text('Punched out'), findsOneWidget);
  });

  testWidgets('who reaches Face check', (tester) async {
    final c = await pumpStafflineApp(tester, signInAs: attendanceManager);
    expect(find.text('Face check'), findsWidgets);
    await go(tester, c, AppRoutes.faceCheck);
    expect(find.text('Selfie punches are off'), findsOneWidget);
    await switchTo(tester, c, employee, location: AppRoutes.faceCheck);
    expect(currentPath(c), AppRoutes.accessDenied);
  });

  test('new notification events default to the right people', () {
    expect(
      NotifyEvent.faceFlagged.onByDefault(Recipient.manager, Channel.inApp),
      isTrue,
    );
    expect(
      NotifyEvent.faceEnrolSubmitted.onByDefault(Recipient.hr, Channel.inApp),
      isTrue,
    );
    expect(
      NotifyEvent.faceDecided.onByDefault(Recipient.employee, Channel.inApp),
      isTrue,
    );
  });
}
