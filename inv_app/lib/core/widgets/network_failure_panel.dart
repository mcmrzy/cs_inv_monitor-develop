import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/theme/csergy_assets.dart';

class NetworkFailurePanel extends StatelessWidget {
  final String title;
  final String message;
  final String retryLabel;
  final VoidCallback onRetry;

  const NetworkFailurePanel({
    super.key,
    required this.title,
    required this.message,
    required this.retryLabel,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const Key('network-failure-panel'),
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: 32.w, vertical: 24.h),
        child: Semantics(
          label: '$title. $message',
          container: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                CsergyAssets.networkConnectionFailed,
                key: const Key('network-connection-failed-illustration'),
                width: 220.w.clamp(168.0, 240.0).toDouble(),
                fit: BoxFit.contain,
                semanticLabel: title,
              ),
              SizedBox(height: 18.h),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColor.textPrimary(context),
                  fontSize: 20.sp,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 8.h),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColor.textSecondary(context),
                  fontSize: 14.sp,
                  height: 1.5,
                ),
              ),
              SizedBox(height: 22.h),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(retryLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
