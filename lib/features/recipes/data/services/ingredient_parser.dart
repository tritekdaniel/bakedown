import '../models/measurement.dart';

class IngredientParser {
  static final _checkboxRe = RegExp(r'^(- \[[ x]\] )(.*)$');

  static String? scaleLine(String checkboxLine, double factor) {
    final m = _checkboxRe.firstMatch(checkboxLine);
    if (m == null) return null;

    final text = m.group(2)!;
    final measurement = Measurement.parse(text);
    if (measurement == null) return null;

    final scaled = measurement.toScaledString(factor);
    return '${m.group(1)}$scaled';
  }

  static Measurement? parseMeasurement(String checkboxLine) {
    final m = _checkboxRe.firstMatch(checkboxLine);
    if (m == null) return null;
    return Measurement.parse(m.group(2)!);
  }

  static String reconstructLine(Measurement measurement, {bool checked = false}) {
    final check = checked ? '- [x] ' : '- [ ] ';
    final text = measurement.toScaledString(1.0);
    return '$check$text';
  }
}
