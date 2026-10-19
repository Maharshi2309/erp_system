import 'package:erp_portal/app/router/app_router.dart';
import 'package:erp_portal/app/router/route_names.dart';
import 'package:erp_portal/core/widgets/app_button.dart';
import 'package:erp_portal/core/widgets/app_card.dart';
import 'package:erp_portal/features/employees/presentation/providers/employee_providers.dart';
import 'package:erp_portal/features/leave/domain/leave.dart';
import 'package:erp_portal/features/leave/presentation/leave_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_helpers/pump_app.dart';

/// The request of [employeeId] on [from], if any.
LeaveRequest? requestOf(ProviderContainer c, String code, DateTime from) {
  final e = c.read(employeesProvider).value!.firstWhere((x) => x.code == code);
  return c
      .read(leaveDataProvider)
      .value!
      .requests
      .where((r) => r.employeeId == e.id && r.from == from)
      .firstOrNull;
}

/// The AppButton labelled [label] inside the card that shows [text].
Finder buttonInCard(String text, String label) => find.descendant(
  of: find.ancestor(of: find.text(text), matching: find.byType(AppCard)).first,
  matching: find.widgetWithText(AppButton, label),
);

DateTime oct(int day) => DateTime(2026, 10, day);

void main() {
  group('employee request → approver decision (Phase 6 gate)', () {
    testWidgets('Isha applies, Aarav approves, the balance drops', (
      tester,
    ) async {
      final c = await pumpStafflineApp(
        tester,
        signInAs: employee,
        location:
            '${AppRoutes.applyLeave}?type=casual&from=2026-10-27&to=2026-10-28',
      );
      final before = c
          .read(leaveBookProvider)
          .value!
          .balance(c.read(selfEmployeeProvider)!, 'casual', 2026);
      expect(find.text('You’ll use 2 days'), findsOneWidget);
      expect(
        find.textContaining('Aarav Bhatt', findRichText: true),
        findsWidgets,
      );
      await enter(tester, 'Reason', 'Cousin’s wedding in Rajkot');
      await tapText(tester, 'Submit request');
      expect(find.text('Request sent to Aarav Bhatt'), findsOneWidget);
      expect(currentPath(c), startsWith('/my/leave/L-'));
      expect(find.text('Waiting for Aarav Bhatt'), findsOneWidget);
      final sent = requestOf(c, 'EMP-0229', oct(27))!;
      expect(sent.status, LeaveStatus.pending);
      expect(
        c
            .read(leaveBookProvider)
            .value!
            .balance(c.read(selfEmployeeProvider)!, 'casual', 2026)
            .pending,
        before.pending + 2,
      );

      await switchTo(
        tester,
        c,
        leaveApprover,
        location: AppRoutes.teamApprovals,
      );
      expect(find.text('3 requests need your decision'), findsOneWidget);
      const what = 'Casual leave · 27–28 Oct · 2 days';
      expect(find.text(what), findsOneWidget);
      final approve = buttonInCard(what, 'Approve');
      await tester.ensureVisible(approve);
      await tester.tap(approve);
      await tester.pumpAndSettle();
      expect(
        find.text(
          '✓ Approved — Isha Rathod has been notified. 2 days deducted.',
        ),
        findsOneWidget,
      );
      expect(find.text('2 requests need your decision'), findsOneWidget);
      expect(requestOf(c, 'EMP-0229', oct(27))!.status, LeaveStatus.approved);

      await switchTo(tester, c, employee, location: AppRoutes.myLeave);
      expect(find.text('Next approved leave'), findsOneWidget);
      final after = c
          .read(leaveBookProvider)
          .value!
          .balance(c.read(selfEmployeeProvider)!, 'casual', 2026);
      expect(after.available, before.available - 2);
      expect(after.used, before.used + 2);
    });

    testWidgets('a rejection needs a reason and reaches the employee', (
      tester,
    ) async {
      final c = await pumpStafflineApp(
        tester,
        signInAs: leaveApprover,
        location: AppRoutes.teamApprovals,
      );
      const what = 'Casual leave · Mon 19 Oct · 1 day';
      final reject = buttonInCard(what, 'Reject…');
      await tester.ensureVisible(reject);
      await tester.tap(reject);
      await tester.pumpAndSettle();
      final confirm = find.widgetWithText(AppButton, 'Reject request');
      expect(tester.widget<AppButton>(confirm).onPressed, isNull);
      await enter(tester, 'Reason for rejection', 'Audit week, please move');
      await tester.ensureVisible(confirm);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(
        find.text('Rejected — Isha Rathod has been notified with your reason.'),
        findsOneWidget,
      );
      final r = requestOf(c, 'EMP-0229', oct(19))!;
      expect(r.status, LeaveStatus.rejected);
      expect(r.decisionNote, 'Audit week, please move');

      await switchTo(
        tester,
        c,
        employee,
        location: AppRoutes.myLeaveRequest(r.id),
      );
      expect(find.text('Rejected'), findsWidgets);
      expect(
        find.textContaining('Rejected · “Audit week, please move”'),
        findsOneWidget,
      );
    });

    testWidgets('approvers can’t act on their own leave', (tester) async {
      await pumpStafflineApp(
        tester,
        signInAs: branchManager,
        location: AppRoutes.leave,
      );
      expect(find.textContaining('waiting for you · Surat'), findsOneWidget);
      await tapText(tester, 'Jignesh Parmar');
      expect(find.text('Routed to HR'), findsWidgets);
      expect(find.textContaining('This is your own request.'), findsOneWidget);
      expect(find.widgetWithText(AppButton, 'Approve'), findsNothing);
    });
  });

  group('S89 apply', () {
    testWidgets('an overlap blocks the request and says what to do', (
      tester,
    ) async {
      await pumpStafflineApp(
        tester,
        signInAs: employee,
        location:
            '${AppRoutes.applyLeave}?type=casual&from=2026-10-19&to=2026-10-21',
      );
      expect(find.text('You’ll use 2 days'), findsOneWidget);
      expect(find.text('Dussehra — holiday, not counted'), findsOneWidget);
      expect(
        find.text(
          'This overlaps your pending request for Mon 19 Oct. Withdraw it '
          'first, or change the start date to Wed 21 Oct.',
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<AppButton>(find.widgetWithText(AppButton, 'Submit request'))
            .onPressed,
        isNull,
      );
      expect(find.text('Resolve the overlap to submit.'), findsOneWidget);
    });

    testWidgets('half days are for one date', (tester) async {
      await pumpStafflineApp(
        tester,
        signInAs: employee,
        location:
            '${AppRoutes.applyLeave}?type=casual&from=2026-10-26&to=2026-10-27',
      );
      await tapText(tester, 'First half');
      expect(
        find.text(
          'Half days are for a single day. Choose full days or one date.',
        ),
        findsOneWidget,
      );
      await pickDate(tester, 'To', '10/26/2026');
      expect(find.text('You’ll use 0.5 day'), findsOneWidget);
      expect(find.text('Counted · half day'), findsOneWidget);
    });

    testWidgets('earned leave hides half days and needs notice', (
      tester,
    ) async {
      await pumpStafflineApp(
        tester,
        signInAs: employee,
        location:
            '${AppRoutes.applyLeave}?type=earned&from=2026-10-16&to=2026-10-16',
      );
      expect(find.text('First half'), findsNothing);
      expect(
        find.text(
          'Earned leave needs 7 days’ notice — start on Wed 21 Oct or later.',
        ),
        findsOneWidget,
      );
      await tapText(tester, 'Submit request');
      expect(find.textContaining('/my/leave/L-'), findsNothing);
    });

    testWidgets('submitting without dates shows the date error', (
      tester,
    ) async {
      await pumpStafflineApp(
        tester,
        signInAs: employee,
        location: AppRoutes.applyLeave,
      );
      await tapText(tester, 'Submit request');
      expect(find.text('Choose the start and end dates.'), findsOneWidget);
    });
  });

  group('S90–S92 my leave', () {
    testWidgets('withdraw a pending request from its page', (tester) async {
      final c = await pumpStafflineApp(
        tester,
        signInAs: employee,
        location: AppRoutes.myLeave,
      );
      await tapText(tester, 'Casual · Mon 19 Oct');
      expect(find.text('Waiting for Aarav Bhatt'), findsOneWidget);
      await tapText(tester, 'Withdraw request');
      expect(find.text('Withdraw this request?'), findsOneWidget);
      await tester.tap(find.widgetWithText(AppButton, 'Withdraw request').last);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Request withdrawn. 1 day is back'),
        findsOneWidget,
      );
      expect(requestOf(c, 'EMP-0229', oct(19))!.status, LeaveStatus.withdrawn);
      expect(find.text('Withdrawn by employee'), findsOneWidget);
    });

    testWidgets('change dates sends the request for approval again', (
      tester,
    ) async {
      final c = await pumpStafflineApp(
        tester,
        signInAs: employee,
        location: AppRoutes.myLeave,
      );
      await tapText(tester, 'Casual · Mon 19 Oct');
      await tapText(tester, 'Change dates');
      expect(find.text('Change dates'), findsOneWidget);
      await pickDate(tester, 'To', '10/21/2026');
      expect(find.text('You’ll use 2 days'), findsOneWidget);
      await tapText(tester, 'Send changes');
      expect(find.text('Changes sent for approval'), findsOneWidget);
      final r = requestOf(c, 'EMP-0229', oct(19))!;
      expect(r.to, oct(21));
      expect(r.amendedFrom, (oct(19), oct(19)));
      expect(find.text('Changed from Mon 19 Oct'), findsOneWidget);
    });

    testWidgets('approved leave that hasn’t started can be cancelled', (
      tester,
    ) async {
      final c = await pumpStafflineApp(
        tester,
        signInAs: leaveApprover,
        location: AppRoutes.myLeave,
      );
      await tapText(tester, 'Casual · 15–16 Oct');
      await tapText(tester, 'Cancel leave');
      await tester.tap(find.widgetWithText(AppButton, 'Cancel leave').last);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Leave cancelled. 2 days are back'),
        findsOneWidget,
      );
      expect(requestOf(c, 'EMP-0201', oct(15))!.status, LeaveStatus.cancelled);
    });

    testWidgets('history explains the balance', (tester) async {
      await pumpStafflineApp(
        tester,
        signInAs: employee,
        location: AppRoutes.leaveHistory,
      );
      expect(find.textContaining('how 11 days is worked out'), findsOneWidget);
      expect(find.text('Pending · Mon 19 Oct'), findsOneWidget);
      expect(find.text('Rejected · Thu 24 Sep'), findsOneWidget);
      expect(find.text('Granted · 1 Jan 2026'), findsOneWidget);
    });

    testWidgets('an optional holiday can be requested from the calendar', (
      tester,
    ) async {
      final c = await pumpStafflineApp(
        tester,
        signInAs: employee,
        location: AppRoutes.myHolidays,
      );
      expect(find.text('Dussehra'), findsOneWidget);
      await tester.tap(find.byTooltip('Next month'));
      await tester.pumpAndSettle();
      expect(find.text('Guru Nanak Jayanti'), findsOneWidget);
      await tapText(tester, 'Request');
      expect(currentUri(c).queryParameters['type'], 'optional');
      expect(
        find.text('Guru Nanak Jayanti — optional holiday'),
        findsOneWidget,
      );
      await tapText(tester, 'Submit request');
      expect(find.textContaining('Request sent'), findsOneWidget);
    });
  });

  group('S57–S61 leave management', () {
    testWidgets('HR decides the branch manager’s own request', (tester) async {
      final c = await pumpStafflineApp(tester, signInAs: hrAdmin);
      final jp = c
          .read(leaveDataProvider)
          .value!
          .requests
          .firstWhere(
            (r) => r.typeKey == 'earned' && r.status == LeaveStatus.pending,
          );
      c.read(appRouterProvider).go('${AppRoutes.leave}?request=${jp.id}');
      await tester.pumpAndSettle();
      expect(
        find.text('Routed to HR — approver cannot approve own request'),
        findsNothing,
      );
      await tapText(tester, 'Approve');
      expect(
        find.textContaining('✓ Approved — Jignesh Parmar'),
        findsOneWidget,
      );
    });

    testWidgets('request changes sends it back with a note', (tester) async {
      final c = await pumpStafflineApp(
        tester,
        signInAs: branchManager,
        location: AppRoutes.leave,
      );
      await tapText(tester, 'Chirag Vaghela');
      await tapText(tester, 'Request changes');
      await enter(tester, 'What should change?', 'Take Thursday instead');
      await tapText(tester, 'Send to Chirag');
      expect(
        find.text('Sent back to Chirag Vaghela for changes.'),
        findsOneWidget,
      );
      final r = c
          .read(leaveDataProvider)
          .value!
          .requests
          .firstWhere((r) => r.decisionNote == 'Take Thursday instead');
      expect(r.status, LeaveStatus.changesRequested);
    });

    testWidgets('requests filter by status and export', (tester) async {
      await pumpStafflineApp(
        tester,
        signInAs: hrAdmin,
        location: AppRoutes.leaveRequests,
      );
      await tapText(tester, 'Rejected 1');
      expect(find.text('Isha Rathod'), findsOneWidget);
      expect(find.textContaining('“Audit week, please move”'), findsOneWidget);
      await tapText(tester, 'Export');
      expect(downloads.saved.single.$1, 'leave_requests_2026-10-14.xlsx');
    });

    testWidgets('HR adjusts a balance with a reason', (tester) async {
      final c = await pumpStafflineApp(
        tester,
        signInAs: hrAdmin,
        location: AppRoutes.leaveBalances,
      );
      // The first row (sorted by name).
      await tester.tap(find.text('Adjust').first);
      await tester.pumpAndSettle();
      expect(find.text('Aditi Mehta'), findsWidgets);
      expect(find.text('Add a reason to save'), findsOneWidget);
      await enter(tester, r'Change \(days\)', '2');
      await enter(tester, 'Reason', 'Comp-off for the Sunday audit');
      await tapText(tester, 'Save adjustment');
      expect(find.textContaining('Adjustment saved.'), findsOneWidget);
      expect(find.textContaining('Logged as evt_'), findsOneWidget);
      final adj = c.read(leaveDataProvider).value!.adjustments.last;
      expect((adj.days, adj.reason), (2.0, 'Comp-off for the Sunday audit'));
      await tester.tap(find.byTooltip('Close').last);
      await tester.pumpAndSettle();
      await tapText(tester, 'Export balances');
      expect(downloads.saved.single.$1, 'leave_balances_2026.xlsx');
    });

    testWidgets('leave types are edited with checks', (tester) async {
      final c = await pumpStafflineApp(
        tester,
        signInAs: hrAdmin,
        location: AppRoutes.leaveTypes,
      );
      await enter(tester, r'Per year \(days\)', '0');
      expect(find.text('Unsaved changes'), findsOneWidget);
      await tapText(tester, 'Save');
      expect(find.text('Enter 0.5 to 60 days a year.'), findsOneWidget);
      await enter(tester, r'Per year \(days\)', '10');
      await tapText(tester, 'Save');
      expect(find.text('Casual leave saved'), findsOneWidget);
      expect(c.read(leaveDataProvider).value!.type('casual')!.allowance, 10);
    });

    testWidgets('a new leave type gets a key from its name', (tester) async {
      final c = await pumpStafflineApp(
        tester,
        signInAs: hrAdmin,
        location: AppRoutes.leaveTypes,
      );
      await tapText(tester, 'New type');
      await enter(tester, 'Name', 'Bereavement leave');
      await tapText(tester, 'Save');
      expect(find.text('Bereavement leave saved'), findsOneWidget);
      expect(
        c.read(leaveDataProvider).value!.type('bereavement_leave'),
        isNotNull,
      );
    });

    testWidgets('policy can’t be saved with errors', (tester) async {
      final c = await pumpStafflineApp(
        tester,
        signInAs: hrAdmin,
        location: AppRoutes.leavePolicy,
      );
      await enter(tester, r'Backdated sick leave \(days\)', '45');
      expect(find.text('Fix 1 error to save'), findsOneWidget);
      await enter(tester, r'Backdated sick leave \(days\)', '10');
      await tapText(tester, 'Save policy');
      expect(find.text('Leave policy saved'), findsOneWidget);
      expect(c.read(leaveDataProvider).value!.policy.backdatedSickDays, 10);
    });
  });

  testWidgets('a leave approver only sees their own team’s balances', (
    tester,
  ) async {
    final c = await pumpStafflineApp(
      tester,
      signInAs: leaveApprover,
      location: AppRoutes.leaveBalances,
    );
    final self = c.read(selfEmployeeProvider)!;
    final team =
        c
            .read(employeesProvider)
            .value!
            .where((e) => e.managerId == self.id && e.status.isEmployed)
            .toList()
          ..sort((a, b) => a.fullName.compareTo(b.fullName));
    final outsider = c
        .read(employeesProvider)
        .value!
        .firstWhere((e) => e.code == 'EMP-0105');
    expect(find.text(team.first.code), findsOneWidget);
    expect(find.text(outsider.code), findsNothing);
    expect(find.text('Adjust'), findsNothing);
  });

  testWidgets('policy routes and blackouts are edited in side forms', (
    tester,
  ) async {
    final c = await pumpStafflineApp(
      tester,
      signInAs: hrAdmin,
      location: AppRoutes.leavePolicy,
      size: const Size(1440, 1400),
    );
    // A second route for the same scope is refused.
    await tapText(tester, 'Add route');
    await tapText(tester, 'All branches');
    await tapText(tester, 'Surat');
    await tapText(tester, 'Use route');
    expect(
      find.text('Two routes apply to the same branch and type.'),
      findsOneWidget,
    );
    expect(find.text('Fix 1 error to save'), findsOneWidget);
    await tester.tap(find.text('Remove').at(1));
    await tester.pumpAndSettle();
    expect(find.text('Save policy'), findsOneWidget);

    // A blackout needs a name and dates.
    await tapText(tester, 'Add period');
    await tapText(tester, 'Use period');
    expect(find.text('Name the period.'), findsOneWidget);
    await enter(tester, 'Name', 'Stock count');
    await pickDate(tester, 'From', '12/14/2026');
    await tapText(tester, 'Finance');
    await tapText(tester, 'Use period');
    expect(find.text('Stock count'), findsOneWidget);

    await tapText(tester, 'Allow negative balance');
    expect(find.textContaining('Down to'), findsWidgets);
    await tapText(tester, 'Save policy');
    expect(find.text('Leave policy saved'), findsOneWidget);
    final p = c.read(leaveDataProvider).value!.policy;
    expect(p.allowNegative, isTrue);
    expect(p.blackouts.last.name, 'Stock count');
    expect(p.blackouts.last.departments, ['Finance']);
    expect(p.routes.length, 3);
  });

  testWidgets('switching types with unsaved changes asks first', (
    tester,
  ) async {
    await pumpStafflineApp(
      tester,
      signInAs: hrAdmin,
      location: AppRoutes.leaveTypes,
      size: const Size(1440, 2000),
    );
    await enter(tester, 'Name', 'Casual leave (CL)');
    await tapText(tester, 'Sick leave');
    expect(find.text('Discard changes?'), findsOneWidget);
    await tapText(tester, 'Discard');
    // The editor now shows Sick leave, and Casual kept its name.
    expect(find.textContaining('Offered to'), findsOneWidget);
    expect(find.text('Casual leave'), findsOneWidget);
    expect(find.text('Casual leave (CL)'), findsNothing);
  });
}
