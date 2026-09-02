part of 'wifi_config_page.dart';
// extension 调用 State.setState 属同库受控拆分，豁免 protected 告警
// ignore_for_file: invalid_use_of_protected_member

/// SoftAP / BLE 配网 UI 分区：自巨型 wifi_config_page 物理拆分，
/// 状态与流程逻辑仍在 _WifiConfigPageState（此处仅迁移构建方法）
extension _WifiConfigProvisionSections on _WifiConfigPageState {
  Widget _buildSoftApSection() {
    final deviceConnected = _provisionStep >= 2;
    final isStep0 = !deviceConnected;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        WifiProvisionStepIndicator(
          steps: [
            WifiProvisionStepData(
              label: AppLocalizations.of(context)!.connectDeviceHotspot,
              isCompleted: _provisionStep > 1,
              isCurrent: _provisionStep == 1 ||
                  (_provisionStep == 0 && !deviceConnected),
            ),
            WifiProvisionStepData(
              label: AppLocalizations.of(context)!.selectWifi,
              isCompleted: _provisionStep > 2 || _provisionOk,
              isCurrent: _provisionStep == 2 && !_provisionOk,
            ),
            WifiProvisionStepData(
              label: AppLocalizations.of(context)!.finish,
              isCompleted: _provisionOk,
              isCurrent: false,
            ),
          ],
        ),
        SizedBox(height: 24.h),
        if (isStep0) ...[
          // 小烁配网引导插画：连接设备热点前的流程引导（美术路由 C7/guide-wifi）
          ClipRRect(
            borderRadius: BorderRadius.circular(14.r),
            // 图片为 1536x1024 横图：等比容器完整显示，避免 cover 裁剪人物头部
            child: AspectRatio(
              aspectRatio: 3 / 2,
              child: Image.asset(
                CsergyAssets.xiaoshuoWifiGuide,
                fit: BoxFit.cover,
              ),
            ),
          ),
          SizedBox(height: 16.h),
          SizedBox(
            width: double.infinity,
            height: 46.h,
            child: ElevatedButton.icon(
              onPressed: _wifiScanning ? null : _scanCSInvWiFi,
              icon: _wifiScanning
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.wifi_find, size: 22),
              label: Text(
                _wifiScanning
                    ? AppLocalizations.of(context)!.scanning
                    : ' ${AppLocalizations.of(context)!.scanNearInverters}',
                style: const TextStyle(fontSize: 15),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.r),
                ),
              ),
            ),
          ),
          if (_csInvNetworks.isNotEmpty) ...[
            SizedBox(height: 10.h),
            Text(
              AppLocalizations.of(context)!
                  .foundNInverters('${_csInvNetworks.length}'),
              style: TextStyle(fontSize: 12.sp, color: AppColor.textHint(context)),
            ),
            SizedBox(height: 8.h),
            ..._csInvNetworks.map((net) {
              final ssid = net.ssid ?? '';
              final rssi = net.level ?? -100;
              final sig = rssi > -50 ? '📶📶📶' : (rssi > -70 ? '📶📶' : '📶');
              return Card(
                margin: EdgeInsets.only(bottom: 8.h),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: ListTile(
                  leading: Container(
                    width: 44.w,
                    height: 44.w,
                    decoration: BoxDecoration(
                      color: AppColor.primarySoft(context),
                      borderRadius: BorderRadius.circular(10.r),
                    ),
                    child: const Icon(
                      Icons.solar_power,
                      color: AppColors.primary,
                      size: 22,
                    ),
                  ),
                  title: Text(
                    ssid,
                    style: TextStyle(
                      fontSize: 15.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    '$sig $rssi dBm',
                    style: TextStyle(
                      fontSize: 11.sp,
                      color: AppColor.textHint(context),
                    ),
                  ),
                  trailing: Icon(
                    Icons.arrow_forward_ios,
                    size: 14,
                    color: AppColor.textHint(context),
                  ),
                  onTap: () => _connectToAp(net),
                ),
              );
            }),
          ],
          if (_csInvNetworks.isEmpty && !_wifiScanning)
            Padding(
              padding: EdgeInsets.only(top: 16.h),
              child: Center(
                child: Container(
                  padding: EdgeInsets.all(24.w),
                  decoration: BoxDecoration(
                    color: AppColor.surfaceHover(context),
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.wifi_off,
                        size: 40.sp,
                        color: AppColor.textHint(context),
                      ),
                      SizedBox(height: 10.h),
                      Text(
                        AppLocalizations.of(context)!.noInverterFound,
                        style: TextStyle(
                          fontSize: 14.sp,
                          color: AppColor.textHint(context),
                        ),
                      ),
                      SizedBox(height: 4.h),
                      Text(
                        AppLocalizations.of(context)!.ensureDevicePowered,
                        style: TextStyle(
                          fontSize: 11.sp,
                          color: AppColor.textHint(context),
                        ),
                      ),
                      SizedBox(height: 12.h),
                      OutlinedButton.icon(
                        onPressed: _scanCSInvWiFi,
                        icon: const Icon(Icons.refresh, size: 16),
                        label: Text(AppLocalizations.of(context)!.retry),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
        if (_provisionStep == 1) ...[
          Container(
            padding: EdgeInsets.all(16.w),
            decoration: BoxDecoration(
              color: AppColor.primarySoft(context),
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: Row(
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Text(
                    _provisionStatus,
                    style: TextStyle(
                      fontSize: 13.sp,
                      color: AppColor.textPrimary(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (deviceConnected) ...[
          Container(
            padding: EdgeInsets.all(12.w),
            margin: EdgeInsets.only(bottom: 16.h),
            decoration: BoxDecoration(
              color: AppColors.badgeNormalBg,
              borderRadius: BorderRadius.circular(10.r),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.check_circle,
                  color: AppColors.successLight,
                  size: 20,
                ),
                SizedBox(width: 8.w),
                Expanded(
                  child: Text(
                    AppLocalizations.of(context)!
                        .connectedTo(_selectedDeviceAp?.ssid ?? ''),
                    style: TextStyle(
                      fontSize: 13.sp,
                      color: AppColors.badgeNormalText,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: _resetProvision,
                  child: Text(
                    AppLocalizations.of(context)!.disconnect,
                    style: TextStyle(
                      fontSize: 12.sp,
                      color: AppColors.errorLight,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (deviceConnected) ...[
          SizedBox(
            width: double.infinity,
            height: 44.h,
            child: OutlinedButton.icon(
              onPressed:
                  _scanningNearbyWifi ? null : _rescanNearbyWifiFromPhone,
              icon: _scanningNearbyWifi
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.wifi, size: 20),
              label: Text(
                _scanningNearbyWifi
                    ? AppLocalizations.of(context)!.scanning
                    : AppLocalizations.of(context)!.scanNearbyWifi,
                style: const TextStyle(fontSize: 14),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.r),
                ),
                side: const BorderSide(color: AppColors.primary),
              ),
            ),
          ),
          SizedBox(height: 8.h),
          if (_nearbyWifiList.isNotEmpty) ...[
            Text(
              AppLocalizations.of(context)!.clickWifiToFill,
              style: TextStyle(fontSize: 11.sp, color: AppColor.textHint(context)),
            ),
            SizedBox(height: 6.h),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(color: AppColor.border(context)),
              ),
              constraints: BoxConstraints(maxHeight: 200.h),
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: _nearbyWifiList.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, indent: 56),
                itemBuilder: (_, i) {
                  final w = _nearbyWifiList[i];
                  final sig =
                      w.rssi > -50 ? '📶📶📶' : (w.rssi > -70 ? '📶📶' : '📶');
                  final selected = _workingSsidController.text == w.ssid;
                  return ListTile(
                    leading: Icon(
                      w.encrypted ? Icons.lock_outline : Icons.wifi,
                      size: 20,
                      color: selected ? AppColors.primary : AppColor.textHint(context),
                    ),
                    title: Text(
                      w.ssid,
                      style: TextStyle(
                        fontSize: 13.sp,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                        color: AppColor.textPrimary(context),
                      ),
                    ),
                    trailing: Text(
                      '$sig ${w.rssi}dBm',
                      style: TextStyle(
                        fontSize: 10.sp,
                        color: AppColor.textHint(context),
                      ),
                    ),
                    tileColor: selected ? AppColor.primarySoft(context) : null,
                    dense: true,
                    onTap: () => _pickWiFi(w),
                  );
                },
              ),
            ),
            SizedBox(height: 16.h),
          ],
          TextField(
            controller: _workingSsidController,
            decoration: InputDecoration(
              labelText: AppLocalizations.of(context)!.wifiName,
              hintText: AppLocalizations.of(context)!.clickAboveOrManual,
              prefixIcon: const Icon(Icons.wifi, color: AppColors.primary),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12.r)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.r),
                borderSide:
                    const BorderSide(color: AppColors.primary, width: 1.5),
              ),
            ),
          ),
          SizedBox(height: 12.h),
          TextField(
            controller: _workingPasswordController,
            obscureText: !_showPassword,
            decoration: InputDecoration(
              labelText: AppLocalizations.of(context)!.wifiPassword,
              hintText: AppLocalizations.of(context)!.inputWifiPassword,
              prefixIcon:
                  Icon(Icons.lock_outline, color: AppColor.textHint(context)),
              suffixIcon: IconButton(
                icon: Icon(
                  _showPassword ? Icons.visibility_off : Icons.visibility,
                  color: AppColor.textHint(context),
                ),
                onPressed: () => setState(() => _showPassword = !_showPassword),
              ),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12.r)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.r),
                borderSide:
                    const BorderSide(color: AppColors.primary, width: 1.5),
              ),
            ),
          ),
          SizedBox(height: 20.h),
          SizedBox(
            width: double.infinity,
            height: 50.h,
            child: ElevatedButton.icon(
              onPressed: _provisioning ? null : _sendProvisionConfig,
              icon: _provisioning
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.router, size: 22),
              label: Text(
                _provisioning
                    ? AppLocalizations.of(context)!.configuring
                    : AppLocalizations.of(context)!.sendingProvisionInfo,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.successLight,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.r),
                ),
              ),
            ),
          ),
        ],
        if (_provisionStatus.isNotEmpty) ...[
          SizedBox(height: 16.h),
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(14.w),
            decoration: BoxDecoration(
              color: _provisionOk
                  ? AppColors.badgeNormalBg
                  : (_provisionStatus.contains('❌')
                      ? AppColors.badgeAlarmBg
                      : AppColor.primarySoft(context)),
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: Row(
              children: [
                Icon(
                  _provisionOk
                      ? Icons.check_circle
                      : (_provisionStatus.contains('❌')
                          ? Icons.error
                          : Icons.info),
                  size: 20.sp,
                  color: _provisionOk
                      ? AppColors.successLight
                      : (_provisionStatus.contains('❌')
                          ? AppColors.errorLight
                          : AppColors.primary),
                ),
                SizedBox(width: 10.w),
                Expanded(
                  child: Text(
                    _provisionStatus,
                    style: TextStyle(
                      fontSize: 13.sp,
                      color: AppColor.textPrimary(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        SizedBox(height: 60.h),
      ],
    );
  }

  Widget _buildBleSection() {
    final l10n = AppLocalizations.of(context)!;
    // 计算Current state
    final bool deviceSelected = _selectedBleDevice != null;
    final bool isConfiguring =
        _bleStatus == BleProvisioningStatus.writingCredentials ||
            _bleStatus == BleProvisioningStatus.waitingForResult;
    final bool isCompleted = _bleStatus == BleProvisioningStatus.wifiConnected;
    final bool isConnected = _bleStatus == BleProvisioningStatus.bleConnected;

    // 判断当前阶段
    final bool isError = _bleStatus == BleProvisioningStatus.failed ||
        _bleStatus == BleProvisioningStatus.error;
    final bool isTimeout = _bleStatus == BleProvisioningStatus.timeout; // 扫描超时
    final bool showSuccessPhase = _provisionSuccess; // 配网成功阶段
    final bool showScanPhase = !showSuccessPhase &&
        (_bleScanning ||
            (_bleDevices.isNotEmpty && !deviceSelected) ||
            (!deviceSelected && !_bleScanning && !isError && !isTimeout));
    final bool showNoDevicePhase = isTimeout &&
        !showSuccessPhase &&
        !isError &&
        !deviceSelected; // 未发现设备阶段
    final bool showConnectingPhase = !showSuccessPhase && _bleConnecting;
    final bool showConfigPhase =
        !showSuccessPhase && isConnected && !isConfiguring;
    final bool showConfiguringPhase = !showSuccessPhase && isConfiguring;
    final bool showCompletedPhase = isCompleted;
    final bool showErrorPhase = !showSuccessPhase && isError && !deviceSelected;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 步骤指示器
        WifiProvisionStepIndicator(
          steps: [
            WifiProvisionStepData(
              label: AppLocalizations.of(context)!.scanNearInverters,
              isCompleted: deviceSelected,
              isCurrent: showScanPhase,
            ),
            WifiProvisionStepData(
              label: AppLocalizations.of(context)!.selectWifi,
              isCompleted: isCompleted || isConnected || isConfiguring,
              isCurrent: showConfigPhase || showConfiguringPhase,
            ),
            WifiProvisionStepData(
              label: AppLocalizations.of(context)!.finish,
              isCompleted: isCompleted,
              isCurrent: showCompletedPhase,
            ),
          ],
        ),
        SizedBox(height: 24.h),

        // 小烁配网引导插画：BLE 扫描阶段流程引导（美术路由 C7/guide-wifi）
        if (showScanPhase) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(14.r),
            // 图片为 1536x1024 横图：等比容器完整显示，避免 cover 裁剪人物头部
            child: AspectRatio(
              aspectRatio: 3 / 2,
              child: Image.asset(
                CsergyAssets.xiaoshuoWifiGuide,
                fit: BoxFit.cover,
              ),
            ),
          ),
          SizedBox(height: 16.h),
        ],

        // 配网成功显示
        if (showSuccessPhase) ...[
          Container(
            padding: EdgeInsets.all(16.w),
            decoration: BoxDecoration(
              color: AppColors.badgeNormalBg,
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: Column(
              children: [
                const Icon(
                  Icons.check_circle,
                  color: AppColors.successLight,
                  size: 40,
                ),
                SizedBox(height: 12.h),
                Text(
                  l10n.bleSuccessExclaim,
                  style: TextStyle(
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w600,
                    color: AppColors.successLight,
                  ),
                ),
                SizedBox(height: 8.h),
                Text(
                  l10n.deviceConnectingWifi,
                  style: TextStyle(
                    fontSize: 13.sp,
                    color: AppColor.textSecondary(context),
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 16.h),
                SizedBox(
                  width: double.infinity,
                  height: 44.h,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        _provisionSuccess = false;
                        _selectedBleDevice = null;
                        _bleErrorMessage = null;
                        _workingSsidController.clear();
                        _workingPasswordController.clear();
                      });
                      _disconnectBleDevice();
                    },
                    icon: const Icon(Icons.check, size: 20),
                    label:
                        Text(l10n.done, style: const TextStyle(fontSize: 15)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        // 错误状态显示
        if (showErrorPhase) ...[
          Container(
            padding: EdgeInsets.all(16.w),
            decoration: BoxDecoration(
              color: AppColors.badgeAlarmBg,
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: Column(
              children: [
                const Icon(
                  Icons.error_outline,
                  color: AppColors.errorLight,
                  size: 40,
                ),
                SizedBox(height: 12.h),
                Text(
                  _bleStatus == BleProvisioningStatus.timeout
                      ? l10n.bleTimeout
                      : _bleStatus == BleProvisioningStatus.failed
                          ? l10n.bleFailed
                          : l10n.bleError,
                  style: TextStyle(
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w600,
                    color: AppColors.errorLight,
                  ),
                ),
                SizedBox(height: 8.h),
                Text(
                  l10n.checkDeviceWorking,
                  style: TextStyle(
                    fontSize: 13.sp,
                    color: AppColor.textSecondary(context),
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 16.h),
                SizedBox(
                  width: double.infinity,
                  height: 44.h,
                  child: ElevatedButton.icon(
                    onPressed: _startBleScan,
                    icon: const Icon(Icons.refresh, size: 20),
                    label:
                        Text(l10n.rescan, style: const TextStyle(fontSize: 15)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        // 未发现设备显示（扫描超时）
        if (showNoDevicePhase) ...[
          Container(
            padding: EdgeInsets.all(16.w),
            decoration: BoxDecoration(
              color: AppColors.badgeAlarmBg,
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.bluetooth_disabled,
                  color: AppColor.textHint(context),
                  size: 40,
                ),
                SizedBox(height: 12.h),
                Text(
                  l10n.noDeviceFound,
                  style: TextStyle(
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w600,
                    color: AppColor.textSecondary(context),
                  ),
                ),
                SizedBox(height: 8.h),
                Text(
                  l10n.ensureProvisionMode,
                  style: TextStyle(fontSize: 13.sp, color: AppColor.textHint(context)),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 16.h),
                SizedBox(
                  width: double.infinity,
                  height: 44.h,
                  child: ElevatedButton.icon(
                    onPressed: _startBleScan,
                    icon: const Icon(Icons.refresh, size: 20),
                    label:
                        Text(l10n.rescan, style: const TextStyle(fontSize: 15)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        // 说明信息（仅在扫描阶段显示）
        if (showScanPhase) ...[
          Container(
            padding: EdgeInsets.all(14.w),
            margin: EdgeInsets.only(bottom: 20.h),
            decoration: BoxDecoration(
              color: AppColor.primarySoft(context),
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline,
                  color: AppColors.primary,
                  size: 20,
                ),
                SizedBox(width: 10.w),
                Expanded(
                  child: Text(
                    l10n.bleModeDescription,
                    style: TextStyle(
                      fontSize: 12.sp,
                      color: AppColor.textPrimary(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        // 扫描按钮（仅在扫描阶段显示）
        if (showScanPhase) ...[
          SizedBox(
            width: double.infinity,
            height: 46.h,
            child: ElevatedButton.icon(
              onPressed: () {
                debugPrint(
                  '[BLE] Scan button clicked, _bleScanning=$_bleScanning',
                );
                if (!_bleScanning) {
                  _startBleScan();
                }
              },
              icon: _bleScanning
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.bluetooth_searching, size: 22),
              label: Text(
                _bleScanning
                    ? AppLocalizations.of(context)!.scanning
                    : AppLocalizations.of(context)!.scanNearInverters,
                style: const TextStyle(fontSize: 15),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.r),
                ),
              ),
            ),
          ),

          SizedBox(height: 16.h),

          // 设备列表
          if (_bleDevices.isNotEmpty) ...[
            Text(
              AppLocalizations.of(context)!
                  .foundNInverters('${_bleDevices.length}'),
              style: TextStyle(fontSize: 12.sp, color: AppColor.textHint(context)),
            ),
            SizedBox(height: 8.h),
            ..._bleDevices.map((device) {
              final rssi = device.rssi;
              final sig = rssi > -50 ? '📶📶📶' : (rssi > -70 ? '📶📶' : '📶');
              return Card(
                margin: EdgeInsets.only(bottom: 8.h),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: ListTile(
                  leading: Container(
                    width: 44.w,
                    height: 44.w,
                    decoration: BoxDecoration(
                      color: AppColor.primarySoft(context),
                      borderRadius: BorderRadius.circular(10.r),
                    ),
                    child: const Icon(
                      Icons.bluetooth,
                      color: AppColors.primary,
                      size: 22,
                    ),
                  ),
                  title: Text(
                    device.sn.isNotEmpty ? device.sn : device.deviceName,
                    style: TextStyle(
                      fontSize: 15.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    '$sig $rssi dBm',
                    style: TextStyle(
                      fontSize: 11.sp,
                      color: AppColor.textHint(context),
                    ),
                  ),
                  trailing: _bleConnecting &&
                          _selectedBleDevice?.macAddress == device.macAddress
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          Icons.arrow_forward_ios,
                          size: 14,
                          color: AppColor.textHint(context),
                        ),
                  onTap:
                      _bleConnecting ? null : () => _connectToBleDevice(device),
                ),
              );
            }),
          ],

          // 无设备提示
          if (_bleDevices.isEmpty && !_bleScanning)
            Padding(
              padding: EdgeInsets.only(top: 16.h),
              child: Center(
                child: Container(
                  padding: EdgeInsets.all(24.w),
                  decoration: BoxDecoration(
                    color: AppColor.surfaceHover(context),
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.bluetooth_disabled,
                        size: 40.sp,
                        color: AppColor.textHint(context),
                      ),
                      SizedBox(height: 10.h),
                      Text(
                        AppLocalizations.of(context)!.noInverterFound,
                        style: TextStyle(
                          fontSize: 14.sp,
                          color: AppColor.textHint(context),
                        ),
                      ),
                      SizedBox(height: 4.h),
                      Text(
                        AppLocalizations.of(context)!.ensureDevicePowered,
                        style: TextStyle(
                          fontSize: 11.sp,
                          color: AppColor.textHint(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ], // 结束扫描阶段

        // 连接阶段
        if (showConnectingPhase) ...[
          SizedBox(height: 16.h),
          Container(
            padding: EdgeInsets.all(16.w),
            decoration: BoxDecoration(
              color: AppColor.primarySoft(context),
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: Row(
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Text(
                    _getBleStatusText(),
                    style: TextStyle(
                      fontSize: 13.sp,
                      color: AppColor.textPrimary(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        // 已连接设备信息
        if (_selectedBleDevice != null &&
            (_bleStatus == BleProvisioningStatus.bleConnected ||
                _bleStatus == BleProvisioningStatus.wifiConnected)) ...[
          Container(
            padding: EdgeInsets.all(12.w),
            margin: EdgeInsets.only(bottom: 16.h),
            decoration: BoxDecoration(
              color: AppColors.badgeNormalBg,
              borderRadius: BorderRadius.circular(10.r),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.check_circle,
                  color: AppColors.successLight,
                  size: 20,
                ),
                SizedBox(width: 8.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.connectedTo(
                          _selectedBleDevice!.sn.isNotEmpty
                              ? _selectedBleDevice!.sn
                              : _selectedBleDevice!.deviceName,
                        ),
                        style: TextStyle(
                          fontSize: 13.sp,
                          color: AppColors.badgeNormalText,
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: _disconnectBleDevice,
                  child: Text(
                    AppLocalizations.of(context)!.disconnect,
                    style: TextStyle(
                      fontSize: 12.sp,
                      color: AppColors.errorLight,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        // 配网失败错误提示
        if (_bleErrorMessage != null && showConfigPhase) ...[
          Container(
            padding: EdgeInsets.all(12.w),
            margin: EdgeInsets.only(bottom: 16.h),
            decoration: BoxDecoration(
              color: AppColors.badgeAlarmBg,
              borderRadius: BorderRadius.circular(10.r),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.error_outline,
                  color: AppColors.errorLight,
                  size: 20,
                ),
                SizedBox(width: 8.w),
                Expanded(
                  child: Text(
                    _bleErrorMessage!,
                    style: TextStyle(
                      fontSize: 13.sp,
                      color: AppColors.error,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() => _bleErrorMessage = null),
                  child: Icon(
                    Icons.close,
                    size: 16,
                    color: AppColor.textHint(context),
                  ),
                ),
              ],
            ),
          ),
        ],

        // WiFi配置表单（仅在配置阶段显示）
        if (showConfigPhase) ...[
          SizedBox(
            width: double.infinity,
            height: 44.h,
            child: OutlinedButton.icon(
              onPressed:
                  _scanningNearbyWifi ? null : _rescanNearbyWifiFromPhone,
              icon: _scanningNearbyWifi
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.wifi, size: 20),
              label: Text(
                _scanningNearbyWifi
                    ? AppLocalizations.of(context)!.scanning
                    : AppLocalizations.of(context)!.scanNearbyWifi,
                style: const TextStyle(fontSize: 14),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.r),
                ),
                side: const BorderSide(color: AppColors.primary),
              ),
            ),
          ),
          SizedBox(height: 8.h),
          if (_nearbyWifiList.isNotEmpty) ...[
            Text(
              AppLocalizations.of(context)!.clickWifiToFill,
              style: TextStyle(fontSize: 11.sp, color: AppColor.textHint(context)),
            ),
            SizedBox(height: 6.h),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(color: AppColor.border(context)),
              ),
              constraints: BoxConstraints(maxHeight: 200.h),
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: _nearbyWifiList.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, indent: 56),
                itemBuilder: (_, i) {
                  final w = _nearbyWifiList[i];
                  final sig =
                      w.rssi > -50 ? '📶📶📶' : (w.rssi > -70 ? '📶📶' : '📶');
                  final selected = _workingSsidController.text == w.ssid;
                  return ListTile(
                    leading: Icon(
                      w.encrypted ? Icons.lock_outline : Icons.wifi,
                      size: 20,
                      color: selected ? AppColors.primary : AppColor.textHint(context),
                    ),
                    title: Text(
                      w.ssid,
                      style: TextStyle(
                        fontSize: 13.sp,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                        color: AppColor.textPrimary(context),
                      ),
                    ),
                    trailing: Text(
                      '$sig ${w.rssi}dBm',
                      style: TextStyle(
                        fontSize: 10.sp,
                        color: AppColor.textHint(context),
                      ),
                    ),
                    tileColor: selected ? AppColor.primarySoft(context) : null,
                    dense: true,
                    onTap: () => _pickWiFi(w),
                  );
                },
              ),
            ),
            SizedBox(height: 16.h),
          ],
          TextField(
            controller: _workingSsidController,
            decoration: InputDecoration(
              labelText: AppLocalizations.of(context)!.wifiName,
              hintText: AppLocalizations.of(context)!.clickAboveOrManual,
              prefixIcon: const Icon(Icons.wifi, color: AppColors.primary),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12.r)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.r),
                borderSide:
                    const BorderSide(color: AppColors.primary, width: 1.5),
              ),
            ),
          ),
          SizedBox(height: 12.h),
          TextField(
            controller: _workingPasswordController,
            obscureText: !_showPassword,
            decoration: InputDecoration(
              labelText: AppLocalizations.of(context)!.wifiPassword,
              hintText: AppLocalizations.of(context)!.inputWifiPassword,
              prefixIcon:
                  Icon(Icons.lock_outline, color: AppColor.textHint(context)),
              suffixIcon: IconButton(
                icon: Icon(
                  _showPassword ? Icons.visibility_off : Icons.visibility,
                  color: AppColor.textHint(context),
                ),
                onPressed: () => setState(() => _showPassword = !_showPassword),
              ),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12.r)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.r),
                borderSide:
                    const BorderSide(color: AppColors.primary, width: 1.5),
              ),
            ),
          ),
          SizedBox(height: 12.h),
          TextField(
            controller: _pinController,
            keyboardType: TextInputType.number,
            maxLength: 6,
            decoration: InputDecoration(
              labelText: l10n.pinInputTitle,
              hintText: l10n.pinInputHint,
              prefixIcon:
                  const Icon(Icons.password, color: AppColors.primary),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12.r)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.r),
                borderSide:
                    const BorderSide(color: AppColors.primary, width: 1.5),
              ),
            ),
          ),
          SizedBox(height: 20.h),
          SizedBox(
            width: double.infinity,
            height: 50.h,
            child: ElevatedButton.icon(
              onPressed: _provisioning ? null : _sendBleProvisionConfig,
              icon: _provisioning
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.bluetooth, size: 22),
              label: Text(
                _provisioning ? l10n.provisioningNow : l10n.sendWifiConfig,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.successLight,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.r),
                ),
              ),
            ),
          ),
        ],

        // 配置中阶段
        if (showConfiguringPhase) ...[
          SizedBox(height: 16.h),
          Container(
            padding: EdgeInsets.all(16.w),
            decoration: BoxDecoration(
              color: AppColor.primarySoft(context),
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: Row(
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Text(
                    _getBleStatusText(),
                    style: TextStyle(
                      fontSize: 13.sp,
                      color: AppColor.textPrimary(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        // 完成阶段
        if (showCompletedPhase) ...[
          SizedBox(height: 16.h),
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(14.w),
            decoration: BoxDecoration(
              color: AppColors.badgeNormalBg,
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.check_circle,
                  color: AppColors.successLight,
                  size: 20,
                ),
                SizedBox(width: 10.w),
                Expanded(
                  child: Text(
                    _getBleStatusText(),
                    style: TextStyle(
                      fontSize: 13.sp,
                      color: AppColor.textPrimary(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        SizedBox(height: 60.h),
      ],
    );
  }

}
