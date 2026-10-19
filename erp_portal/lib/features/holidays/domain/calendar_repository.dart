import 'company_holiday.dart';
import 'work_calendar.dart';

/// The organization holiday calendar (boards S62–S65) and dated schedule
/// assignments (board S66). Branch lists from setup stay on the branch.
abstract interface class CalendarRepository {
  Future<List<CompanyHoliday>> holidays(String organizationId);

  /// Creates (empty id) or updates a holiday. Past days can't change.
  Future<CompanyHoliday> saveHoliday(
    String organizationId,
    CompanyHoliday holiday,
  );

  Future<void> deleteHoliday(String organizationId, String id);

  /// Adds checked import rows in one go (board S65).
  Future<List<CompanyHoliday>> importHolidays(
    String organizationId,
    List<CompanyHoliday> rows,
  );

  Future<List<ScheduleAssignment>> assignments(String organizationId);

  Future<ScheduleAssignment> addAssignment(
    String organizationId,
    ScheduleAssignment assignment,
  );
}
