/// DEMO ONLY — a stable pseudo-random number for [key] (FNV-1a), so demo
/// data generated in different places agrees (e.g. an absent day in the
/// attendance seed is the day the leave seed books leave).
int demoRandom(String key) {
  var h = 2166136261;
  for (final c in key.codeUnits) {
    h = ((h ^ c) * 16777619) & 0x7fffffff;
  }
  return h;
}

/// True when the demo attendance generator leaves [employeeCode] absent on
/// [date] (floating).
bool demoAbsent(String employeeCode, DateTime date) =>
    demoRandom(
          '$employeeCode${DateTime(date.year, date.month, date.day).toIso8601String()}',
        ) %
        100 <
    5;
