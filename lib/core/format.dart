/// Human-readable byte size, e.g. "18,4 MB".
String formatBytes(int bytes) {
  if (bytes <= 0) return '--';
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB'];
  var value = bytes / 1024;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final text = value >= 10 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
  return '${text.replaceAll('.', ',')} ${units[unit]}';
}

/// "12/03/2026"
String formatDate(DateTime date) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(date.day)}/${two(date.month)}/${date.year}';
}

/// "123 456" — grouped so the code is easy to read out loud over the phone.
String formatAccessCode(String code) {
  if (code.length != 6) return code;
  return '${code.substring(0, 3)} ${code.substring(3)}';
}
