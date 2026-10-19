/// Up to two uppercase initials from a name, e.g. "Ankit Patel" → "AP".
String initialsOf(String name) {
  final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  final letters = words.take(2).map((w) => w[0].toUpperCase()).join();
  return letters.isEmpty ? '··' : letters;
}
