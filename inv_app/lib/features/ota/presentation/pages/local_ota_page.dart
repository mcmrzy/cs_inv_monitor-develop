import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:inv_app/core/services/firmware_download_service.dart';
import 'package:inv_app/core/services/local_communication_service.dart';
import 'package:inv_app/core/errors/ota_error_types.dart';
import 'package:inv_app/core/services/local_firmware_service.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/l10n/app_localizations.dart';
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
  final String? targetChip; // 'esp' 或 'arm'

  const LocalOTAPage({
    super.key,
    required this.deviceSN,
    required this.deviceIP,
    this.firmwareId,
    this.firmwareUrl,
    this.firmwareFileName,
    this.targetChip,
  });

  @override
  State<LocalOTAPage> createState() => _LocalOTAPageState();
}

class _LocalOTAPageState extends State<LocalOTAPage> {
  LocalOTAStep _currentStep = LocalOTAStep.selectFirmware;
  LocalOTAResult? _result;
  String? _resultMessage;
  String? _newVersion;

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
    WiFiForIoTPlugin.forceWifiUsage(false).catchError((_) => false);
    super.dispose();
  }

  void _goToStep(LocalOTAStep step) {
    setState(() {
      _currentStep = step;
      _isProcessing = false;
      _errorMessage = null;
    });
    // 进入连接设备步骤时自动开始扫描+连接
    if (step == LocalOTAStep.connectDevice) {
      _autoScanAndConnect();
    }
  }

  /// 自动扫描热点并连接，整个流程只触发两次 setState（开始/结束）
  Future<void> _autoScanAndConnect() async {
    // 已在处理中或已连接成功，不重复触发
    if (_scanningWifi || _autoConnecting || _isProcessing || _selectedAp != null) return;

    setState(() { _scanningWifi = true; _errorMessage = null; });
    try {
      final status = await Permission.location.request();
      if (!mounted) return;
      if (!status.isGranted && !status.isLimited) {
        final l10n = AppLocalizations.of(context)!;
        setState(() { _scanningWifi = false; _errorMessage = l10n.locationPermissionRequired; });
        return;
      }
      final serviceEnabled = await Permission.location.serviceStatus.isEnabled;
      if (!serviceEnabled) {
        final l10n = AppLocalizations.of(context)!;
        setState(() { _scanningWifi = false; _errorMessage = l10n.enableLocationService; });
        return;
      }
      await WiFiForIoTPlugin.forceWifiUsage(true);
      final networks = await WiFiForIoTPlugin.loadWifiList();
      if (!mounted) return;

      final sn = widget.deviceSN.toUpperCase();
      final target = networks.where((n) {
        final ssid = (n.ssid ?? '').toUpperCase();
        return ssid == 'CS_INV_$sn' || ssid == 'CS-INV-$sn';
      }).toList();

      if (target.isEmpty) {
        final l10n = AppLocalizations.of(context)!;
        setState(() {
          _scanningWifi = false;
          _errorMessage = l10n.str('device_hotspot_not_found', {'sn': widget.deviceSN});
        });
        return;
      }

      // 找到热点，继续连接（不更新 UI，保持扫描中状态）
      final network = target.first;
      _selectedAp = network;
      final ssid = network.ssid ?? '';
      final cap = network.capabilities?.toUpperCase() ?? '';
      final isOpen = !cap.contains('WPA') && !cap.contains('WEP') && !cap.contains('EAP');

      final connected = await WiFiForIoTPlugin.connect(ssid,
        password: null,
        security: isOpen ? NetworkSecurity.NONE : NetworkSecurity.WPA,
        joinOnce: true,
      );
      if (!mounted) return;

      if (!connected) {
        final l10n = AppLocalizations.of(context)!;
        setState(() {
          _scanningWifi = false;
          _selectedAp = null;
          _errorMessage = l10n.str('connection_failed_retry', {'ssid': ssid});
        });
        return;
      }

      await WiFiForIoTPlugin.forceWifiUsage(true);
      await Future.delayed(const Duration(seconds: 3));

      final currentSsid = await WiFiForIoTPlugin.getSSID();
      if (!mounted) return;
      if (currentSsid == null || !(currentSsid.toUpperCase().contains('CS_INV') || currentSsid.toUpperCase().contains('CS-INV'))) {
        final l10n = AppLocalizations.of(context)!;
        setState(() {
          _scanningWifi = false;
          _selectedAp = null;
          _errorMessage = l10n.connectionFailedNoHotspot;
        });
        return;
      }

      // 连接成功，一次性更新状态
      setState(() {
        _scanningWifi = false;
        _autoConnecting = false;
      });

      // 自动测试连接并进入下一步
      _checkConnectionAndProceed();
    } catch (e) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      setState(() {
        _scanningWifi = false;
        _selectedAp = null;
        _errorMessage = l10n.str('scan_failed', {'error': '$e'});
      });
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
        final l10n = AppLocalizations.of(context)!;
        setState(() {
          _isDownloading = false;
          _errorMessage = l10n.str('download_failed', {'error': '$e'});
        });
      }
    }
  }

  Future<void> _checkConnectionAndProceed() async {
    final l10n = AppLocalizations.of(context)!;
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
          _errorMessage = l10n.str('connect_wifi_first', {'wifi': currentSsid ?? ''});
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
            title: Text(l10n.connectionFailed),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.connectedHotspotCannotAccess),
                const SizedBox(height: 12),
                Text(l10n.tryFollowing, style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(l10n.disableMobileData),
                Text(l10n.ensureWifiConnected),
                Text(l10n.waitAndRetry),
                const SizedBox(height: 12),
                Text('${l10n.currentHotspot}: $currentSsid', style: const TextStyle(color: Colors.grey)),
                Text('${l10n.deviceIpLabel}: ${widget.deviceIP}', style: const TextStyle(color: Colors.grey)),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(l10n.cancel),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _checkConnectionAndProceed(); // 重试
                },
                child: Text(l10n.retry),
              ),
            ],
          ),
        );
      }
    }
  }

  Future<void> _startPushFirmware() async {
    final l10n = AppLocalizations.of(context)!;
    if (_selectedFilePath == null) {
      setState(() {
        _isProcessing = false;
        _result = LocalOTAResult.failed;
        _resultMessage = l10n.firmwareFileNotFound;
        _currentStep = LocalOTAStep.result;
      });
      return;
    }

    setState(() {
      _isProcessing = true;
      _uploadProgress = 0.0;
      _errorMessage = null;
    });

    final isEsp = (widget.targetChip ?? 'esp') == 'esp';

    try {
      // 上传固件文件到设备
      await _firmwareService.uploadFirmware(
        deviceIP: widget.deviceIP,
        filePath: _selectedFilePath!,
        target: widget.targetChip ?? 'esp',
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

      if (isEsp) {
        // ESP自升级：传完固件 → ESP写Flash → HTTP 200 → 立即重启(~500ms)
        // ESP重启极快，仅短暂等待后立即开始轮询
        setState(() {
          _upgradeStatus = l10n.str('push_complete_wait_reboot', {});
        });
        await Future.delayed(const Duration(milliseconds: 500));
      } else {
        // ARM升级：ESP作为桥接转发固件给ARM，ESP不重启
        // 直接轮询 /ota/progress 获取实时进度
        setState(() {
          _upgradeStatus = l10n.uploadingStatus;
        });
      }

      // 统一轮询 /ota/progress
      _pollUpgradeProgress();
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _result = LocalOTAResult.failed;
        _resultMessage = l10n.str('upload_firmware_failed', {'error': '$e'});
        _currentStep = LocalOTAStep.result;
      });
      _disconnectDeviceHotspot();
    }
  }

  /// 升级结束后断开设备热点WiFi，恢复正常网络
  void _disconnectDeviceHotspot() {
    WiFiForIoTPlugin.forceWifiUsage(false).catchError((_) => false);
  }

  /// 检测当前 WiFi 是否仍连接到设备热点
  Future<bool> _isDeviceHotspotConnected() async {
    try {
      final ssid = await WiFiForIoTPlugin.getSSID();
      if (ssid == null || ssid.isEmpty || ssid == '<unknown ssid>') return false;
      final upper = ssid.toUpperCase();
      return upper.contains('CS_INV') || upper.contains('CS-INV');
    } catch (_) {
      return false;
    }
  }

  /// 尝试重新连接设备热点
  Future<bool> _reconnectDeviceHotspot() async {
    try {
      await WiFiForIoTPlugin.forceWifiUsage(true);
      final networks = await WiFiForIoTPlugin.loadWifiList();
      final sn = widget.deviceSN.toUpperCase();
      final target = networks.where((n) {
        final ssid = (n.ssid ?? '').toUpperCase();
        return ssid == 'CS_INV_$sn' || ssid == 'CS-INV-$sn';
      }).toList();

      if (target.isEmpty) return false;

      final network = target.first;
      final ssid = network.ssid ?? '';
      final cap = network.capabilities?.toUpperCase() ?? '';
      final isOpen = !cap.contains('WPA') && !cap.contains('WEP') && !cap.contains('EAP');

      final connected = await WiFiForIoTPlugin.connect(
        ssid,
        password: null,
        security: isOpen ? NetworkSecurity.NONE : NetworkSecurity.WPA,
        joinOnce: true,
      );
      if (!connected) return false;

      await WiFiForIoTPlugin.forceWifiUsage(true);
      await Future.delayed(const Duration(seconds: 3)); // 等待IP分配
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 统一轮询 /ota/progress，ESP和ARM走同一套逻辑
  /// ESP: NVS持久化结果，重启后首次请求返回 done/error
  /// ARM: 实时返回 uploading → verifying → done
  Future<void> _pollUpgradeProgress() async {
    final l10n = AppLocalizations.of(context)!;
    final isEsp = (widget.targetChip ?? 'esp') == 'esp';
    final versionKey = isEsp ? 'esp_version' : 'arm_version';

    int totalWaitSeconds = 0;
    int offlineCount = 0; // 连续离线计数
    const maxTotalWait = 180; // 总超时 3 分钟
    bool isFirstPoll = true; // 首次轮询跳过初始延迟

    while (totalWaitSeconds < maxTotalWait) {
      // 首次轮询不等待，后续每次间隔 1 秒
      if (!isFirstPoll) {
        await Future.delayed(const Duration(seconds: 1));
        if (!mounted) return;
        totalWaitSeconds += 1;
      }
      isFirstPoll = false;

      // 1. 先检查 WiFi 连接状态
      final wifiConnected = await _isDeviceHotspotConnected();

      if (!wifiConnected) {
        offlineCount++;
        // 设备热点断开 = 正在重启
        if (mounted) {
          setState(() {
            _upgradeStatus = l10n.str('waiting_hotspot_recovery',
                {'seconds': '$totalWaitSeconds'});
          });
        }

        // 每 2 次离线检测（约 2 秒）尝试一次重连
        if (offlineCount % 2 == 0) {
          final reconnected = await _reconnectDeviceHotspot();
          if (reconnected && mounted) {
            setState(() {
              _upgradeStatus = l10n.str('hotspot_reconnected', {});
            });
            offlineCount = 0;
            // 重连成功，继续下面的轮询
          } else {
            continue; // 重连失败，继续等待
          }
        } else {
          continue; // 热点未恢复，继续等待
        }
      } else {
        offlineCount = 0;
      }

      // 2. 热点已连接，尝试获取升级进度
      try {
        final progress =
            await _firmwareService.getLocalOTAProgress(deviceIP: widget.deviceIP);
        final status = progress['status'] as String? ?? '';
        final percent = (progress['progress'] as num?)?.toDouble() ?? 0.0;
        final message = progress['message'] as String? ?? '';
        final version = progress['version'] as String? ?? '';

        if (mounted) {
          setState(() {
            _upgradeProgress = percent / 100.0;
            _upgradeStatus = message.isNotEmpty ? message : _mapStatus(status);
          });
        }

        if (status == 'done') {
          // 优先从 /ota/progress 的 version 字段获取新版本号
          // 如果为空，再从 /ota/info 获取
          String? newVersion = version.isNotEmpty ? version : null;
          if (newVersion == null) {
            try {
              final info = await _firmwareService.getDeviceInfo(
                  deviceIP: widget.deviceIP);
              newVersion = info[versionKey] as String? ?? '';
              if (newVersion.isEmpty) newVersion = null;
            } catch (_) {}
          }
          if (mounted) {
            setState(() {
              _isProcessing = false;
              _result = LocalOTAResult.success;
              _newVersion = newVersion;
              _currentStep = LocalOTAStep.result;
            });
          }
          _disconnectDeviceHotspot();
          return;
        }

        if (status == 'error') {
          if (mounted) {
            setState(() {
              _isProcessing = false;
              _result = LocalOTAResult.failed;
              _resultMessage =
                  message.isNotEmpty ? message : l10n.upgradeFailed;
              _currentStep = LocalOTAStep.result;
            });
          }
          _disconnectDeviceHotspot();
          return;
        }
      } on DeviceConnectionException {
        // 连接失败，设备可能刚重启完还在初始化 HTTP 服务
        offlineCount++;
        if (mounted) {
          setState(() {
            _upgradeStatus = l10n.str('waiting_device_response',
                {'seconds': '$totalWaitSeconds'});
          });
        }
        continue;
      } catch (_) {
        // 其他异常，继续等待
        continue;
      }
    }

    // 总超时
    if (mounted) {
      setState(() {
        _isProcessing = false;
        _result = LocalOTAResult.failed;
        _resultMessage = l10n.upgradeTimeout;
        _currentStep = LocalOTAStep.result;
      });
    }
    _disconnectDeviceHotspot();
  }

  String _mapStatus(String status) {
    final l10n = AppLocalizations.of(context)!;
    switch (status) {
      case 'idle':
        return l10n.idleStatus;
      case 'downloading':
        return l10n.downloading;
      case 'uploading':
        return l10n.uploadingStatus;
      case 'verifying':
        return l10n.verifying;
      case 'done':
        return l10n.done;
      case 'error':
        return l10n.failure;
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(50.h),
        child: AppBar(
          title: Text(l10n.localFirmwareUpgrade, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 17)),
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
    final l10n = AppLocalizations.of(context)!;
    switch (step) {
      case LocalOTAStep.selectFirmware:
        return l10n.selectFirmware;
      case LocalOTAStep.connectDevice:
        return l10n.connectDevice;
      case LocalOTAStep.pushFirmware:
        return l10n.pushFirmware;
      case LocalOTAStep.triggerUpgrade:
        return l10n.upgrading;
      case LocalOTAStep.result:
        return l10n.upgradeResult;
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
    final l10n = AppLocalizations.of(context)!;
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
              Text(l10n.selectFirmware, style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              SizedBox(height: 12.h),
              if (_selectedFilePath != null)
                _buildSelectedFirmwareInfo()
              else if (_isDownloading)
                _buildDownloadingProgress()
              else
                Text(l10n.firmwareDownloadHint, style: TextStyle(fontSize: 13.sp, color: AppColors.textHint)),
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
              child: Text(l10n.downloadFirmware, style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600)),
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
              child: Text(l10n.next, style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600)),
            ),
          ),
      ],
    );
  }

  Widget _buildDownloadingProgress() {
    final l10n = AppLocalizations.of(context)!;
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
          _downloadProgress > 0 ? '${(_downloadProgress * 100).toStringAsFixed(1)}%' : '${l10n.downloading}...',
          style: TextStyle(fontSize: 12.sp, color: AppColors.primary),
        ),
      ],
    );
  }

  Widget _buildSelectedFirmwareInfo() {
    final l10n = AppLocalizations.of(context)!;
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
                Text(l10n.firmwareReady, style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.successLight)),
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
    final l10n = AppLocalizations.of(context)!;

    // 判断是否正在自动流程中（扫描 + 连接）
    final isInProgress = _scanningWifi || _autoConnecting || _isProcessing;

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
                if (isInProgress) ...[
                  SizedBox(width: 48, height: 48, child: CircularProgressIndicator(strokeWidth: 3, color: AppColors.primary)),
                  SizedBox(height: 12.h),
                  Text(
                    _isProcessing
                        ? l10n.checkConnection
                        : _selectedAp != null
                            ? l10n.str('connecting_to', {'ssid': _selectedAp?.ssid ?? ''})
                            : l10n.scanningDeviceHotspot,
                    style: TextStyle(fontSize: 14.sp, color: AppColors.textSecondary),
                  ),
                ] else if (_selectedAp != null && _errorMessage == null) ...[
                  Icon(Icons.wifi_rounded, size: 48.sp, color: AppColors.successLight),
                  SizedBox(height: 12.h),
                  Text(l10n.connected, style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600, color: AppColors.successLight)),
                  SizedBox(height: 4.h),
                  Text(_selectedAp!.ssid ?? '', style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)),
                ] else ...[
                  Icon(Icons.wifi_find_rounded, size: 48.sp, color: AppColors.primary),
                  SizedBox(height: 12.h),
                  Text(l10n.connectDeviceAp, style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  SizedBox(height: 8.h),
                  Text(
                    l10n.autoScanHint,
                    style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    '${l10n.deviceIpLabel}: ${widget.deviceIP}',
                    style: TextStyle(fontSize: 12.sp, color: AppColors.primary, fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: 12.h),
                  SizedBox(
                    width: double.infinity,
                    height: 40.h,
                    child: OutlinedButton.icon(
                      onPressed: _autoScanAndConnect,
                      icon: Icon(Icons.refresh_rounded, size: 18.sp),
                      label: Text(l10n.rescanHotspot, style: TextStyle(fontSize: 13.sp)),
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
            onPressed: isInProgress ? null : _checkConnectionAndProceed,
            style: ElevatedButton.styleFrom(
              backgroundColor: isInProgress ? AppColors.textHint : AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
              elevation: 0,
            ),
            child: _isProcessing
                ? SizedBox(width: 20.w, height: 20.w, child: const CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(l10n.checkConnection, style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }

  Widget _buildPushFirmwareStep() {
    final l10n = AppLocalizations.of(context)!;
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
              Text(l10n.pushingFirmware, style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
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
    final l10n = AppLocalizations.of(context)!;
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
                _upgradeStatus.isNotEmpty ? _upgradeStatus : l10n.upgrading,
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
                l10n.doNotDisconnect,
                style: TextStyle(fontSize: 12.sp, color: AppColors.warning),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildResultStep() {
    final l10n = AppLocalizations.of(context)!;
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
                Text(l10n.upgradeSuccess, style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                if (_newVersion != null) ...[
                  SizedBox(height: 8.h),
                  Text(l10n.str('new_version_label', {'version': _newVersion!}), style: TextStyle(fontSize: 14.sp, color: AppColors.textSecondary)),
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
                    child: Text(l10n.done, style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
              if (_result == LocalOTAResult.failed) ...[
                Icon(Icons.cancel_rounded, size: 64.sp, color: AppColors.error),
                SizedBox(height: 16.h),
                Text(l10n.upgradeFailed, style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                SizedBox(height: 8.h),
                Text(_resultMessage ?? l10n.unknown, style: TextStyle(fontSize: 14.sp, color: AppColors.textSecondary), textAlign: TextAlign.center),
                SizedBox(height: 24.h),
                SizedBox(
                  width: double.infinity,
                  height: 48.h,
                  child: ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _result = null;
                        _resultMessage = null;
                        _selectedAp = null;
                        _isProcessing = false;
                      });
                      _goToStep(LocalOTAStep.connectDevice);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.error,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                      elevation: 0,
                    ),
                    child: Text(l10n.retry, style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
              if (_result == LocalOTAResult.verifyFailed) ...[
                Icon(Icons.warning_rounded, size: 64.sp, color: AppColors.warning),
                SizedBox(height: 16.h),
                Text(l10n.firmwareVerifyFailed, style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                SizedBox(height: 8.h),
                Text(l10n.firmwareCorruptedHint, style: TextStyle(fontSize: 14.sp, color: AppColors.textSecondary), textAlign: TextAlign.center),
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
                    child: Text(l10n.redownload, style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600)),
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
    final l10n = AppLocalizations.of(context)!;
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
                Text(l10n.currentDevice, style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
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
