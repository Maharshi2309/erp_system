import 'dart:convert';
import 'dart:typed_data';

import 'package:erp_portal/app/router/app_router.dart';
import 'package:erp_portal/app/router/route_names.dart';
import 'package:erp_portal/core/utils/image_picking.dart';
import 'package:erp_portal/features/attendance/domain/attendance_book.dart';
import 'package:erp_portal/features/attendance/presentation/attendance_providers.dart';
import 'package:erp_portal/features/employees/presentation/providers/employee_providers.dart';
import 'package:erp_portal/features/holidays/presentation/calendar_providers.dart';
import 'package:erp_portal/features/leave/domain/leave.dart';
import 'package:erp_portal/features/leave/presentation/leave_providers.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_helpers/pump_app.dart';

class FakePicker implements SpreadsheetPicking {
  FakePicker(this.name, this.content);

  final String name;
  final String content;

  @override
  Future<PickedImage?> pickSpreadsheet() async =>
      PickedImage(name: name, bytes: Uint8List.fromList(utf8.encode(content)));
}

void main() {
  group('S62–S64 holiday calendar and form', () {
    testWidgets('the calendar shows organization and branch holidays', (
      tester,
    ) async {
      await pumpStafflineApp(tester, signInAs: hrAdmin, location: '/holidays');
      expect(find.text('Holiday calendar 2026'), findsOneWidget);
      expect(
        find.text(
          '14 holidays · 10 organization-wide · 2 branch-specific · 2 optional',
        ),
        findsOneWidget,
      );
      expect(find.text('Dussehra'), findsWidgets);
      await tester.tap(find.byTooltip('Next month'));
      await tester.pumpAndSettle();
      expect(find.text('Bhai Dooj · Ahmedabad HQ, Vadodara'), findsOneWidget);
      await tapText(tester, 'Year');
      expect(
        find.textContaining('28 Aug Raksha Bandhan (Surat)'),
        findsOneWidget,
      );
      await tapText(tester, 'List');
      expect(find.text('Guru Nanak Jayanti'), findsOneWidget);
    });

    testWidgets('editing an upcoming holiday shows its impact', (tester) async {
      final c = await pumpStafflineApp(
        tester,
        signInAs: hrAdmin,
        location: '/holidays',
      );
      await tapText(tester, 'Edit');
      expect(find.text('Edit holiday'), findsOneWidget);
      expect(find.textContaining('get the day off.'), findsOneWidget);
      expect(find.textContaining('were scheduled to work.'), findsOneWidget);
      await enter(tester, 'Holiday name', 'Vijayadashami');
      await tapText(tester, 'Save holiday');
      expect(find.text('Vijayadashami saved'), findsOneWidget);
      expect(currentPath(c), AppRoutes.holidayList);
      expect(
        c
            .read(companyHolidaysProvider)
            .value!
            .any((h) => h.name == 'Vijayadashami'),
        isTrue,
      );
    });

    testWidgets('past holidays are view-only', (tester) async {
      await pumpStafflineApp(
        tester,
        signInAs: hrAdmin,
        location: AppRoutes.holidayEdit('hol-8'),
      );
      expect(find.text('Gandhi Jayanti'), findsWidgets);
      expect(find.textContaining('This holiday has passed.'), findsOneWidget);
      expect(find.text('Save holiday'), findsNothing);
    });

    testWidgets('a new holiday warns about clashes and frees leave days', (
      tester,
    ) async {
      final c = await pumpStafflineApp(
        tester,
        signInAs: hrAdmin,
        location: AppRoutes.newHoliday,
      );
      await tapText(tester, 'Save holiday');
      expect(find.text('Enter the holiday name.'), findsOneWidget);
      expect(find.text('Choose a date.'), findsOneWidget);
      await enter(tester, 'Holiday name', 'Foundation day');
      await pickDate(tester, 'Date,', '11/10/2026');
      expect(
        find.textContaining('is already “Diwali break” for all branches'),
        findsOneWidget,
      );
      // Aarav's approved leave on 15–16 Oct gets a day back when the 16th
      // becomes a holiday.
      await pickDate(tester, 'Date,', '10/16/2026');
      expect(
        find.textContaining('Leave already approved on this date: '),
        findsOneWidget,
      );
      final aarav = c
          .read(employeesProvider)
          .value!
          .firstWhere((e) => e.code == 'EMP-0201');
      LeaveRequest leave() => c
          .read(leaveDataProvider)
          .value!
          .requests
          .firstWhere(
            (r) =>
                r.employeeId == aarav.id &&
                r.status == LeaveStatus.approved &&
                r.from.day == 15,
          );
      expect(c.read(leaveBookProvider).value!.daysOf(leave()), 2);
      await tapText(tester, 'Save holiday');
      expect(find.text('Foundation day saved'), findsOneWidget);
      expect(c.read(leaveBookProvider).value!.daysOf(leave()), 1);
    });

    testWidgets('branch-specific holidays need a branch', (tester) async {
      await pumpStafflineApp(
        tester,
        signInAs: hrAdmin,
        location: AppRoutes.newHoliday,
      );
      await enter(tester, 'Holiday name', 'Surat fair');
      await pickDate(tester, 'Date,', '11/16/2026');
      await tapText(tester, 'Selected branches');
      await tapText(tester, 'Save holiday');
      expect(find.text('Choose at least one branch.'), findsOneWidget);
      await tapText(tester, 'Surat');
      expect(
        find.textContaining('employees in Surat get the day off.'),
        findsOneWidget,
      );
      await tapText(tester, 'Save holiday');
      expect(find.text('Surat fair saved'), findsOneWidget);
    });
  });

  group('S63, S65, S66 list, import and schedules', () {
    testWidgets('the list filters and exports', (tester) async {
      await pumpStafflineApp(
        tester,
        signInAs: hrAdmin,
        location: AppRoutes.holidayList,
      );
      expect(find.text('Past'), findsWidgets);
      expect(find.text('Upcoming · on a weekly off'), findsOneWidget);
      await tapText(tester, 'Export');
      expect(downloads.saved.single.$1, 'holidays_2026.xlsx');
    });

    testWidgets('an import is checked before anything is saved', (
      tester,
    ) async {
      final c = await pumpStafflineApp(
        tester,
        signInAs: hrAdmin,
        location: AppRoutes.holidayImport,
        overrides: [
          spreadsheetPickingProvider.overrideWithValue(
            FakePicker(
              'holidays_2027.csv',
              'Date,Holiday,Applies to,Category\n'
                  '14/01/2027,Uttarayan,All branches,Festival\n'
                  '26/01/2027,Republic Day,All branches,National\n'
                  '26/01/2027,Republic Day,All branches,National\n'
                  '31/09/2027,Navratri,Surat,\n',
            ),
          ),
        ],
      );
      final before = c.read(companyHolidaysProvider).value!.length;
      await tapText(tester, 'Choose file');
      expect(find.text('✓ 2 ready · 1 duplicate · 1 invalid'), findsOneWidget);
      expect(find.text('September has 30 days'), findsOneWidget);
      expect(c.read(companyHolidaysProvider).value!.length, before);
      await tapText(tester, 'Add 2 holidays');
      expect(find.text('2 holidays added'), findsOneWidget);
      expect(c.read(companyHolidaysProvider).value!.length, before + 2);
      await tapText(tester, 'Download blank import template');
      expect(downloads.saved.last.$1, 'holiday_import_template.xlsx');
    });

    testWidgets('a schedule change is dated and previewed', (tester) async {
      final c = await pumpStafflineApp(
        tester,
        signInAs: hrAdmin,
        location: AppRoutes.schedules,
      );
      expect(find.text('Surat dyeing night crew'), findsWidgets);
      expect(find.textContaining('Nobody’s schedule changes'), findsOneWidget);
      await tapText(tester, 'Branch closed days');
      await tapText(tester, 'Saturday');
      expect(find.textContaining('move to the new schedule'), findsOneWidget);
      await tapText(tester, 'Schedule change');
      expect(find.textContaining('change scheduled for'), findsOneWidget);
      expect(c.read(scheduleAssignmentsProvider).value!.length, 2);
    });

    testWidgets('branch managers see holidays but can’t change them', (
      tester,
    ) async {
      final c = await pumpStafflineApp(
        tester,
        signInAs: branchManager,
        location: '/holidays',
      );
      expect(find.text('Add holiday'), findsNothing);
      expect(find.text('Import / export'), findsNothing);
      c.read(appRouterProvider).go(AppRoutes.newHoliday);
      await tester.pumpAndSettle();
      expect(currentPath(c), AppRoutes.accessDenied);
    });
  });

  group('holidays and leave in attendance', () {
    testWidgets('organization holidays and approved leave show in records', (
      tester,
    ) async {
      final c = await pumpStafflineApp(tester, signInAs: hrAdmin);
      await c.read(attendanceDataProvider.future);
      await tester.pumpAndSettle();
      final book = c.read(attendanceBookProvider).value!;
      final isha = c
          .read(employeesProvider)
          .value!
          .firstWhere((e) => e.code == 'EMP-0229');
      final gandhi = book.day(isha, DateTime(2026, 10, 2));
      expect(gandhi.status, DayStatus.holiday);
      expect(gandhi.holidayName, 'Gandhi Jayanti');

      final leave = c.read(leaveBookProvider).value!;
      final past = leave.data.requests.firstWhere(
        (r) =>
            r.status == LeaveStatus.approved &&
            r.to.isBefore(DateTime(2026, 10, 14)) &&
            leave.daysOf(r) > 0,
      );
      final who = leave.person(past.employeeId)!;
      expect(book.day(who, past.from).status, DayStatus.onLeave);
    });
  });
}
