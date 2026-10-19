import 'custom_field.dart';
import 'employee.dart';
import 'employee_import.dart';

/// Employee records, custom field definitions and imports. Implementations
/// throw a `Failure` when an operation is refused.
abstract interface class EmployeeRepository {
  Future<List<Employee>> employees(String organizationId);

  /// Creates the employee; with [sendInvite] an invitation email goes out.
  Future<Employee> create(
    String organizationId,
    Employee employee, {
    required bool sendInvite,
    required String by,
  });

  /// Saves changes. [notes] describe each change for the activity history.
  Future<Employee> update(
    String organizationId,
    Employee employee, {
    required String by,
    required List<String> notes,
  });

  /// Lifecycle: deactivate, reactivate, notice period, terminate.
  Future<Employee> setStatus(
    String organizationId,
    String employeeId,
    EmploymentStatus status, {
    required String by,
    String reason = '',
    DateTime? lastWorkingDay,
  });

  /// Returns how many invitations were sent (signed-in people are skipped).
  Future<int> resendInvites(
    String organizationId,
    List<String> employeeIds, {
    required String by,
  });

  /// Moves people to [branchId]; each reports to [managerId] afterwards.
  Future<int> changeBranch(
    String organizationId,
    List<String> employeeIds, {
    required String branchId,
    required String? managerId,
    required DateTime effectiveFrom,
    required String by,
  });

  /// Sends a password reset link. Passwords are never shown or set here.
  Future<void> sendPasswordReset(String organizationId, String employeeId);

  /// People assigned to [branchId], including inactive ones (terminated
  /// people are archived). Used for branch head counts.
  int countInBranch(String organizationId, String branchId);

  Future<List<CustomField>> customFields(String organizationId);

  /// Creates or updates a field. [renamedOptions] (old → new) also updates
  /// employees' saved values; options in use can be renamed, not removed.
  Future<CustomField> saveCustomField(
    String organizationId,
    CustomField field, {
    Map<String, String> renamedOptions = const {},
  });

  Future<void> reorderCustomFields(
    String organizationId,
    List<String> fieldIds,
  );

  Future<List<ImportRecord>> imports(String organizationId);

  /// Saves [plan] row by row; a row that fails is listed, never half-saved.
  Future<ImportRecord> commitImport(
    String organizationId, {
    required String fileName,
    required ImportPlan plan,
    required List<NotImportedRow> skipped,
    required bool sendInvites,
    required String by,
  });
}
