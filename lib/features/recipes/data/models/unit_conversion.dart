import 'measurement.dart';

class UnitEntry {
  final String singular;
  final String plural;
  final String category;
  final double toBase;

  const UnitEntry({
    required this.singular,
    required this.plural,
    required this.category,
    required this.toBase,
  });
}

class UnitConverter {
  UnitConverter._();

  static const _units = <String, UnitEntry>{
    'teaspoon': UnitEntry(singular: 'teaspoon', plural: 'teaspoons', category: 'volume', toBase: 1.0),
    'teaspoons': UnitEntry(singular: 'teaspoon', plural: 'teaspoons', category: 'volume', toBase: 1.0),
    'tablespoon': UnitEntry(singular: 'tablespoon', plural: 'tablespoons', category: 'volume', toBase: 3.0),
    'tablespoons': UnitEntry(singular: 'tablespoon', plural: 'tablespoons', category: 'volume', toBase: 3.0),
    'fluid': UnitEntry(singular: 'fluid ounce', plural: 'fluid ounces', category: 'volume', toBase: 6.0),
    'fluid ounce': UnitEntry(singular: 'fluid ounce', plural: 'fluid ounces', category: 'volume', toBase: 6.0),
    'fluid ounces': UnitEntry(singular: 'fluid ounce', plural: 'fluid ounces', category: 'volume', toBase: 6.0),
    'cup': UnitEntry(singular: 'cup', plural: 'cups', category: 'volume', toBase: 48.0),
    'cups': UnitEntry(singular: 'cup', plural: 'cups', category: 'volume', toBase: 48.0),
    'pint': UnitEntry(singular: 'pint', plural: 'pints', category: 'volume', toBase: 96.0),
    'pints': UnitEntry(singular: 'pint', plural: 'pints', category: 'volume', toBase: 96.0),
    'quart': UnitEntry(singular: 'quart', plural: 'quarts', category: 'volume', toBase: 192.0),
    'quarts': UnitEntry(singular: 'quart', plural: 'quarts', category: 'volume', toBase: 192.0),
    'gallon': UnitEntry(singular: 'gallon', plural: 'gallons', category: 'volume', toBase: 768.0),
    'gallons': UnitEntry(singular: 'gallon', plural: 'gallons', category: 'volume', toBase: 768.0),
    'milliliter': UnitEntry(singular: 'milliliter', plural: 'milliliters', category: 'volume', toBase: 0.202884),
    'milliliters': UnitEntry(singular: 'milliliter', plural: 'milliliters', category: 'volume', toBase: 0.202884),
    'liter': UnitEntry(singular: 'liter', plural: 'liters', category: 'volume', toBase: 202.884),
    'liters': UnitEntry(singular: 'liter', plural: 'liters', category: 'volume', toBase: 202.884),
    'ounce': UnitEntry(singular: 'ounce', plural: 'ounces', category: 'weight', toBase: 1.0),
    'ounces': UnitEntry(singular: 'ounce', plural: 'ounces', category: 'weight', toBase: 1.0),
    'pound': UnitEntry(singular: 'pound', plural: 'pounds', category: 'weight', toBase: 16.0),
    'pounds': UnitEntry(singular: 'pound', plural: 'pounds', category: 'weight', toBase: 16.0),
    'gram': UnitEntry(singular: 'gram', plural: 'grams', category: 'weight', toBase: 0.035274),
    'grams': UnitEntry(singular: 'gram', plural: 'grams', category: 'weight', toBase: 0.035274),
    'kilogram': UnitEntry(singular: 'kilogram', plural: 'kilograms', category: 'weight', toBase: 35.274),
    'kilograms': UnitEntry(singular: 'kilogram', plural: 'kilograms', category: 'weight', toBase: 35.274),
  };

  static ({double quantity, UnitEntry entry, String rest})? detectUnit(
      String text) {
    final m = Measurement.parse(text);
    if (m == null) return null;

    final unitLower = m.unitWord.toLowerCase();

    if (m.rest.isNotEmpty) {
      final words = m.rest.split(' ');
      final twoWord = '$unitLower ${words.first.toLowerCase()}';
      final entry = _units[twoWord];
      if (entry != null) {
        return (
          quantity: m.quantity,
          entry: entry,
          rest: words.sublist(1).join(' '),
        );
      }
    }

    final entry = _units[unitLower];
    if (entry != null) {
      if (entry.singular.contains(' ') && m.rest.isNotEmpty) {
        final words = m.rest.split(' ');
        final unitWords = entry.singular.split(' ');
        if (words.first.toLowerCase() == unitWords.last.toLowerCase()) {
          return (
            quantity: m.quantity,
            entry: entry,
            rest: words.sublist(1).join(' '),
          );
        }
      }
      return (quantity: m.quantity, entry: entry, rest: m.rest);
    }

    return null;
  }

  static List<UnitEntry> compatibleUnitEntries(String ingredientText) {
    final result = detectUnit(ingredientText);
    if (result == null) return [];
    final category = result.entry.category;
    final map = <String, UnitEntry>{};
    for (final u in _units.values) {
      if (u.category == category) {
        map[u.singular] = u;
      }
    }
    final list = map.values.toList();
    list.sort((a, b) => a.singular.compareTo(b.singular));
    return list;
  }

  static String? convert(String ingredientText, String targetUnitName) {
    final result = detectUnit(ingredientText);
    if (result == null) return null;

    final targetKey = targetUnitName.toLowerCase();
    final targetEntry = _units[targetKey];
    if (targetEntry == null) return null;

    final newQty = result.entry.toBase == 0
        ? 0.0
        : result.quantity * result.entry.toBase / targetEntry.toBase;

    final qtyStr = Measurement.formatQuantity(newQty);
    final unitStr = newQty > 1 ? targetEntry.plural : targetEntry.singular;

    final rest = result.rest.trim();
    if (rest.isEmpty) return '$qtyStr $unitStr';
    return '$qtyStr $unitStr $rest';
  }
}
