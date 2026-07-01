import 'package:recipe_app/features/recipes/data/models/recipe_model.dart';
import 'voice_command.dart';

const List<String> kRecipeNameNoisePrefixes = [
  'open', 'show', 'find', 'go to', 'take me to', 'load', 'pull up',
  'navigate to', 'the', 'my', 'a', 'recipe',
];

const List<String> kWakePhrases = [
  'hey recipe', 'okay recipe', 'ok recipe', 'hey receipe',
  'hey recipient', 'hey recently', 'hey reasoning',
];

String _normalize(String text) {
  var t = text.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ').trim();
  for (final phrase in kWakePhrases) {
    if (t.startsWith(phrase)) {
      t = t.substring(phrase.length).trim();
    }
  }
  return t;
}

double _levenshteinSimilarity(String a, String b) {
  if (a == b) return 1.0;
  if (a.isEmpty) return b.isEmpty ? 1.0 : 0.0;
  if (b.isEmpty) return 0.0;

  final matrix = List.generate(a.length + 1, (_) => List.filled(b.length + 1, 0));
  for (var i = 0; i <= a.length; i++) { matrix[i][0] = i; }
  for (var j = 0; j <= b.length; j++) { matrix[0][j] = j; }

  for (var i = 1; i <= a.length; i++) {
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      matrix[i][j] = [
        matrix[i - 1][j] + 1,
        matrix[i][j - 1] + 1,
        matrix[i - 1][j - 1] + cost,
      ].reduce((a, b) => a < b ? a : b);
    }
  }

  final distance = matrix[a.length][b.length].toDouble();
  final maxLen = a.length > b.length ? a.length.toDouble() : b.length.toDouble();
  if (maxLen == 0) return 1.0;
  return 1.0 - distance / maxLen;
}

String? _fuzzyMatchRecipe(String query, List<RecipeModel> recipes) {
  var q = query.toLowerCase().trim();
  for (final prefix in kRecipeNameNoisePrefixes) {
    q = q.replaceAll(RegExp('\\b$prefix\\b'), '');
  }
  q = q.replaceAll(RegExp(r'\s+'), ' ').trim();

  String? bestMatch;
  double bestScore = 0;
  for (final r in recipes) {
    final title = r.title.toLowerCase();
    final score = _levenshteinSimilarity(q, title);
    if (score > bestScore && score >= 0.65) {
      bestScore = score;
      bestMatch = r.fileName;
    }
  }
  return bestMatch;
}

int _timerSeconds(int amount, String unit) {
  if (unit.startsWith('min') || unit == 'm') return amount * 60;
  return amount;
}

String _replaceNumberWords(String text) {
  var result = text;
  // Sort by word length descending to match "twenty" before "two"
  final sorted = kNumberWords.entries.toList()
    ..sort((a, b) => b.key.length.compareTo(a.key.length));
  for (final entry in sorted) {
    result = result.replaceAll(RegExp('\\b${entry.key}\\b'), '${entry.value}');
  }
  return result;
}

const Map<String, double> kScaleWordMap = {
  'half': 0.5,
  'halve': 0.5,
  'quarter': 0.25,
  'double': 2.0,
  'twice': 2.0,
  'two times': 2.0,
  'triple': 3.0,
  'three times': 3.0,
  'quadruple': 4.0,
  'four times': 4.0,
};

const Map<String, int> kNumberWords = {
  'zero': 0, 'one': 1, 'two': 2, 'three': 3, 'four': 4,
  'five': 5, 'six': 6, 'seven': 7, 'eight': 8, 'nine': 9,
  'ten': 10, 'eleven': 11, 'twelve': 12, 'thirteen': 13,
  'fourteen': 14, 'fifteen': 15, 'sixteen': 16, 'seventeen': 17,
  'eighteen': 18, 'nineteen': 19, 'twenty': 20,
};

const List<String> kUnitNames = [
  'gram', 'grams',
  'kilogram', 'kilograms',
  'ounce', 'ounces',
  'pound', 'pounds',
  'cup', 'cups',
  'milliliter', 'milliliters',
  'liter', 'liters',
  'teaspoon', 'teaspoons',
  'tablespoon', 'tablespoons',
  'pint', 'pints',
  'quart', 'quarts',
  'gallon', 'gallons',
  'celsius', 'centigrade',
  'fahrenheit',
];

VoiceCommand matchCommand(
  String text, {
  List<RecipeModel>? recipes,
  bool requireWake = false,
}) {
  final normalized = _normalize(text);

  if (requireWake) {
    final lower = text.toLowerCase().trim();
    final hasWake = kWakePhrases.any((p) => lower.startsWith(p));
    if (!hasWake) return UnknownCommand(text);
  }

  if (normalized.isEmpty) return UnknownCommand(text);

  // 1. stopListening
  if (normalized.contains('stop listening') ||
      normalized.contains('stop voice') ||
      normalized.contains('stop hearing') ||
      normalized.contains('go to sleep') ||
      normalized.contains('pause listening') ||
      (normalized.contains('turn off') &&
          (normalized.contains('listening') ||
           normalized.contains('voice') ||
           normalized.contains('mic') ||
           normalized.contains('hearing'))) ||
      normalized == 'quiet' ||
      normalized.contains('bye') ||
      normalized == 'stop' ||
      normalized == 'sleep' ||
      normalized == 'done') {
    return StopListening();
  }

  // 2. Read control (stop/pause/resume reading)
  if (normalized == 'stop reading' || normalized == 'stop speaking' ||
      normalized == 'quiet now') {
    return ReadStop();
  }
  if (normalized == 'pause reading' || normalized == 'pause') {
    return ReadPause();
  }
  if (normalized == 'resume reading' || normalized == 'resume' ||
      normalized == 'continue reading' || normalized == 'continue' ||
      normalized == 'keep going') {
    return ReadResume();
  }

  // 3. howMuchTimeLeft
  if (normalized.contains('how much time') ||
      normalized.contains('time left') ||
      normalized == 'remaining' ||
      normalized.contains('time remaining')) {
    return HowMuchTimeLeft();
  }

  // 4. next / previous (reading navigation)
  if (normalized == 'next' || normalized == 'next step' ||
      normalized == 'next ingredient' || normalized == 'forward') {
    return ReadNext();
  }
  if (normalized == 'previous' || normalized == 'previous step' ||
      normalized == 'previous ingredient') {
    return ReadPrevious();
  }

  // 5. navigateToRecipe
  if (recipes != null && recipes.isNotEmpty) {
    final triggerWords = ['open', 'show', 'find', 'load', 'go to', 'take me to', 'pull up', 'navigate to'];
    final hasTrigger = triggerWords.any((w) => normalized.startsWith(w) || normalized.contains(' $w'));
    if (hasTrigger) {
      final matched = _fuzzyMatchRecipe(text, recipes);
      if (matched != null) {
        final recipe = recipes.firstWhere((r) => r.fileName == matched);
        return NavigateToRecipe(recipe.folder, recipe.fileName);
      }
    }
  }

  // 6. goBack
  if (normalized.contains('back') || normalized.contains('return') || normalized.contains('previous page')) {
    return GoBack();
  }

  // 7. navigateHome
  if ((normalized.contains('home') || normalized.contains('recipes') || normalized.contains('folders') || normalized.contains('main')) &&
      !normalized.contains('settings')) {
    return NavigateHome();
  }

  // 8. navigateSettings
  if (normalized.contains('settings') || normalized.contains('preferences') || normalized.contains('options')) {
    return NavigateSettings();
  }

  // 9. navigateTranscode
  if (normalized.contains('transcode') || normalized.contains('transcribe') ||
      normalized.contains('import') || normalized.contains('scan') ||
      normalized.contains('add recipe') || normalized.contains('add a recipe') ||
      normalized.contains('new recipe') || normalized.contains('create recipe')) {
    return NavigateTranscode();
  }

  // 10. scaleRecipe
  final hasScaleVerb = normalized.contains('scale') || normalized.contains('reduce') ||
      normalized.contains('increase') || normalized.contains('multiply') ||
      normalized.contains('make') || normalized.contains('times');
  final hasWordNumber = kScaleWordMap.entries.any((e) => normalized.contains(e.key));
  final hasDigit = RegExp(r'\d').hasMatch(normalized);
  if (hasWordNumber || (hasScaleVerb && hasDigit)) {
    for (final entry in kScaleWordMap.entries) {
      if (normalized.contains(entry.key)) {
        return ScaleRecipe(entry.value);
      }
    }
    final digitMatch = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(normalized);
    if (digitMatch != null) {
      final factor = double.tryParse(digitMatch.group(1)!);
      if (factor != null && factor > 0) {
        return ScaleRecipe(factor);
      }
    }
  }

  // 11. convertUnit
  final hasConvertVerb = normalized.contains('convert') ||
      normalized.contains('change to') || normalized.contains('switch to') ||
      normalized.contains('use') || normalized.contains('display in') ||
      normalized.contains('show in');
  final hasUnit = kUnitNames.any((u) => normalized.contains(u));
  if (hasConvertVerb && hasUnit) {
    for (final unit in kUnitNames) {
      if (normalized.contains(unit)) {
        return ConvertUnit(unit);
      }
    }
  }

  // 12. toggleCheckbox
  if (normalized == 'check' || normalized == 'mark' ||
      normalized == 'x' || normalized == 'done' ||
      normalized.contains('check that') || normalized.contains('mark that') ||
      normalized.contains('check off') || normalized.contains('mark done') ||
      normalized.contains('uncheck') || normalized.contains('unmark')) {
    return ToggleCheckbox(-1);
  }
  final checkIndexRe = RegExp(r'(?:check|mark|uncheck|unmark)\s+(?:item|line|#)\s*(\d+)', caseSensitive: false);
  final checkIndexMatch = checkIndexRe.firstMatch(normalized);
  if (checkIndexMatch != null) {
    final index = int.parse(checkIndexMatch.group(1)!) - 1;
    return ToggleCheckbox(index < 0 ? 0 : index);
  }

  // 13. Timer control (cancel/pause/resume before set)
  if (normalized.startsWith('cancel timer') || normalized.startsWith('stop timer')) {
    final label = normalized.replaceFirst(RegExp(r'^(?:cancel|stop)\s+timer'), '').trim();
    return CancelTimer(label.isNotEmpty ? label : null);
  }
  if (normalized.startsWith('pause timer')) {
    final label = normalized.replaceFirst('pause timer', '').trim();
    return PauseTimer(label.isNotEmpty ? label : null);
  }
  if (normalized.startsWith('resume timer')) {
    final label = normalized.replaceFirst('resume timer', '').trim();
    return ResumeTimer(label.isNotEmpty ? label : null);
  }

  // 14. Set timer
  final timerText = _replaceNumberWords(normalized);
  final setTimerRe = RegExp(
    r'set\s+(?:a\s+|an\s+)?timer(?: for)?\s+(\d+)\s*(min(?:ute)?s?|sec(?:ond)?s?|m|s)\s*(.*)',
    caseSensitive: false,
  );
  var m = setTimerRe.firstMatch(timerText);
  if (m != null) {
    final seconds = _timerSeconds(int.parse(m.group(1)!), m.group(2)!);
    final label = m.group(3)?.trim();
    return SetTimer(seconds, label: label?.isNotEmpty == true ? label : null);
  }
  final timerNounRe = RegExp(
    r'(\d+)\s*(min(?:ute)?s?|m)\s+timer\s*(.*)',
    caseSensitive: false,
  );
  m = timerNounRe.firstMatch(timerText);
  if (m != null) {
    final seconds = _timerSeconds(int.parse(m.group(1)!), m.group(2)!);
    final label = m.group(3)?.trim();
    return SetTimer(seconds, label: label?.isNotEmpty == true ? label : null);
  }
  final timerShortRe = RegExp(
    r'^timer\s+(\d+)\s*(min(?:ute)?s?|sec(?:ond)?s?|m|s)\s*(.*)',
    caseSensitive: false,
  );
  m = timerShortRe.firstMatch(timerText);
  if (m != null) {
    final seconds = _timerSeconds(int.parse(m.group(1)!), m.group(2)!);
    final label = m.group(3)?.trim();
    return SetTimer(seconds, label: label?.isNotEmpty == true ? label : null);
  }

  // 15. Read commands (require explicit "read" prefix)
  if (normalized.startsWith('read ') || normalized == 'read') {
    if (normalized.contains('ingredient') || normalized.contains('recipe content')) {
      return ReadIngredients();
    }
    if (normalized.contains('instruction') || normalized.contains('direction') ||
        normalized.contains('step')) {
      final stepMatch = RegExp(r'step\s+(\d+)').firstMatch(normalized);
      if (stepMatch != null) {
        return ReadStepN(int.parse(stepMatch.group(1)!));
      }
      return ReadInstructions();
    }
    return ReadIngredients();
  }

  // 16. switchTab
  if (normalized.contains('ingredients') || normalized.contains('reader') ||
      normalized.contains('view recipe') || normalized == 'view' ||
      (normalized.contains('instructions') && !normalized.contains('edit'))) {
    return SwitchTab(0);
  }
  if (normalized.contains('editor') || normalized.contains('edit mode') ||
      normalized.contains('editing') || normalized == 'edit') {
    return SwitchTab(1);
  }

  return UnknownCommand(text);
}
