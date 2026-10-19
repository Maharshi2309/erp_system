import 'dart:typed_data';

import '../../../core/errors/failure.dart';
import '../domain/branch.dart';
import '../domain/organization.dart';
import '../domain/organization_repository.dart';

/// Called when a new organization is created, so the demo sign-in data can
/// add the owner's membership (a real backend does this itself).
typedef OnOrganizationCreated =
    void Function(String accountId, Organization organization);

/// Counts employees still assigned to a branch (from employee records).
typedef EmployeeCounter = int Function(String organizationId, String branchId);

/// In-memory stand-in for the organization backend (no backend yet, D-01).
/// Seeded with the design's sample organizations; resets on reload.
class DemoOrganizationRepository implements OrganizationRepository {
  DemoOrganizationRepository({
    this.latency = const Duration(milliseconds: 500),
    this.onOrganizationCreated,
    this.countEmployees,
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now {
    _seed();
  }

  final Duration latency;
  final OnOrganizationCreated? onOrganizationCreated;

  /// When set, head counts come from employee records instead of the seed.
  final EmployeeCounter? countEmployees;

  Branch _counted(String organizationId, Branch b) => countEmployees == null
      ? b
      : b.copyWith(employeeCount: countEmployees!(organizationId, b.id));
  final DateTime Function() _now;

  final _organizations = <String, Organization>{};
  final _owners = <String, OwnerProfile>{};
  final _branches = <String, List<Branch>>{};
  final _bookmarks = <String, SetupBookmark>{};
  int _nextId = 1;

  Future<void> _delay() =>
      latency == Duration.zero ? Future.value() : Future.delayed(latency);

  void _seed() {
    const meridian = 'org_meridian-tex';
    _organizations[meridian] = Organization(
      id: meridian,
      name: 'Meridian Textiles',
      employeeRange: '201–500',
      legalName: 'Meridian Textiles Private Limited',
      industry: 'Textile manufacturing',
      registrationNumber: 'U17110GJ2015PTC085512',
      contactEmail: 'hr@meridiantex.in',
      contactPhone: '+91 79 4000 2210',
      address: '4th Floor, Shivalik Plaza, Ambawadi',
      city: 'Ahmedabad',
      state: 'Gujarat',
      pin: '380015',
      createdAt: DateTime(2025, 3, 3),
      updatedAt: DateTime(2026, 10, 2),
      updatedBy: 'Ankit Patel',
    );
    _owners[meridian] = const OwnerProfile(
      fullName: 'Ankit Patel',
      email: 'ankit@meridiantex.in',
      phone: '+91 98250 41736',
      designation: 'Managing Director',
    );
    final hq10to7 = HoursPresets.monToSat(hm(10, 0), hm(19, 0));
    final vadodaraHours = [
      for (var i = 0; i < 5; i++)
        DayHours(open: true, opensAt: hm(9, 0), closesAt: hm(18, 0)),
      DayHours(open: true, opensAt: hm(9, 0), closesAt: hm(14, 0)),
      const DayHours.closed(),
    ];
    _branches[meridian] = [
      Branch(
        id: 'b-ahm',
        name: 'Ahmedabad HQ',
        code: 'AHM-01',
        address: '4th floor, Shivalik Plaza, Ashram Road',
        city: 'Ahmedabad',
        state: 'Gujarat',
        pin: '380009',
        phone: '+91 79 4000 2210',
        hours: hq10to7,
        employeeCount: 126,
        attendance: const AttendanceRules(),
        holidays: HolidaySetup.from(HolidaySource.gujarat),
        leave: LeaveSetup.defaults,
        roles: const RolesSetup(
          manager: BranchManagerChoice.invite,
          managerEmail: 'kiran.d@meridiantex.in',
        ),
        reminders: const ReminderSettings(),
        reviewed: true,
        openedOn: DateTime(2019, 4, 1),
      ),
      Branch(
        id: 'b-sur',
        name: 'Surat',
        code: 'SUR-01',
        address: 'Plot 22, GIDC Sachin',
        city: 'Surat',
        state: 'Gujarat',
        pin: '394230',
        phone: '+91 261 400 7712',
        email: 'surat@meridiantex.in',
        hours: HoursPresets.monSat930,
        employeeCount: 78,
        attendance: const AttendanceRules(
          method: PunchMethod.both,
          shiftMode: ShiftMode.several,
        ),
        leave: LeaveSetup.defaults,
        openedOn: DateTime(2022, 8, 18),
      ),
      Branch(
        id: 'b-vad',
        name: 'Vadodara',
        code: 'VAD-01',
        address: 'Shed 7, Makarpura GIDC',
        city: 'Vadodara',
        state: 'Gujarat',
        pin: '390010',
        hours: vadodaraHours,
        employeeCount: 44,
        holidays: HolidaySetup.from(HolidaySource.national),
        openedOn: DateTime(2024, 1, 15),
      ),
      Branch(
        id: 'b-raj',
        name: 'Rajkot depot',
        code: 'RAJ-01',
        address: 'Aji GIDC',
        city: 'Rajkot',
        state: 'Gujarat',
        pin: '360003',
        hours: HoursPresets.monSat930,
        status: BranchStatus.inactive,
        openedOn: DateTime(2021, 6, 1),
      ),
    ];
    _bookmarks[meridian] = const SetupBookmark(
      branchId: 'b-sur',
      step: 'holidays',
    );

    const patel = 'org_pateldyes';
    _organizations[patel] = Organization(
      id: patel,
      name: 'Patel Dyes & Chemicals',
      employeeRange: '11–50',
      address: 'GIDC Phase 2',
      city: 'Vapi',
      state: 'Gujarat',
      pin: '396195',
      createdAt: DateTime(2024, 6, 10),
    );
    _owners[patel] = const OwnerProfile(
      fullName: 'Rina Patel',
      email: 'rina@pateldyes.in',
    );
    _branches[patel] = [
      Branch(
        id: 'b-vapi',
        name: 'Vapi',
        code: 'VAP-01',
        address: 'Plot 118, GIDC Phase 2',
        city: 'Vapi',
        state: 'Gujarat',
        pin: '396195',
        hours: HoursPresets.monSat930,
        employeeCount: 42,
        attendance: const AttendanceRules(),
        holidays: HolidaySetup.from(HolidaySource.gujarat),
        leave: LeaveSetup.defaults,
        roles: const RolesSetup(),
        reviewed: true,
      ),
    ];
  }

  Organization _org(String id) {
    final org = _organizations[id];
    if (org == null) throw const NotFoundFailure();
    return org;
  }

  List<Branch> _list(String organizationId) {
    _org(organizationId);
    return _branches.putIfAbsent(organizationId, () => []);
  }

  @override
  Future<Organization> createOrganization({
    required String ownerAccountId,
    required String ownerName,
    required String ownerEmail,
    required String name,
    required String employeeRange,
    Uint8List? logo,
  }) async {
    await _delay();
    final trimmed = name.trim();
    if (trimmed.length < 2) {
      throw const ValidationFailure(
        'Check the organisation name.',
        fieldErrors: {'name': 'Use at least 2 characters.'},
      );
    }
    final slug = trimmed
        .toLowerCase()
        .replaceAll(RegExp('[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    var id = 'org_$slug';
    while (_organizations.containsKey(id)) {
      id = 'org_$slug-${_nextId++}';
    }
    final now = _now();
    final organization = Organization(
      id: id,
      name: trimmed,
      employeeRange: employeeRange,
      logo: logo,
      contactEmail: ownerEmail,
      createdAt: now,
      updatedAt: now,
      updatedBy: ownerName,
    );
    _organizations[id] = organization;
    _branches[id] = [];
    onOrganizationCreated?.call(ownerAccountId, organization);
    return organization;
  }

  @override
  Future<Organization> organization(String organizationId) async {
    await _delay();
    return _org(organizationId);
  }

  @override
  Future<Organization> updateOrganization(
    Organization organization, {
    required String updatedBy,
  }) async {
    await _delay();
    _org(organization.id);
    if (organization.name.trim().isEmpty) {
      throw const ValidationFailure(
        'Enter the display name.',
        fieldErrors: {'name': 'Enter the display name.'},
      );
    }
    final saved = organization.copyWith(
      updatedAt: _now(),
      updatedBy: updatedBy,
    );
    _organizations[organization.id] = saved;
    return saved;
  }

  @override
  Future<OwnerProfile?> ownerProfile(String organizationId) async {
    await _delay();
    _org(organizationId);
    return _owners[organizationId];
  }

  @override
  Future<void> saveOwnerProfile(
    String organizationId,
    OwnerProfile profile,
  ) async {
    await _delay();
    _org(organizationId);
    if (profile.fullName.trim().isEmpty) {
      throw const ValidationFailure(
        'Enter your full name.',
        fieldErrors: {'name': 'Enter your full name.'},
      );
    }
    _owners[organizationId] = profile;
  }

  @override
  Future<List<Branch>> branches(String organizationId) async {
    await _delay();
    return List.unmodifiable([
      for (final b in _list(organizationId)) _counted(organizationId, b),
    ]);
  }

  /// [branch] is new unless [existing] is set; a new branch's ID is a
  /// placeholder and must not exempt it from the checks.
  void _checkUnique(
    String organizationId,
    Branch branch, {
    bool existing = false,
  }) {
    for (final other in _list(organizationId)) {
      if (existing && other.id == branch.id) continue;
      if (other.name.trim().toLowerCase() == branch.name.trim().toLowerCase()) {
        throw const ValidationFailure(
          'You already have a branch with this name.',
          fieldErrors: {'name': 'You already have a branch with this name.'},
        );
      }
      if (branch.code.isNotEmpty &&
          other.code.toUpperCase() == branch.code.toUpperCase()) {
        throw ValidationFailure(
          'That branch code is taken.',
          fieldErrors: {
            'code':
                '${branch.code.toUpperCase()} is already used by ${other.name}. '
                'Choose another code.',
          },
        );
      }
    }
  }

  @override
  Future<Branch> createBranch(String organizationId, Branch branch) async {
    await _delay();
    _checkUnique(organizationId, branch);
    final list = _list(organizationId);
    final code = branch.code.isNotEmpty
        ? branch.code
        : _suggestCode(list, branch.name);
    final created = Branch(
      id: 'b-${_nextId++}',
      name: branch.name.trim(),
      code: code,
      address: branch.address,
      city: branch.city,
      state: branch.state,
      pin: branch.pin,
      phone: branch.phone,
      email: branch.email,
      timeZone: branch.timeZone,
      hours: branch.hours,
      openedOn: _now(),
    );
    list.add(created);
    return created;
  }

  /// "SUR-01" from "Surat"; the number grows if the letters are taken.
  static String _suggestCode(List<Branch> existing, String name) {
    final letters = name.replaceAll(RegExp('[^A-Za-z]'), '').toUpperCase();
    final stem = (letters.length >= 3
        ? letters.substring(0, 3)
        : letters.padRight(3, 'X'));
    for (var n = 1; ; n++) {
      final code = '$stem-${n.toString().padLeft(2, '0')}';
      if (!existing.any((b) => b.code == code)) return code;
    }
  }

  @override
  Future<Branch> updateBranch(String organizationId, Branch branch) async {
    await _delay();
    final list = _list(organizationId);
    final index = list.indexWhere((b) => b.id == branch.id);
    if (index < 0) throw const NotFoundFailure();
    _checkUnique(organizationId, branch, existing: true);
    list[index] = branch;
    return branch;
  }

  @override
  Future<Branch> setBranchStatus(
    String organizationId,
    String branchId,
    BranchStatus status,
  ) async {
    await _delay();
    final list = _list(organizationId);
    final index = list.indexWhere((b) => b.id == branchId);
    if (index < 0) throw const NotFoundFailure();
    final branch = _counted(organizationId, list[index]);
    if (status == BranchStatus.inactive && branch.employeeCount > 0) {
      throw ValidationFailure(
        '${branch.employeeCount} employees must be moved to another branch '
        'first. History and reports are kept.',
      );
    }
    return list[index] = branch.copyWith(status: status);
  }

  @override
  Future<SetupBookmark?> setupBookmark(String organizationId) async {
    await _delay();
    return _bookmarks[organizationId];
  }

  @override
  Future<void> saveSetupBookmark(
    String organizationId,
    SetupBookmark bookmark,
  ) async {
    _bookmarks[organizationId] = bookmark;
  }
}
