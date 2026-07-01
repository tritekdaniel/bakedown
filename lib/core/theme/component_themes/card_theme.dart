import 'package:flutter/material.dart';

CardThemeData appCardTheme(ColorScheme colorScheme) {
  return CardThemeData(
    elevation: 0,
    shadowColor: colorScheme.shadow,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    ),
    color: colorScheme.surfaceContainerLow,
    clipBehavior: Clip.antiAlias,
    margin: EdgeInsets.zero,
  );
}
