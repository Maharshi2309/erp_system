import '../../../core/errors/failure.dart';
import '../../../core/permissions/system_roles.dart';
import '../domain/custom_field.dart';
import '../domain/employee.dart';
import '../domain/employee_import.dart';
import '../domain/employee_repository.dart';

/// DEMO ONLY — employees kept in memory, seeded so the design's numbers
/// (Meridian Textiles: 248 people, Ahmedabad HQ 126 · Surat 78 · Vadodara 44)
/// come from real records. Replaced by an API client when a backend exists.
class DemoEmployeeRepository implements EmployeeRepository {
  DemoEmployeeRepository({
    this.latency = const Duration(milliseconds: 500),
    DateTime Function()? clock,
    bool seed = true,
  }) : _now = clock ?? DateTime.now {
    if (!seed) return;
    _seedMeridian();
    _seedGeneric(
      'org_pateldyes',
      'b-vapi',
      42,
      domain: 'pateldyes.in',
      firstCode: 501,
    );
  }

  final Duration latency;
  final DateTime Function() _now;

  final _employees = <String, List<Employee>>{};
  final _fields = <String, List<CustomField>>{};
  final _imports = <String, List<ImportRecord>>{};
  int _nextId = 1;

  Future<void> _delay() =>
      latency == Duration.zero ? Future.value() : Future.delayed(latency);

  List<Employee> _list(String organizationId) =>
      _employees.putIfAbsent(organizationId, () => []);

  // ---------- Seed ----------

  static const _first = [
    'Aditi',
    'Bhavesh',
    'Chetan',
    'Dhruv',
    'Ekta',
    'Farhan',
    'Gopal',
    'Hina',
    'Ishaan',
    'Jaya',
    'Kunal',
    'Lata',
    'Manish',
    'Neha',
    'Om',
    'Pankaj',
    'Riya',
    'Sagar',
    'Tejal',
    'Umesh',
    'Varsha',
    'Yogesh',
    'Zoya',
    'Alpesh',
    'Bina',
    'Darshan',
    'Falguni',
    'Hardik',
    'Jinal',
    'Ketan',
    'Mansi',
    'Nilesh',
    'Pallavi',
    'Rakesh',
    'Sneha',
    'Tushar',
    'Vaishali',
    'Yash',
    'Hemant',
    'Payal',
    'Kishan',
    'Rekha',
  ];
  static const _last = [
    'Patel',
    'Shah',
    'Mehta',
    'Joshi',
    'Desai',
    'Parmar',
    'Chauhan',
    'Solanki',
    'Vaghela',
    'Trivedi',
    'Pandya',
    'Rathod',
    'Makwana',
    'Bhatt',
    'Gohil',
    'Prajapati',
    'Barot',
    'Mistry',
    'Thakor',
    'Modi',
    'Vora',
    'Dave',
    'Raval',
    'Panchal',
    'Soni',
    'Kotadia',
    'Jadeja',
    'Rana',
  ];
  static const _designations = {
    'Production': [
      'Machine Operator',
      'Dyeing Technician',
      'Weaver',
      'Production Associate',
      'Line Supervisor',
    ],
    'Quality': ['QC Inspector', 'QA Analyst', 'Quality Inspector'],
    'Logistics': ['Loader', 'Driver', 'Logistics Associate'],
    'Stores': ['Store Keeper', 'Stores Assistant'],
    'Dispatch': ['Packer', 'Dispatch Associate'],
    'Finance': ['Accounts Assistant', 'Accounts Associate'],
    'People Ops': ['HR Executive', 'HR Assistant'],
    'Facilities': ['Electrician', 'Maintenance Technician', 'Security Guard'],
    'Admin': ['Office Administrator', 'Receptionist'],
  };

  /// Department for the n-th generated person; roughly the design's mix.
  static String _departmentFor(int n) => switch (n % 20) {
    < 9 => 'Production',
    < 11 => 'Quality',
    < 13 => 'Logistics',
    13 => 'Stores',
    < 16 => 'Dispatch',
    16 => 'Finance',
    17 => 'People Ops',
    18 => 'Facilities',
    _ => 'Admin',
  };

  static const _sizes = ['XS', 'S', 'M', 'L', 'XL'];

  void _seedMeridian() {
    const org = 'org_meridian-tex';
    final list = _list(org);
    final emails = <String>{};
    final codes = <String>{};

    Employee add({
      required String code,
      required String first,
      required String last,
      required String designation,
      required String department,
      required String branch,
      required DateTime joined,
      String? manager,
      EmploymentStatus status = EmploymentStatus.active,
      AccountStatus account = AccountStatus.signedIn,
      SystemRole role = SystemRole.employee,
      String? email,
      List<EmployeeActivity> activity = const [],
      Map<String, Object?> custom = const {},
      int probation = 0,
    }) {
      final mail = email ?? _uniqueEmail(first, last, 'meridiantex.in', emails);
      emails.add(mail);
      codes.add(code);
      final managerId = manager == null
          ? null
          : list.firstWhere((e) => e.code == manager).id;
      final e = Employee(
        id: 'e-${_nextId++}',
        organizationId: org,
        code: code,
        firstName: first,
        lastName: last,
        workEmail: mail,
        mobile: _mobileFor(code),
        designation: designation,
        department: department,
        type: EmploymentType.fullTime,
        joiningDate: joined,
        probationMonths: probation,
        status: status,
        branchId: branch,
        managerId: managerId,
        shift: 'General',
        accountStatus: account,
        role: role,
        invitedAt: account == AccountStatus.noAccount ? null : joined,
        lastSignInAt: account == AccountStatus.signedIn
            ? DateTime(2026, 10, 14, 9, 28)
            : null,
        hasAttendance: joined.isBefore(DateTime(2026, 10)),
        customValues: custom,
        activity: activity.isNotEmpty
            ? activity
            : [
                EmployeeActivity(
                  text: 'Employee created',
                  by: 'Hetal Shah',
                  at: joined,
                  kind: ActivityKind.created,
                ),
              ],
      );
      list.add(e);
      return e;
    }

    // People named on the design boards.
    add(
      code: 'EMP-0101',
      first: 'Kiran',
      last: 'Desai',
      designation: 'Branch Manager',
      department: 'Admin',
      branch: 'b-ahm',
      joined: DateTime(2016, 4, 4),
      role: SystemRole.branchManager,
      email: 'kiran.d@meridiantex.in',
    );
    add(
      code: 'EMP-0105',
      first: 'Hetal',
      last: 'Shah',
      designation: 'HR Manager',
      department: 'People Ops',
      branch: 'b-ahm',
      joined: DateTime(2017, 6, 12),
      role: SystemRole.hrAdmin,
      email: 'hetal.s@meridiantex.in',
    );
    add(
      code: 'EMP-0108',
      first: 'Priya',
      last: 'Desai',
      designation: 'Finance Manager',
      department: 'Finance',
      branch: 'b-ahm',
      joined: DateTime(2018, 1, 8),
      manager: 'EMP-0101',
      email: 'priya.d@meridiantex.in',
    );
    add(
      code: 'EMP-0102',
      first: 'Jignesh',
      last: 'Parmar',
      designation: 'Branch Manager',
      department: 'Admin',
      branch: 'b-sur',
      joined: DateTime(2016, 9, 1),
      role: SystemRole.branchManager,
      email: 'jignesh.p@meridiantex.in',
    );
    add(
      code: 'EMP-0110',
      first: 'Mitesh',
      last: 'Rana',
      designation: 'Logistics Supervisor',
      department: 'Logistics',
      branch: 'b-sur',
      joined: DateTime(2018, 3, 19),
      manager: 'EMP-0102',
      role: SystemRole.attendanceManager,
      email: 'mitesh.r@meridiantex.in',
      custom: {'uniform_size': 'L'},
    );
    add(
      code: 'EMP-0201',
      first: 'Aarav',
      last: 'Bhatt',
      designation: 'Floor Supervisor',
      department: 'Production',
      branch: 'b-sur',
      joined: DateTime(2021, 2, 3),
      manager: 'EMP-0102',
      role: SystemRole.leaveApprover,
      email: 'aarav.b@meridiantex.in',
      custom: {
        'uniform_size': 'L',
        'safety_certification_expiry': DateTime(2027, 5, 31),
      },
    );
    add(
      code: 'EMP-0217',
      first: 'Bhavna',
      last: 'Solanki',
      designation: 'QA Analyst',
      department: 'Quality',
      branch: 'b-sur',
      joined: DateTime(2022, 8, 18),
      manager: 'EMP-0102',
      email: 'bhavna.s@meridiantex.in',
      custom: {'uniform_size': 'S'},
    );
    add(
      code: 'EMP-0233',
      first: 'Chirag',
      last: 'Vaghela',
      designation: 'Machine Operator',
      department: 'Production',
      branch: 'b-sur',
      joined: DateTime(2026, 10, 1),
      manager: 'EMP-0201',
      status: EmploymentStatus.probation,
      probation: 6,
      account: AccountStatus.invited,
      email: 'chirag.v@meridiantex.in',
      custom: {'uniform_size': 'L'},
    );
    add(
      code: 'EMP-0198',
      first: 'Deepa',
      last: 'Nair',
      designation: 'HR Executive',
      department: 'People Ops',
      branch: 'b-sur',
      joined: DateTime(2021, 1, 12),
      manager: 'EMP-0102',
      email: 'deepa.n@meridiantex.in',
    );
    add(
      code: 'EMP-0240',
      first: 'Faisal',
      last: 'Shaikh',
      designation: 'Store Keeper',
      department: 'Logistics',
      branch: 'b-sur',
      joined: DateTime(2026, 10, 6),
      manager: 'EMP-0110',
      status: EmploymentStatus.probation,
      probation: 6,
      account: AccountStatus.inviteExpired,
      email: 'faisal.s@meridiantex.in',
      custom: {'uniform_size': 'M'},
    );
    add(
      code: 'EMP-0176',
      first: 'Gauri',
      last: 'Pandya',
      designation: 'Accounts Associate',
      department: 'Finance',
      branch: 'b-sur',
      joined: DateTime(2020, 6, 22),
      manager: 'EMP-0102',
      email: 'gauri.p@meridiantex.in',
    );
    add(
      code: 'EMP-0152',
      first: 'Harsh',
      last: 'Trivedi',
      designation: 'Maintenance Lead',
      department: 'Facilities',
      branch: 'b-sur',
      joined: DateTime(2019, 3, 9),
      manager: 'EMP-0102',
      status: EmploymentStatus.noticePeriod,
      email: 'harsh.t@meridiantex.in',
    );
    add(
      code: 'EMP-0229',
      first: 'Isha',
      last: 'Rathod',
      designation: 'Dyeing Technician',
      department: 'Production',
      branch: 'b-sur',
      joined: DateTime(2025, 7, 14),
      manager: 'EMP-0201',
      probation: 6,
      email: 'isha.r@meridiantex.in',
      custom: {
        'uniform_size': 'M',
        'locker_number': 'B-112',
        'safety_certification_expiry': DateTime(2027, 3, 31),
      },
      activity: [
        EmployeeActivity(
          text: 'Probation completed',
          by: 'System · policy “6-month probation”',
          at: DateTime(2026, 1, 14),
          kind: ActivityKind.status,
        ),
        EmployeeActivity(
          text: 'Employee created and invited',
          by: 'Hetal Shah · import surat_staff_jul.xlsx',
          at: DateTime(2025, 7, 14),
          kind: ActivityKind.created,
        ),
      ],
    );
    add(
      code: 'EMP-0118',
      first: 'Jayesh',
      last: 'Makwana',
      designation: 'Driver',
      department: 'Logistics',
      branch: 'b-sur',
      joined: DateTime(2017, 11, 30),
      manager: 'EMP-0110',
      status: EmploymentStatus.inactive,
      account: AccountStatus.noAccount,
      email: 'jayesh.m@meridiantex.in',
    );
    add(
      code: 'EMP-0236',
      first: 'Komal',
      last: 'Desai',
      designation: 'Packing Associate',
      department: 'Logistics',
      branch: 'b-sur',
      joined: DateTime(2026, 10, 2),
      manager: 'EMP-0110',
      account: AccountStatus.invited,
      email: 'komal.d@meridiantex.in',
      custom: {'uniform_size': 'S'},
    );
    add(
      code: 'EMP-0190',
      first: 'Meera',
      last: 'Rao',
      designation: 'Quality Inspector',
      department: 'Quality',
      branch: 'b-sur',
      joined: DateTime(2020, 2, 17),
      manager: 'EMP-0217',
      email: 'meera.r@meridiantex.in',
      custom: {'uniform_size': 'M'},
      activity: [
        EmployeeActivity(
          text: 'Moved to Surat from Ahmedabad HQ · effective 15 Oct 2026',
          by: 'Ankit Patel',
          at: DateTime(2026, 10, 13, 11, 20),
          kind: ActivityKind.moved,
        ),
        EmployeeActivity(
          text: 'Employee created',
          by: 'Hetal Shah',
          at: DateTime(2020, 2, 17),
          kind: ActivityKind.created,
        ),
      ],
    );
    add(
      code: 'EMP-0104',
      first: 'Nikhil',
      last: 'Joshi',
      designation: 'Plant Supervisor',
      department: 'Production',
      branch: 'b-vad',
      joined: DateTime(2019, 7, 1),
      role: SystemRole.branchManager,
      email: 'nikhil.j@meridiantex.in',
      custom: {
        'uniform_size': 'M',
        'safety_certification_expiry': DateTime(2027, 2, 28),
      },
    );

    // Everyone else, generated to reach each branch's head count.
    const targets = {'b-ahm': 126, 'b-sur': 78, 'b-vad': 44};
    const leads = {
      'b-ahm': 'EMP-0101',
      'b-sur': 'EMP-0201',
      'b-vad': 'EMP-0104',
    };
    var n = 0;
    var code = 101;
    var missingUniform = 0;
    for (final MapEntry(key: branch, value: target) in targets.entries) {
      while (list.where((e) => e.branchId == branch).length < target) {
        while (codes.contains(_code(code))) {
          code++;
        }
        final first = _first[n % _first.length];
        final last = _last[(n * 5 + n ~/ _first.length) % _last.length];
        final department = _departmentFor(n);
        final titles = _designations[department]!;
        final joined = n < 3
            // Three more joiners this month (design: "+6 this month").
            ? DateTime(2026, 10, 5 + n * 3)
            : DateTime(2017 + n % 9, 1 + (n * 5) % 12, 1 + (n * 3) % 28);
        final status = switch (n) {
          40 || 90 => EmploymentStatus.inactive,
          _ when n < 3 => EmploymentStatus.probation,
          _ => EmploymentStatus.active,
        };
        final usesUniform = const [
          'Production',
          'Quality',
          'Logistics',
        ].contains(department);
        Map<String, Object?> custom = {};
        if (usesUniform) {
          // 12 production people have no size yet (board S45 warning).
          if (department == 'Production' && missingUniform < 12 && n % 3 == 0) {
            missingUniform++;
          } else {
            custom = {'uniform_size': _sizes[n % _sizes.length]};
          }
        }
        if (department == 'Production' && n % 4 != 1) {
          custom = {
            ...custom,
            'safety_certification_expiry': DateTime(
              2027,
              1 + n % 12,
              1 + n % 27,
            ),
          };
        }
        if (n % 5 == 0) custom = {...custom, 'locker_number': 'A-${100 + n}'};
        add(
          code: _code(code),
          first: first,
          last: last,
          designation: titles[n % titles.length],
          department: department,
          branch: branch,
          joined: joined,
          manager: leads[branch],
          status: status,
          probation: n < 3 ? 6 : 0,
          account: n == 1
              ? AccountStatus.invited
              : (status == EmploymentStatus.inactive
                    ? AccountStatus.noAccount
                    : AccountStatus.signedIn),
          custom: custom,
        );
        code++;
        n++;
      }
    }

    // Three Surat machine operators work the night shift (21:00–06:00).
    var night = 0;
    for (var i = 0; i < list.length && night < 3; i++) {
      final e = list[i];
      if (e.branchId == 'b-sur' &&
          e.designation == 'Machine Operator' &&
          e.code.compareTo('EMP-0240') > 0) {
        list[i] = e.copyWith(shift: 'Night');
        night++;
      }
    }

    _fields[org] = [
      CustomField(
        id: 'cf-1',
        key: 'safety_certification_expiry',
        label: 'Safety certification expiry',
        type: CustomFieldType.date,
        required: true,
        departments: const ['Production'],
        createdAt: DateTime(2025, 3, 3),
      ),
      CustomField(
        id: 'cf-2',
        key: 'uniform_size',
        label: 'Uniform size',
        type: CustomFieldType.singleSelect,
        description: 'For issuing work uniforms',
        options: const ['XS', 'S', 'M', 'L', 'XL', 'XXL'],
        required: true,
        departments: const ['Production', 'Quality', 'Logistics'],
        createdAt: DateTime(2025, 3, 3),
      ),
      CustomField(
        id: 'cf-3',
        key: 'locker_number',
        label: 'Locker number',
        type: CustomFieldType.shortText,
        createdAt: DateTime(2025, 3, 3),
      ),
      CustomField(
        id: 'cf-4',
        key: 'machine_licence',
        label: 'Machine licence',
        type: CustomFieldType.url,
        departments: const ['Production'],
        createdAt: DateTime(2025, 4, 10),
      ),
      CustomField(
        id: 'cf-5',
        key: 'blood_group',
        label: 'Blood group',
        type: CustomFieldType.singleSelect,
        options: const ['A+', 'A−', 'B+', 'B−', 'AB+', 'AB−', 'O+', 'O−'],
        sensitive: true,
        createdAt: DateTime(2025, 4, 10),
        access: const {
          FieldAudience.hrAdmin: FieldAccess(view: true, edit: true),
          FieldAudience.branchManager: FieldAccess(),
          FieldAudience.attendanceManager: FieldAccess(),
          FieldAudience.self: FieldAccess(view: true, edit: true),
        },
      ),
      CustomField(
        id: 'cf-6',
        key: 'languages_spoken',
        label: 'Languages spoken',
        type: CustomFieldType.multiSelect,
        options: const ['Gujarati', 'Hindi', 'English', 'Marathi'],
        createdAt: DateTime(2025, 5, 2),
      ),
      CustomField(
        id: 'cf-7',
        key: 'bus_route',
        label: 'Bus route',
        type: CustomFieldType.singleSelect,
        options: const [
          'Route 1 · Adajan',
          'Route 2 · Varachha',
          'Route 3 · Udhna',
        ],
        branchIds: const ['b-sur'],
        createdAt: DateTime(2025, 6, 9),
      ),
      CustomField(
        id: 'cf-8',
        key: 'previous_employer',
        label: 'Previous employer',
        type: CustomFieldType.shortText,
        archived: true,
        createdAt: DateTime(2025, 3, 3),
      ),
    ];

    _imports[org] = [
      ImportRecord(
        id: 'imp-3',
        fileName: 'vadodara_staff.xlsx',
        finishedAt: DateTime(2026, 10, 12, 16, 15),
        by: 'Hetal Shah',
        created: 38,
        updated: 0,
        skipped: 0,
        failed: 4,
        branchIds: const ['b-vad'],
        invitationsSent: 38,
        notImported: const [
          NotImportedRow(
            rowNumber: 9,
            name: 'Ritesh Panchal',
            code: 'EMP-0412',
            outcome: RowOutcome.failed,
            reason:
                'Email was taken by an employee added while this import ran.',
          ),
          NotImportedRow(
            rowNumber: 17,
            name: 'Sonal Dave',
            code: 'EMP-0420',
            outcome: RowOutcome.failed,
            reason:
                'Branch “Vadodara 2” was deactivated while this import ran.',
          ),
          NotImportedRow(
            rowNumber: 23,
            name: 'Hiren Soni',
            code: 'EMP-0426',
            outcome: RowOutcome.failed,
            reason:
                'Employee ID was taken by an employee added while this import ran.',
          ),
          NotImportedRow(
            rowNumber: 31,
            name: 'Kajal Raval',
            code: 'EMP-0434',
            outcome: RowOutcome.failed,
            reason: 'Reporting manager was deactivated while this import ran.',
          ),
        ],
      ),
      ImportRecord(
        id: 'imp-2',
        fileName: 'surat_staff_jul.xlsx',
        finishedAt: DateTime(2025, 7, 14, 11, 2),
        by: 'Hetal Shah',
        created: 22,
        updated: 0,
        skipped: 0,
        failed: 0,
        branchIds: const ['b-sur'],
        invitationsSent: 22,
      ),
      ImportRecord(
        id: 'imp-1',
        fileName: 'ahm_hq_initial.csv',
        finishedAt: DateTime(2025, 3, 5, 10, 30),
        by: 'Ankit Patel',
        created: 126,
        updated: 0,
        skipped: 0,
        failed: 0,
        branchIds: const ['b-ahm'],
        invitationsSent: 126,
      ),
    ];
  }

  void _seedGeneric(
    String org,
    String branch,
    int count, {
    required String domain,
    required int firstCode,
  }) {
    final list = _list(org);
    final emails = <String>{};
    for (var i = 0; i < count; i++) {
      final first = _first[(i * 5 + 3) % _first.length];
      final last = _last[(i * 3 + 1) % _last.length];
      final department = _departmentFor(i);
      final titles = _designations[department]!;
      final email = _uniqueEmail(first, last, domain, emails);
      emails.add(email);
      final joined = DateTime(2018 + i % 8, 1 + i % 12, 1 + i % 28);
      list.add(
        Employee(
          id: 'e-${_nextId++}',
          organizationId: org,
          code: _code(firstCode + i),
          firstName: first,
          lastName: last,
          workEmail: email,
          mobile: _mobileFor(_code(firstCode + i)),
          designation: i == 0 ? 'Plant Manager' : titles[i % titles.length],
          department: i == 0 ? 'Admin' : department,
          type: EmploymentType.fullTime,
          joiningDate: joined,
          branchId: branch,
          managerId: i == 0 ? null : list.first.id,
          role: i == 0 ? SystemRole.branchManager : SystemRole.employee,
          shift: 'General',
          accountStatus: AccountStatus.signedIn,
          hasAttendance: true,
          activity: [
            EmployeeActivity(
              text: 'Employee created',
              by: 'Ankit Patel',
              at: joined,
              kind: ActivityKind.created,
            ),
          ],
        ),
      );
    }
    _fields[org] = [];
    _imports[org] = [];
  }

  static String _code(int n) => 'EMP-${n.toString().padLeft(4, '0')}';

  static String _mobileFor(String code) {
    final n = int.parse(code.replaceAll(RegExp(r'\D'), ''));
    final tail = (1000 + (n * 37) % 9000).toString();
    return '+91 98${(250 + n % 700).toString().padLeft(3, '0')} ${(41000 + n * 13 % 9000).toString().substring(0, 1)}$tail';
  }

  static String _uniqueEmail(
    String first,
    String last,
    String domain,
    Set<String> taken,
  ) {
    final base = '${first.toLowerCase()}.${last[0].toLowerCase()}';
    var email = '$base@$domain';
    for (var i = 2; taken.contains(email); i++) {
      email = '$base$i@$domain';
    }
    return email;
  }

  // ---------- Employees ----------

  @override
  Future<List<Employee>> employees(String organizationId) async {
    await _delay();
    return List.unmodifiable(_list(organizationId));
  }

  @override
  int countInBranch(String organizationId, String branchId) =>
      _list(organizationId)
          .where(
            (e) =>
                e.branchId == branchId &&
                e.status != EmploymentStatus.terminated,
          )
          .length;

  void _checkUnique(String organizationId, Employee e) {
    for (final other in _list(organizationId)) {
      if (other.id == e.id) continue;
      if (other.code.toUpperCase() == e.code.toUpperCase()) {
        throw ValidationFailure(
          'That employee ID is taken.',
          fieldErrors: {
            'code':
                '${e.code.toUpperCase()} already belongs to ${other.fullName}.',
          },
        );
      }
      if (e.workEmail.isNotEmpty &&
          other.workEmail.toLowerCase() == e.workEmail.toLowerCase()) {
        throw ValidationFailure(
          'That email is taken.',
          fieldErrors: {
            'workEmail':
                'This email belongs to ${other.fullName} (${other.code}). '
                'Use a different address.',
          },
        );
      }
    }
  }

  Employee _byId(String organizationId, String id) =>
      _list(organizationId).where((e) => e.id == id).firstOrNull ??
      (throw const NotFoundFailure());

  void _replace(String organizationId, Employee e) {
    final list = _list(organizationId);
    list[list.indexWhere((x) => x.id == e.id)] = e;
  }

  @override
  Future<Employee> create(
    String organizationId,
    Employee employee, {
    required bool sendInvite,
    required String by,
  }) async {
    await _delay();
    _checkUnique(organizationId, employee);
    final now = _now();
    final created = employee.copyWith(
      code: employee.code.trim().toUpperCase(),
      workEmail: employee.workEmail.trim().toLowerCase(),
      accountStatus: sendInvite
          ? AccountStatus.invited
          : AccountStatus.noAccount,
      invitedAt: sendInvite ? now : null,
      activity: [
        EmployeeActivity(
          text: sendInvite
              ? 'Employee created and invited'
              : 'Employee created',
          by: by,
          at: now,
          kind: ActivityKind.created,
        ),
      ],
    );
    final withId = Employee(
      id: 'e-${_nextId++}',
      organizationId: organizationId,
      code: created.code,
      firstName: created.firstName.trim(),
      lastName: created.lastName.trim(),
      displayName: created.displayName.trim(),
      workEmail: created.workEmail,
      mobile: created.mobile.trim(),
      personalEmail: created.personalEmail.trim(),
      dateOfBirth: created.dateOfBirth,
      emergencyContact: created.emergencyContact,
      designation: created.designation.trim(),
      department: created.department,
      type: created.type,
      joiningDate: created.joiningDate,
      probationMonths: created.probationMonths,
      status: created.probationMonths > 0
          ? EmploymentStatus.probation
          : EmploymentStatus.active,
      branchId: created.branchId,
      workLocation: created.workLocation,
      managerId: created.managerId,
      shift: created.shift,
      weeklyOff: created.weeklyOff,
      accountStatus: created.accountStatus,
      role: created.role,
      invitedAt: created.invitedAt,
      customValues: created.customValues,
      activity: created.activity,
    );
    _list(organizationId).add(withId);
    return withId;
  }

  @override
  Future<Employee> update(
    String organizationId,
    Employee employee, {
    required String by,
    required List<String> notes,
  }) async {
    await _delay();
    final before = _byId(organizationId, employee.id);
    _checkUnique(organizationId, employee);
    if (before.hasAttendance && before.code != employee.code) {
      throw const ValidationFailure(
        'Employee IDs never change once attendance exists.',
        fieldErrors: {'code': 'IDs never change once attendance exists.'},
      );
    }
    final now = _now();
    final moved = before.branchId != employee.branchId;
    final saved = employee.copyWith(
      activity: [
        for (final note in notes)
          EmployeeActivity(
            text: note,
            by: by,
            at: now,
            kind: moved && note.startsWith('Branch')
                ? ActivityKind.moved
                : ActivityKind.updated,
          ),
        ...before.activity,
      ],
    );
    _replace(organizationId, saved);
    return saved;
  }

  @override
  Future<Employee> setStatus(
    String organizationId,
    String employeeId,
    EmploymentStatus status, {
    required String by,
    String reason = '',
    DateTime? lastWorkingDay,
  }) async {
    await _delay();
    final before = _byId(organizationId, employeeId);
    if (status == before.status) return before;
    if (!status.isEmployed) {
      final reports = _list(
        organizationId,
      ).where((e) => e.managerId == employeeId && e.status.isEmployed);
      if (reports.isNotEmpty) {
        throw ValidationFailure(
          '${reports.length} ${reports.length == 1 ? 'person reports' : 'people report'} '
          'to ${before.fullName}. Choose a new manager for them first.',
        );
      }
    }
    final text = switch (status) {
      EmploymentStatus.inactive => 'Deactivated',
      EmploymentStatus.terminated => 'Terminated and archived',
      EmploymentStatus.noticePeriod => 'Notice period started',
      _ => 'Reactivated',
    };
    final saved = before.copyWith(
      status: status,
      statusReason: reason,
      lastWorkingDay: lastWorkingDay,
      accountStatus: status.isEmployed ? null : AccountStatus.noAccount,
      activity: [
        EmployeeActivity(
          text: reason.isEmpty ? text : '$text · reason: $reason',
          by: by,
          at: _now(),
          kind: ActivityKind.status,
        ),
        ...before.activity,
      ],
    );
    _replace(organizationId, saved);
    return saved;
  }

  @override
  Future<int> resendInvites(
    String organizationId,
    List<String> employeeIds, {
    required String by,
  }) async {
    await _delay();
    var sent = 0;
    for (final id in employeeIds) {
      final e = _byId(organizationId, id);
      if (e.accountStatus == AccountStatus.signedIn ||
          !e.status.isEmployed ||
          e.workEmail.isEmpty) {
        continue;
      }
      sent++;
      _replace(
        organizationId,
        e.copyWith(
          accountStatus: AccountStatus.invited,
          invitedAt: _now(),
          activity: [
            EmployeeActivity(
              text: 'Invitation sent to ${e.workEmail}',
              by: by,
              at: _now(),
              kind: ActivityKind.account,
            ),
            ...e.activity,
          ],
        ),
      );
    }
    return sent;
  }

  @override
  Future<int> changeBranch(
    String organizationId,
    List<String> employeeIds, {
    required String branchId,
    required String? managerId,
    required DateTime effectiveFrom,
    required String by,
  }) async {
    await _delay();
    var moved = 0;
    for (final id in employeeIds) {
      final e = _byId(organizationId, id);
      if (e.branchId == branchId) continue;
      moved++;
      _replace(
        organizationId,
        e.copyWith(
          branchId: branchId,
          managerId: managerId == id ? null : managerId,
          shift: 'General',
          activity: [
            EmployeeActivity(
              text:
                  'Branch changed · effective '
                  '${effectiveFrom.day}/${effectiveFrom.month}/${effectiveFrom.year}',
              by: by,
              at: _now(),
              kind: ActivityKind.moved,
            ),
            ...e.activity,
          ],
        ),
      );
    }
    return moved;
  }

  @override
  Future<void> sendPasswordReset(
    String organizationId,
    String employeeId,
  ) async {
    await _delay();
    final e = _byId(organizationId, employeeId);
    if (e.accountStatus != AccountStatus.signedIn) {
      throw const ValidationFailure(
        'This person hasn’t set up their account yet. Resend the invitation instead.',
      );
    }
  }

  // ---------- Custom fields ----------

  @override
  Future<List<CustomField>> customFields(String organizationId) async {
    await _delay();
    return List.unmodifiable(_fields[organizationId] ?? const []);
  }

  @override
  Future<CustomField> saveCustomField(
    String organizationId,
    CustomField field, {
    Map<String, String> renamedOptions = const {},
  }) async {
    await _delay();
    final list = _fields.putIfAbsent(organizationId, () => []);
    final errors = validateFieldDefinition(field, others: list);
    if (errors.isNotEmpty) {
      throw ValidationFailure('Check the field.', fieldErrors: errors);
    }
    final index = list.indexWhere((f) => f.id == field.id);
    if (index < 0) {
      final created = CustomField(
        id: 'cf-${_nextId++}',
        key: field.key,
        label: field.label.trim(),
        type: field.type,
        description: field.description,
        options: field.options,
        required: field.required,
        sensitive: field.sensitive,
        departments: field.departments,
        branchIds: field.branchIds,
        access: field.access,
        createdAt: _now(),
      );
      list.add(created);
      return created;
    }
    final before = list[index];
    final hasValues = _list(
      organizationId,
    ).any((e) => !isBlankValue(e.customValues[before.key]));
    if (!allowedTypeChanges(
      before.type,
      hasValues: hasValues,
    ).contains(field.type)) {
      throw const ValidationFailure(
        'The field type is locked because values exist.',
        fieldErrors: {'type': 'Locked because values exist.'},
      );
    }
    for (final option in before.options) {
      if (renamedOptions.containsKey(option)) continue;
      if (!field.options.contains(option) &&
          optionUsage(before, option, _list(organizationId)) > 0) {
        throw ValidationFailure(
          'Options in use can’t be removed.',
          fieldErrors: {'options': '“$option” is in use and can’t be removed.'},
        );
      }
    }
    if (renamedOptions.isNotEmpty) {
      final people = _list(organizationId);
      Object? rename(Object? v) => switch (v) {
        final String s => renamedOptions[s] ?? s,
        final List<Object?> l => [for (final x in l) rename(x)],
        _ => v,
      };
      for (var i = 0; i < people.length; i++) {
        final e = people[i];
        if (!e.customValues.containsKey(field.key)) continue;
        people[i] = e.copyWith(
          customValues: {
            ...e.customValues,
            field.key: rename(e.customValues[field.key]),
          },
        );
      }
    }
    list[index] = field;
    return field;
  }

  @override
  Future<void> reorderCustomFields(
    String organizationId,
    List<String> fieldIds,
  ) async {
    await _delay();
    final list = _fields[organizationId] ?? [];
    list.sort(
      (a, b) => fieldIds.indexOf(a.id).compareTo(fieldIds.indexOf(b.id)),
    );
  }

  // ---------- Import ----------

  @override
  Future<List<ImportRecord>> imports(String organizationId) async {
    await _delay();
    return List.unmodifiable(_imports[organizationId] ?? const []);
  }

  @override
  Future<ImportRecord> commitImport(
    String organizationId, {
    required String fileName,
    required ImportPlan plan,
    required List<NotImportedRow> skipped,
    required bool sendInvites,
    required String by,
  }) async {
    await _delay();
    final failed = <NotImportedRow>[];
    final createdIds = <String>[];
    final branchIds = <String>{};
    var updated = 0;
    final now = _now();

    for (final row in plan.toCreate) {
      final e = row.employee;
      // Re-checked at save time: someone may have added the same person
      // while the import was being reviewed.
      try {
        _checkUnique(organizationId, e.copyWith());
      } on ValidationFailure catch (f) {
        failed.add(
          NotImportedRow(
            rowNumber: row.rowNumber,
            name: e.fullName,
            code: e.code,
            email: e.workEmail,
            outcome: RowOutcome.failed,
            reason: f.fieldErrors.values.firstOrNull ?? f.message,
          ),
        );
        continue;
      }
      final invited = sendInvites && e.workEmail.isNotEmpty;
      final saved = e.copyWith(
        accountStatus: invited
            ? AccountStatus.invited
            : AccountStatus.noAccount,
        invitedAt: invited ? now : null,
        activity: [
          EmployeeActivity(
            text: invited ? 'Employee created and invited' : 'Employee created',
            by: '$by · import $fileName',
            at: now,
            kind: ActivityKind.created,
          ),
        ],
      );
      final withId = _withNewId(saved);
      _list(organizationId).add(withId);
      createdIds.add(withId.id);
      branchIds.add(withId.branchId);
    }

    for (final row in plan.toUpdate) {
      final e = row.employee;
      final current = _list(
        organizationId,
      ).where((x) => x.id == e.id).firstOrNull;
      if (current == null) {
        failed.add(
          NotImportedRow(
            rowNumber: row.rowNumber,
            name: e.fullName,
            code: e.code,
            outcome: RowOutcome.failed,
            reason: 'The existing employee was removed while this import ran.',
          ),
        );
        continue;
      }
      updated++;
      _replace(
        organizationId,
        e.copyWith(
          activity: [
            for (final c in row.changes)
              EmployeeActivity(
                text: '${c.field}: ${c.now} → ${c.incoming}',
                by: '$by · import $fileName',
                at: now,
              ),
            ...current.activity,
          ],
        ),
      );
    }

    final record = ImportRecord(
      id: 'imp-${_nextId++}',
      fileName: fileName,
      finishedAt: now,
      by: by,
      created: createdIds.length,
      updated: updated,
      skipped: skipped.length,
      failed: failed.length,
      branchIds: branchIds.toList(),
      invitationsSent: sendInvites
          ? createdIds
                .map((id) => _byId(organizationId, id))
                .where((e) => e.accountStatus == AccountStatus.invited)
                .length
          : 0,
      notImported: [...failed, ...skipped],
      createdEmployeeIds: createdIds,
    );
    _imports.putIfAbsent(organizationId, () => []).insert(0, record);
    return record;
  }

  Employee _withNewId(Employee e) => Employee(
    id: 'e-${_nextId++}',
    organizationId: e.organizationId,
    code: e.code,
    firstName: e.firstName,
    lastName: e.lastName,
    workEmail: e.workEmail,
    mobile: e.mobile,
    designation: e.designation,
    department: e.department,
    type: e.type,
    joiningDate: e.joiningDate,
    probationMonths: e.probationMonths,
    status: e.status,
    branchId: e.branchId,
    managerId: e.managerId,
    shift: e.shift,
    accountStatus: e.accountStatus,
    invitedAt: e.invitedAt,
    customValues: e.customValues,
    activity: e.activity,
  );
}
