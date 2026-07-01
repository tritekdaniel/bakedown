import 'package:flutter/material.dart';

FilledButtonThemeData appFilledButtonTheme(ColorScheme colorScheme) {
  return FilledButtonThemeData(
    style: FilledButton.styleFrom(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      disabledBackgroundColor: colorScheme.onSurface.withValues(alpha: 0.12),
      disabledForegroundColor: colorScheme.onSurface.withValues(alpha: 0.38),
    ),
  );
}

OutlinedButtonThemeData appOutlinedButtonTheme(ColorScheme colorScheme) {
  return OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      side: BorderSide(color: colorScheme.outline),
      disabledForegroundColor: colorScheme.onSurface.withValues(alpha: 0.38),
    ),
  );
}

TextButtonThemeData appTextButtonTheme(ColorScheme colorScheme) {
  return TextButtonThemeData(
    style: TextButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      disabledForegroundColor: colorScheme.onSurface.withValues(alpha: 0.38),
    ),
  );
}
