import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:inv_app/core/services/firmware_download_service.dart';
import 'package:inv_app/core/services/local_communication_service.dart';
import 'package:inv_app/core/services/local_firmware_service.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wifi_iot/wifi_iot.dart';

enum LocalOTAStep {
  selectFirmware,
  connectDevice,
  pushFirmware,
  triggerUpgrade,
  result,
}

enum LocalOTAResult { success, failed, verifyFailed }

class LocalOTAPage extends StatefulWidget {
  final String deviceSN;
  final String deviceIP;
  final int? firmwareId;
  final String? firmwareUrl;
  final String? firmwareFileName;

  const LocalOTAPage({
    super.key,
    required this.deviceSN,
    required this.deviceIP,
    this.firmwareId,
    this.firmwareUrl,
    this.firmwareFileName,
  });

  @override
  State<LocalOTAPage> createState() => _LocalOTAPageState();
}

class _LocalOTAPageState extends State<LocalOTAPage> {
  LocalOTAStep _currentStep = LocalOTAStep.selectFirmware;
  LocalOTAResult? _result;
  String? _resultMessage;
  String? _newVersion;
  String? _preUpgradeVersion;

  String? _selectedFilePath;
  double _downloadProgress = 0.0;
  bool _isDownloading = false;

  double _uploadProgress = 0.0;
  double _upgradeProgress = 0.0;
  String _upgradeStatus = '';

  bool _isProcessing = false;
  String? _errorMessage;

  // WiFi 热点扫描
  bool _scanningWifi = false;
  List<WifiNetwork> _csInvNetworks = [];
  WifiNetwork? _selectedAp;
  bool _autoConnecting = false;

  late final FirmwareDownloadService _downloadService;
  late final LocalFirmwareService _firmwareService;

  StreamSubscription<double>? _downloadProgressSub;

  @override
  void initState() {
    super.initState();
    _downloadService = FirmwareDownloadService(getIt<Dio>(), getIt<SharedPreferences>());
    _firmwareService = LocalFirmwareService(LocalCommunicationService());

    _downloadProgressSub = _downloadService.downloadProgressStream.listen((progress) {
      if (mounted) {
        setState(() {
          _downloadProgress = progress;
        });
      }
    });

    _initFirmware();
  }

  Future<void> _initFirmware() async {
    if (widget.firmwareId != null) {
      final isDownloaded = await _downloadService.isFirmwareDownloaded(widget.firmwareId!);
      if (isDownloaded) {
        final path = await _downloadService.getDownloadedFirmwarePath(widget.firmwareId!);
        if (path != null && mounted) {
          setState(() {
            _selectedFilePath = path;
          });
        }
      }
    }
  }

  @override
  void dispose() {
    _downloadProgressSub?.cancel();
    _downloadService.dispose();
    // 退出页面时恢复正常网络，取消forceWifiUsage
    WiFiForIoTPlugin.forceWifiUsage(false).catchError((_) {});
    super.dispose();
  }

  void _goToStep(LocalOTAStep step) {
    setState(() {
      _currentStep = step;
      _isProcessing = false;
      _errorMessage = null;
    });
  }

  Future<void> _scanForDeviceHotspot() async {
    setState(() { _scanningWifi = true; _csInvNetworks = []; _errorMessage = null; });
    try {
      final status = await Permission.location.request();
      if (!status.isGranted && !status.isLimited) {
        setState(() { _scanningWifi = false; _errorMessage = '需要位置权限才能扫描WiFi'; });
        return;
      }
      final serviceEnabled = await Permission.location.serviceStatus.isEnabled;
      if (!serviceEnabled) {
        setState(() { _scanningWifi = false; _errorMessage = '请先开启位置服务(GPS)'; });
        return;
      }
      await WiFiForIoTPlugin.forceWifiUsage(true);
      final networks = await WiFiForIoTPlugin.loadWifiList();

      if (!mounted) return;

      // 直接查找指定 SN 的热点: CS_INV_{SN} 或 CS-INV-{SN}
      final sn = widget.deviceSN.toUpperCase();
      final target = networks.where((n) {
        final ssid = (n.ssid ?? '').toUpperCase();
        return ssid == 'CS_INV_$sn' || ssid == 'CS-INV-$sn';
      }).toList();

      if (target.isNotEmpty) {
        setState(() { _csInvNetworks = target; _scanningWifi = false; });
        _connectToAp(target.first);
      } else {
        setState(() {
          _scanningWifi = false;
          _errorMessage = '未找到设备 ${widget.deviceSN} 的热点 (CS_INV_${widget.deviceSN})，请确认设备已开启热点';
        });
      }
    } catch (e) {
      setState(() { _scanningWifi = false; _errorMessage = '扫描失败: $e'; });
    }
  }

  Future<void> _connectToAp(WifiNetwork network) async {
    setState(() {
      _selectedAp = network;
      _autoConnecting = true;
      _errorMessage = null;
    });

    try {
      final ssid = network.ssid ?? '';
      final cap = network.capabilities?.toUpperCase() ?? '';
      final isOpen = !cap.contains('WPA') && !cap.contains('WEP') && !cap.contains('EAP');

      final connected = await WiFiForIoTPlugin.connect(ssid,
        password: null,
        security: isOpen ? NetworkSecurity.NONE : NetworkSecurity.WPA,
        joinOnce: true,
      );

      if (!mounted) return;

      if (connected) {
        // 强制 HTTP 请求走 WiFi 而不是移动数据
        await WiFiForIoTPlugin.forceWifiUsage(true);

        // 等待连接稳定，热点分配IP需要时间
        await Future.delayed(const Duration(seconds: 3));

        // 验证确实连上了设备热点
        final currentSsid = await WiFiForIoTPlugin.getSSID();
        if (currentSsid == null || !(currentSsid.toUpperCase().contains('CS_INV') || currentSsid.toUpperCase().contains('CS-INV'))) {
          setState(() { _autoConnecting = false; _errorMessage = '连接失败：未检测到设备热点，请重试'; });
          return;
        }

        setState(() { _autoConnecting = false; });

        // 自动测试连接
        _checkConnectionAndProceed();
      } else {
        setState(() { _autoConnecting = false; _errorMessage = '连接 $ssid 失败，请重试'; });
      }
    } catch (e) {
      setState(() { _autoConnecting = false; _errorMessage = '连接失败: $e'; });
    }
  }

  Future<void> _startDownload() async {
    if (widget.firmwareUrl == null || widget.firmwareFileName == null || widget.firmwareId == null) return;

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
      _errorMessage = null;
    });

    try {
      final path = await _downloadService.downloadFirmware(
        url: widget.firmwareUrl!,
        fileName: widget.firmwareFileName!,
        firmwareId: widget.firmwareId!,
      );
      if (mounted) {
        setState(() {
          _selectedFilePath = path;
          _isDownloading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _errorMessage = '下载失败: $e';
        });
      }
    }
  }

  Future<void> _checkConnectionAndProceed() async {
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    // 检查当前WiFi连接
    String? currentSsid;
    try {
      currentSsid = await WiFiForIoTPlugin.getSSID();
      final isConnected = await WiFiForIoTPlugin.isConnected();
      print('Current SSID: $currentSsid, isConnected: $isConnected');
      
      if (currentSsid == null || !currentSsid.startsWith('CS_INV')) {
        setState(() {
          _isProcessing = false;
          _errorMessage = '请先连接设备热点 (当前WiFi: $currentSsid)';
        });
        return;
      }
    } catch (e) {
      print('getSSID error: $e');
    }

    // 强制使用WiFi
    try {
      await WiFiForIoTPlugin.forceWifiUsage(true);
      print('forceWifiUsage(true) called');
      await Future.delayed(const Duration(seconds: 3));
    } catch (e) {
      print('forceWifiUsage error: $e');
    }

    // 尝试连接
    final connected = await _firmwareService.testDeviceConnection(widget.deviceIP);
    print('Connection test result: $connected');
    
    if (connected) {
      _goToStep(LocalOTAStep.pushFirmware);
      _startPushFirmware();
    } else {
      // 连接失败，显示对话框提示用户关闭移动数据
      setState(() {
        _isProcessing = false;
      });
      
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('连接失败'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('已连接设备热点，但无法访问设备。'),
                const SizedBox(height: 12),
                const Text('请尝试以下操作：', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text('1. 在手机设置中关闭移动数据'),
                const Text('2. 确保WiFi已连接到设备热点'),
                const Text('3. 等待几秒后重试'),
                const SizedBox(height: 12),
                Text('当前热点: $currentSsid', style: const TextStyle(color: Colors.grey)),
                Text('设备IP: ${widget.deviceIP}', style: const TextStyle(color: Colors.grey)),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _checkConnectionAndProceed(); // 重试
                },
                child: const Text('重试'),
              ),
            ],
          ),
        );
      }
    }
  }

  Future<void> _startPushFirmware() async {
    if (_selectedFilePath == null) {
      setState(() {
        _isProcessing = false;
        _result = LocalOTAResult.failed;
        _resultMessage = '固件文件不存在';
        _currentStep = LocalOTAStep.result;
      });
      return;
    }

    setState(() {
      _isProcessing = true;
      _uploadProgress = 0.0;
      _errorMessage = null;
    });

    try {
      // 上传固件文件到设备
      await _firmwareService.uploadFirmware(
        deviceIP: widget.deviceIP,
        filePath: _selectedFilePath!,
        onProgress: (sent, total) {
          if (total > 0 && mounted) {
            setState(() {
              _uploadProgress = sent / total;
            });
          }
        },
      );

      setState(() {
        _uploadProgress = 1.0;
      });

      _goToStep(LocalOTAStep.triggerUpgrade);
      
      // 等待ESP32重启（OTA成功后ESP32会自动重启）
      setState(() {
        _upgradeStatus = '上传完成，等待设备重启...';
      });
      await Future.delayed(const Duration(seconds: 5));
      
      _pollUpgradeProgress();
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _result = LocalOTAResult.failed;
        _resultMessage = '上传固件失败: $e';
        _currentStep = LocalOTAStep.result;
      });
    }
  }

  Future<void> _pollUpgradeProgress() async {
    bool progressEndpointWorking = false;
    
    for (int i = 0; i < 120; i++) {
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;

      try {
        // 先检查设备信息，看版本是否已更新
         final deviceInfo = await _firmwareService.getDeviceInfo(deviceIP: widget.deviceIP);
         final currentVersion = deviceInfo['esp_version'] as String? ?? '';
         
         // 首次获取版本，记录下来
         if (_preUpgradeVersion == null && currentVersion.isNotEmpty) {
           _preUpgradeVersion = currentVersion;
         }
         
         // 如果版本已更新（和升级前不同），说明OTA成功
         if (_preUpgradeVersion != null && currentVersion.isNotEmpty && 
             currentVersion != _preUpgradeVersion) {
          setState(() {
            _isProcessing = false;
            _result = LocalOTAResult.success;
            _newVersion = currentVersion;
            _currentStep = LocalOTAStep.result;
          });
          return;
        }
        
        // 尝试获取升级进度
        final progress = await _firmwareService.getLocalOTAProgress(deviceIP: widget.deviceIP);
        final status = progress['status'] as String? ?? '';
        final percent = (progress['progress'] as num?)?.toDouble() ?? 0.0;
        final target = progress['target'] as String? ?? '';
        final message = progress['message'] as String? ?? '';
        
        progressEndpointWorking = true;

        setState(() {
          _upgradeProgress = percent / 100.0;
          _upgradeStatus = _mapStatus(status) + (message.isNotEmpty ? ' ($message)' : '');
        });

        if (status == 'done') {
          setState(() {
            _isProcessing = false;
            _result = LocalOTAResult.success;
            _newVersion = target;
            _currentStep = LocalOTAStep.result;
          });
          return;
        }

        if (status == 'error') {
          setState(() {
            _isProcessing = false;
            _result = LocalOTAResult.failed;
            _resultMessage = message.isNotEmpty ? message : '升级失败';
            _currentStep = LocalOTAStep.result;
          });
          return;
        }
      } catch (_) {
        // 设备可能还在重启中，继续等待
        if (i % 5 == 0) {
          setState(() {
            _upgradeStatus = '等待设备响应... (${i * 2}s)';
          });
        }
        continue;
      }
    }

    if (mounted) {
      setState(() {
        _isProcessing = false;
        _result = LocalOTAResult.failed;
        _resultMessage = '升级超时';
        _currentStep = LocalOTAStep.result;
      });
    }
  }

  String _mapStatus(String status) {
    switch (status) {
      case 'idle':
        return '空闲';
      case 'downloading':
        return '下载中';
      case 'uploading':
        return '上传中';
      case 'verifying':
        return '校验中';
      case 'done':
        return '完成';
      case 'error':
        return '失败';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(50.h),
        child: AppBar(
          title: const Text('本地固件升级', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 17)),
          centerTitle: true,
          elevation: 0,
          scrolledUnderElevation: 0.5,
          backgroundColor: Colors.white,
          foregroundColor: AppColors.textPrimary,
        ),
      ),
      body: Column(
        children: [
          _buildStepIndicator(),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(16.w),
              child: _buildCurrentStepContent(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepIndicator() {
    final steps = LocalOTAStep.values;
    final currentIndex = steps.indexOf(_currentStep);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
      color: Colors.white,
      child: Row(
        children: steps.asMap().entries.map((entry) {
          final index = entry.key;
          final step = entry.value;
          final isCompleted = currentIndex > index;
          final isCurrent = currentIndex == index;

          Color stepColor;
          if (isCompleted) {
            stepColor = AppColors.successLight;
          } else if (isCurrent) {
            stepColor = AppColors.primary;
          } else {
            stepColor = AppColors.textHint;
          }

          return Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Container(
                        width: 28.w,
                        height: 28.w,
                        decoration: BoxDecoration(
                          color: stepColor.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                          border: Border.all(color: stepColor, width: 2),
                        ),
                        child: isCompleted
                            ? Icon(Icons.check, size: 14.sp, color: stepColor)
                            : Center(
                                child: Text(
                                  '${index + 1}',
                                  style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600, color: stepColor),
                                ),
                              ),
                      ),
                      SizedBox(height: 4.h),
                      Text(
                        _stepLabel(step),
                        style: TextStyle(
                          fontSize: 10.sp,
                          color: isCurrent || isCompleted ? AppColors.textPrimary : AppColors.textHint,
                          fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (index < steps.length - 1)
                  Container(
                    width: 16.w,
                    height: 2,
                    color: isCompleted ? AppColors.successLight : const Color(0xFFE5E7EB),
                  ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  String _stepLabel(LocalOTAStep step) {
    switch (step) {
      case LocalOTAStep.selectFirmware:
        return '选择固件';
      case LocalOTAStep.connectDevice:
        return '连接设备';
      case LocalOTAStep.pushFirmware:
        return '推送固件';
      case LocalOTAStep.triggerUpgrade:
        return '升级中';
      case LocalOTAStep.result:
        return '结果';
    }
  }

  Widget _buildCurrentStepContent() {
    switch (_currentStep) {
      case LocalOTAStep.selectFirmware:
        return _buildSelectFirmwareStep();
      case LocalOTAStep.connectDevice:
        return _buildConnectDeviceStep();
      case LocalOTAStep.pushFirmware:
        return _buildPushFirmwareStep();
      case LocalOTAStep.triggerUpgrade:
        return _buildTriggerUpgradeStep();
      case LocalOTAStep.result:
        return _buildResultStep();
    }
  }

  Widget _buildSelectFirmwareStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildDeviceInfoCard(),
        SizedBox(height: 16.h),
        Container(
          padding: EdgeInsets.all(16.w),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14.r),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('选择固件', style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              SizedBox(height: 12.h),
              if (_selectedFilePath != null)
                _buildSelectedFirmwareInfo()
              else if (_isDownloading)
                _buildDownloadingProgress()
              else
                Text('请先在OTA页面预下载固件，或点击下方按钮下载', style: TextStyle(fontSize: 13.sp, color: AppColors.textHint)),
              if (_errorMessage != null) ...[
                SizedBox(height: 8.h),
                Text(_errorMessage!, style: TextStyle(fontSize: 12.sp, color: AppColors.error)),
              ],
            ],
          ),
        ),
        SizedBox(height: 24.h),
        if (_selectedFilePath == null && !_isDownloading && widget.firmwareUrl != null)
          SizedBox(
            width: double.infinity,
            height: 48.h,
            child: ElevatedButton(
              onPressed: _startDownload,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                elevation: 0,
              ),
              child: Text('下载固件', style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600)),
            ),
          ),
        if (_selectedFilePath != null)
          SizedBox(
            width: double.infinity,
            height: 48.h,
            child: ElevatedButton(
              onPressed: () => _goToStep(LocalOTAStep.connectDevice),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                elevation: 0,
              ),
              child: Text('下一步', style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600)),
            ),
          ),
      ],
    );
  }

  Widget _buildDownloadingProgress() {
    return Column(
      children: [
        SizedBox(height: 8.h),
        ClipRRect(
          borderRadius: BorderRadius.circular(8.r),
          child: LinearProgressIndicator(
            value: _downloadProgress > 0 ? _downloadProgress : null,
            minHeight: 8.h,
            backgroundColor: const Color(0xFFE5E7EB),
            valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
          ),
        ),
        SizedBox(height: 8.h),
        Text(
          _downloadProgress > 0 ? '${(_downloadProgress * 100).toStringAsFixed(1)}%' : '下载中...',
          style: TextStyle(fontSize: 12.sp, color: AppColors.primary),
        ),
      ],
    );
  }

  Widget _buildSelectedFirmwareInfo() {
    return Container(
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: const Color(0xFFECFDF5),
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(color: AppColors.successLight.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_rounded, size: 20.sp, color: AppColors.successLight),
          SizedBox(width: 8.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('固件已就绪', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.successLight)),
                SizedBox(height: 2.h),
                Text(
                  widget.firmwareFileName ?? _selectedFilePath!.split('/').last,
                  style: TextStyle(fontSize: 11.sp, color: AppColors.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectDeviceStep() {
    // 进入此步骤时自动扫描热点
    if (!_scanningWifi && _csInvNetworks.isEmpty && !_autoConnecting && _selectedAp == null && !_isProcessing) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scanForDeviceHotspot());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildDeviceInfoCard(),
        SizedBox(height: 16.h),
        Center(
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.all(20.w),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(14.r),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
            ),
            child: Column(
              children: [
                if (_autoConnecting) ...[
                  SizedBox(width: 48, height: 48, child: CircularProgressIndicator(strokeWidth: 3, color: AppColors.primary)),
                  SizedBox(height: 12.h),
                  Text('正在连接 ${_selectedAp?.ssid ?? ""}...', style: TextStyle(fontSize: 14.sp, color: AppColors.textSecondary)),
                ] else if (_scanningWifi) ...[
                  SizedBox(width: 48, height: 48, child: CircularProgressIndicator(strokeWidth: 3, color: AppColors.primary)),
                  SizedBox(height: 12.h),
                  Text('正在扫描设备热点...', style: TextStyle(fontSize: 14.sp, color: AppColors.textSecondary)),
                ] else if (_selectedAp != null) ...[
                  Icon(Icons.wifi_rounded, size: 48.sp, color: AppColors.successLight),
                  SizedBox(height: 12.h),
                  Text('已连接', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600, color: AppColors.successLight)),
                  SizedBox(height: 4.h),
                  Text(_selectedAp!.ssid ?? '', style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)),
                ] else ...[
                  Icon(Icons.wifi_find_rounded, size: 48.sp, color: AppColors.primary),
                  SizedBox(height: 12.h),
                  Text('连接设备AP热点', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  SizedBox(height: 8.h),
                  Text(
                    '自动扫描设备热点，或手动连接后点击下方按钮',
                    style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    '设备IP: ${widget.deviceIP}',
                    style: TextStyle(fontSize: 12.sp, color: AppColors.primary, fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: 12.h),
                  SizedBox(
                    width: double.infinity,
                    height: 40.h,
                    child: OutlinedButton.icon(
                      onPressed: _scanningWifi ? null : _scanForDeviceHotspot,
                      icon: Icon(Icons.refresh_rounded, size: 18.sp),
                      label: Text('重新扫描热点', style: TextStyle(fontSize: 13.sp)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: BorderSide(color: AppColors.primary.withValues(alpha: 0.4)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (_errorMessage != null) ...[
          SizedBox(height: 12.h),
          Container(
            padding: EdgeInsets.all(12.w),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(10.r),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline_rounded, size: 18.sp, color: AppColors.error),
                SizedBox(width: 8.w),
                Expanded(child: Text(_errorMessage!, style: TextStyle(fontSize: 12.sp, color: AppColors.error))),
              ],
            ),
          ),
        ],
        SizedBox(height: 24.h),
        SizedBox(
          width: double.infinity,
          height: 48.h,
          child: ElevatedButton(
            onPressed: (_isProcessing || _autoConnecting || _scanningWifi) ? null : _checkConnectionAndProceed,
            style: ElevatedButton.styleFrom(
              backgroundColor: (_isProcessing || _autoConnecting || _scanningWifi) ? AppColors.textHint : AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
              elevation: 0,
            ),
            child: _isProcessing
                ? SizedBox(width: 20.w, height: 20.w, child: const CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text('检测连接', style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }

  Widget _buildPushFirmwareStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildDeviceInfoCard(),
        SizedBox(height: 16.h),
        Container(
          padding: EdgeInsets.all(20.w),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14.r),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2)),
            ],
          ),
          child: Column(
            children: [
              Icon(Icons.cloud_upload_rounded, size: 48.sp, color: AppColors.primary),
              SizedBox(height: 12.h),
              Text('推送固件中', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              SizedBox(height: 20.h),
              ClipRRect(
                borderRadius: BorderRadius.circular(8.r),
                child: LinearProgressIndicator(
                  value: _uploadProgress,
                  minHeight: 10.h,
                  backgroundColor: const Color(0xFFE5E7EB),
                  valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                ),
              ),
              SizedBox(height: 10.h),
              Text(
                '${(_uploadProgress * 100).toStringAsFixed(1)}%',
                style: TextStyle(fontSize: 24.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTriggerUpgradeStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildDeviceInfoCard(),
        SizedBox(height: 16.h),
        Container(
          padding: EdgeInsets.all(20.w),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14.r),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2)),
            ],
          ),
          child: Column(
            children: [
              Icon(Icons.system_update_rounded, size: 48.sp, color: AppColors.primary),
              SizedBox(height: 12.h),
              Text(
                _upgradeStatus.isNotEmpty ? _upgradeStatus : '升级中',
                style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
              ),
              SizedBox(height: 20.h),
              ClipRRect(
                borderRadius: BorderRadius.circular(8.r),
                child: LinearProgressIndicator(
                  value: _upgradeProgress,
                  minHeight: 10.h,
                  backgroundColor: const Color(0xFFE5E7EB),
                  valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                ),
              ),
              SizedBox(height: 10.h),
              Text(
                '${(_upgradeProgress * 100).toStringAsFixed(1)}%',
                style: TextStyle(fontSize: 24.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
              ),
              SizedBox(height: 8.h),
              Text(
                '请勿断开设备电源',
                style: TextStyle(fontSize: 12.sp, color: AppColors.warning),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildResultStep() {
    return Column(
      children: [
        _buildDeviceInfoCard(),
        SizedBox(height: 16.h),
        Container(
          padding: EdgeInsets.all(24.w),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14.r),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2)),
            ],
          ),
          child: Column(
            children: [
              if (_result == LocalOTAResult.success) ...[
                Icon(Icons.check_circle_rounded, size: 64.sp, color: AppColors.successLight),
                SizedBox(height: 16.h),
                Text('升级成功', style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                if (_newVersion != null) ...[
                  SizedBox(height: 8.h),
                  Text('新版本: $_newVersion', style: TextStyle(fontSize: 14.sp, color: AppColors.textSecondary)),
                ],
                SizedBox(height: 24.h),
                SizedBox(
                  width: double.infinity,
                  height: 48.h,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.successLight,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                      elevation: 0,
                    ),
                    child: Text('完成', style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
              if (_result == LocalOTAResult.failed) ...[
                Icon(Icons.cancel_rounded, size: 64.sp, color: AppColors.error),
                SizedBox(height: 16.h),
                Text('升级失败', style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                SizedBox(height: 8.h),
                Text(_resultMessage ?? '未知错误', style: TextStyle(fontSize: 14.sp, color: AppColors.textSecondary), textAlign: TextAlign.center),
                SizedBox(height: 24.h),
                SizedBox(
                  width: double.infinity,
                  height: 48.h,
                  child: ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _currentStep = LocalOTAStep.connectDevice;
                        _result = null;
                        _resultMessage = null;
                      });
                      _startPushFirmware();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.error,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                      elevation: 0,
                    ),
                    child: Text('重试', style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
              if (_result == LocalOTAResult.verifyFailed) ...[
                Icon(Icons.warning_rounded, size: 64.sp, color: AppColors.warning),
                SizedBox(height: 16.h),
                Text('固件校验失败', style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                SizedBox(height: 8.h),
                Text('固件文件可能已损坏，请重新下载', style: TextStyle(fontSize: 14.sp, color: AppColors.textSecondary), textAlign: TextAlign.center),
                SizedBox(height: 24.h),
                SizedBox(
                  width: double.infinity,
                  height: 48.h,
                  child: ElevatedButton(
                    onPressed: () async {
                      if (widget.firmwareId != null) {
                        await _downloadService.deleteDownloadedFirmware(widget.firmwareId!);
                      }
                      setState(() {
                        _selectedFilePath = null;
                        _currentStep = LocalOTAStep.selectFirmware;
                        _result = null;
                        _resultMessage = null;
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.warning,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                      elevation: 0,
                    ),
                    child: Text('重新下载', style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDeviceInfoCard() {
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14.r),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 36.w,
            height: 36.w,
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(10.r),
            ),
            child: Icon(Icons.devices_rounded, size: 18.sp, color: AppColors.primary),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('当前设备', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                SizedBox(height: 2.h),
                Text(widget.deviceSN, style: TextStyle(fontSize: 12.sp, color: AppColors.textHint)),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(6.r),
            ),
            child: Text(widget.deviceIP, style: TextStyle(fontSize: 11.sp, fontWeight: FontWeight.w600, color: AppColors.primary)),
          ),
        ],
      ),
    );
  }
}
