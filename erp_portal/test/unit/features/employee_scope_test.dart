import 'package:erp_portal/core/permissions/system_roles.dart';
import 'package:erp_portal/features/employees/data/demo_employee_repository.dart';
import 'package:erp_portal/features/employees/presentation/providers/employee_providers.dart';
import 'package:erp_portal/shared/models/app_session.dart';
import 'package:flutter_test/flutter_test.dart';

AppSession session(
  SystemRole role, {
  List<String> branches = const [],
  String? code,
}) => AppSession(
  userId: 'u',
  displayName: 'X',
  email: 'x@x.in',
  organizationId: 'org_meridian-tex',
  organizationName: 'Meridian Textiles',
  role: role,
  branchIds: branches,
  employeeId: code,
);

void main() {
  test('each role sees only its data scope (PRD §3.1)', () async {
    final people = await DemoEmployeeRepository(
      latency: Duration.zero,
    ).employees('org_meridian-tex');
    int count(AppSession s) {
      final self = people.where((e) => e.code == s.employeeId).firstOrNull;
      return people.where((e) => canSeeEmployee(s, e, self: self)).length;
    }

    expect(count(session(SystemRole.owner)), 248);
    expect(count(session(SystemRole.hrAdmin)), 248);
    expect(count(session(SystemRole.branchManager, branches: ['b-sur'])), 78);
    expect(
      count(
        session(SystemRole.attendanceManager, branches: ['b-sur', 'b-vad']),
      ),
      122,
    );
    final aarav = people.firstWhere((e) => e.code == 'EMP-0201');
    final team = people.where((e) => e.managerId == aarav.id).length;
    expect(
      count(session(SystemRole.leaveApprover, code: 'EMP-0201')),
      team + 1,
    );
    expect(count(session(SystemRole.employee, code: 'EMP-0229')), 1);
    expect(
      count(session(SystemRole.employee)),
      0,
      reason: 'no employee record, nothing visible',
    );
  });
}
