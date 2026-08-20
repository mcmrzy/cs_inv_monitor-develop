part of 'device_control_page.dart';
// extension 调用 State.setState 属同库受控拆分，豁免 protected 告警
// ignore_for_file: invalid_use_of_protected_member

/// 设备控制页各 Tab 构建方法：自巨型 device_control_page 物理拆分，
/// 状态与数据加载仍在 _DeviceControlPageState（此处仅迁移构建方法）
extension _DeviceControlTabSections on _DeviceControlPageState {
  Widget _buildBatteryProtectionTab() {
    final l10n = AppLocalizations.of(context)!;
    return ListView(
      padding: EdgeInsets.all(16.w),
      children: [
        _buildOfflineWarning(),

        // 备电保留 SOC
        _buildSliderCard(
          title: l10n.str('control_reserve_soc'),
          subtitle: l10n.str('control_reserve_soc_hint'),
          value: _reserveSoc,
          min: 0,
          max: 80,
          unit: '%',
          icon: Icons.battery_saver,
          color: AppColors.warning,
          onChanged: (v) => setState(() => _reserveSoc = v),
          onCommit: () => _sendSocWindow(),
        ),

        SizedBox(height: 12.h),

        // 充电目标 SOC
        _buildSliderCard(
          title: l10n.str('control_target_soc'),
          subtitle: l10n.str('control_target_soc_hint'),
          value: _chargeTargetSoc,
          min: 20,
          max: 100,
          unit: '%',
          icon: Icons.battery_charging_full,
          color: AppColors.success,
          onChanged: (v) => setState(() => _chargeTargetSoc = v),
          onCommit: () => _sendSocWindow(),
        ),

        SizedBox(height: 12.h),

        // 充电速度预设
        _buildChargeSpeedCard(),

        SizedBox(height: 12.h),

        // BMS 实时限制
        _buildBmsLimitsCard(),
      ],
    );
  }

  Widget _buildSliderCard({
    required String title,
    required String subtitle,
    required double value,
    required double min,
    required double max,
    required String unit,
    required IconData icon,
    required Color color,
    required ValueChanged<double> onChanged,
    required VoidCallback onCommit,
  }) {
    return Container(
      decoration: AppColor.card(context),
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36.w,
                height: 36.w,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8.r),
                ),
                child: Icon(icon, size: 18.sp, color: color),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 2.h),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11.sp,
                        color: AppColor.textHint(context),
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${value.toStringAsFixed(0)}$unit',
                style: TextStyle(
                  fontSize: 18.sp,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
          SizedBox(height: 8.h),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: ((max - min) ~/ 5),
            activeColor: color,
            onChanged: _isOnline ? onChanged : null,
            onChangeEnd: (_) => _isOnline ? onCommit() : null,
          ),
        ],
      ),
    );
  }

  void _sendSocWindow() {
    final lowX10 = (_reserveSoc * 10).round();
    final highX10 = (_chargeTargetSoc * 10).round();
    _sendCommand(
      'set_soc_window',
      params: {
        'low_x10': lowX10,
        'high_x10': highX10,
      },
    );
  }

  Widget _buildChargeSpeedCard() {
    final l10n = AppLocalizations.of(context)!;
    final presets = [
      {
        'label': l10n.str('control_charge_gentle'),
        'icon': Icons.eco_outlined,
        'color': AppColors.teal,
        'limit': 30,
      },
      {
        'label': l10n.str('control_charge_standard'),
        'icon': Icons.speed_outlined,
        'color': AppColors.primary,
        'limit': 60,
      },
      {
        'label': l10n.str('control_charge_fast'),
        'icon': Icons.flash_on,
        'color': AppColors.orange,
        'limit': 100,
      },
    ];

    return Container(
      decoration: AppColor.card(context),
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.speed_rounded,
                size: 20.sp,
                color: AppColors.primary,
              ),
              SizedBox(width: 8.w),
              Text(
                l10n.str('control_charge_speed'),
                style: TextStyle(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          SizedBox(height: 12.h),
          Row(
            children: presets.asMap().entries.map((entry) {
              final idx = entry.key;
              final p = entry.value;
              final isSelected = _chargeSpeedPreset == idx;
              final color = p['color'] as Color;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: idx == 1 ? 8.w : 0,
                  ),
                  child: GestureDetector(
                    onTap: _isOnline
                        ? () {
                            setState(() => _chargeSpeedPreset = idx);
                            _sendCommand(
                              'set_charge_limit',
                              params: {
                                'max_current_pct': p['limit'],
                              },
                            );
                          }
                        : null,
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        vertical: 12.h,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? color.withValues(alpha: 0.1)
                            : AppColor.surfaceHover(context)
                                .withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(10.r),
                        border: Border.all(
                          color: isSelected ? color : Colors.transparent,
                          width: 1.5,
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            p['icon'] as IconData,
                            size: 22.sp,
                            color: isSelected ? color : AppColor.textHint(context),
                          ),
                          SizedBox(height: 4.h),
                          Text(
                            p['label'] as String,
                            style: TextStyle(
                              fontSize: 12.sp,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                              color:
                                  isSelected ? color : AppColor.textSecondary(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildBmsLimitsCard() {
    final l10n = AppLocalizations.of(context)!;
    final entries = _bmsLimits.entries.toList();
    return Container(
      decoration: AppColor.card(context),
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.security_outlined,
                size: 20.sp,
                color: AppColors.info,
              ),
              SizedBox(width: 8.w),
              Text(
                l10n.str('control_bms_limits'),
                style: TextStyle(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          SizedBox(height: 8.h),
          if (entries.isEmpty)
            Text(
              l10n.noData,
              style: TextStyle(
                fontSize: 12.sp,
                color: AppColor.textHint(context),
              ),
            )
          else
            ...entries.map(
              (e) => Padding(
                padding: EdgeInsets.symmetric(vertical: 4.h),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      e.key,
                      style: TextStyle(
                        fontSize: 13.sp,
                        color: AppColor.textSecondary(context),
                      ),
                    ),
                    Text(
                      '${e.value}',
                      style: TextStyle(
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  //  Tab 3 — 能源计划
  // ─────────────────────────────────────────────────────────────────────

  Widget _buildEnergyScheduleTab() {
    final l10n = AppLocalizations.of(context)!;
    return ListView(
      padding: EdgeInsets.all(16.w),
      children: [
        _buildOfflineWarning(),

        // 时间段列表
        Container(
          decoration: AppColor.card(context),
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
          child: Row(
            children: [
              Icon(
                Icons.schedule_rounded,
                size: 20.sp,
                color: AppColors.primary,
              ),
              SizedBox(width: 8.w),
              Expanded(
                child: Text(
                  l10n.str('control_schedule_list'),
                  style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                onPressed:
                    _isOnline ? () => _showEnergyScheduleEditor(null) : null,
                icon: Icon(
                  Icons.add_circle_outline,
                  size: 22.sp,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 8.h),

        if (_energySchedule.isEmpty)
          Container(
            decoration: AppColor.card(context),
            padding: EdgeInsets.all(24.w),
            child: Column(
              children: [
                Icon(
                  Icons.event_available,
                  size: 36.sp,
                  color: AppColor.textHint(context),
                ),
                SizedBox(height: 8.h),
                Text(
                  l10n.noData,
                  style: TextStyle(
                    fontSize: 13.sp,
                    color: AppColor.textHint(context),
                  ),
                ),
              ],
            ),
          )
        else
          ..._energySchedule.map(_buildEnergyScheduleItem),

        SizedBox(height: 12.h),

        // 临时覆盖显示
        Container(
          decoration: AppColor.card(context),
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.edit_calendar,
                    size: 20.sp,
                    color: AppColors.warning,
                  ),
                  SizedBox(width: 8.w),
                  Text(
                    l10n.str('control_temporary_override'),
                    style: TextStyle(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 8.h),
              if (_controlOverrides.isEmpty)
                Text(
                  l10n.str('control_no_override'),
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: AppColor.textHint(context),
                  ),
                )
              else
                ..._controlOverrides.map((o) {
                  final m = o as Map<String, dynamic>;
                  return Padding(
                    padding: EdgeInsets.symmetric(vertical: 4.h),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${m['command'] ?? '—'}',
                          style: TextStyle(
                            fontSize: 13.sp,
                            color: AppColor.textSecondary(context),
                          ),
                        ),
                        Text(
                          '${m['params'] ?? ''}',
                          style: TextStyle(
                            fontSize: 12.sp,
                            color: AppColor.textHint(context),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEnergyScheduleItem(Map<String, dynamic> slot) {
    final l10n = AppLocalizations.of(context)!;
    final start = slot['start_time'] ?? slot['start'] ?? '—';
    final end = slot['end_time'] ?? slot['end'] ?? '—';
    final mode = slot['mode'] ?? slot['action'] ?? '—';
    final enabled = slot['enabled'] ?? true;

    return Container(
      margin: EdgeInsets.only(bottom: 8.h),
      decoration: AppColor.card(context),
      child: ListTile(
        contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 4.h),
        leading: Container(
          width: 40.w,
          height: 40.w,
          decoration: BoxDecoration(
            color: (enabled ? AppColors.primary : AppColor.textHint(context))
                .withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10.r),
          ),
          child: Icon(
            Icons.timer_outlined,
            size: 20.sp,
            color: enabled ? AppColors.primary : AppColor.textHint(context),
          ),
        ),
        title: Text(
          '$start — $end',
          style: TextStyle(
            fontSize: 14.sp,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Text(
          l10n.str('control_mode_value', {'mode': '$mode'}),
          style: TextStyle(
            fontSize: 11.sp,
            color: AppColor.textHint(context),
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(
                Icons.edit_outlined,
                size: 18.sp,
                color: AppColors.primary,
              ),
              onPressed:
                  _isOnline ? () => _showEnergyScheduleEditor(slot) : null,
            ),
            IconButton(
              icon: Icon(
                Icons.delete_outline,
                size: 18.sp,
                color: AppColors.error,
              ),
              onPressed: _isOnline ? () => _deleteEnergySchedule(slot) : null,
            ),
          ],
        ),
      ),
    );
  }

  void _showEnergyScheduleEditor(Map<String, dynamic>? existing) {
    final l10n = AppLocalizations.of(context)!;
    final isEdit = existing != null;
    final startCtrl =
        TextEditingController(text: existing?['start_time'] ?? '');
    final endCtrl = TextEditingController(text: existing?['end_time'] ?? '');
    final modeCtrl = TextEditingController(text: existing?['mode'] ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          isEdit
              ? l10n.str('control_edit_schedule')
              : l10n.str('control_add_schedule'),
          style: TextStyle(
            fontSize: 16.sp,
            fontWeight: FontWeight.w600,
          ),
        ),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: startCtrl,
                decoration: InputDecoration(
                  labelText: l10n.str('control_start_time'),
                  hintText: l10n.str('control_start_time_hint'),
                ),
              ),
              SizedBox(height: 12.h),
              TextField(
                controller: endCtrl,
                decoration: InputDecoration(
                  labelText: l10n.str('control_end_time'),
                  hintText: l10n.str('control_end_time_hint'),
                ),
              ),
              SizedBox(height: 12.h),
              TextField(
                controller: modeCtrl,
                decoration: InputDecoration(
                  labelText: l10n.str('control_mode'),
                  hintText: l10n.str('control_mode_hint'),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _saveEnergySchedule(
                existing,
                startCtrl.text,
                endCtrl.text,
                modeCtrl.text,
                isEdit,
              );
            },
            child: Text(AppLocalizations.of(context)!.save),
          ),
        ],
      ),
    );
  }

  void _saveEnergySchedule(
    Map<String, dynamic>? existing,
    String start,
    String end,
    String mode,
    bool isEdit,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final dio = getIt<Dio>();
    try {
      var periods = _energySchedule.map(Map<String, dynamic>.from).toList();
      final updatedPeriod = <String, dynamic>{
        if (existing != null) ...existing,
        'start_time': start,
        'end_time': end,
        'mode': mode,
        'enabled': existing?['enabled'] ?? true,
      };
      if (isEdit && existing != null) {
        periods = replaceSchedulePeriod(periods, existing, updatedPeriod);
      } else {
        periods.add(updatedPeriod);
      }
      final response = await dio.put(
        '/devices/by-sn/${widget.deviceSN}/energy-schedule',
        data: {
          'timezone': _energyScheduleTimezone,
          'enabled': _energyScheduleEnabled,
          'periods': periods,
        },
        options: Options(
          headers: {'If-Match': '$_energyScheduleRevision'},
        ),
      );
      final schedule = unwrapApiResponse<Map<String, dynamic>>(
        response.data,
        validate: isEnergySchedulePayload,
        expected: 'an updated schedule object',
      );
      if (mounted) {
        setState(() {
          _energySchedule = normalizeSchedulePeriods(schedule['periods']);
          _energyScheduleRevision = (schedule['revision'] as num?)?.toInt() ??
              _energyScheduleRevision;
          _energyScheduleTimezone =
              schedule['timezone'] as String? ?? _energyScheduleTimezone;
          _energyScheduleEnabled =
              schedule['enabled'] as bool? ?? _energyScheduleEnabled;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isEdit
                  ? l10n.str('control_schedule_updated')
                  : l10n.str('control_schedule_added'),
            ),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.str('control_schedule_save_failed')),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _deleteEnergySchedule(Map<String, dynamic> slot) async {
    final l10n = AppLocalizations.of(context)!;
    final dio = getIt<Dio>();
    try {
      final periods = removeSchedulePeriod(_energySchedule, slot);
      final response = await dio.put(
        '/devices/by-sn/${widget.deviceSN}/energy-schedule',
        data: {
          'timezone': _energyScheduleTimezone,
          'enabled': _energyScheduleEnabled,
          'periods': periods,
        },
        options: Options(
          headers: {'If-Match': '$_energyScheduleRevision'},
        ),
      );
      final schedule = unwrapApiResponse<Map<String, dynamic>>(
        response.data,
        validate: isEnergySchedulePayload,
        expected: 'an updated schedule object',
      );
      if (mounted) {
        setState(() {
          _energySchedule = normalizeSchedulePeriods(schedule['periods']);
          _energyScheduleRevision = (schedule['revision'] as num?)?.toInt() ??
              _energyScheduleRevision;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.str('control_schedule_deleted')),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.str('control_schedule_delete_failed')),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  //  Tab 4 — 设备信息
  // ─────────────────────────────────────────────────────────────────────

  Widget _buildDeviceInfoTab() {
    final l10n = AppLocalizations.of(context)!;
    return ListView(
      padding: EdgeInsets.all(16.w),
      children: [
        // 安装配置只读展示
        _buildInfoSection(
          l10n.str('control_installation'),
          Icons.build_outlined,
          _extractDeviceInfoFields(),
        ),

        SizedBox(height: 12.h),

        // 固件版本
        _buildFirmwareCard(),

        SizedBox(height: 12.h),

        // OTA升级按钮
        _buildOtaButtonsCard(),

        SizedBox(height: 12.h),

        // desired/reported 配置差异
        _buildConfigDiffCard(),

        SizedBox(height: 12.h),

        // 命令记录
        _buildCommandHistoryCard(),
      ],
    );
  }

  Map<String, dynamic> _extractDeviceInfoFields() {
    final l10n = AppLocalizations.of(context)!;
    final device =
        _deviceInfo['device'] as Map<String, dynamic>? ?? _deviceInfo;
    final ratedPowerW = device['rated_power_w'] as num?;
    final phase = device['phase'] as String?;
    return {
      l10n.str('control_device_sn'): widget.deviceSN,
      l10n.str('control_device_model'):
          device['model'] ?? device['model_name'] ?? '—',
      l10n.str('control_device_name'): device['alias'] ?? '—',
      if (ratedPowerW != null && ratedPowerW > 0)
        l10n.str('control_rated_power'):
            '${ratedPowerW.toDouble().toStringAsFixed(0)} W',
      if (phase != null && phase.isNotEmpty)
        l10n.str('control_phase'): phase,
      l10n.str('control_install_date'):
          device['install_date'] ?? device['created_at'] ?? '—',
      l10n.str('control_station'):
          device['station_name'] ?? device['station'] ?? '—',
    };
  }

  Widget _buildInfoSection(
    String title,
    IconData icon,
    Map<String, dynamic> fields,
  ) {
    return Container(
      decoration: AppColor.card(context),
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20.sp, color: AppColors.primary),
              SizedBox(width: 8.w),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          SizedBox(height: 8.h),
          ...fields.entries.map(
            (e) => Padding(
              padding: EdgeInsets.symmetric(vertical: 3.h),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    e.key,
                    style: TextStyle(
                      fontSize: 13.sp,
                      color: AppColor.textSecondary(context),
                    ),
                  ),
                  Flexible(
                    child: Text(
                      '${e.value}',
                      style: TextStyle(
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFirmwareCard() {
    final l10n = AppLocalizations.of(context)!;
    final device =
        _deviceInfo['device'] as Map<String, dynamic>? ?? _deviceInfo;
    // devices 表 V2.1 字段：firmware_arm / firmware_esp / hardware_version / bootloader_version
    final fwArm = device['firmware_arm'] as String?;
    final fwEsp = device['firmware_esp'] as String?;
    final hwVersion = device['hardware_version'] as String?;
    final bootloaderVersion = device['bootloader_version'] as String?;

    return Container(
      decoration: AppColor.card(context),
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.memory,
                size: 20.sp,
                color: AppColors.indigo,
              ),
              SizedBox(width: 8.w),
              Text(
                l10n.str('control_firmware_versions'),
                style: TextStyle(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          SizedBox(height: 8.h),
          _buildInfoRow(l10n.str('control_firmware_arm'),
              fwVersionLabel(fwArm)),
          _buildInfoRow(l10n.str('control_firmware_esp'),
              fwVersionLabel(fwEsp)),
          _buildInfoRow(l10n.str('control_hardware_version'),
              fwVersionLabel(hwVersion)),
          if (bootloaderVersion != null && bootloaderVersion.isNotEmpty)
            _buildInfoRow(
                l10n.str('control_bootloader_version'), bootloaderVersion),
        ],
      ),
    );
  }

  /// 空版本号统一展示为占位符
  static String fwVersionLabel(String? v) =>
      (v == null || v.isEmpty) ? '—' : v;

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 3.h),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13.sp,
              color: AppColor.textSecondary(context),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13.sp,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOtaButtonsCard() {
    final l10n = AppLocalizations.of(context)!;
    final device =
        _deviceInfo['device'] as Map<String, dynamic>? ?? _deviceInfo;
    final deviceModel =
        device['model'] ?? device['model_name'] ?? '';
    // 设备当前 ARM 主控固件版本（devices.firmware_arm）
    final firmwareVersion = device['firmware_arm'] as String? ?? '';

    return Container(
      decoration: AppColor.card(context),
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.system_update,
                size: 20.sp,
                color: AppColors.blue,
              ),
              SizedBox(width: 8.w),
              Text(
                l10n.firmwareUpgrade,
                style: TextStyle(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          SizedBox(height: 12.h),
          Row(
            children: [
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => LocalOTAChannelSelectPage(
                          deviceSN: widget.deviceSN,
                          deviceModel: deviceModel,
                          currentFirmwareVersion: firmwareVersion,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.phone_android),
                  label: Text(l10n.localUpgrade),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildConfigDiffCard() {
    final l10n = AppLocalizations.of(context)!;
    final desired = _controlState['desired'] as Map<String, dynamic>? ?? {};
    final reported = _controlState['reported'] as Map<String, dynamic>? ?? {};
    final allKeys = {...desired.keys, ...reported.keys}.toList()..sort();

    final diffKeys = allKeys.where((k) {
      final d = desired[k];
      final r = reported[k];
      return '$d' != '$r';
    }).toList();

    return Container(
      decoration: AppColor.card(context),
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.compare_arrows,
                size: 20.sp,
                color: AppColors.purple,
              ),
              SizedBox(width: 8.w),
              Text(
                l10n.str('control_config_diff'),
                style: TextStyle(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          SizedBox(height: 8.h),
          if (diffKeys.isEmpty)
            Text(
              l10n.str('control_config_in_sync'),
              style: TextStyle(
                fontSize: 12.sp,
                color: AppColors.success,
              ),
            )
          else
            ...diffKeys.map((k) {
              final d = desired[k] ?? '—';
              final r = reported[k] ?? '—';
              return Container(
                margin: EdgeInsets.only(bottom: 6.h),
                padding: EdgeInsets.all(8.w),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8.r),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      k,
                      style: TextStyle(
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w600,
                        color: AppColor.textPrimary(context),
                      ),
                    ),
                    SizedBox(height: 2.h),
                    Text(
                      l10n.str('control_desired_value', {'value': '$d'}),
                      style: TextStyle(
                        fontSize: 11.sp,
                        color: AppColors.primary,
                      ),
                    ),
                    Text(
                      l10n.str('control_reported_value', {'value': '$r'}),
                      style: TextStyle(
                        fontSize: 11.sp,
                        color: AppColor.textSecondary(context),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildCommandHistoryCard() {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      decoration: AppColor.card(context),
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.history,
                size: 20.sp,
                color: AppColors.teal,
              ),
              SizedBox(width: 8.w),
              Text(
                l10n.str('control_command_history'),
                style: TextStyle(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: _fetchCommandHistory,
                icon: Icon(
                  Icons.refresh,
                  size: 18.sp,
                  color: AppColor.textHint(context),
                ),
              ),
            ],
          ),
          SizedBox(height: 8.h),
          if (_commandHistory.isEmpty)
            Text(
              l10n.str('control_no_command_history'),
              style: TextStyle(
                fontSize: 12.sp,
                color: AppColor.textHint(context),
              ),
            )
          else
            ..._commandHistory.take(10).map((cmd) {
              final m = cmd as Map<String, dynamic>;
              final status = m['status'] as String? ?? '—';
              final command = m['command'] as String? ?? '—';
              final time = m['created_at'] ?? m['timestamp'] ?? '';
              return _buildCommandHistoryItem(command, status, '$time');
            }),
        ],
      ),
    );
  }

  Widget _buildCommandHistoryItem(
    String command,
    String status,
    String time,
  ) {
    Color statusColor;
    switch (status) {
      case 'success':
      case 'completed':
        statusColor = AppColors.success;
        break;
      case 'failed':
      case 'timeout':
      case 'cancelled':
        statusColor = AppColors.error;
        break;
      case 'acknowledged':
      case 'executing':
        statusColor = AppColors.info;
        break;
      default:
        statusColor = AppColor.textHint(context);
    }

    return Container(
      margin: EdgeInsets.only(bottom: 6.h),
      padding: EdgeInsets.symmetric(
        horizontal: 10.w,
        vertical: 8.h,
      ),
      decoration: BoxDecoration(
        color: AppColor.surfaceHover(context).withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8.r),
      ),
      child: Row(
        children: [
          Container(
            width: 8.w,
            height: 8.w,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: 8.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  command,
                  style: TextStyle(
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (time.isNotEmpty)
                  Text(
                    time,
                    style: TextStyle(
                      fontSize: 10.sp,
                      color: AppColor.textHint(context),
                    ),
                  ),
              ],
            ),
          ),
          Text(
            status,
            style: TextStyle(
              fontSize: 11.sp,
              color: statusColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  //  Dialogs
  // ─────────────────────────────────────────────────────────────────────

  void _showConfirmDialog(
    String title,
    String message,
    VoidCallback onConfirm,
  ) {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              onConfirm();
            },
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );
  }
}
