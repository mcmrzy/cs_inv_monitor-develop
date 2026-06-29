import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/l10n/app_localizations.dart';

Future<bool> showWifiSwitchDialog(BuildContext context, {String? originalSsid}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => const _WifiSwitchDialog(originalSsid: null),
  ).then((v) => v ?? false);
}

class _WifiSwitchDialog extends StatelessWidget {
  final String? originalSsid;

  const _WifiSwitchDialog({this.originalSsid});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
      title: Row(children: [
        Container(
          width: 40.w, height: 40.w,
          decoration: BoxDecoration(
            color: AppColors.successLight.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10.r),
          ),
          child: const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 24),
        ),
        SizedBox(width: 12.w),
        Expanded(child: Text(AppLocalizations.of(context)?.configSuccess ?? 'Config Success', style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w700))),
      ]),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(AppLocalizations.of(context)?.provisionSuccessWifi ?? 'Provisioning success, please switch back to your WiFi for remote monitoring.',
          style: TextStyle(fontSize: 14.sp, color: AppColors.textPrimary)),
        if (originalSsid != null) ...[
          SizedBox(height: 8.h),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(8.r),
            ),
            child: Row(children: [
              Icon(Icons.wifi, size: 18, color: AppColors.primary),
              SizedBox(width: 8.w),
              Text(originalSsid!, style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            ]),
          ),
        ],
      ]),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(AppLocalizations.of(context)?.cancel ?? 'Later', style: TextStyle(fontSize: 14.sp, color: AppColors.textHint)),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
            padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 10.h),
          ),
          child: Text(AppLocalizations.of(context)?.switchWifi ?? 'Switch WiFi', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}
