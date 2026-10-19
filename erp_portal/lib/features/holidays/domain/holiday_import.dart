import 'package:intl/intl.dart';

import '../../organization/domain/branch.dart';
import 'company_holiday.dart';

enum HolidayRowStatus { ready, duplicate, invalid }

/// One checked import row (board S65).
typedef HolidayRow = ({
  int row,
  String dateText,
  String name,
  String scopeText,
  HolidayRowStatus status,
  String note,
  CompanyHoliday? holiday,
});

/// Columns of the import template, in order.
const holidayTemplateHeaders = ['Date', 'Holiday', 'Applies to', 'Category'];

/// "14/01/2027", "2027-01-14" or "14 Jan 2027"; null with a reason.
(DateTime?, String) parseHolidayDate(String text) {
  final t = text.trim();
  final dmy = RegExp(r'^(\d{1,2})[/.-](\d{1,2})[/.-](\d{4})$').firstMatch(t);
  final ymd = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(t);
  int? y, m, d;
  if (dmy != null) {
    d = int.parse(dmy.group(1)!);
    m = int.parse(dmy.group(2)!);
    y = int.parse(dmy.group(3)!);
  } else if (ymd != null) {
    y = int.parse(ymd.group(1)!);
    m = int.parse(ymd.group(2)!);
    d = int.parse(ymd.group(3)!);
  } else {
    try {
      final p = DateFormat('d MMM y').parseStrict(t);
      return (DateTime(p.year, p.month, p.day), '');
    } on FormatException {
      return (null, 'Use DD/MM/YYYY');
    }
  }
  if (m < 1 || m > 12) return (null, 'There is no month $m');
  final days = DateTime(y, m + 1, 0).day;
  if (d < 1 || d > days) {
    return (
      null,
      '${DateFormat('MMMM').format(DateTime(y, m))} has $days days',
    );
  }
  return (DateTime(y, m, d), '');
}

/// Checks spreadsheet [rows] (without the header) against the calendar.
/// Row numbers start at 2 (row 1 is the header).
List<HolidayRow> checkHolidayRows(
  List<List<String>> rows, {
  required List<CompanyHoliday> existing,
  required List<Branch> branches,
  required DateTime today,
}) {
  final out = <HolidayRow>[];
  final seen = <String, int>{};
  for (var i = 0; i < rows.length; i++) {
    final cells = rows[i];
    String cell(int c) => c < cells.length ? cells[c].trim() : '';
    final n = i + 2;
    final dateText = cell(0);
    final name = cell(1);
    final scopeText = cell(2).isEmpty ? 'All branches' : cell(2);
    if (dateText.isEmpty && name.isEmpty) continue;
    HolidayRow bad(String note) => (
      row: n,
      dateText: dateText,
      name: name,
      scopeText: scopeText,
      status: HolidayRowStatus.invalid,
      note: note,
      holiday: null,
    );
    final (date, why) = parseHolidayDate(dateText);
    if (date == null) {
      out.add(bad(dateText.isEmpty ? 'Date is missing' : why));
      continue;
    }
    if (name.length < 2) {
      out.add(bad('Holiday name is missing'));
      continue;
    }
    if (date.isBefore(today)) {
      out.add(bad('Date has passed'));
      continue;
    }
    final optional = scopeText.toLowerCase().startsWith('optional');
    final ids = <String>[];
    if (!optional && scopeText.toLowerCase() != 'all branches') {
      final unknown = <String>[];
      for (final part in scopeText.split(RegExp(r'[,;]'))) {
        final p = part.trim().toLowerCase();
        if (p.isEmpty) continue;
        final b = branches
            .where(
              (b) =>
                  b.name.toLowerCase() == p ||
                  b.code.toLowerCase() == p ||
                  b.name.toLowerCase().split(' ').first == p,
            )
            .firstOrNull;
        if (b == null) {
          unknown.add(part.trim());
        } else {
          ids.add(b.id);
        }
      }
      if (unknown.isNotEmpty) {
        out.add(bad('No branch called “${unknown.first}”'));
        continue;
      }
    }
    final key = '${date.toIso8601String()}|${name.toLowerCase()}';
    final earlier = seen[key];
    if (earlier != null) {
      out.add((
        row: n,
        dateText: dateText,
        name: name,
        scopeText: scopeText,
        status: HolidayRowStatus.duplicate,
        note: 'Same as row $earlier',
        holiday: null,
      ));
      continue;
    }
    seen[key] = n;
    final clash = existing
        .where(
          (h) =>
              h.covers(date) &&
              (h.name.toLowerCase() == name.toLowerCase() ||
                  (h.orgWide && ids.isEmpty)),
        )
        .firstOrNull;
    if (clash != null) {
      out.add((
        row: n,
        dateText: dateText,
        name: name,
        scopeText: scopeText,
        status: HolidayRowStatus.duplicate,
        note: clash.name.toLowerCase() == name.toLowerCase()
            ? 'Already exists for ${date.year}'
            : 'Already “${clash.name}” that day',
        holiday: null,
      ));
      continue;
    }
    final category = switch (cell(3).toLowerCase()) {
      'national' => HolidayCategory.national,
      'regional' => HolidayCategory.regional,
      'company' => HolidayCategory.company,
      _ => HolidayCategory.festival,
    };
    out.add((
      row: n,
      dateText: dateText,
      name: name,
      scopeText: scopeText,
      status: HolidayRowStatus.ready,
      note: '',
      holiday: CompanyHoliday(
        id: '',
        name: name,
        date: date,
        category: category,
        branchIds: ids,
        optional: optional,
      ),
    ));
  }
  return out;
}

/// Holidays on [date] that a new one for [branchIds] would overlap (board
/// S64 duplicate warning).
List<CompanyHoliday> overlapping(List<CompanyHoliday> all, CompanyHoliday h) =>
    [
      for (final o in all)
        if (o.id != h.id &&
            !o.endDate.isBefore(h.date) &&
            !o.date.isAfter(h.endDate) &&
            (o.orgWide || h.orgWide || o.branchIds.any(h.branchIds.contains)))
          o,
    ];
