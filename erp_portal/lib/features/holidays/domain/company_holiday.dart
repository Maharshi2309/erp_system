import 'package:flutter/foundation.dart';

import '../../organization/domain/branch.dart';

/// A holiday on the organization calendar (boards S62–S64): for every
/// branch or for selected ones, one day or a range, fixed or optional.
@immutable
class CompanyHoliday {
  const CompanyHoliday({
    required this.id,
    required this.name,
    required this.date,
    DateTime? endDate,
    this.category = HolidayCategory.festival,
    this.branchIds = const [],
    this.optional = false,
    this.description = '',
    this.createdBy = '',
  }) : endDate = endDate ?? date;

  final String id;
  final String name;

  /// Floating dates; [endDate] equals [date] for a single day.
  final DateTime date;
  final DateTime endDate;
  final HolidayCategory category;

  /// Empty means the whole organization, including future branches.
  final List<String> branchIds;

  /// Employees choose to take it with an optional-holiday request.
  final bool optional;
  final String description;
  final String createdBy;

  bool get orgWide => branchIds.isEmpty;
  bool get isRange => endDate != date;

  bool appliesTo(String? branchId) =>
      branchIds.isEmpty || branchIds.contains(branchId);

  bool covers(DateTime d) => !d.isBefore(date) && !d.isAfter(endDate);

  /// The days it covers.
  List<DateTime> get days => [
    for (
      var d = date;
      !d.isAfter(endDate);
      d = DateTime(d.year, d.month, d.day + 1)
    )
      d,
  ];

  HolidayItem itemOn(DateTime d) => HolidayItem(
    name: name,
    date: d,
    custom: true,
    category: category,
    optional: optional,
    orgWide: orgWide,
    description: description,
  );

  CompanyHoliday copyWith({
    String? id,
    String? name,
    DateTime? date,
    DateTime? endDate,
    HolidayCategory? category,
    List<String>? branchIds,
    bool? optional,
    String? description,
    String? createdBy,
  }) => CompanyHoliday(
    id: id ?? this.id,
    name: name ?? this.name,
    date: date ?? this.date,
    endDate: endDate ?? this.endDate,
    category: category ?? this.category,
    branchIds: branchIds ?? this.branchIds,
    optional: optional ?? this.optional,
    description: description ?? this.description,
    createdBy: createdBy ?? this.createdBy,
  );
}
