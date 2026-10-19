import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';

import '../domain/employee_import.dart';

/// Reads an .xlsx or .csv file into text cells, checking type, size, row
/// count and headers (PRD §6.4, board S46).
ImportTable readSpreadsheet(String fileName, Uint8List bytes) {
  final lower = fileName.toLowerCase();
  final isXlsx = lower.endsWith('.xlsx');
  final isCsv = lower.endsWith('.csv');
  if (!isXlsx && !isCsv) {
    throw ImportFileProblem(
      'We can’t read “$fileName”',
      'Only .xlsx and .csv files work. In Excel, use File › Save as › '
          'Excel Workbook, then try again.',
    );
  }
  if (bytes.length > maxImportBytes) {
    throw ImportFileProblem(
      '“$fileName” is larger than 5 MB',
      'Split it into smaller files, or remove extra sheets and columns.',
    );
  }

  late final List<List<String>> table;
  var sheetName = '';
  try {
    if (isCsv) {
      table = parseCsv(utf8.decode(bytes, allowMalformed: true));
    } else {
      final book = Excel.decodeBytes(bytes);
      final entry = book.tables.entries.firstWhere(
        (e) => e.value.maxRows > 0,
        orElse: () => throw const ImportFileProblem(
          'The file is empty',
          'Add a header row and at least one employee, then try again.',
        ),
      );
      sheetName = entry.key;
      table = [
        for (final row in entry.value.rows)
          [for (final cell in row) _cellText(cell?.value)],
      ];
    }
  } on ImportFileProblem {
    rethrow;
  } on Object {
    throw ImportFileProblem(
      'We can’t read “$fileName”',
      'The file may be damaged or password-protected. Open it in Excel, '
          'save a copy, then try again.',
    );
  }

  final rows = table.where((r) => r.any((c) => c.trim().isNotEmpty)).toList();
  if (rows.isEmpty) {
    throw const ImportFileProblem(
      'The file is empty',
      'Add a header row and at least one employee, then try again.',
    );
  }
  final headers = rows.first.map((h) => h.trim()).toList();
  while (headers.isNotEmpty && headers.last.isEmpty) {
    headers.removeLast();
  }
  if (headers.isEmpty || headers.any((h) => h.isEmpty)) {
    throw const ImportFileProblem(
      'The first row must be headers',
      'Give every column a name in row 1, e.g. Employee ID, First name.',
    );
  }
  final lowerHeaders = headers.map((h) => h.toLowerCase()).toList();
  if (lowerHeaders.toSet().length != headers.length) {
    throw const ImportFileProblem(
      'Two columns have the same header',
      'Rename one of them so every column name is different.',
    );
  }
  final data = rows.skip(1).toList();
  if (data.isEmpty) {
    throw const ImportFileProblem(
      'There are no employees in the file',
      'Add one row per employee under the header row.',
    );
  }
  if (data.length > maxImportRows) {
    throw ImportFileProblem(
      'The file has ${data.length} rows',
      'Up to 2,000 rows can be imported at once. Split the file and import '
          'each part.',
    );
  }
  return ImportTable(
    fileName: fileName,
    sheetName: sheetName,
    headers: headers,
    sizeBytes: bytes.length,
    rows: [
      for (final r in data)
        [
          for (var c = 0; c < headers.length; c++)
            c < r.length ? r[c].trim() : '',
        ],
    ],
  );
}

String _cellText(CellValue? value) => switch (value) {
  null => '',
  TextCellValue(:final value) => value.toString(),
  IntCellValue(:final value) => '$value',
  DoubleCellValue(:final value) =>
    value == value.truncateToDouble() ? '${value.toInt()}' : '$value',
  DateCellValue(:final year, :final month, :final day) =>
    '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}',
  DateTimeCellValue(:final year, :final month, :final day) =>
    '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}',
  BoolCellValue(:final value) => value ? 'Yes' : 'No',
  _ => value.toString(),
};

/// RFC 4180 CSV: quoted fields, doubled quotes, CRLF or LF, optional BOM.
List<List<String>> parseCsv(String text) {
  final source = text.startsWith('﻿') ? text.substring(1) : text;
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var quoted = false;
  for (var i = 0; i < source.length; i++) {
    final ch = source[i];
    if (quoted) {
      if (ch == '"') {
        if (i + 1 < source.length && source[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        field.write(ch);
      }
    } else if (ch == '"' && field.isEmpty) {
      quoted = true;
    } else if (ch == ',') {
      row.add(field.toString());
      field.clear();
    } else if (ch == '\n' || ch == '\r') {
      if (ch == '\r' && i + 1 < source.length && source[i + 1] == '\n') i++;
      row.add(field.toString());
      field.clear();
      rows.add(row);
      row = <String>[];
    } else {
      field.write(ch);
    }
  }
  if (field.isNotEmpty || row.isNotEmpty) {
    row.add(field.toString());
    rows.add(row);
  }
  return rows;
}

/// One-sheet workbook from text rows (first row = headers).
Uint8List buildXlsx(String sheetName, List<List<String>> rows) {
  final book = Excel.createExcel();
  final defaultSheet = book.getDefaultSheet()!;
  book.rename(defaultSheet, sheetName);
  final sheet = book[sheetName];
  for (final row in rows) {
    sheet.appendRow([for (final cell in row) TextCellValue(cell)]);
  }
  return Uint8List.fromList(book.encode()!);
}

String buildCsv(List<List<String>> rows) => rows
    .map(
      (r) => r
          .map(
            (c) => c.contains(RegExp('[",\n\r]'))
                ? '"${c.replaceAll('"', '""')}"'
                : c,
          )
          .join(','),
    )
    .join('\r\n');
