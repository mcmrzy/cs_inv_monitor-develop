import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static ThemeData get light {
    final textTheme = GoogleFonts.notoSansScTextTheme();
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF1565C0),
        brightness: Brightness.light,
      ),
      textTheme: textTheme,
      scaffoldBackgroundColor: const Color(0xFFF5F5F5),
      appBarTheme: AppBarTheme(
        elevation: 0,
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        titleTextStyle: TextStyle(
          fontSize: 18.sp,
          fontWeight: FontWeight.w600,
          color: Colors.black,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16.r)),
        ),
        color: Colors.white,
        shadowColor: Colors.transparent,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 12.h),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.r),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 12.h),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.r),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF3F4F6),
        contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.r),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.r),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.r),
          borderSide: const BorderSide(color: Color(0xFF1565C0), width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.r),
          borderSide: const BorderSide(color: Color(0xFFE53935)),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        backgroundColor: Colors.white,
        selectedItemColor: const Color(0xFF1565C0),
        unselectedItemColor: const Color(0xFF9E9E9E),
        selectedLabelStyle: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600),
        unselectedLabelStyle: TextStyle(fontSize: 12.sp),
      ),
      dividerTheme: const DividerThemeData(
        thickness: 1,
        color: Color(0xFFE5E7EB),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16.w),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.r),
        ),
      ),
    );
  }

  static ThemeData get dark {
    final textTheme = GoogleFonts.notoSansScTextTheme(
      ThemeData(brightness: Brightness.dark).textTheme,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF2196F3),
        brightness: Brightness.dark,
      ),
      textTheme: textTheme,
      scaffoldBackgroundColor: const Color(0xFF0F1115),
      appBarTheme: AppBarTheme(
        elevation: 0,
        centerTitle: true,
        backgroundColor: const Color(0xFF1A1D24),
        foregroundColor: Colors.white,
        titleTextStyle: TextStyle(
          fontSize: 18.sp,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16.r)),
        ),
        color: const Color(0xFF1A1D24),
        shadowColor: Colors.transparent,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 12.h),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.r),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 12.h),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.r),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF252830),
        contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.r),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.r),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.r),
          borderSide: const BorderSide(color: Color(0xFF42A5F5), width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.r),
          borderSide: const BorderSide(color: Color(0xFFEF5350)),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        backgroundColor: const Color(0xFF1A1D24),
        selectedItemColor: const Color(0xFF42A5F5),
        unselectedItemColor: const Color(0xFF6B7280),
        selectedLabelStyle: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600),
        unselectedLabelStyle: TextStyle(fontSize: 12.sp),
      ),
      dividerTheme: const DividerThemeData(
        thickness: 1,
        color: Color(0xFF2A2D35),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16.w),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.r),
        ),
      ),
    );
  }
}

/// Context-aware color accessors for theme-dependent colors.
///
/// Usage: `AppColor.surface(context)` instead of `Theme.of(context).colorScheme.surface`
class AppColor {
  static Color surface(BuildContext context) => Theme.of(context).colorScheme.surface;
  static Color onSurface(BuildContext context) => Theme.of(context).colorScheme.onSurface;
  static Color onSurfaceVariant(BuildContext context) => Theme.of(context).colorScheme.onSurfaceVariant;
  static Color outline(BuildContext context) => Theme.of(context).colorScheme.outline;
  static Color primary(BuildContext context) => Theme.of(context).colorScheme.primary;
  static Color primaryContainer(BuildContext context) => Theme.of(context).colorScheme.primaryContainer;

  /// Standard card decoration used across the app.
  static BoxDecoration card(BuildContext context, {EdgeInsets? padding}) => BoxDecoration(
    color: Theme.of(context).colorScheme.surface,
    borderRadius: BorderRadius.circular(16.r),
  );

  /// Card decoration with subtle shadow for elevated sections.
  static BoxDecoration cardElevated(BuildContext context) => BoxDecoration(
    color: Theme.of(context).colorScheme.surface,
    borderRadius: BorderRadius.circular(20.r),
    boxShadow: [
      BoxShadow(
        color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.06),
        blurRadius: 16,
        offset: const Offset(0, 4),
      ),
    ],
  );

  /// Hero card with primary gradient background.
  static BoxDecoration heroCard(BuildContext context) => BoxDecoration(
    gradient: const LinearGradient(
      colors: [
        Color(0xFF1565C0),
        Color(0xFF1976D2),
        Color(0xFF2196F3),
      ],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    borderRadius: BorderRadius.circular(20.r),
    boxShadow: [
      BoxShadow(
        color: const Color(0xFF1565C0).withValues(alpha: 0.4),
        blurRadius: 20,
        offset: const Offset(0, 8),
      ),
    ],
  );

  /// Info card with primary container gradient.
  static BoxDecoration infoCard(BuildContext context) => BoxDecoration(
    gradient: LinearGradient(
      colors: [
        Theme.of(context).colorScheme.primaryContainer,
        Theme.of(context).colorScheme.surface,
      ],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    borderRadius: BorderRadius.circular(16.r),
  );
}

/// Semantic color constants that work in both light and dark modes.
/// Use these for status indicators, badges, and semantic coloring.
class AppColors {
  // Brand colors
  static const Color primary = Color(0xFF1565C0);
  static const Color primaryDark = Color(0xFF0D47A1);
  static const Color primaryLight = Color(0xFF42A5F5);

  // Semantic status colors
  static const Color success = Color(0xFF2E7D32);
  static const Color successLight = Color(0xFF10B981);
  static const Color warning = Color(0xFFF9A825);
  static const Color error = Color(0xFFC62828);
  static const Color errorLight = Color(0xFFEF4444);
  static const Color info = Color(0xFF1565C0);

  // Device status colors
  static const Color online = Color(0xFF2E7D32);
  static const Color offline = Color(0xFF9E9E9E);
  static const Color fault = Color(0xFFC62828);

  // Text colors (for light backgrounds)
  static const Color textPrimary = Color(0xFF1F2937);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textHint = Color(0xFF9CA3AF);

  // Surface colors (light mode)
  static const Color divider = Color(0xFFE5E7EB);
  static const Color background = Color(0xFFF7F8FA);
  static const Color surfaceHover = Color(0xFFF3F4F6);

  // Status badge colors
  static const Color badgeNormalBg = Color(0xFFECFDF5);
  static const Color badgeNormalText = Color(0xFF10B981);
  static const Color badgeAlarmBg = Color(0xFFFEF2F2);
  static const Color badgeAlarmText = Color(0xFFEF4444);
  static const Color badgeOfflineBg = Color(0xFFF3F4F6);
  static const Color badgeOfflineText = Color(0xFF9CA3AF);

  // Accent palette
  static const Color blue = Color(0xFF3B82F6);
  static const Color teal = Color(0xFF14B8A6);
  static const Color orange = Color(0xFFF59E0B);
  static const Color purple = Color(0xFF8B5CF6);
  static const Color indigo = Color(0xFF6366F1);
}
