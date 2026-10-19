import 'dart:convert';
import 'dart:typed_data';

import 'package:erp_portal/app/router/app_router.dart';
import 'package:erp_portal/app/router/route_names.dart';
import 'package:erp_portal/core/utils/image_picking.dart';
import 'package:erp_portal/features/employees/presentation/providers/employee_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_helpers/pump_app.dart';
import '../../unit/features/employee_import_test.dart' show sampleCsv;

class FakeSpreadsheetPicking implements SpreadsheetPicking {
  FakeSpreadsheetPicking(this.name, this.content);

  String name;
  String content;

  @override
  Future<PickedImage?> pickSpreadsheet() async =>
      PickedImage(name: name, bytes: Uint8List.fromList(utf8.encode(content)));
}

Future<ProviderContainer> openImport(
  WidgetTester tester,
  FakeSpreadsheetPicking picker,
) => pumpStafflineApp(
  tester,
  location: AppRoutes.employeeImport,
  overrides: [spreadsheetPickingProvider.overrideWithValue(picker)],
);

void main() {
  group('S46–S51 import', () {
    testWidgets('the whole wizard, with an update to an existing employee', (
      tester,
    ) async {
      final c = await openImport(
        tester,
        FakeSpreadsheetPicking('surat_staff_oct.csv', sampleCsv),
      );
      expect(find.text('Upload a spreadsheet'), findsOneWidget);
      expect(
        find.text('vadodara_staff.xlsx'),
        findsOneWidget,
        reason: 'recent imports',
      );
      await tapText(tester, 'Choose file');
      expect(find.text('10 rows · 14 columns · 2 KB'), findsOneWidget);

      await tapText(tester, 'Continue to mapping');
      expect(
        find.textContaining('We matched 12 of 14 columns by name'),
        findsOneWidget,
      );
      final validate = find.widgetWithText(InkWell, 'Validate 10 rows');
      expect(find.text('Choose the date format.'), findsOneWidget);
      await tapText(tester, 'DD/MM/YYYY');
      await tester.tap(validate.first);
      await tester.pumpAndSettle();

      expect(find.text('Review rows before importing'), findsOneWidget);
      expect(find.text('Rows with problems · 9'), findsOneWidget);
      await tapText(tester, 'Download error report');
      expect(downloads.saved.single.$1, 'import_errors_surat_staff_oct.xlsx');
      await dismissToasts(tester);

      await tapText(tester, 'Resolve 3 duplicates');
      expect(find.text('3 rows match existing employees'), findsOneWidget);
      await tapText(tester, 'Update existing employees');
      expect(find.text('Tick the confirmation to continue'), findsOneWidget);
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      await tapText(tester, 'Continue to summary');

      expect(find.text('Ready to import'), findsOneWidget);
      await tapText(tester, 'Import 5 employees');
      expect(find.text('4 employees added to Surat'), findsOneWidget);
      expect(
        find.text(
          '5 were skipped and 1 updated. 4 invitations are being sent.',
        ),
        findsOneWidget,
      );
      final codes = c.read(employeesProvider).value!.map((e) => e.code);
      expect(
        codes,
        containsAll(['EMP-0902', 'EMP-0904', 'EMP-0905', 'EMP-0906']),
      );
      expect(codes, isNot(contains('EMP-0901')));

      await tapText(tester, 'View new employees');
      expect(currentPath(c), AppRoutes.employees);
      expect(find.text('252 people across 3 branches'), findsOneWidget);
    });

    testWidgets('a wrong file type is explained', (tester) async {
      await openImport(
        tester,
        FakeSpreadsheetPicking('staff list.pdf', '%PDF-1.4'),
      );
      await tapText(tester, 'Choose file');
      expect(find.text('We can’t read “staff list.pdf”'), findsOneWidget);
      expect(
        find.textContaining('Only .xlsx and .csv files work'),
        findsOneWidget,
      );
      expect(find.text('Choose a different file'), findsOneWidget);
    });

    testWidgets('missing required columns block validation', (tester) async {
      await openImport(
        tester,
        FakeSpreadsheetPicking('min.csv', 'First Name,Email\nA,a@x.in\n'),
      );
      await tapText(tester, 'Choose file');
      await tapText(tester, 'Continue to mapping');
      expect(find.text('Employee ID isn’t mapped.'), findsOneWidget);
    });

    testWidgets('leaving mid-way asks first', (tester) async {
      final c = await openImport(
        tester,
        FakeSpreadsheetPicking('surat.csv', sampleCsv),
      );
      await tapText(tester, 'Choose file');
      await tester.tap(find.byTooltip('Close import'));
      await tester.pumpAndSettle();
      expect(find.text('Leave the import?'), findsOneWidget);
      await tester.tap(find.text('Leave').last);
      await tester.pumpAndSettle();
      expect(currentPath(c), AppRoutes.employees);
    });

    testWidgets('past results open from recent imports', (tester) async {
      final c = await openImport(tester, FakeSpreadsheetPicking('x.csv', ''));
      await tester.tap(find.text('View').first);
      await tester.pumpAndSettle();
      expect(currentPath(c), AppRoutes.importResult('imp-3'));
      expect(find.text('38 employees added to Vadodara'), findsOneWidget);
      expect(find.text('Not imported · 4 rows'), findsOneWidget);
      await tapText(tester, 'Download error report (.xlsx)');
      expect(downloads.saved.single.$1, 'import_report_vadodara_staff.xlsx');
    });
  });

  group('S30–S33 dashboards', () {
    testWidgets('owner KPIs come from records and filter by branch', (
      tester,
    ) async {
      await pumpStafflineApp(tester, location: AppRoutes.overview);
      expect(find.text('Good afternoon, Ankit'), findsOneWidget);
      expect(
        find.text(
          'Wednesday, 14 October 2026 · All branches · 3 branches, 248 employees',
        ),
        findsOneWidget,
      );
      expect(find.text('+6 in the last 14 days'), findsOneWidget);
      expect(find.text('241'), findsOneWidget);
      expect(find.text('7 inactive or invited'), findsOneWidget);
      expect(find.text('Next: Dussehra, 20 Oct'), findsOneWidget);
      expect(find.text('Employee import failed for 4 rows'), findsOneWidget);
      await tapText(tester, 'All branches');
      await tester.tap(find.text('Vadodara').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('Vadodara · 44 employees'), findsOneWidget);
    });

    testWidgets('attention items link to their records', (tester) async {
      final c = await pumpStafflineApp(tester, location: AppRoutes.overview);
      await tapText(tester, 'Employee import failed for 4 rows');
      expect(currentPath(c), AppRoutes.importResult('imp-3'));
    });

    testWidgets('KPI cards open the filtered directory', (tester) async {
      final c = await pumpStafflineApp(tester, location: AppRoutes.overview);
      await tester.tap(find.bySemanticsLabel(RegExp('^Total employees')));
      await tester.pumpAndSettle();
      expect(currentPath(c), AppRoutes.employees);
    });

    testWidgets('branch manager sees their branch only', (tester) async {
      final c = await pumpStafflineApp(tester, signInAs: branchManager);
      c.read(appRouterProvider).go(AppRoutes.branchDashboard);
      await tester.pumpAndSettle();
      expect(find.text('Good afternoon, Jignesh'), findsOneWidget);
      expect(find.text('Branch: Surat'), findsOneWidget);
      expect(find.textContaining('Surat · 78 employees'), findsOneWidget);
      expect(find.text('Production'), findsOneWidget);
      expect(find.textContaining('You see Surat only.'), findsOneWidget);
      expect(
        find.text('Dussehra · Tue 20 Oct (branch closed)'),
        findsNothing,
        reason: 'Surat has no holiday calendar yet',
      );
    });
  });
}
