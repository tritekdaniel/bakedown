class Measurement {
  final double quantity;
  final String unitWord;
  final String rest;

  Measurement({
    required this.quantity,
    required this.unitWord,
    required this.rest,
  });

  static final _patterns = <RegExp>[
    RegExp(r'^(\d+)\s+(\d+)/(\d+)\s+(.+)$'),
    RegExp(r'^(\d+)-(\d+)\s+(.+)$'),
    RegExp(r'^(\d+)/(\d+)\s+(.+)$'),
    RegExp(r'^(\d+)\s+(\d+)/(\d+)$'),
    RegExp(r'^(\d+)/(\d+)$'),
    RegExp(r'^(\d+)$'),
    RegExp(r'^(\d+(?:\.\d+)?)\s+(.+)$'),
  ];

  static final _unicodeFrac = <String, String>{
    '\u00BD': ' 1/2', // ½
    '\u00BC': ' 1/4', // ¼
    '\u00BE': ' 3/4', // ¾
    '\u2153': ' 1/3', // ⅓
    '\u2154': ' 2/3', // ⅔
    '\u215B': ' 1/8', // ⅛
    '\u215C': ' 3/8', // ⅜
    '\u215D': ' 5/8', // ⅝
    '\u215E': ' 7/8', // ⅞
  };

  static String _normalize(String text) {
    var result = text;
    for (final e in _unicodeFrac.entries) {
      result = result.replaceAll(e.key, e.value);
    }
    return result;
  }

  static Measurement? parse(String text) {
    final normalized = _normalize(text).trim();
    for (var i = 0; i < _patterns.length; i++) {
      final m = _patterns[i].firstMatch(normalized);
      if (m == null) continue;

      double qty;
      String after;

      switch (i) {
        case 0:
          qty = int.parse(m.group(1)!) +
              int.parse(m.group(2)!) / int.parse(m.group(3)!);
          after = m.group(4)!;
          break;
        case 1:
          final a = int.parse(m.group(1)!);
          final b = int.parse(m.group(2)!);
          qty = (a + b) / 2.0;
          after = m.group(3)!;
          break;
        case 2:
          qty = int.parse(m.group(1)!) / int.parse(m.group(2)!);
          after = m.group(3)!;
          break;
        case 3:
          qty = int.parse(m.group(1)!) +
              int.parse(m.group(2)!) / int.parse(m.group(3)!);
          return Measurement(quantity: qty, unitWord: '', rest: '');
        case 4:
          qty = int.parse(m.group(1)!) / int.parse(m.group(2)!);
          return Measurement(quantity: qty, unitWord: '', rest: '');
        case 5:
          qty = double.parse(m.group(1)!);
          return Measurement(quantity: qty, unitWord: '', rest: '');
        case 6:
          qty = double.parse(m.group(1)!);
          after = m.group(2)!;
          break;
        default:
          return null;
      }

      return _split(qty, after);
    }
    return null;
  }

  static Measurement _split(double qty, String after) {
    final s = after.trim();
    if (s.isEmpty) return Measurement(quantity: qty, unitWord: '', rest: '');
    final space = s.indexOf(' ');
    if (space == -1) {
      return Measurement(quantity: qty, unitWord: s, rest: '');
    }
    return Measurement(
      quantity: qty,
      unitWord: s.substring(0, space),
      rest: s.substring(space + 1).trim(),
    );
  }

  String toScaledString(double factor) {
    return _buildString(quantity * factor);
  }

  String toEditedString(double newQuantity) {
    return _buildString(newQuantity);
  }

  String _buildString(double qty) {
    final qtyStr = Measurement.formatQuantity(qty);
    if (unitWord.isEmpty && rest.isEmpty) return qtyStr;
    if (rest.isEmpty) return '$qtyStr $unitWord';
    return '$qtyStr $unitWord $rest';
  }

  static final _fractionList = <(double, String)>[
    (1 / 8, '1/8'),
    (1 / 4, '1/4'),
    (1 / 3, '1/3'),
    (3 / 8, '3/8'),
    (1 / 2, '1/2'),
    (5 / 8, '5/8'),
    (2 / 3, '2/3'),
    (3 / 4, '3/4'),
    (7 / 8, '7/8'),
  ];

  static String formatQuantity(double value) {
    if (value == 0) return '0';
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }

    final whole = value.floor();
    final frac = value - whole;

    for (final f in _fractionList) {
      if ((frac - f.$1).abs() < 0.02) {
        if (whole > 0) return '$whole ${f.$2}';
        return f.$2;
      }
    }

    String s = value.toStringAsFixed(2);
    s = s.replaceFirst(RegExp(r'\.?0+$'), '');
    return s;
  }
}
