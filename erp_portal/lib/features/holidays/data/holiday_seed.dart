import '../../organization/domain/branch.dart';
import '../domain/company_holiday.dart';

/// DEMO ONLY — the 2026 organization calendar from boards S62–S63.
List<CompanyHoliday> demoCompanyHolidays() {
  var n = 1;
  CompanyHoliday h(
    String name,
    DateTime date, {
    DateTime? end,
    HolidayCategory category = HolidayCategory.festival,
    List<String> branches = const [],
    bool optional = false,
  }) => CompanyHoliday(
    id: 'hol-${n++}',
    name: name,
    date: date,
    endDate: end,
    category: category,
    branchIds: branches,
    optional: optional,
    createdBy: 'Hetal Shah',
  );

  return [
    h('Uttarayan', DateTime(2026, 1, 14)),
    h(
      'Republic Day',
      DateTime(2026, 1, 26),
      category: HolidayCategory.national,
    ),
    h('Holi', DateTime(2026, 3, 4)),
    h('Gujarat Day', DateTime(2026, 5, 1), category: HolidayCategory.regional),
    h(
      'Independence Day',
      DateTime(2026, 8, 15),
      category: HolidayCategory.national,
    ),
    h('Raksha Bandhan', DateTime(2026, 8, 28), branches: const ['b-sur']),
    h('Janmashtami', DateTime(2026, 9, 4)),
    h(
      'Gandhi Jayanti',
      DateTime(2026, 10, 2),
      category: HolidayCategory.national,
    ),
    h('Dussehra', DateTime(2026, 10, 20)),
    h('Diwali', DateTime(2026, 11, 8)),
    h('Diwali break', DateTime(2026, 11, 9), end: DateTime(2026, 11, 10)),
    h('Bhai Dooj', DateTime(2026, 11, 11), branches: const ['b-ahm', 'b-vad']),
    h(
      'Guru Nanak Jayanti',
      DateTime(2026, 11, 24),
      category: HolidayCategory.national,
      optional: true,
    ),
    h('Christmas', DateTime(2026, 12, 25), optional: true),
  ];
}
