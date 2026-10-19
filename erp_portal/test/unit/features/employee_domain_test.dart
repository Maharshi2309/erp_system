import 'package:erp_portal/core/permissions/system_roles.dart';
import 'package:erp_portal/features/employees/domain/custom_field.dart';
import 'package:erp_portal/features/employees/domain/employee.dart';
import 'package:erp_portal/features/employees/domain/employee_query.dart';
import 'package:erp_portal/features/employees/domain/employee_rules.dart';
import 'package:erp_portal/features/organization/domain/branch.dart';
import 'package:flutter_test/flutter_test.dart';

final surat = Branch(
  id: 'b-sur',
  name: 'Surat',
  address: 'Plot 22',
  city: 'Surat',
  state: 'Gujarat',
  pin: '394230',
  hours: HoursPresets.monSat930,
  attendance: const AttendanceRules(shiftMode: ShiftMode.several),
);
final ahmedabad = Branch(
  id: 'b-ahm',
  name: 'Ahmedabad HQ',
  address: 'Ashram Road',
  city: 'Ahmedabad',
  state: 'Gujarat',
  pin: '380009',
  hours: HoursPresets.monSat930,
);

Employee person(
  String id, {
  String code = 'EMP-0001',
  String first = 'Isha',
  String last = 'Rathod',
  String email = 'isha.r@x.in',
  String branch = 'b-sur',
  String? manager = 'm',
  String department = 'Production',
  String shift = 'General',
  EmploymentStatus status = EmploymentStatus.active,
  SystemRole role = SystemRole.employee,
  DateTime? joined,
  Map<String, Object?> custom = const {},
  String mobile = '',
}) => Employee(
  id: id,
  organizationId: 'org',
  code: code,
  firstName: first,
  lastName: last,
  workEmail: email,
  designation: 'Technician',
  department: department,
  type: EmploymentType.fullTime,
  joiningDate: joined ?? DateTime(2025, 7, 14),
  branchId: branch,
  managerId: manager,
  shift: shift,
  status: status,
  role: role,
  customValues: custom,
  mobile: mobile,
);

final manager = person(
  'm',
  code: 'EMP-0201',
  first: 'Aarav',
  last: 'Bhatt',
  email: 'aarav.b@x.in',
  manager: null,
  role: SystemRole.branchManager,
);
final deepa = person(
  'd',
  code: 'EMP-0198',
  first: 'Deepa',
  last: 'Nair',
  email: 'deepa.n@meridiantex.in',
);

void main() {
  group('validateEmployee', () {
    Map<String, String> check(
      Employee e, {
      Branch? branch,
      bool invite = true,
      List<CustomField> fields = const [],
    }) => validateEmployee(
      e,
      others: [manager, deepa],
      fields: fields,
      branch: branch ?? surat,
      sendInvite: invite,
    );

    test('a complete record passes', () {
      expect(check(person('new', code: 'EMP-0244')), isEmpty);
    });

    test('a taken work email names its owner (board S43)', () {
      final errors = check(
        person('new', code: 'EMP-0244', email: 'Deepa.N@meridiantex.in'),
      );
      expect(
        errors['workEmail'],
        'This email belongs to Deepa Nair (EMP-0198). Use a different address.',
      );
    });

    test('a taken employee ID is refused', () {
      expect(
        check(person('new', code: 'emp-0198'))['code'],
        'EMP-0198 already belongs to Deepa Nair.',
      );
    });

    test('an invitation needs a work email; saving without one does not', () {
      expect(
        check(person('new', code: 'EMP-0244', email: ''))['workEmail'],
        isNotNull,
      );
      expect(
        check(person('new', code: 'EMP-0244', email: ''), invite: false),
        isEmpty,
      );
    });

    test('the shift must be one the branch offers, listing them', () {
      final errors = check(person('new', code: 'EMP-0244', shift: ''));
      expect(
        errors['shift'],
        'Choose a shift. Surat has General (09:30–18:30) and Night (21:00–06:00).',
      );
    });

    test('the manager must work at the same branch (board S44)', () {
      final moved = person('new', code: 'EMP-0244', branch: 'b-ahm');
      expect(
        check(moved, branch: ahmedabad)['managerId'],
        'Required — Aarav Bhatt is not at Ahmedabad HQ.',
      );
    });

    test('branch managers may report straight to the owner', () {
      expect(
        check(person('new', code: 'EMP-0244', manager: null))['managerId'],
        isNotNull,
      );
      expect(
        check(
          person(
            'new',
            code: 'EMP-0244',
            manager: null,
            role: SystemRole.branchManager,
          ),
        ),
        isEmpty,
      );
    });

    test('an inactive branch is refused', () {
      final closed = surat.copyWith(status: BranchStatus.inactive);
      expect(
        check(person('new', code: 'EMP-0244'), branch: closed)['branchId'],
        contains('inactive'),
      );
    });

    test('mobile numbers need 10–12 digits', () {
      expect(
        check(person('new', code: 'EMP-0244', mobile: '98250'))['mobile'],
        isNotNull,
      );
      expect(
        check(person('new', code: 'EMP-0244', mobile: '+91 98250 61233')),
        isEmpty,
      );
    });

    test('required custom fields apply only to their departments', () {
      const field = CustomField(
        id: 'f',
        key: 'uniform_size',
        label: 'Uniform size',
        type: CustomFieldType.singleSelect,
        options: ['S', 'M'],
        required: true,
        departments: ['Production'],
      );
      expect(
        check(
          person('new', code: 'EMP-0244'),
          fields: [field],
        )['custom.uniform_size'],
        'Uniform size is required.',
      );
      expect(
        check(
          person('new', code: 'EMP-0244', department: 'Finance'),
          fields: [field],
        ),
        isEmpty,
      );
    });
  });

  group('custom fields', () {
    const select = CustomField(
      id: 's',
      key: 'size',
      label: 'Size',
      type: CustomFieldType.singleSelect,
      options: ['S', 'M'],
    );

    test('values are checked by type', () {
      expect(validateCustomValue(select, 'XL'), contains('isn’t an option'));
      expect(validateCustomValue(select, 'M'), isNull);
      const number = CustomField(
        id: 'n',
        key: 'n',
        label: 'Locker',
        type: CustomFieldType.number,
      );
      expect(validateCustomValue(number, 'abc'), contains('number'));
      expect(validateCustomValue(number, 12), isNull);
      const url = CustomField(
        id: 'u',
        key: 'u',
        label: 'Licence',
        type: CustomFieldType.url,
      );
      expect(validateCustomValue(url, 'licence.pdf'), contains('https://'));
      expect(validateCustomValue(url, 'https://x.in/a.pdf'), isNull);
      const multi = CustomField(
        id: 'm',
        key: 'm',
        label: 'Languages',
        type: CustomFieldType.multiSelect,
        options: ['Hindi'],
      );
      expect(validateCustomValue(multi, ['Hindi', 'Tamil']), contains('Tamil'));
      const yes = CustomField(
        id: 'y',
        key: 'y',
        label: 'Smoker',
        type: CustomFieldType.yesNo,
      );
      expect(validateCustomValue(yes, 'maybe'), contains('yes or no'));
      const date = CustomField(
        id: 'd',
        key: 'd',
        label: 'Expiry',
        type: CustomFieldType.date,
        required: true,
      );
      expect(validateCustomValue(date, null), 'Expiry is required.');
      expect(validateCustomValue(date, DateTime(2027)), isNull);
    });

    test('the type is locked once values exist (board S45)', () {
      expect(
        allowedTypeChanges(CustomFieldType.singleSelect, hasValues: true),
        {CustomFieldType.singleSelect, CustomFieldType.multiSelect},
      );
      expect(allowedTypeChanges(CustomFieldType.date, hasValues: true), {
        CustomFieldType.date,
      });
      expect(
        allowedTypeChanges(CustomFieldType.date, hasValues: false),
        CustomFieldType.values.toSet(),
      );
    });

    test('keys come from labels and never collide', () {
      expect(fieldKeyFor(' Uniform size! '), 'uniform_size');
      final errors = validateFieldDefinition(
        const CustomField(
          id: 'new',
          key: 'size',
          label: 'size',
          type: CustomFieldType.shortText,
        ),
        others: [select],
      );
      expect(errors['label'], 'Another field already uses this name.');
    });

    test('options must be present and unique', () {
      expect(
        validateFieldDefinition(
          select.copyWith(options: ['S', 'S']),
          others: const [],
        )['options'],
        'Each option must be different.',
      );
      expect(
        validateFieldDefinition(
          select.copyWith(options: const []),
          others: const [],
        )['options'],
        'Add at least one option.',
      );
    });

    test('usage and missing-value counts drive the builder warnings', () {
      final people = [
        person('a', custom: {'size': 'M'}),
        person('b', custom: {'size': 'M'}),
        person('c'),
        person('d', status: EmploymentStatus.inactive),
      ];
      expect(optionUsage(select, 'M', people), 2);
      expect(optionUsage(select, 'S', people), 0);
      expect(missingValues(select, people), 1);
    });

    test('field access follows the matrix; the owner sees everything', () {
      const blood = CustomField(
        id: 'b',
        key: 'blood',
        label: 'Blood group',
        type: CustomFieldType.shortText,
        access: {
          FieldAudience.hrAdmin: FieldAccess(view: true, edit: true),
          FieldAudience.self: FieldAccess(view: true),
        },
      );
      expect(blood.canEdit(SystemRole.owner), isTrue);
      expect(blood.canEdit(SystemRole.hrAdmin), isTrue);
      expect(blood.canView(SystemRole.branchManager), isFalse);
      expect(blood.canView(SystemRole.employee, self: true), isTrue);
      expect(blood.canEdit(SystemRole.employee, self: true), isFalse);
    });
  });

  group('directory query', () {
    final people = [
      for (var i = 0; i < 30; i++)
        person(
          'e$i',
          code: 'EMP-${(100 + i).toString()}',
          first: 'Name$i',
          last: i.isEven ? 'Shah' : 'Patel',
          email: 'p$i@x.in',
          branch: i < 20 ? 'b-sur' : 'b-ahm',
          department: i % 3 == 0 ? 'Quality' : 'Production',
          status: i == 5 ? EmploymentStatus.inactive : EmploymentStatus.active,
          joined: DateTime(2020, 1, 1 + i),
          mobile: i == 7 ? '+91 98250 61233' : '',
        ),
    ];

    test('searches name, ID, email and mobile', () {
      expect(
        applyQuery(people, const EmployeeQuery(search: 'name12')).single.id,
        'e12',
      );
      expect(
        applyQuery(people, const EmployeeQuery(search: 'emp-103')).single.id,
        'e3',
      );
      expect(
        applyQuery(people, const EmployeeQuery(search: 'p4@')).single.id,
        'e4',
      );
      expect(
        applyQuery(people, const EmployeeQuery(search: '61233')).single.id,
        'e7',
      );
    });

    test('filters combine', () {
      const q = EmployeeQuery(branchId: 'b-sur', department: 'Quality');
      expect(applyQuery(people, q).length, 7);
      expect(
        applyQuery(
          people,
          const EmployeeQuery(status: EmploymentStatus.inactive),
        ).single.id,
        'e5',
      );
      expect(q.activeFilters, 2);
    });

    test('sorts both ways with a stable tie-break', () {
      final asc = applyQuery(
        people,
        const EmployeeQuery(sort: EmployeeSort.joined),
      );
      expect(asc.first.id, 'e0');
      final desc = applyQuery(
        people,
        const EmployeeQuery(sort: EmployeeSort.joined, ascending: false),
      );
      expect(desc.first.id, 'e29');
    });

    test('pages slice the filtered list and reset on changes', () {
      final all = applyQuery(people, const EmployeeQuery());
      expect(pageOf(all, const EmployeeQuery(page: 2)).length, 10);
      expect(pageOf(all, const EmployeeQuery(page: 3)), isEmpty);
      expect(pageOf(all, const EmployeeQuery(pageSize: 25, page: 1)).length, 5);
      expect(const EmployeeQuery(page: 2).copyWith(search: 'x').page, 0);
      expect(const EmployeeQuery(page: 2).copyWith(page: 1).page, 1);
    });
  });

  group('helpers', () {
    test('mobile masking keeps two leading and four trailing digits', () {
      expect(maskPhone('+91 98250 44417'), '+91 98•• ••4417');
      expect(maskPhone(''), '');
    });

    test('next employee ID follows the highest number', () {
      expect(nextEmployeeCode(['EMP-0243', 'EMP-0198', 'X']), 'EMP-0244');
      expect(nextEmployeeCode(const []), 'EMP-0001');
    });

    test('probation end date and display name', () {
      final e = person(
        'a',
        joined: DateTime(2026, 10, 19),
      ).copyWith(probationMonths: 6, displayName: 'Ishu');
      expect(e.probationEndsOn, DateTime(2027, 4, 19));
      expect(e.name, 'Ishu');
    });

    test('branch moves list their consequences', () {
      final items = branchMoveConsequences(
        before: person('a'),
        to: ahmedabad,
        pendingLeaveRequests: 1,
      );
      expect(
        items.first,
        'Schedule becomes General (09:30–18:30) (Ahmedabad HQ default)',
      );
      expect(
        items,
        contains('1 pending leave request moves to the new manager'),
      );
    });
  });
}
