import 'package:flutter_riverpod/flutter_riverpod.dart';

/// "Now" as a UTC instant. Tests and screenshots override it with a fixed
/// moment so date-based figures are stable. Screens convert it to local
/// wall time with `zoned_time.dart` (organization or branch time zone).
final clockProvider = Provider<DateTime Function()>(
  (ref) =>
      () => DateTime.now().toUtc(),
);
