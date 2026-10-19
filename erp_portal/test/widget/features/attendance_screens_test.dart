import 'package:erp_portal/app/router/app_router.dart';
import 'package:erp_portal/app/router/route_names.dart';
import 'package:erp_portal/features/attendance/data/demo_attendance_repository.dart';
import 'package:erp_portal/features/attendance/domain/attendance.dart';
import 'package:erp_portal/features/attendance/presentation/attendance_providers.dart';
import 'package:erp_portal/features/employees/domain/employee.dart';
import 'package:erp_portal/features/employees/presentation/providers/employee_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_helpers/pump_app.dart';

Employee byCode(ProviderContainer c, String code) =>
    c.read(employeesProvider).value!.firstWhere((e) => e.code == code);

Future<void> go(WidgetTester tester, ProviderContainer c, String to) async {
  c.read(appRouterProvider).go(to);
  await tester.pumpAndSettle();
}

final yesterday = DateTime(2026, 10, 13);

void main() {
  group('S86–S88 employee self-service', () {
    testWidgets(
      'punch out and back in; state changes only after confirmation',
      (tester) async {
        final c = await pumpStafflineApp(
          tester,
          size: const Size(390, 1400),
          signInAs: employee,
          location: AppRoutes.home,
        );
        expect(find.text('Good afternoon, Isha'), findsOneWidget);
        expect(find.text('Punched in'), findsOneWidget);
        expect(find.text('since 09:24'), findsOneWidget);
        expect(find.text('04:46:00'), findsOneWidget);

        // The server can't be reached: nothing changes.
        (c.read(attendanceRepositoryProvider) as DemoAttendanceRepository)
                .failNextPunch =
            true;
        await tapText(tester, 'Punch out');
        expect(find.textContaining('Punch not recorded'), findsOneWidget);
        expect(find.text('Punched in'), findsOneWidget);

        await tapText(tester, 'Punch out');
        expect(find.text('Punched out'), findsOneWidget);
        expect(find.text('Punch in'), findsOneWidget);
        expect(find.textContaining('Punch not recorded'), findsNothing);
        final punches = c
            .read(attendanceDataProvider)
            .value!
            .punches
            .where((p) => p.employeeId == byCode(c, 'EMP-0229').id);
        expect(punches.last.kind, PunchKind.punchOut);
      },
    );

    testWidgets('the correction notice and recent days link to the day', (
      tester,
    ) async {
      final c = await pumpStafflineApp(
        tester,
        size: const Size(390, 1400),
        signInAs: employee,
        location: AppRoutes.home,
      );
      expect(
        find.text(
          'Your 13 Oct punch-out was corrected to 18:34 by Mitesh Rana.',
        ),
        findsOneWidget,
      );
      await tapText(tester, 'View');
      expect(currentPath(c), AppRoutes.myDay(yesterday));
      expect(find.textContaining('Added by correction'), findsOneWidget);
      expect(find.textContaining('Corrected by Mitesh Rana'), findsOneWidget);
    });

    testWidgets('my month lists days with notes', (tester) async {
      await pumpStafflineApp(
        tester,
        size: const Size(390, 1600),
        signInAs: employee,
        location: AppRoutes.myAttendance,
      );
      expect(find.text('09:24 → now'), findsOneWidget);
      expect(find.text('Session in progress'), findsOneWidget);
      expect(find.text('Corrected by Mitesh Rana'), findsOneWidget);
      expect(find.text('10:12 → 18:34'), findsOneWidget);
    });

    testWidgets('request a correction within three days', (tester) async {
      final c = await pumpStafflineApp(
        tester,
        size: const Size(390, 1400),
        signInAs: employee,
      );
      await go(tester, c, AppRoutes.myDay(DateTime(2026, 10, 12)));
      expect(
        find.text('Available until Thu 15 Oct · goes to Aarav Bhatt'),
        findsOneWidget,
      );
      await tapText(tester, 'Request correction');
      await tapText(tester, 'Send request');
      expect(find.textContaining('at least 5 characters'), findsOneWidget);
      await enter(tester, 'What happened?', 'Kiosk was offline at closing.');
      await tapText(tester, 'Send request');
      expect(find.text('Request sent to Aarav Bhatt'), findsOneWidget);
      expect(find.textContaining('You asked for a correction'), findsOneWidget);
      expect(find.text('Request correction'), findsNothing);
    });

    testWidgets('days older than three days can’t be requested', (
      tester,
    ) async {
      final c = await pumpStafflineApp(
        tester,
        size: const Size(390, 1400),
        signInAs: employee,
      );
      await go(tester, c, AppRoutes.myDay(DateTime(2026, 10, 5)));
      expect(find.text('Request correction'), findsNothing);
    });
  });

  group('S52–S56 attendance administration', () {
    testWidgets('overview switches between daily and weekly', (tester) async {
      await pumpStafflineApp(tester, location: AppRoutes.attendance);
      expect(find.text('Attendance overview'), findsOneWidget);
      expect(find.text('Arrivals today'), findsOneWidget);
      expect(find.text('Missing punches · 7'), findsOneWidget);
      await tapText(tester, 'Weekly');
      expect(find.text('This week by day'), findsOneWidget);
      await tapText(tester, 'Monthly');
      expect(find.text('October by working day'), findsOneWidget);
    });

    testWidgets('records: exceptions, detail panel and correcting as the owner', (
      tester,
    ) async {
      final c = await pumpStafflineApp(
        tester,
        location: '${AppRoutes.attendanceRecords}?date=2026-10-13&branch=b-sur',
      );
      expect(find.text('Tuesday, 13 October 2026 · Surat'), findsOneWidget);
      expect(find.text('Faisal Shaikh'), findsOneWidget);
      expect(
        find.text('Mitesh Rana'),
        findsNothing,
        reason: 'on time, hidden by “Exceptions only”',
      );
      await tapText(tester, 'Faisal Shaikh');
      expect(
        find.text(
          'Session 2 has no punch-out. Worked time excludes it until corrected.',
        ),
        findsOneWidget,
      );
      await tapText(tester, 'Correct attendance…');
      expect(
        currentPath(c),
        AppRoutes.correctAttendance(byCode(c, 'EMP-0240').id, yesterday),
      );
      expect(
        find.text('Save correction'),
        findsOneWidget,
        reason: 'the owner needs no second approval',
      );
      await tapText(tester, 'Save correction');
      expect(
        find.text('Give a reason of at least 5 characters.'),
        findsOneWidget,
      );
      await enter(
        tester,
        'Reason for correction',
        'Verified with the store CCTV.',
      );
      await tapText(tester, 'Save correction');
      expect(find.text('Correction saved'), findsOneWidget);
      final faisal = c
          .read(attendanceBookProvider)
          .value!
          .day(byCode(c, 'EMP-0240'), yesterday);
      expect(faisal.corrected, isTrue);
      expect(faisal.status.name, 'late');
    });

    testWidgets('records: filters, totals views and export', (tester) async {
      await pumpStafflineApp(
        tester,
        location: '${AppRoutes.attendanceRecords}?date=2026-10-13&branch=b-sur',
      );
      await tester.tap(find.widgetWithText(FilterChip, 'Missing punch'));
      await tester.pumpAndSettle();
      expect(find.text('Faisal Shaikh'), findsOneWidget);
      expect(find.text('Isha Rathod'), findsNothing);
      await tapText(tester, 'Show all records');
      expect(find.text('Mitesh Rana'), findsOneWidget);
      await tapText(tester, 'Export');
      expect(downloads.saved.single.$1, 'attendance_2026-10-13.xlsx');
      await tester.tap(find.byTooltip('Previous day'));
      await tester.pumpAndSettle();
      expect(find.text('Monday, 12 October 2026 · Surat'), findsOneWidget);
      await tapText(tester, 'Weekly');
      expect(find.text('VS EXPECTED'), findsOneWidget);
      await tapText(tester, 'Monthly');
      expect(find.text('MISSING'), findsOneWidget);
    });

    testWidgets('a manager’s correction waits for HR approval', (tester) async {
      final c = await pumpStafflineApp(
        tester,
        signInAs: attendanceManager,
        location: AppRoutes.missingPunches,
      );
      expect(
        find.text(
          '7 open sessions · worked time for these days is excluded until corrected',
        ),
        findsNothing,
        reason: 'Mitesh covers Surat and Vadodara only',
      );
      expect(find.textContaining('4 open sessions'), findsOneWidget);
      await tester.ensureVisible(find.text('Review request').first);
      await tester.tap(find.text('Review request').first);
      await tester.pumpAndSettle();
      expect(find.text('Send for approval'), findsOneWidget);
      expect(
        find.textContaining('this goes to Hetal Shah (HR Admin)'),
        findsOneWidget,
      );
      await enter(
        tester,
        'Reason for correction',
        'Supervisor confirmed 18:30.',
      );
      await tapText(tester, 'Send for approval');
      expect(find.text('Sent for approval'), findsOneWidget);
      final faisal = c
          .read(attendanceBookProvider)
          .value!
          .day(byCode(c, 'EMP-0240'), yesterday);
      expect(
        faisal.status.name,
        'missingPunch',
        reason: 'not counted until approved',
      );
      expect(faisal.pendingCorrection, isNotNull);
    });

    testWidgets('HR approves a pending correction', (tester) async {
      final c = await pumpStafflineApp(tester, signInAs: hrAdmin);
      final faisal = byCode(c, 'EMP-0240');
      await c
          .read(attendanceDataProvider.notifier)
          .correct(
            Correction(
              id: '',
              employeeId: faisal.id,
              workDate: yesterday,
              changes: [
                CorrectionChange(
                  kind: PunchKind.punchOut,
                  at: DateTime.utc(2026, 10, 13, 13, 0),
                ),
              ],
              reason: 'Supervisor confirmed 18:30.',
              by: 'Mitesh Rana',
              createdAt: yesterday,
              approverNote: 'Hetal Shah (HR Admin)',
            ),
            needsSecondApproval: true,
          );
      await go(tester, c, AppRoutes.corrections);
      expect(find.textContaining('1 waiting for approval'), findsOneWidget);
      await tapText(tester, 'Approve');
      expect(find.text('Correction approved'), findsOneWidget);
      expect(
        c.read(attendanceBookProvider).value!.day(faisal, yesterday).corrected,
        isTrue,
      );
    });

    testWidgets('remind and reject from the queue', (tester) async {
      await pumpStafflineApp(tester, location: AppRoutes.missingPunches);
      await tester.ensureVisible(find.text('Remind').first);
      await tester.tap(find.text('Remind').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('Reminder sent to'), findsOneWidget);
      await dismissToasts(tester);
      await tester.ensureVisible(find.text('Reject request').first);
      await tester.tap(find.text('Reject request').first);
      await tester.pumpAndSettle();
      await enter(tester, 'Reason', 'Please ask your supervisor to confirm.');
      await tester.tap(find.text('Reject request').last);
      await tester.pumpAndSettle();
      expect(find.text('Request rejected'), findsOneWidget);
    });

    testWidgets('monthly grid opens a person’s day list and exports', (
      tester,
    ) async {
      await pumpStafflineApp(tester, location: AppRoutes.monthlySummary);
      expect(find.text('October 2026'), findsWidgets);
      await tapText(tester, 'Export');
      expect(downloads.saved.single.$1, 'attendance_2026_10.xlsx');
      await tester.tap(
        find.bySemanticsLabel(RegExp('^Day list for Aarav Bhatt')),
      );
      await tester.pumpAndSettle();
      // 2 Oct (Gandhi Jayanti) is a holiday on the organization calendar.
      // Approved leave on 15–16 Oct counts as leave, not absence.
      expect(
        find.text('Present 11 · Late 1 · Absent 0 · Leave 2'),
        findsOneWidget,
      );
    });

    testWidgets('exports a date range', (tester) async {
      await pumpStafflineApp(tester, location: AppRoutes.attendanceExports);
      expect(find.textContaining('13 days'), findsOneWidget);
      await tapText(tester, 'Download');
      expect(downloads.saved.single.$1, 'attendance_20261001_20261013.xlsx');
    });
  });

  group('dashboards use real attendance', () {
    testWidgets('owner dashboard', (tester) async {
      await pumpStafflineApp(tester, location: AppRoutes.overview);
      expect(find.text('7 open sessions'), findsOneWidget);
      expect(find.text('Attendance trend'), findsOneWidget);
      expect(find.textContaining('% present'), findsOneWidget);
      expect(find.textContaining('excludes'), findsOneWidget);
    });

    testWidgets('branch manager dashboard', (tester) async {
      await pumpStafflineApp(
        tester,
        signInAs: branchManager,
        location: AppRoutes.branchDashboard,
      );
      expect(find.text('All exceptions'), findsOneWidget);
      expect(find.text('Faisal Shaikh · no punch-out'), findsOneWidget);
    });

    testWidgets('profile shows the month at a glance', (tester) async {
      final c = await pumpStafflineApp(tester);
      await go(tester, c, AppRoutes.employee(byCode(c, 'EMP-0229').id));
      expect(find.text('Present days'), findsOneWidget);
      await tapText(tester, 'Attendance');
      expect(
        find.bySemanticsLabel(RegExp('^13 October: Late')),
        findsOneWidget,
      );
    });
  });
}
