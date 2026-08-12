import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class AppTheme {
  static ThemeData get light {
    final textTheme = Typography.material2021().black;
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
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24.r),
        ),
        titleTextStyle: TextStyle(
          fontSize: 18.sp,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        contentTextStyle: TextStyle(
          fontSize: 15.sp,
          height: 1.5,
          color: AppColors.textSecondary,
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        modalBackgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: Color(0xFFD1D5DB),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        // 柔和中性深灰蓝：避免纯蓝黑"一坨"观感（与 AppToast info 背景一致）
        backgroundColor: const Color(0xFF374151),
        contentTextStyle: TextStyle(fontSize: 14.sp, color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.r),
        ),
        elevation: 4,
      ),
      timePickerTheme: TimePickerThemeData(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20.r),
        ),
        dialBackgroundColor: const Color(0xFFF3F4F6),
        dialHandColor: AppColors.primary,
        dialTextColor: AppColors.textPrimary,
        hourMinuteColor: AppColors.primary,
        hourMinuteTextColor: Colors.white,
        entryModeIconColor: AppColors.primary,
        dayPeriodColor: AppColors.primary.withValues(alpha: 0.1),
        dayPeriodTextColor: AppColors.primary,
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20.r),
        ),
        headerBackgroundColor: AppColors.primary,
        headerForegroundColor: Colors.white,
        todayBorder: const BorderSide(color: AppColors.primary, width: 1.5),
        dayOverlayColor:
            WidgetStatePropertyAll(AppColors.primary.withValues(alpha: 0.1)),
        confirmButtonStyle: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600),
        ),
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
        selectedItemColor: const Color(0xFF0D47A1),
        unselectedItemColor: const Color(0xFF9E9E9E),
        selectedLabelStyle:
            TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600),
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
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.r),
          ),
          textStyle: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w500),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.r),
          ),
          textStyle: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w500),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.white
              : const Color(0xFF9CA3AF),
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.primary
              : const Color(0xFFD1D5DB),
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.primary
              : Colors.transparent,
        ),
        checkColor: const WidgetStatePropertyAll(Colors.white),
        side: const BorderSide(color: Color(0xFF9CA3AF), width: 1.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4.r),
        ),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.primary
              : const Color(0xFF9CA3AF),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.primary,
        unselectedLabelColor: AppColors.textSecondary,
        indicatorColor: AppColors.primary,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: Colors.transparent,
        labelStyle: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600),
        unselectedLabelStyle:
            TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w400),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFFF3F4F6),
        selectedColor: AppColors.primary.withValues(alpha: 0.12),
        labelStyle: TextStyle(fontSize: 13.sp, color: AppColors.textPrimary),
        secondaryLabelStyle:
            TextStyle(fontSize: 13.sp, color: AppColors.primary),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8.r),
        ),
      ),
      iconTheme: const IconThemeData(color: Color(0xFF6B7280), size: 22),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primary,
        linearTrackColor: Color(0xFFE5E7EB),
        circularTrackColor: Color(0xFFE5E7EB),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: const Color(0xFF1F2937),
          borderRadius: BorderRadius.circular(8.r),
        ),
        textStyle: TextStyle(fontSize: 12.sp, color: Colors.white),
        waitDuration: const Duration(milliseconds: 400),
      ),
      badgeTheme: BadgeThemeData(
        backgroundColor: AppColors.error,
        textColor: Colors.white,
        textStyle: TextStyle(fontSize: 10.sp, fontWeight: FontWeight.w600),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: AppColors.primary,
        inactiveTrackColor: const Color(0xFFE5E7EB),
        thumbColor: AppColors.primary,
        overlayColor: AppColors.primary.withValues(alpha: 0.12),
        trackHeight: 4,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(
          const Color(0xFFD1D5DB).withValues(alpha: 0.6),
        ),
        radius: const Radius.circular(4),
        thickness: const WidgetStatePropertyAll(4),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.r),
        ),
        elevation: 4,
        textStyle: TextStyle(fontSize: 14.sp, color: AppColors.textPrimary),
      ),
    );
  }

  static ThemeData get dark {
    final textTheme = Typography.material2021().white;
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
      dialogTheme: DialogThemeData(
        backgroundColor: const Color(0xFF1A1D24),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24.r),
        ),
        titleTextStyle: TextStyle(
          fontSize: 18.sp,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
        contentTextStyle: TextStyle(
          fontSize: 15.sp,
          height: 1.5,
          color: const Color(0xFF9CA3AF),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Color(0xFF1A1D24),
        modalBackgroundColor: Color(0xFF1A1D24),
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: Color(0xFF4B5563),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF374151),
        contentTextStyle: TextStyle(fontSize: 14.sp, color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.r),
        ),
        elevation: 4,
      ),
      timePickerTheme: TimePickerThemeData(
        backgroundColor: const Color(0xFF1A1D24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20.r),
        ),
        dialBackgroundColor: const Color(0xFF252830),
        dialHandColor: const Color(0xFF42A5F5),
        dialTextColor: Colors.white,
        hourMinuteColor: const Color(0xFF42A5F5),
        hourMinuteTextColor: Colors.white,
        entryModeIconColor: const Color(0xFF42A5F5),
        dayPeriodColor: const Color(0xFF42A5F5).withValues(alpha: 0.2),
        dayPeriodTextColor: const Color(0xFF42A5F5),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: const Color(0xFF1A1D24),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20.r),
        ),
        headerBackgroundColor: const Color(0xFF1E88E5),
        headerForegroundColor: Colors.white,
        todayBorder: const BorderSide(color: Color(0xFF42A5F5), width: 1.5),
        dayOverlayColor: WidgetStatePropertyAll(
          const Color(0xFF42A5F5).withValues(alpha: 0.2),
        ),
        confirmButtonStyle: TextButton.styleFrom(
          foregroundColor: const Color(0xFF42A5F5),
          textStyle: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600),
        ),
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
        selectedLabelStyle:
            TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600),
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
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFF42A5F5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.r),
          ),
          textStyle: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w500),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.r),
          ),
          textStyle: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w500),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.white
              : const Color(0xFF9CA3AF),
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? const Color(0xFF42A5F5)
              : const Color(0xFF374151),
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? const Color(0xFF42A5F5)
              : Colors.transparent,
        ),
        checkColor: const WidgetStatePropertyAll(Colors.white),
        side: const BorderSide(color: Color(0xFF9CA3AF), width: 1.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4.r),
        ),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? const Color(0xFF42A5F5)
              : const Color(0xFF9CA3AF),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: const Color(0xFF42A5F5),
        unselectedLabelColor: const Color(0xFF9CA3AF),
        indicatorColor: const Color(0xFF42A5F5),
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: Colors.transparent,
        labelStyle: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600),
        unselectedLabelStyle:
            TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w400),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFF252830),
        selectedColor: const Color(0xFF42A5F5).withValues(alpha: 0.2),
        labelStyle: const TextStyle(fontSize: 13, color: Colors.white),
        secondaryLabelStyle:
            const TextStyle(fontSize: 13, color: Color(0xFF42A5F5)),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8.r),
        ),
      ),
      iconTheme: const IconThemeData(color: Color(0xFF9CA3AF), size: 22),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: Color(0xFF42A5F5),
        linearTrackColor: Color(0xFF2A2D35),
        circularTrackColor: Color(0xFF2A2D35),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: const Color(0xFF374151),
          borderRadius: BorderRadius.circular(8.r),
        ),
        textStyle: TextStyle(fontSize: 12.sp, color: Colors.white),
        waitDuration: const Duration(milliseconds: 400),
      ),
      badgeTheme: BadgeThemeData(
        backgroundColor: const Color(0xFFEF5350),
        textColor: Colors.white,
        textStyle: TextStyle(fontSize: 10.sp, fontWeight: FontWeight.w600),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: const Color(0xFF42A5F5),
        inactiveTrackColor: const Color(0xFF374151),
        thumbColor: const Color(0xFF42A5F5),
        overlayColor: const Color(0xFF42A5F5).withValues(alpha: 0.2),
        trackHeight: 4,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(
          const Color(0xFF4B5563).withValues(alpha: 0.6),
        ),
        radius: const Radius.circular(4),
        thickness: const WidgetStatePropertyAll(4),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: const Color(0xFF1A1D24),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.r),
        ),
        elevation: 4,
        textStyle: TextStyle(fontSize: 14.sp, color: Colors.white),
      ),
    );
  }
}

/// Context-aware color accessors for theme-dependent colors.
///
/// Usage: `AppColor.surface(context)` instead of hard-coded colors or
/// `Theme.of(context).colorScheme.surface`. All values are explicitly mapped
/// for light/dark modes to keep the visual language consistent.
class AppColor {
  static bool _isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  /// Page background (matches Scaffold background).
  static Color surface(BuildContext context) =>
      _isDark(context) ? const Color(0xFF0F1115) : const Color(0xFFF5F5F5);

  /// Card / dialog / bottom sheet / nav bar background.
  static Color surfaceContainer(BuildContext context) =>
      _isDark(context) ? const Color(0xFF1A1D24) : Colors.white;

  /// Input fill / pressed / subtle fill background.
  static Color surfaceHover(BuildContext context) =>
      _isDark(context) ? const Color(0xFF252830) : const Color(0xFFF3F4F6);

  static Color onSurface(BuildContext context) =>
      _isDark(context) ? Colors.white : AppColors.textPrimary;

  static Color onSurfaceVariant(BuildContext context) =>
      _isDark(context) ? const Color(0xFF9CA3AF) : AppColors.textSecondary;

  static Color outline(BuildContext context) =>
      _isDark(context) ? const Color(0xFF3A3F4A) : const Color(0xFFD1D5DB);

  static Color primary(BuildContext context) =>
      _isDark(context) ? const Color(0xFF42A5F5) : AppColors.primary;

  static Color primaryContainer(BuildContext context) => _isDark(context)
      ? const Color(0xFF42A5F5).withValues(alpha: 0.18)
      : const Color(0xFFEFF6FF);

  static Color textPrimary(BuildContext context) =>
      _isDark(context) ? Colors.white : AppColors.textPrimary;

  static Color textSecondary(BuildContext context) =>
      _isDark(context) ? const Color(0xFF9CA3AF) : AppColors.textSecondary;

  static Color textHint(BuildContext context) =>
      _isDark(context) ? const Color(0xFF6B7280) : AppColors.textHint;

  static Color border(BuildContext context) =>
      _isDark(context) ? const Color(0xFF2A2D35) : AppColors.border;

  /// Soft brand-tint background for info panels and selected states.
  static Color primarySoft(BuildContext context) => _isDark(context)
      ? const Color(0xFF42A5F5).withValues(alpha: 0.12)
      : const Color(0xFFEFF6FF);

  /// Standard card decoration used across the app.
  static BoxDecoration card(BuildContext context, {EdgeInsets? padding}) =>
      BoxDecoration(
        color: surfaceContainer(context),
        borderRadius: BorderRadius.circular(16.r),
      );

  /// Card decoration with subtle shadow for elevated sections.
  static BoxDecoration cardElevated(BuildContext context) => BoxDecoration(
        color: surfaceContainer(context),
        borderRadius: BorderRadius.circular(20.r),
        boxShadow: [
          BoxShadow(
            color: _isDark(context)
                ? Colors.black.withValues(alpha: 0.4)
                : AppColors.primary.withValues(alpha: 0.06),
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
            primaryContainer(context),
            surfaceContainer(context),
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

  /// Soft brand-tint background (light mode), e.g. info panels.
  static const Color primarySoft = Color(0xFFEFF6FF);

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
  static const Color border = Color(0xFFE5E7EB);
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
