import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:inv_app/features/device/presentation/bloc/device_bloc.dart';
import 'package:inv_app/features/station/presentation/bloc/station_bloc.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/utils/sn_utils.dart';
import 'package:inv_app/l10n/app_localizations.dart';

class AddDevicePage extends StatefulWidget {
  final int? stationId;

  const AddDevicePage({super.key, this.stationId});

  @override
  State<AddDevicePage> createState() => _AddDevicePageState();
}

class _AddDevicePageState extends State<AddDevicePage> with SingleTickerProviderStateMixin {
  final _snController = TextEditingController();

  late TabController _tabController;
  bool _scanning = false;
  MobileScannerController? _cameraController;
  String _lastScanned = '';
  String _scannedPin = '';

  int _sessionBoundCount = 0;
  bool _bindSuccess = false;
  List<_ScanHistoryEntry> _scanHistory = [];
  bool _autoFlash = true;

  int? _selectedStationId;
  String? _selectedStationName;

  @override
  void initState() {
    super.initState();
    _selectedStationId = widget.stationId;
    _tabController = TabController(length: 2, vsync: this);
    _cameraController = MobileScannerController(
      torchEnabled: _autoFlash,
    );
    _loadScanHistory();
    _loadStationName();
  }

  Future<void> _loadStationName() async {
    if (_selectedStationId == null) return;
    try {
      final dio = getIt<Dio>();
      final res = await dio.get('/stations/$_selectedStationId');
      if (res.statusCode == 200 && mounted) {
        final data = res.data as Map<String, dynamic>;
        final station = data['station'] ?? data['data'] ?? data;
        final name = (station['station_name'] ?? station['name'] ?? '').toString();
        if (name.isNotEmpty) {
          setState(() => _selectedStationName = name);
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _snController.dispose();
    _tabController.dispose();
    _cameraController?.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_scanning) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null || barcode.rawValue == null) return;
    final raw = barcode.rawValue!.trim();
    if (raw.isEmpty || raw == _lastScanned) return;

    _scanning = true;

    final qr = parseQRCode(raw);
    if (qr == null) {
      _lastScanned = raw;
      _scannedPin = '';
      _scanning = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${AppLocalizations.of(context)!.qrNotRecognized}:\n$raw'),
          backgroundColor: AppColors.errorLight,
          duration: const Duration(seconds: 3),
        ),);
      }
      return;
    }

    final sn = qr.sn.toUpperCase();
    final pin = qr.pin ?? '';

    if (!validateSNFormat(sn)) {
      _lastScanned = sn;
      _scannedPin = '';
      _scanning = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${AppLocalizations.of(context)!.snFormatError}:\n${formatSNForDisplay(sn)}'),
          backgroundColor: AppColors.errorLight,
          duration: const Duration(seconds: 3),
        ),);
      }
      return;
    }

    if (!validateCheckDigitOnly(sn)) {
      _scanning = false;
      if (mounted) {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(AppLocalizations.of(context)!.checksumMismatch),
            content: Text('SN: ${formatSNForDisplay(sn)}\n${AppLocalizations.of(context)!.checksumMismatch}\n${AppLocalizations.of(context)!.snConfirmAdd}'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(AppLocalizations.of(context)!.cancel)),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(AppLocalizations.of(context)!.continueAdd)),
            ],
          ),
        );
        if (confirm != true) return;
      } else {
        return;
      }
      _scanning = true;
    }

    _lastScanned = sn;
    _scannedPin = pin;
    _bindDevice(sn);
  }

  Future<void> _bindDevice(String sn) async {
    if (!mounted) return;
    if (_selectedStationId == null) {
      final result = await _showStationSelector();
      if (result == null) return;
      _selectedStationId = result.$1;
      _selectedStationName = result.$2;
      setState(() {});
    }
    context.read<DeviceBloc>().add(DeviceBindRequested(sn: sn, stationId: _selectedStationId));
  }

  Future<(int, String)?> _showStationSelector() async {
    final completer = Completer<(int, String)?>();
    if (!mounted) {
      completer.complete(null);
      return completer.future;
    }
    context.read<StationBloc>().add(StationSummaryRequested());

    if (!mounted) {
      completer.complete(null);
      return completer.future;
    }
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
      ),
      builder: (ctx) => _StationSelectorSheet(
        onSelected: (id, name) {
          Navigator.pop(ctx);
          completer.complete((id, name));
        },
        onCancel: () {
          Navigator.pop(ctx);
          completer.complete(null);
        },
      ),
    );
    return completer.future;
  }

  Future<void> _manualBind() async {
    final raw = _snController.text.trim();
    if (raw.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.pleaseInputSn)));
      return;
    }

    final qr = parseQRCode(raw);
    final sn = qr != null ? qr.sn.toUpperCase() : raw.toUpperCase();

    if (!validateSNFormat(sn)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${AppLocalizations.of(context)!.snFormatError}:\n${formatSNForDisplay(sn)}'),
        backgroundColor: AppColors.errorLight,
        duration: const Duration(seconds: 3),
      ),);
      return;
    }

    if (!validateCheckDigitOnly(sn)) {
      if (mounted) {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(AppLocalizations.of(context)!.checksumMismatch),
            content: Text('SN: ${formatSNForDisplay(sn)}\n${AppLocalizations.of(context)!.checksumMismatch}\n${AppLocalizations.of(context)!.snConfirmAdd}'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(AppLocalizations.of(context)!.cancel)),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(AppLocalizations.of(context)!.continueAdd)),
            ],
          ),
        );
        if (confirm != true) return;
      } else {
        return;
      }
    }

    _bindDevice(sn);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.addDevice),
        actions: [
          if (_selectedStationId != null && _selectedStationName != null)
            Padding(
              padding: EdgeInsets.only(right: 12.w),
              child: Center(
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.solar_power, size: 16, color: AppColors.primary),
                      SizedBox(width: 4.w),
                      Text(_selectedStationName!, style: TextStyle(fontSize: 12.sp, color: AppColors.primary, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            )
          else
            TextButton.icon(
              onPressed: () async {
                final result = await _showStationSelector();
                if (result != null) {
                  _selectedStationId = result.$1;
                  _selectedStationName = result.$2;
                  setState(() {});
                }
              },
              icon: const Icon(Icons.home_work, size: 18),
              label: Text(AppLocalizations.of(context)!.selectStation, style: TextStyle(fontSize: 13.sp)),
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textHint,
          indicatorColor: AppColors.primary,
          tabs: [
            Tab(text: AppLocalizations.of(context)!.scanCode, icon: const Icon(Icons.qr_code_scanner, size: 20)),
            Tab(text: AppLocalizations.of(context)!.manualInput, icon: const Icon(Icons.edit, size: 20)),
          ],
        ),
      ),
      body: BlocConsumer<DeviceBloc, DeviceState>(
        listener: (context, state) {
          if (state is DeviceBindSuccess) {
            if (_selectedStationId != null) {
              context.read<StationBloc>().add(StationDetailRequested(stationId: _selectedStationId!));
            }
            setState(() {
              _sessionBoundCount++;
              _bindSuccess = true;
              _scanning = false;
            });
            _addToScanHistory(_lastScanned, true);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('✅ ${AppLocalizations.of(context)!.alreadyBoundNDevices('$_sessionBoundCount')}'),
              backgroundColor: AppColors.successLight,
            ),);
          } else if (state is DeviceError) {
            _scanning = false;
            _lastScanned = '';
            _scannedPin = '';
            _addToScanHistory(_lastScanned, false);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(AppLocalizations.of(context)!.translateError(state.message)),
              backgroundColor: AppColors.errorLight,
            ),);
          }
        },
        builder: (context, state) {
          return TabBarView(
            controller: _tabController,
            children: [
              _buildScanTab(state),
              _buildManualTab(state),
            ],
          );
        },
      ),
    );
  }

  Widget _buildScanTab(DeviceState state) {
    return Column(
      children: [
        if (_sessionBoundCount > 0)
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
            color: const Color(0xFFECFDF5),
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: AppColors.successLight, size: 18),
                SizedBox(width: 6.w),
                Text(AppLocalizations.of(context)!.alreadyBoundNDevices('$_sessionBoundCount'),
                  style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: const Color(0xFF065F46)),),
              ],
            ),
          ),
        Expanded(
          flex: 3,
          child: Stack(
            fit: StackFit.expand,
            children: [
              MobileScanner(controller: _cameraController, onDetect: _onDetect),
              Center(
                child: Container(
                  width: 220.w, height: 220.w,
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.primary, width: 2),
                    borderRadius: BorderRadius.circular(16.r),
                  ),
                ),
              ),
              if (_scanning || state is DeviceLoading)
                Container(color: Colors.black54,
                  child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const CircularProgressIndicator(color: Colors.white),
                    const SizedBox(height: 16),
                    Text(AppLocalizations.of(context)!.addingDevice, style: const TextStyle(color: Colors.white, fontSize: 16)),
                  ],),),),
            ],
          ),
        ),
        Container(
          padding: EdgeInsets.all(16.w),
          color: Colors.white,
          child: Column(
            children: [
              if (_bindSuccess) ...[
                Row(children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _continueScanning,
                      icon: const Icon(Icons.qr_code_scanner, size: 20),
                      label: Text(AppLocalizations.of(context)!.continueScan, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                        padding: EdgeInsets.symmetric(vertical: 12.h),
                      ),
                    ),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => context.pop(),
                      icon: const Icon(Icons.check_circle_outline, size: 20),
                      label: Text(AppLocalizations.of(context)!.finish, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.successLight,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                        padding: EdgeInsets.symmetric(vertical: 12.h),
                      ),
                    ),
                  ),
                ],),
                SizedBox(height: 12.h),
              ] else ...[
                if (_lastScanned.isNotEmpty) ...[
                  Text('SN: ${formatSNForDisplay(_lastScanned)}',
                    style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary),),
                  if (_scannedPin.isNotEmpty)
                    Padding(padding: EdgeInsets.only(top: 4.h),
                      child: Text('PIN: $_scannedPin',
                        style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600, color: AppColors.successLight),),),
                ] else
                  Text(AppLocalizations.of(context)!.pointSnAtScan,
                    style: TextStyle(fontSize: 14.sp, color: AppColors.textSecondary),),
              ],
              SizedBox(height: 8.h),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _actionChip(Icons.flash_on, AppLocalizations.of(context)!.flashLight, () => _cameraController?.toggleTorch()),
                  SizedBox(width: 12.w),
                  _actionChip(Icons.flip_camera_android, AppLocalizations.of(context)!.flipCamera, () => _cameraController?.switchCamera()),
                  SizedBox(width: 12.w),
                  GestureDetector(
                    onTap: () => setState(() => _autoFlash = !_autoFlash),
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                      decoration: BoxDecoration(
                        color: _autoFlash ? AppColors.primary.withValues(alpha: 0.1) : AppColors.surfaceHover,
                        borderRadius: BorderRadius.circular(20.r),
                        border: _autoFlash ? Border.all(color: AppColors.primary.withValues(alpha: 0.3)) : null,
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.auto_fix_high, size: 16.sp, color: _autoFlash ? AppColors.primary : AppColors.textSecondary),
                        SizedBox(width: 4.w),
                        Text(AppLocalizations.of(context)!.autoFlash, style: TextStyle(fontSize: 12.sp, color: _autoFlash ? AppColors.primary : AppColors.textSecondary)),
                      ],),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_scanHistory.isNotEmpty)
          Container(
            constraints: BoxConstraints(maxHeight: 160.h),
            color: const Color(0xFFF9FAFB),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 4.h),
                  child: Text(AppLocalizations.of(context)!.scanRecords, style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                ),
                Expanded(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.symmetric(horizontal: 16.w),
                    itemCount: _scanHistory.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final entry = _scanHistory[i];
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 2.h),
                        leading: Icon(
                          entry.success ? Icons.check_circle : Icons.error,
                          size: 18,
                          color: entry.success ? AppColors.successLight : AppColors.errorLight,
                        ),
                        title: Text(formatSNForDisplay(entry.sn),
                          style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w500, color: AppColors.textPrimary),),
                        trailing: Text(entry.success ? AppLocalizations.of(context)!.bindSuccess : AppLocalizations.of(context)!.bindFailed,
                          style: TextStyle(fontSize: 11.sp, color: entry.success ? AppColors.successLight : AppColors.errorLight),),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _actionChip(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
        decoration: BoxDecoration(color: AppColors.surfaceHover, borderRadius: BorderRadius.circular(20.r)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16.sp, color: AppColors.textSecondary),
          SizedBox(width: 4.w),
          Text(label, style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary)),
        ],),
      ),
    );
  }

  Widget _buildManualTab(DeviceState state) {
    return ListView(padding: EdgeInsets.all(20.w), children: [
      Text(AppLocalizations.of(context)!.manualInputSn, style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
      SizedBox(height: 8.h),
      Text(AppLocalizations.of(context)!.snFormatDesc, style: TextStyle(fontSize: 11.sp, color: AppColors.textHint)),
      SizedBox(height: 4.h),
      Text(AppLocalizations.of(context)!.snFormatHint, style: TextStyle(fontSize: 11.sp, color: AppColors.textHint)),
      SizedBox(height: 16.h),
      TextField(
        controller: _snController,
        decoration: InputDecoration(
          labelText: AppLocalizations.of(context)!.deviceSnLabel, hintText: AppLocalizations.of(context)!.input16DigitSn,
          prefixIcon: const Icon(Icons.devices, color: AppColors.textHint),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r),
            borderSide: const BorderSide(color: AppColors.primary, width: 1.5),),
        ),
      ),
      SizedBox(height: 20.h),
      SizedBox(width: double.infinity, height: 48.h,
        child: ElevatedButton(
          onPressed: state is DeviceLoading ? null : _manualBind,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary, foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
          ),
          child: state is DeviceLoading
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(AppLocalizations.of(context)!.bindDevice, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
      ),
    ],);
  }

  void _continueScanning() {
    setState(() {
      _lastScanned = '';
      _scannedPin = '';
      _scanning = false;
      _bindSuccess = false;
    });
  }

  static const String _scanHistoryKey = 'scan_history';

  Future<void> _loadScanHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_scanHistoryKey);
      if (jsonStr != null) {
        final list = jsonDecode(jsonStr) as List;
        setState(() {
          _scanHistory = list.map((e) => _ScanHistoryEntry.fromJson(e as Map<String, dynamic>)).toList();
        });
      }
    } catch (_) {}
  }

  Future<void> _saveScanHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final trimmed = _scanHistory.length > 10 ? _scanHistory.sublist(_scanHistory.length - 10) : _scanHistory;
      final jsonStr = jsonEncode(trimmed.map((e) => e.toJson()).toList());
      await prefs.setString(_scanHistoryKey, jsonStr);
    } catch (_) {}
  }

  void _addToScanHistory(String sn, bool success) {
    if (sn.isEmpty) return;
    setState(() {
      _scanHistory.add(_ScanHistoryEntry(sn: sn, success: success, time: DateTime.now()));
      if (_scanHistory.length > 10) {
        _scanHistory = _scanHistory.sublist(_scanHistory.length - 10);
      }
    });
    _saveScanHistory();
  }
}

class _ScanHistoryEntry {
  final String sn;
  final bool success;
  final DateTime time;

  _ScanHistoryEntry({required this.sn, required this.success, required this.time});

  Map<String, dynamic> toJson() => {
    'sn': sn,
    'success': success,
    'time': time.toIso8601String(),
  };

  factory _ScanHistoryEntry.fromJson(Map<String, dynamic> json) => _ScanHistoryEntry(
    sn: json['sn'] as String,
    success: json['success'] as bool,
    time: DateTime.parse(json['time'] as String),
  );
}

class _StationSelectorSheet extends StatefulWidget {
  final void Function(int stationId, String stationName) onSelected;
  final VoidCallback onCancel;

  const _StationSelectorSheet({required this.onSelected, required this.onCancel});

  @override
  State<_StationSelectorSheet> createState() => _StationSelectorSheetState();
}

class _StationSelectorSheetState extends State<_StationSelectorSheet> {
  @override
  void initState() {
    super.initState();
    context.read<StationBloc>().add(StationSummaryRequested());
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      expand: false,
      builder: (ctx, scrollCtl) {
        return Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(20.w, 16.h, 20.w, 8.h),
              child: Row(
                children: [
                  Container(
                    width: 40.w,
                    height: 4.h,
                    decoration: BoxDecoration(
                      color: AppColors.divider,
                      borderRadius: BorderRadius.circular(2.r),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 8.h),
              child: Row(
                children: [
                  Text(AppLocalizations.of(context)!.selectStation, style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  const Spacer(),
                  GestureDetector(
                    onTap: widget.onCancel,
                    child: const Icon(Icons.close, size: 24, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 20.w),
              child: Text(AppLocalizations.of(context)!.selectStationForDevice, style: TextStyle(fontSize: 13.sp, color: AppColors.textHint)),
            ),
            SizedBox(height: 12.h),
            Expanded(
              child: BlocBuilder<StationBloc, StationState>(
                builder: (context, state) {
                  if (state is StationLoading || state is StationInitial) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (state is StationError) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(AppLocalizations.of(context)!.translateError(state.message), style: TextStyle(fontSize: 14.sp, color: AppColors.errorLight)),
                          SizedBox(height: 12.h),
                          ElevatedButton(
                            onPressed: () => context.read<StationBloc>().add(StationSummaryRequested()),
                            child: Text(AppLocalizations.of(context)!.retry),
                          ),
                        ],
                      ),
                    );
                  }
                  List<dynamic> stations = [];
                  if (state is StationSummaryLoaded) {
                    stations = state.stations;
                  }
                  if (stations.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.home_work_outlined, size: 48, color: AppColors.textHint),
                          SizedBox(height: 12.h),
                          Text(AppLocalizations.of(context)!.noStationsYet, style: TextStyle(fontSize: 15.sp, color: AppColors.textSecondary)),
                          SizedBox(height: 8.h),
                          Text(AppLocalizations.of(context)!.createStationFirst, style: TextStyle(fontSize: 13.sp, color: AppColors.textHint)),
                          SizedBox(height: 16.h),
                          ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              context.push('/station/create');
                            },
                            icon: const Icon(Icons.add),
                            label: Text(AppLocalizations.of(context)!.createStation),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  return ListView.separated(
                    controller: scrollCtl,
                    padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 8.h),
                    itemCount: stations.length,
                    separatorBuilder: (_, __) => SizedBox(height: 8.h),
                    itemBuilder: (_, i) {
                      final s = stations[i];
                      final id = (s['station_id'] ?? s['id']) as int;
                      final name = (s['station_name'] ?? s['name'] ?? '').toString();
                      final deviceCount = (s['device_count'] as num?)?.toInt() ?? 0;
                      return Material(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12.r),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12.r),
                          onTap: () => widget.onSelected(id, name),
                          child: Padding(
                            padding: EdgeInsets.all(16.w),
                            child: Row(
                              children: [
                                Container(
                                  width: 44.w,
                                  height: 44.w,
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(10.r),
                                  ),
                                  child: const Icon(Icons.solar_power, color: AppColors.primary, size: 22),
                                ),
                                SizedBox(width: 14.w),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(name, style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                                      SizedBox(height: 2.h),
                                      Text(AppLocalizations.of(context)!.nDevices('$deviceCount'), style: TextStyle(fontSize: 12.sp, color: AppColors.textHint)),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.arrow_forward_ios, size: 16, color: AppColors.textHint),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
