import 'package:timezone/data/latest_10y.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

bool _loaded = false;

tz.Location _location(String zone) {
  if (!_loaded) {
    tz_data.initializeTimeZones();
    _loaded = true;
  }
  try {
    return tz.getLocation(zone);
  } on Object {
    return tz.getLocation('Asia/Kolkata');
  }
}

/// The wall-clock time in [zone] at [instant], as a plain ("floating")
/// DateTime: its fields are the local date and time there. Dates stored in
/// the app (joining dates, holidays, work days) are floating too, so they
/// compare field by field.
DateTime wallTime(DateTime instant, String zone) {
  final t = tz.TZDateTime.from(instant, _location(zone));
  return DateTime(t.year, t.month, t.day, t.hour, t.minute, t.second);
}

/// The UTC instant of [wall] (floating date and time) in [zone].
DateTime instantOf(DateTime wall, String zone) => tz.TZDateTime(
  _location(zone),
  wall.year,
  wall.month,
  wall.day,
  wall.hour,
  wall.minute,
  wall.second,
).toUtc();

/// Midnight of [d] (floating).
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
