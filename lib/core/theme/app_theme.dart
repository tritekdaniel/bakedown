import 'package:flutter/material.dart';
import 'color_scheme.dart';
import 'text_theme.dart';
import 'component_themes/card_theme.dart';
import 'component_themes/input_theme.dart';
import 'component_themes/button_theme.dart';

class AppTheme {
  static ThemeData build({required Brightness brightness}) {
    final colorScheme = brightness == Brightness.light
        ? AppColors.lightScheme()
        : AppColors.darkScheme();

    final customColors = brightness == Brightness.light
        ? CustomColors.light
        : CustomColors.dark;

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      pageTransitionsTheme: PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
      textTheme: appTextTheme(colorScheme),
      cardTheme: appCardTheme(colorScheme),
      inputDecorationTheme: appInputDecorationTheme(colorScheme),
      filledButtonTheme: appFilledButtonTheme(colorScheme),
      outlinedButtonTheme: appOutlinedButtonTheme(colorScheme),
      textButtonTheme: appTextButtonTheme(colorScheme),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        tileColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        titleTextStyle: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 16,
          color: colorScheme.onSurface,
        ),
        subtitleTextStyle: TextStyle(
          fontSize: 14,
          color: colorScheme.onSurfaceVariant,
        ),
        leadingAndTrailingTextStyle: TextStyle(
          color: colorScheme.onSurfaceVariant,
        ),
        iconColor: colorScheme.onSurfaceVariant,
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        labelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colorScheme.onSurface),
        secondaryLabelStyle: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
        backgroundColor: colorScheme.surfaceContainerHighest,
        selectedColor: colorScheme.secondaryContainer,
        iconTheme: IconThemeData(size: 16, color: colorScheme.onSurfaceVariant),
        checkmarkColor: colorScheme.onSecondaryContainer,
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
        height: 65,
        backgroundColor: colorScheme.surface,
        indicatorColor: colorScheme.secondaryContainer,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: colorScheme.surface,
        indicatorColor: colorScheme.secondaryContainer,
        labelType: NavigationRailLabelType.all,
        useIndicator: true,
        elevation: 0,
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        surfaceTintColor: colorScheme.surfaceTint,
        elevation: 0,
        scrolledUnderElevation: 1,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: colorScheme.onSurface,
        ),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        elevation: 3,
        backgroundColor: colorScheme.surface,
        surfaceTintColor: colorScheme.surfaceTint,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: colorScheme.onSurface,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return colorScheme.primary;
          return Colors.transparent;
        }),
        checkColor: WidgetStateProperty.all(colorScheme.onPrimary),
        side: BorderSide(color: colorScheme.outline),
        overlayColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.pressed)) return colorScheme.primary.withValues(alpha: 0.1);
          if (states.contains(WidgetState.hovered)) return colorScheme.primary.withValues(alpha: 0.04);
          return Colors.transparent;
        }),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return colorScheme.primary;
          return colorScheme.outline;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return colorScheme.primaryContainer;
          return colorScheme.surfaceContainerHighest;
        }),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        backgroundColor: colorScheme.surface,
        surfaceTintColor: colorScheme.surfaceTint,
        elevation: 2,
      ),
      popupMenuTheme: PopupMenuThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        elevation: 3,
        color: colorScheme.surface,
        surfaceTintColor: colorScheme.surfaceTint,
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          shape: WidgetStateProperty.all(RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          )),
          elevation: WidgetStateProperty.all(3),
          backgroundColor: WidgetStateProperty.all(colorScheme.surface),
          surfaceTintColor: WidgetStateProperty.all(colorScheme.surfaceTint),
        ),
      ),
      searchBarTheme: SearchBarThemeData(
        shape: WidgetStateProperty.all(RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        )),
        elevation: WidgetStateProperty.all(0),
        backgroundColor: WidgetStateProperty.all(colorScheme.surfaceContainerHighest),
        textStyle: WidgetStateProperty.all(TextStyle(color: colorScheme.onSurface)),
        hintStyle: WidgetStateProperty.all(TextStyle(color: colorScheme.onSurfaceVariant)),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: colorScheme.primary,
        unselectedLabelColor: colorScheme.onSurfaceVariant,
        indicatorSize: TabBarIndicatorSize.tab,
        indicatorColor: colorScheme.primary,
        labelStyle: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        unselectedLabelStyle: TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
      ),
      snackBarTheme: SnackBarThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        behavior: SnackBarBehavior.floating,
        elevation: 3,
        contentTextStyle: TextStyle(color: colorScheme.onInverseSurface),
      ),
      extensions: [customColors],
    );
  }

  static final lightTheme = build(brightness: Brightness.light);
  static final darkTheme = build(brightness: Brightness.dark);
}
