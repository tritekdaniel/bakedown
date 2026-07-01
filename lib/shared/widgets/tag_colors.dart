import 'package:flutter/material.dart';

Color tagColor(String tag, ColorScheme cs) {
  final hue = (tag.hashCode.abs() * 137.5) % 360.0;
  final isLight = cs.brightness == Brightness.light;
  return HSLColor.fromAHSL(1.0, hue, isLight ? 0.55 : 0.45, isLight ? 0.55 : 0.75).toColor();
}
