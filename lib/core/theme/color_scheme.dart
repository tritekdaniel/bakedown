import 'package:flutter/material.dart';

@immutable
class CustomColors extends ThemeExtension<CustomColors> {
  final Color textDisabled;
  final Color surfaceOverlay;
  final Color textLink;

  const CustomColors({
    required this.textDisabled,
    required this.surfaceOverlay,
    required this.textLink,
  });

  @override
  CustomColors copyWith({
    Color? textDisabled,
    Color? surfaceOverlay,
    Color? textLink,
  }) {
    return CustomColors(
      textDisabled: textDisabled ?? this.textDisabled,
      surfaceOverlay: surfaceOverlay ?? this.surfaceOverlay,
      textLink: textLink ?? this.textLink,
    );
  }

  @override
  CustomColors lerp(ThemeExtension<CustomColors> other, double t) {
    if (other is! CustomColors) return this;
    return CustomColors(
      textDisabled: Color.lerp(textDisabled, other.textDisabled, t)!,
      surfaceOverlay: Color.lerp(surfaceOverlay, other.surfaceOverlay, t)!,
      textLink: Color.lerp(textLink, other.textLink, t)!,
    );
  }

  static const light = CustomColors(
    textDisabled: Color(0xFF9E9E9E),
    surfaceOverlay: Color(0x1A000000),
    textLink: Color(0xFF1565C0),
  );

  static const dark = CustomColors(
    textDisabled: Color(0xFF616161),
    surfaceOverlay: Color(0x33000000),
    textLink: Color(0xFF64B5F6),
  );
}

abstract final class AppColors {
  static const Color _seed = Color(0xFFE65100);

  static ColorScheme lightScheme() => ColorScheme.fromSeed(
        seedColor: _seed,
        brightness: Brightness.light,
      );

  static ColorScheme darkScheme() => ColorScheme.fromSeed(
        seedColor: _seed,
        brightness: Brightness.dark,
      );
}
