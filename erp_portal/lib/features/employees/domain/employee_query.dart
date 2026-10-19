import 'package:flutter/foundation.dart';

import 'employee.dart';

enum EmployeeSort {
  name('Employee'),
  department('Department'),
  joined('Joined'),
  code('Employee ID');

  const EmployeeSort(this.label);

  final String label;
}

/// Directory search, filters, sort and page (boards S39–S41).
@immutable
class EmployeeQuery {
  const EmployeeQuery({
    this.search = '',
    this.branchId,
    this.department,
    this.status,
    this.type,
    this.sort = EmployeeSort.name,
    this.ascending = true,
    this.page = 0,
    this.pageSize = 10,
  });

  final String search;
  final String? branchId;
  final String? department;
  final EmploymentStatus? status;
  final EmploymentType? type;
  final EmployeeSort sort;
  final bool ascending;
  final int page;
  final int pageSize;

  int get activeFilters =>
      [branchId, department, status, type].where((f) => f != null).length;

  bool get isFiltered => search.trim().isNotEmpty || activeFilters > 0;

  EmployeeQuery copyWith({
    String? search,
    Object? branchId = _keep,
    Object? department = _keep,
    Object? status = _keep,
    Object? type = _keep,
    EmployeeSort? sort,
    bool? ascending,
    int? page,
    int? pageSize,
  }) => EmployeeQuery(
    search: search ?? this.search,
    branchId: identical(branchId, _keep) ? this.branchId : branchId as String?,
    department: identical(department, _keep)
        ? this.department
        : department as String?,
    status: identical(status, _keep)
        ? this.status
        : status as EmploymentStatus?,
    type: identical(type, _keep) ? this.type : type as EmploymentType?,
    sort: sort ?? this.sort,
    ascending: ascending ?? this.ascending,
    // Any change other than paging goes back to the first page.
    page: page ?? 0,
    pageSize: pageSize ?? this.pageSize,
  );
}

const _keep = Object();

/// Filters and sorts [all]; paging is applied by [pageOf].
List<Employee> applyQuery(List<Employee> all, EmployeeQuery q) {
  final terms = q.search.trim().toLowerCase();
  final digits = terms.replaceAll(RegExp(r'\D'), '');
  final list = all.where((e) {
    if (q.branchId != null && e.branchId != q.branchId) return false;
    if (q.department != null && e.department != q.department) return false;
    if (q.status != null && e.status != q.status) return false;
    if (q.type != null && e.type != q.type) return false;
    if (terms.isEmpty) return true;
    final text = '${e.fullName} ${e.displayName} ${e.code} ${e.workEmail}'
        .toLowerCase();
    return text.contains(terms) ||
        (digits.length >= 4 &&
            e.mobile.replaceAll(RegExp(r'\D'), '').contains(digits));
  }).toList();

  int compare(Employee a, Employee b) => switch (q.sort) {
    EmployeeSort.name => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    EmployeeSort.department => a.department.compareTo(b.department),
    EmployeeSort.joined => a.joiningDate.compareTo(b.joiningDate),
    EmployeeSort.code => a.code.compareTo(b.code),
  };
  list.sort((a, b) {
    final c = compare(a, b);
    // Stable tie-break so pages never shuffle.
    final result = c != 0 ? c : a.code.compareTo(b.code);
    return q.ascending ? result : -result;
  });
  return list;
}

List<Employee> pageOf(List<Employee> filtered, EmployeeQuery q) {
  final start = q.page * q.pageSize;
  if (start >= filtered.length) return const [];
  return filtered.sublist(
    start,
    (start + q.pageSize).clamp(0, filtered.length),
  );
}
