import 'package:flutter/material.dart';

class ResponsiveUtils {
  static bool isTablet(BuildContext context) {
    return MediaQuery.of(context).size.shortestSide >= 600;
  }

  static bool _isLargeTablet(BuildContext context) {
    return MediaQuery.of(context).size.shortestSide >= 900;
  }

  static double scaledFontSize(BuildContext context, double base) {
    if (_isLargeTablet(context)) return base * 1.5;
    if (isTablet(context)) return base * 1.3;
    return base;
  }

  static double scaledIconSize(BuildContext context, double base) {
    if (_isLargeTablet(context)) return base * 1.4;
    if (isTablet(context)) return base * 1.2;
    return base;
  }

  static double scaledPadding(BuildContext context, double base) {
    if (_isLargeTablet(context)) return base * 1.4;
    if (isTablet(context)) return base * 1.2;
    return base;
  }

  static bool isLandscape(BuildContext context) {
    return MediaQuery.of(context).orientation == Orientation.landscape;
  }

  static double cardWidth(BuildContext context) {
    if (isTablet(context)) {
      return MediaQuery.of(context).size.width / 2;
    }
    return MediaQuery.of(context).size.width;
  }

  static int gridColumns(BuildContext context) {
    if (_isLargeTablet(context)) return 4;
    if (isTablet(context)) return 3;
    return 2;
  }
}
