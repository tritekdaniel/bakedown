import 'package:flutter/material.dart';

abstract final class AppBreakpoints {
  static const double mobile = 0;
  static const double tablet = 600;
  static const double desktop = 1024;

  static bool isMobile(double width) => width < tablet;
  static bool isTablet(double width) => width >= tablet && width < desktop;
  static bool isDesktop(double width) => width >= desktop;

  static bool isMobileContext(BuildContext context) =>
      isMobile(MediaQuery.sizeOf(context).width);

  static bool isTabletContext(BuildContext context) =>
      isTablet(MediaQuery.sizeOf(context).width);

  static bool isDesktopContext(BuildContext context) =>
      isDesktop(MediaQuery.sizeOf(context).width);
}
