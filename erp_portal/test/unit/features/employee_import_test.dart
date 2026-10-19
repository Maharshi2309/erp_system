import 'dart:convert';
import 'dart:typed_data';

import 'package:erp_portal/core/errors/failure.dart';
import 'package:erp_portal/features/dashboard/domain/dashboard_metrics.dart';
import 'package:erp_portal/features/employees/data/demo_employee_repository.dart';
import 'package:erp_portal/features/employees/data/employee_files.dart';
import 'package:erp_portal/features/employees/data/spreadsheet.dart';
import 'package:erp_portal/features/employees/domain/custom_field.dart';
import 'package:erp_portal/features/employees/domain/employee.dart';
import 'package:erp_portal/features/employees/domain/employee_import.dart';
import 'package:erp_portal/features/organization/data/demo_organization_repository.dart';
import 'package:erp_portal/features/organization/domain/branch.dart';
import 'package:flutter_test/flutter_test.dart';

const org = 'org_meridian-tex';

/// Modelled on the design's surat_staff_oct.xlsx (boards S47–S49).
const sampleCsv =
    'Emp_Code,First Name,Last Name,Email,Mobile,Designation,Dept,Location,Reports_To,Joining_Dt,Emp_Type,Uniform,Shoe size,Remarks\r\n'
    'EMP-0901,Mahesh,Gohil,,98250 61233,Machine Operator,Production,Surat,J Parmar,04/11/2026,Permanent,M,8,\r\n'
    'EMP-0198,Deepa,Nair,deepa.n@meridiantex.in,,HR Executive,People Ops,Surat,Jignesh Parmar,12/01/2021,Permanent,,,\r\n'
    'EMP-0902,Pooja,Chauhan,pooja.c@meridiantex.in,,Quality Inspector,Quality,Surat,Bhavna Solanki,03/10/2026,Permanent,M,,\r\n'
    'EMP-0903,Ravi,Prajapati,ravi.p@meridiantex,,Packer,Dispatch,Surat,Jignesh Parmar,15/10/2026,Permanent,,,\r\n'
    'EMP-0217,Bhavna,Solanki,bhavna.s@meridiantex.in,,QA Analyst,Quality,Surat,,18/08/2022,Permanent,S,,\r\n'
    'EMP-0904,Sunil,Barot,sunil.b@meridiantex.in,,Packer,Dispatch,Surat Unit 2,Jignesh Parmar,16/10/2026,Permanent,,,\r\n'
    'EMP-0905,Tanvi,Mistry,tanvi.m@meridiantex.in,,Packer,Dispatch,Surat,Mitesh R,19/10/2026,Permanent,,,\r\n'
    'EMP-0233,Chirag,Vaghela,chirag.v@meridiantex.in,,Senior Operator,Production,Surat,Aarav Bhatt,01/10/2026,Probation,L,,\r\n'
    'EMP-0906,Yash,Kotadia,yash.k@meridiantex.in,,Loader,Logistics,Surat,Mitesh Rana,13/10/2026,Permanent,L,9,\r\n'
    '"EMP-0906","Yash, again",Kotadia,yash2@meridiantex.in,,Loader,Logistics,Surat,Mitesh Rana,13/10/2026,Permanent,L,,\r\n';

Uint8List bytes(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  late DemoEmployeeRepository repo;
  late List<Employee> people;
  late List<Branch> branches;
  late List<CustomField> fields;

  setUp(() async {
    repo = DemoEmployeeRepository(
      latency: Duration.zero,
      clock: () => DateTime(2026, 10, 14, 14, 10),
    );
    people = await repo.employees(org);
    branches = await DemoOrganizationRepository(
      latency: Duration.zero,
    ).branches(org);
    fields = await repo.customFields(org);
  });

  ImportContext ctx({
    DateOrder? order = DateOrder.dayFirst,
    bool invite = true,
  }) => ImportContext(
    organizationId: org,
    existing: people,
    branches: branches,
    fields: fields,
    dateOrder: order,
    sendInvites: invite,
  );

  group('reading files', () {
    test('CSV with quotes, commas and CRLF', () {
      expect(parseCsv('a,"b, c","d ""q"""\r\n1,2,3\n'), [
        ['a', 'b, c', 'd "q"'],
        ['1', '2', '3'],
      ]);
    });

    test('the sample reads as 10 rows × 14 columns', () {
      final t = readSpreadsheet('surat_staff_oct.csv', bytes(sampleCsv));
      expect(t.headers.length, 14);
      expect(t.rows.length, 10);
      expect(t.rows.last[1], 'Yash, again');
      expect(t.samples(6), 'Production, People Ops, Quality');
    });

    test('rejects other file types with the design message', () {
      expect(
        () => readSpreadsheet('staff list.pdf', bytes('%PDF')),
        throwsA(
          isA<ImportFileProblem>().having(
            (p) => p.title,
            'title',
            'We can’t read “staff list.pdf”',
          ),
        ),
      );
    });

    test('rejects files over 5 MB, over 2,000 rows, or without headers', () {
      expect(
        () => readSpreadsheet('big.csv', Uint8List(maxImportBytes + 1)),
        throwsA(
          isA<ImportFileProblem>().having(
            (p) => p.title,
            'title',
            contains('5 MB'),
          ),
        ),
      );
      final many = StringBuffer('Employee ID\n');
      for (var i = 0; i < 2001; i++) {
        many.writeln('E$i');
      }
      expect(
        () => readSpreadsheet('many.csv', bytes(many.toString())),
        throwsA(
          isA<ImportFileProblem>().having(
            (p) => p.title,
            'title',
            'The file has 2001 rows',
          ),
        ),
      );
      expect(
        () => readSpreadsheet('h.csv', bytes('Name,,Email\nA,B,C\n')),
        throwsA(
          isA<ImportFileProblem>().having(
            (p) => p.title,
            'title',
            'The first row must be headers',
          ),
        ),
      );
      expect(
        () => readSpreadsheet('d.csv', bytes('Email,email\nA,B\n')),
        throwsA(
          isA<ImportFileProblem>().having(
            (p) => p.title,
            'title',
            contains('same header'),
          ),
        ),
      );
      expect(
        () => readSpreadsheet('e.csv', bytes('Email\n')),
        throwsA(isA<ImportFileProblem>()),
      );
    });

    test('an .xlsx we write reads back the same', () {
      final rows = templateRows(fields);
      final t = readSpreadsheet('template.xlsx', buildXlsx('Employees', rows));
      expect(t.headers, rows.first);
      expect(t.rows.single.first, 'EMP-0001');
      expect(t.headers, containsAll(['Uniform size', 'Locker number']));
      expect(
        t.headers,
        isNot(contains('Previous employer')),
        reason: 'archived fields are left out',
      );
    });

    test('a damaged .xlsx gets a readable message', () {
      expect(
        () => readSpreadsheet('broken.xlsx', bytes('not a zip')),
        throwsA(
          isA<ImportFileProblem>().having(
            (p) => p.detail,
            'detail',
            contains('damaged'),
          ),
        ),
      );
    });
  });

  group('mapping', () {
    test('matches 12 of the 14 design columns by name', () {
      final t = readSpreadsheet('s.csv', bytes(sampleCsv));
      final mapping = autoMatchColumns(t.headers, fields);
      expect(mapping.where((m) => !m.isIgnored).length, 12);
      expect(mapping[7], const ImportTarget.field(ImportField.branch));
      expect(mapping[11], const ImportTarget.custom('uniform_size'));
      expect(mapping[12].isIgnored, isTrue);
      expect(unmappedRequired(mapping), isEmpty);
    });

    test('ambiguous dates must be resolved, not guessed', () {
      expect(isAmbiguousDate('03/10/2026'), isTrue);
      expect(isAmbiguousDate('13/10/2026'), isFalse);
      expect(isAmbiguousDate('10/10/2026'), isFalse);
      expect(
        parseImportDate('03/10/2026', DateOrder.dayFirst),
        DateTime(2026, 10, 3),
      );
      expect(
        parseImportDate('03/10/2026', DateOrder.monthFirst),
        DateTime(2026, 3, 10),
      );
      expect(parseImportDate('13/10/2026', null), DateTime(2026, 10, 13));
      expect(parseImportDate('2026-10-03', null), DateTime(2026, 10, 3));
      expect(parseImportDate('31/02/2026', DateOrder.dayFirst), isNull);
      final t = readSpreadsheet('s.csv', bytes(sampleCsv));
      expect(needsDateOrder(t, autoMatchColumns(t.headers, fields)), isTrue);
    });

    test('missing required columns are reported', () {
      final mapping = autoMatchColumns(['First Name', 'Email'], fields);
      expect(
        unmappedRequired(mapping),
        containsAll([
          ImportField.code,
          ImportField.lastName,
          ImportField.branch,
          ImportField.joiningDate,
        ]),
      );
    });
  });

  group('validation', () {
    late List<ImportRow> rows;
    late ImportTable table;
    late List<ImportTarget> mapping;

    setUp(() {
      table = readSpreadsheet('s.csv', bytes(sampleCsv));
      mapping = autoMatchColumns(table.headers, fields);
      rows = classifyRows(table, mapping, ctx());
    });

    ImportRow row(int n) => rows.firstWhere((r) => r.rowNumber == n);

    test('every row lands in exactly one bucket', () {
      int count(RowResult r) => rows.where((x) => x.result == r).length;
      expect(rows.length, 10);
      expect(count(RowResult.ready), 1);
      expect(count(RowResult.warning), 3);
      expect(count(RowResult.duplicate), 3);
      expect(count(RowResult.invalid), 3);
    });

    test('invalid rows say what to fix', () {
      expect(row(2).issue, contains('Email is required for invited accounts'));
      expect(
        row(5).issue,
        contains('“ravi.p@meridiantex” is not a valid email address.'),
      );
      expect(
        row(11).issue,
        contains('EMP-0906 is also used on row 10 of this file.'),
      );
    });

    test('warnings explain the assumption made', () {
      expect(
        row(4).issue,
        contains('Ambiguous date read as 3 Oct 2026 (DD/MM/YYYY)'),
      );
      expect(
        row(7).issue,
        contains('Branch “Surat Unit 2” not found. Will be assigned to Surat.'),
      );
      expect(row(8).issue, contains('matched to Mitesh Rana. Confirm.'));
      expect(row(10).result, RowResult.ready);
    });

    test('duplicates show what differs', () {
      expect(row(3).changes, isEmpty);
      expect(row(6).issue, contains('Same values'));
      expect(row(9).changes.single, (
        field: 'Designation',
        now: 'Machine Operator',
        incoming: 'Senior Operator',
      ));
    });

    test('turning invitations off makes a missing email acceptable', () {
      final noInvite = classifyRows(table, mapping, ctx(invite: false));
      final mahesh = noInvite.firstWhere((r) => r.rowNumber == 2);
      expect(mahesh.issue, isNot(contains('Email is required')));
    });

    test('the duplicate policy decides each duplicate', () {
      expect(
        duplicateOutcome(row(9), DuplicatePolicy.reject),
        DuplicateOutcome.skipped,
      );
      expect(
        duplicateOutcome(row(9), DuplicatePolicy.update),
        DuplicateOutcome.willUpdate,
      );
      expect(
        duplicateOutcome(row(3), DuplicatePolicy.update),
        DuplicateOutcome.noChange,
      );
      expect(
        duplicateOutcome(row(3), DuplicatePolicy.skipSame),
        DuplicateOutcome.noChange,
      );
      expect(
        duplicateOutcome(row(9), DuplicatePolicy.skipSame),
        DuplicateOutcome.skipped,
      );
    });

    test('the plan adds up to the file', () {
      final plan = ImportPlan.from(rows, DuplicatePolicy.update);
      expect(
        plan.ready + plan.warnings + plan.invalid + plan.duplicates,
        plan.total,
      );
      expect(plan.toCreate.length, 4);
      expect(plan.toUpdate.single.existing!.code, 'EMP-0233');
    });

    test('the error report lists only problem rows', () {
      final report = errorReportRows(rows);
      expect(report.first, [
        'Row',
        'Employee ID',
        'Name',
        'Email',
        'Result',
        'What to fix',
      ]);
      expect(report.length, 1 + 9);
      expect(report.skip(1).where((r) => r[4] == 'Ready'), isEmpty);
    });

    test('committing saves rows and the counts reconcile', () async {
      final plan = ImportPlan.from(rows, DuplicatePolicy.update);
      // Someone adds Pooja by hand while the import is under review.
      await repo.create(
        org,
        plan.toCreate.firstWhere((r) => r.rowNumber == 4).employee,
        sendInvite: false,
        by: 'Hetal Shah',
      );
      final skipped = [
        for (final r in rows.where((r) => r.result == RowResult.invalid))
          NotImportedRow(
            rowNumber: r.rowNumber,
            name: r.employee.fullName,
            code: r.employee.code,
            outcome: RowOutcome.skipped,
            reason: r.issue,
          ),
      ];
      final record = await repo.commitImport(
        org,
        fileName: 's.csv',
        plan: plan,
        skipped: skipped,
        sendInvites: true,
        by: 'Hetal Shah',
      );
      expect(record.created, 3);
      expect(record.updated, 1);
      expect(record.failed, 1);
      expect(record.skipped, 3);
      expect(
        record.notImported.first.reason,
        contains('EMP-0902 already belongs to Pooja Chauhan'),
      );
      expect(record.invitationsSent, 3);
      final after = await repo.employees(org);
      expect(after.length, people.length + 1 + 3);
      expect(
        after.firstWhere((e) => e.code == 'EMP-0233').designation,
        'Senior Operator',
      );
      expect((await repo.imports(org)).first.id, record.id);
    });
  });

  group('DemoEmployeeRepository', () {
    test('seed matches the design head counts', () {
      expect(people.length, 248);
      expect(repo.countInBranch(org, 'b-ahm'), 126);
      expect(repo.countInBranch(org, 'b-sur'), 78);
      expect(repo.countInBranch(org, 'b-vad'), 44);
      expect(people.map((e) => e.code).toSet().length, 248);
      expect(people.map((e) => e.workEmail).toSet().length, 248);
    });

    test('IDs never change once attendance exists', () async {
      final isha = people.firstWhere((e) => e.code == 'EMP-0229');
      await expectLater(
        repo.update(
          org,
          isha.copyWith(code: 'EMP-9999'),
          by: 'x',
          notes: const [],
        ),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('someone who still manages people cannot be deactivated', () async {
      final aarav = people.firstWhere((e) => e.code == 'EMP-0201');
      await expectLater(
        repo.setStatus(org, aarav.id, EmploymentStatus.inactive, by: 'x'),
        throwsA(
          isA<ValidationFailure>().having(
            (f) => f.message,
            'message',
            contains('report to Aarav Bhatt'),
          ),
        ),
      );
      final isha = people.firstWhere((e) => e.code == 'EMP-0229');
      final off = await repo.setStatus(
        org,
        isha.id,
        EmploymentStatus.inactive,
        by: 'Hetal Shah',
        reason: 'Left',
      );
      expect(off.accountStatus, AccountStatus.noAccount);
      expect(off.activity.first.text, 'Deactivated · reason: Left');
    });

    test('resending skips people who already signed in', () async {
      final ids = [
        for (final e in people.where(
          (e) => ['EMP-0233', 'EMP-0240', 'EMP-0229'].contains(e.code),
        ))
          e.id,
      ];
      expect(await repo.resendInvites(org, ids, by: 'x'), 2);
    });

    test('an option in use can be renamed, not removed', () async {
      final size = fields.firstWhere((f) => f.key == 'uniform_size');
      await expectLater(
        repo.saveCustomField(
          org,
          size.copyWith(options: ['XS', 'S', 'L', 'XL', 'XXL']),
        ),
        throwsA(isA<ValidationFailure>()),
      );
      await repo.saveCustomField(
        org,
        size.copyWith(options: ['XS', 'S', 'Medium', 'L', 'XL', 'XXL']),
        renamedOptions: {'M': 'Medium'},
      );
      final isha = (await repo.employees(
        org,
      )).firstWhere((e) => e.code == 'EMP-0229');
      expect(isha.customValues['uniform_size'], 'Medium');
    });

    test('the type of a field with values is locked', () async {
      final size = fields.firstWhere((f) => f.key == 'uniform_size');
      await expectLater(
        repo.saveCustomField(org, size.copyWith(type: CustomFieldType.number)),
        throwsA(isA<ValidationFailure>()),
      );
      final multi = await repo.saveCustomField(
        org,
        size.copyWith(type: CustomFieldType.multiSelect),
      );
      expect(multi.type, CustomFieldType.multiSelect);
    });

    test('branch moves are recorded as moves', () async {
      final isha = people.firstWhere((e) => e.code == 'EMP-0229');
      final kiran = people.firstWhere((e) => e.code == 'EMP-0101');
      expect(
        await repo.changeBranch(
          org,
          [isha.id],
          branchId: 'b-ahm',
          managerId: kiran.id,
          effectiveFrom: DateTime(2026, 11),
          by: 'x',
        ),
        1,
      );
      final moved = (await repo.employees(
        org,
      )).firstWhere((e) => e.id == isha.id);
      expect(moved.branchId, 'b-ahm');
      expect(moved.activity.first.kind, ActivityKind.moved);
    });
  });

  group('dashboard metrics', () {
    final now = DateTime(2026, 10, 14, 14, 10);

    test('owner figures come from records (board S30)', () async {
      final m = DashboardMetrics.compute(
        employees: people,
        branches: branches,
        imports: await repo.imports(org),
        fields: fields,
        period: DashboardPeriod.last14,
        now: now,
      );
      expect(m.total, 248);
      expect(m.active, 241);
      expect(m.inactiveOrInvited, 7);
      expect(m.joined, 6);
      expect(m.headcount.map((h) => (h.branch.name, h.count)), [
        ('Ahmedabad HQ', 126),
        ('Surat', 78),
        ('Vadodara', 44),
      ]);
      expect(m.upcomingHolidays.first.name, 'Dussehra');
      expect(
        m.attention.map((a) => a.kind),
        containsAll([
          AttentionKind.import,
          AttentionKind.invite,
          AttentionKind.incomplete,
          AttentionKind.change,
        ]),
      );
      expect(
        m.attention.firstWhere((a) => a.kind == AttentionKind.import).title,
        'Employee import failed for 4 rows',
      );
    });

    test('the branch filter narrows every figure', () async {
      final m = DashboardMetrics.compute(
        employees: people,
        branches: branches,
        imports: const [],
        fields: const [],
        period: DashboardPeriod.thisMonth,
        now: now,
        branchId: 'b-vad',
      );
      expect(m.total, 44);
      expect(m.headcount.single.count, 44);
      expect(
        m.upcomingHolidays,
        isEmpty,
        reason: 'Vadodara follows national holidays only',
      );
    });

    test('departments scheduled today for a branch (board S33)', () {
      final surat = branches.firstWhere((b) => b.id == 'b-sur');
      final rows = departmentsToday(people, surat, now);
      expect(
        rows.fold<int>(0, (s, r) => s + r.people),
        77,
        reason: 'Surat minus one inactive',
      );
      final sunday = departmentsToday(people, surat, DateTime(2026, 10, 18));
      expect(
        sunday.fold<int>(0, (s, r) => s + r.scheduled),
        0,
        reason: 'Surat is closed on Sundays',
      );
    });

    test('greeting follows the time of day', () {
      expect(greetingFor(DateTime(2026, 1, 1, 9)), 'Good morning');
      expect(greetingFor(now), 'Good afternoon');
      expect(greetingFor(DateTime(2026, 1, 1, 19)), 'Good evening');
    });
  });
}
