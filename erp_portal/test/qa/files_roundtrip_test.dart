// D-80: every download produces a file that opens, templates come back in
// through their own import, and saving reports success, cancel and failure.
import 'dart:async';
import 'dart:convert';

import 'package:erp_portal/app/router/app_router.dart';
import 'package:erp_portal/app/router/route_names.dart';
import 'package:erp_portal/core/errors/failure.dart';
import 'package:erp_portal/core/utils/image_picking.dart';
import 'package:erp_portal/features/employees/data/spreadsheet.dart';
import 'package:erp_portal/features/employees/domain/employee_import.dart';
import 'package:erp_portal/features/employees/presentation/providers/employee_providers.dart';
import 'package:erp_portal/features/employees/presentation/providers/import_controller.dart';
import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers/pump_app.dart';

class FakeSheets implements SpreadsheetPicking {
  PickedImage? next;

  @override
  Future<PickedImage?> pickSpreadsheet() async => next;
}

/// Opens the last saved file with the spreadsheet library itself (the
/// import reader caps rows, which an export may exceed).
({List<String> headers, List<List<String>> rows}) lastFile() {
  final (name, bytes) = downloads.saved.last;
  if (name.endsWith('.csv')) {
    final lines = utf8
        .decode(bytes)
        .split(RegExp(r'\r?\n'))
        .where((l) => l.trim().isNotEmpty)
        .toList();
    return (
      headers: lines.first.split(','),
      rows: [for (final l in lines.skip(1)) l.split(',')],
    );
  }
  final book = Excel.decodeBytes(bytes);
  final sheet = book.tables.values.first;
  final all = [
    for (final r in sheet.rows) [for (final c in r) c?.value?.toString() ?? ''],
  ];
  return (headers: all.first, rows: all.skip(1).toList());
}

/// Runs [work] while letting test time pass, so timers inside it fire.
Future<void> pumping(WidgetTester tester, Future<void> work) async {
  var done = false;
  unawaited(work.then((_) => done = true));
  while (!done) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> go(WidgetTester tester, ProviderContainer c, String to) async {
  c.read(appRouterProvider).go(to);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('every download button saves a file that opens', (tester) async {
    final c = await pumpStafflineApp(tester, size: const Size(1440, 2400));
    final cases = <(String, Finder, String)>[
      (AppRoutes.employees, find.text('Export'), 'employees'),
      (AppRoutes.employees, find.text('Template'), 'employee template'),
      (AppRoutes.attendanceRecords, find.text('Export'), 'attendance records'),
      (AppRoutes.monthlySummary, find.text('Export'), 'monthly summary'),
      (AppRoutes.attendanceExports, find.text('Download'), 'attendance export'),
      (AppRoutes.leaveRequests, find.text('Export'), 'leave requests'),
      (AppRoutes.leaveBalances, find.text('Export balances'), 'leave balances'),
      (AppRoutes.holidayList, find.text('Export'), 'holiday list'),
      (
        AppRoutes.holidayImport,
        find.textContaining(RegExp(r'^Download \d+ holiday')),
        'holiday export',
      ),
      (
        AppRoutes.holidayImport,
        find.text('Download blank import template'),
        'holiday template',
      ),
      (AppRoutes.auditLog, find.text('Export'), 'audit log'),
    ];
    for (final (route, button, what) in cases) {
      await go(tester, c, route);
      final before = downloads.saved.length;
      await tester.ensureVisible(button.last);
      await tester.pumpAndSettle();
      await tester.tap(button.last);
      await tester.pumpAndSettle();
      expect(downloads.saved.length, before + 1, reason: '$what saved');
      final table = lastFile();
      expect(table.headers, isNotEmpty, reason: '$what has headers');
      expect(table.rows, isNotEmpty, reason: '$what has rows');
      expect(tester.takeException(), isNull, reason: what);
    }

    // Holidays also export as CSV.
    await go(tester, c, AppRoutes.holidayImport);
    await tapText(tester, 'CSV');
    await tester.tap(
      find.textContaining(RegExp(r'^Download \d+ holiday')).last,
    );
    await tester.pumpAndSettle();
    expect(downloads.saved.last.$1, endsWith('.csv'));
    expect(lastFile().rows, isNotEmpty);
  });

  testWidgets('the employee template imports back without remapping', (
    tester,
  ) async {
    final c = await pumpStafflineApp(tester, size: const Size(1440, 2400));
    await go(tester, c, AppRoutes.employees);
    await tapText(tester, 'Template');
    final table = readSpreadsheet(
      downloads.saved.last.$1,
      downloads.saved.last.$2,
    );
    final fields = c.read(customFieldsProvider).value!;
    final mapping = autoMatchColumns(table.headers, fields);
    final standard =
        table.headers.length - fields.where((f) => !f.archived).length;
    for (var i = 0; i < standard; i++) {
      expect(mapping[i].isIgnored, isFalse, reason: table.headers[i]);
    }
    expect(unmappedRequired(mapping), isEmpty);

    await go(tester, c, AppRoutes.employeeImport);
    final (name, bytes) = downloads.saved.last;
    final ctl = c.read(importControllerProvider.notifier);
    await pumping(tester, ctl.loadFile(name, bytes));
    await pumping(tester, ctl.validate());
    await tester.pumpAndSettle();
    final rows = c.read(importControllerProvider).rows;
    expect(rows, hasLength(1));
    expect(
      rows.single.result,
      isNot(RowResult.invalid),
      reason: rows.single.messages.join('; '),
    );
  });

  testWidgets('the holiday template uploads back into the holiday import', (
    tester,
  ) async {
    final sheets = FakeSheets();
    final c = await pumpStafflineApp(
      tester,
      size: const Size(1440, 2400),
      overrides: [spreadsheetPickingProvider.overrideWithValue(sheets)],
    );
    await go(tester, c, AppRoutes.holidayImport);
    await tapText(tester, 'Download blank import template');
    final (name, bytes) = downloads.saved.last;
    sheets.next = PickedImage(name: name, bytes: bytes);
    await tapText(tester, 'Choose file');
    expect(find.text('Uttarayan'), findsWidgets);
    expect(find.text('Raksha Bandhan'), findsWidgets);
  });

  testWidgets('cancelling the save shows nothing', (tester) async {
    final c = await pumpStafflineApp(tester, size: const Size(1440, 1400));
    await go(tester, c, AppRoutes.employees);
    downloads.cancel = true;
    await tapText(tester, 'Template');
    expect(find.text('Template downloaded'), findsNothing);
    downloads.cancel = false;
    await tapText(tester, 'Template');
    expect(find.text('Template downloaded'), findsOneWidget);
  });

  testWidgets('a save that fails says so', (tester) async {
    final c2 = await pumpStafflineApp(tester, size: const Size(1440, 1400));
    downloads.fail = true;
    await go(tester, c2, AppRoutes.employees);
    await tapText(tester, 'Template');
    expect(
      find.textContaining('Couldn’t save staffline_employee_template.xlsx'),
      findsOneWidget,
    );
  });

  testWidgets('a picker that fails explains itself instead of doing nothing', (
    tester,
  ) async {
    final c = await pumpStafflineApp(
      tester,
      size: const Size(1440, 1400),
      overrides: [
        spreadsheetPickingProvider.overrideWithValue(_FailingSheets()),
      ],
    );
    // The wizard keeps the import alive while it is open.
    final keep = c.listen(importControllerProvider, (_, _) {});
    addTearDown(keep.close);
    await pumping(tester, c.read(importControllerProvider.notifier).pickFile());
    expect(
      c.read(importControllerProvider).problem?.title,
      'The file couldn’t be opened',
    );
  });
}

/// Like the real picker after its guard: a [Failure] with a message.
class _FailingSheets implements SpreadsheetPicking {
  @override
  Future<PickedImage?> pickSpreadsheet() async =>
      throw const UnexpectedFailure('The file couldn’t be opened.');
}
