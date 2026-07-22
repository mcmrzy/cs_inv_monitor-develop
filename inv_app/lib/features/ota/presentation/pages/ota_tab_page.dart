import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/widgets/styled_refresh_indicator.dart';
import 'package:inv_app/features/device/presentation/bloc/device_bloc.dart';
import 'package:inv_app/l10n/app_localizations.dart';

class OtaTabPage extends StatefulWidget {
  const OtaTabPage({super.key});

  @override
  State<OtaTabPage> createState() => _OtaTabPageState();
}

class _OtaTabPageState extends State<OtaTabPage> {
  DeviceListLoaded? _cachedState;

  @override
  void initState() {
    super.initState();
    context.read<DeviceBloc>().add(const DeviceListRequested());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(50.h),
        child: AppBar(
          title: Text(
            l10n.otaTitle,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 17),
          ),
          centerTitle: true,
          elevation: 0,
          scrolledUnderElevation: 0.5,
          backgroundColor: Colors.white,
          foregroundColor: AppColors.textPrimary,
        ),
      ),
      body: BlocBuilder<DeviceBloc, DeviceState>(
        builder: (context, state) {
          if (state is DeviceListLoaded) {
            _cachedState = state;
          }

          if (_cachedState != null) {
            return _buildDeviceList(context, _cachedState!, l10n);
          }

          if (state is DeviceError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: EdgeInsets.all(20.w),
                    decoration: BoxDecoration(
                      color: AppColors.error.withAlpha(20),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.error_outline_rounded,
                      size: 40.sp,
                      color: AppColors.error,
                    ),
                  ),
                  SizedBox(height: 12.h),
                  Text(
                    l10n.translateError(state.message),
                    style: TextStyle(
                      fontSize: 14.sp,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  SizedBox(height: 16.h),
                  OutlinedButton(
                    onPressed: () => context
                        .read<DeviceBloc>()
                        .add(const DeviceListRequested()),
                    child: Text(l10n.retry),
                  ),
                ],
              ),
            );
          }

          return const Center(child: CircularProgressIndicator(strokeWidth: 3));
        },
      ),
    );
  }

  Widget _buildDeviceList(
    BuildContext context,
    DeviceListLoaded state,
    AppLocalizations l10n,
  ) {
    if (state.devices.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.system_update_outlined,
              size: 64.sp,
              color: AppColors.textHint,
            ),
            SizedBox(height: 16.h),
            Text(
              l10n.noUpgradableDevices,
              style: TextStyle(fontSize: 16.sp, color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }
    return StyledRefreshIndicator(
      onRefresh: () async =>
          context.read<DeviceBloc>().add(const DeviceListRequested()),
      child: ListView.builder(
        padding: EdgeInsets.all(12.w),
        itemCount: state.devices.length,
        itemBuilder: (context, index) =>
            _buildDeviceCard(context, state.devices[index], l10n),
      ),
    );
  }

  Widget _buildDeviceCard(
    BuildContext context,
    dynamic device,
    AppLocalizations l10n,
  ) {
    final sn = device['sn'] ?? device['device_sn'] ?? '';
    final name = device['name'] ?? device['device_name'] ?? sn;
    final model = device['model'] ?? device['device_model'] ?? '';
    final status = device['status'] ?? 0;
    // Show main_version (system-generated package version) if available,
    // otherwise fall back to legacy sub-version concatenation.
    final mainVersion = device['main_version'] as String? ?? '';
    final firmwareVersion = mainVersion.isNotEmpty
        ? mainVersion
        : (() {
            final firmwareArm = device['firmware_arm'] as String? ?? '';
            final firmwareEsp = device['firmware_esp'] as String? ?? '';
            final parts = <String>[];
            if (firmwareArm.isNotEmpty) parts.add(firmwareArm);
            if (firmwareEsp.isNotEmpty) parts.add(firmwareEsp);
            return parts.isNotEmpty ? parts.join('-') : l10n.firmwareUnknown;
          })();
    final isOnline = status == 1;

    return Container(
      margin: EdgeInsets.only(bottom: 10.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14.r),
      ),
      child: InkWell(
        onTap: isOnline ? () => context.push('/ota/$sn') : null,
        borderRadius: BorderRadius.circular(14.r),
        child: Padding(
          padding: EdgeInsets.all(14.w),
          child: Row(
            children: [
              Container(
                width: 44.w,
                height: 44.w,
                decoration: BoxDecoration(
                  color: isOnline
                      ? AppColors.primary.withAlpha(15)
                      : AppColors.textHint.withAlpha(15),
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Icon(
                  isOnline
                      ? Icons.system_update_alt_rounded
                      : Icons.update_disabled_rounded,
                  size: 24.sp,
                  color: isOnline ? AppColors.primary : AppColors.textHint,
                ),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        fontSize: 15.sp,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    SizedBox(height: 2.h),
                    Text(
                      '${l10n.modelLabel}: $model',
                      style: TextStyle(
                        fontSize: 12.sp,
                        color: AppColors.textHint,
                      ),
                    ),
                    SizedBox(height: 2.h),
                    Text(
                      '${l10n.firmwareLabel}: $firmwareVersion',
                      style: TextStyle(
                        fontSize: 12.sp,
                        color: AppColors.textHint,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding:
                        EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                    decoration: BoxDecoration(
                      color: isOnline
                          ? AppColors.success.withAlpha(20)
                          : AppColors.textHint.withAlpha(20),
                      borderRadius: BorderRadius.circular(6.r),
                    ),
                    child: Text(
                      isOnline ? l10n.online : l10n.offline,
                      style: TextStyle(
                        fontSize: 11.sp,
                        fontWeight: FontWeight.w600,
                        color:
                            isOnline ? AppColors.success : AppColors.textHint,
                      ),
                    ),
                  ),
                  SizedBox(height: 4.h),
                  if (isOnline)
                    Icon(
                      Icons.chevron_right,
                      color: AppColors.primary,
                      size: 20.sp,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
