import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/widgets/app_toast.dart';
import 'package:inv_app/features/device/domain/repositories/device_repository.dart';
import 'package:inv_app/features/ota/domain/entities/device_firmware_history.dart';
import 'package:inv_app/features/ota/domain/entities/device_firmware_overview.dart';
import 'package:inv_app/features/ota/domain/repositories/ota_repository.dart';
import 'package:inv_app/features/ota/presentation/models/firmware_module_presentation.dart';
import 'package:inv_app/features/ota/presentation/widgets/device_firmware_history_tile.dart';
import 'package:inv_app/l10n/app_localizations.dart';

class DeviceFirmwareDetailPage extends StatefulWidget {
  const DeviceFirmwareDetailPage(
      {super.key,
      required this.deviceSN,
      this.deviceRepository,
      this.otaRepository});
  final String deviceSN;
  final DeviceRepository? deviceRepository;
  final OtaRepository? otaRepository;
  @override
  State<DeviceFirmwareDetailPage> createState() =>
      _DeviceFirmwareDetailPageState();
}

class _DeviceFirmwareDetailPageState extends State<DeviceFirmwareDetailPage> {
  late final DeviceRepository _devices =
      widget.deviceRepository ?? getIt<DeviceRepository>();
  late final OtaRepository _ota =
      widget.otaRepository ?? getIt<OtaRepository>();
  Map<String, dynamic>? _device;
  DeviceFirmwareOverview? _overview;
  List<DeviceFirmwareHistory> _history = const [];
  bool _loadingDevice = true;
  bool _loadingOverview = true;
  bool _loadingHistory = true;
  bool? _realtimeOnline;
  String? _deviceError;
  String? _overviewError;
  String? _historyError;
  bool _triggering = false;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// 检查更新：原地刷新固件概览与历史，不再 push 本页路由
  Future<void> _reloadOverview() async {
    setState(() => _refreshing = true);
    try {
      await Future.wait([
        _loadOverview(),
        _loadHistory(),
      ]);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _load() async {
    await Future.wait([
      _loadDevice(),
      _loadOverview(),
      _loadHistory(),
    ]);
  }

  Future<void> _loadDevice() async {
    setState(() {
      _loadingDevice = true;
      _deviceError = null;
    });
    final result = await _devices.getDetail(widget.deviceSN);
    if (!mounted) return;
    result.match(
      (failure) => setState(() {
        _loadingDevice = false;
        _deviceError = failure.message;
      }),
      (data) => setState(() {
        _loadingDevice = false;
        final raw = data['device'];
        _device = raw is Map ? Map<String, dynamic>.from(raw) : data;
        final onlineStatus = data['online_status'];
        _realtimeOnline = onlineStatus is Map &&
                onlineStatus.containsKey('online') &&
                onlineStatus['online'] is bool
            ? onlineStatus['online'] as bool
            : null;
      }),
    );
  }

  Future<void> _loadOverview() async {
    setState(() {
      _loadingOverview = true;
      _overviewError = null;
    });
    final result = await _ota.getFirmwareOverview(widget.deviceSN);
    if (!mounted) return;
    result.match(
      (failure) => setState(() {
        _loadingOverview = false;
        _overviewError = failure.message;
      }),
      (overview) => setState(() {
        _loadingOverview = false;
        _overview = overview;
      }),
    );
  }

  Future<void> _loadHistory() async {
    setState(() {
      _loadingHistory = true;
      _historyError = null;
    });
    final result = await _ota.getDeviceHistory(widget.deviceSN, pageSize: 5);
    if (!mounted) return;
    result.match(
      (failure) => setState(() {
        _loadingHistory = false;
        _historyError = failure.message;
      }),
      (page) => setState(() {
        _loadingHistory = false;
        _history = page.items;
      }),
    );
  }

  String _value(String key, [String fallback = '—']) {
    final value = _device?[key]?.toString().trim() ?? '';
    return value.isEmpty ? fallback : value;
  }

  String _firstValue(List<String> keys, [String fallback = '—']) {
    for (final key in keys) {
      final value = _device?[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return fallback;
  }

  bool get _online =>
      _realtimeOnline ??
      (_device?['online'] == true ||
          _device?['status'] == 1 ||
          _device?['status'] == 2);

  bool get _canUpgrade =>
      !_loadingDevice &&
      _deviceError == null &&
      _device != null &&
      _online &&
      !_triggering;

  List<FirmwareModuleOverview> get _updatableModules =>
      _overview?.modules.where((m) => m.canRemoteUpgrade).toList() ??
      const [];

  Future<void> _triggerSingle(FirmwareModuleOverview module) async {
    final l10n = AppLocalizations.of(context)!;
    if (!_canUpgrade || module.latestFirmwareId <= 0) return;
    final moduleLabel =
        FirmwareModulePresentation.fromTarget(module.target).displayLabel(l10n);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.str('firmware_upgrade_this_module')),
        content: Text(l10n.str('firmware_upgrade_confirm_single', {
          'module': moduleLabel,
          'version': module.latestVersion,
        })),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _doTrigger([module.latestFirmwareId]);
  }

  Future<void> _triggerAll() async {
    final l10n = AppLocalizations.of(context)!;
    final modules = _updatableModules;
    if (!_canUpgrade || modules.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.str('firmware_upgrade_all_modules')),
        content: Text(
          l10n.str('firmware_upgrade_confirm_all', {'count': '${modules.length}'}),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final ids = modules
        .where((m) => m.latestFirmwareId > 0)
        .map((m) => m.latestFirmwareId)
        .toList();
    await _doTrigger(ids);
  }

  Future<void> _doTrigger(List<int> firmwareIds) async {
    final l10n = AppLocalizations.of(context)!;
    if (firmwareIds.isEmpty) return;
    setState(() => _triggering = true);
    final key =
        'app-${widget.deviceSN}-${DateTime.now().millisecondsSinceEpoch}';
    final result = await _ota.triggerFirmware(
      widget.deviceSN,
      firmwareIds,
      idempotencyKey: key,
    );
    if (!mounted) return;
    setState(() => _triggering = false);
    result.match(
      (failure) => AppToast.show(
        context,
        l10n.str('firmware_upgrade_failed', {'error': failure.message}),
        type: ToastType.error,
      ),
      (tasks) {
        AppToast.show(
          context,
          l10n.str('firmware_upgrade_started'),
          type: ToastType.success,
        );
        final firstTaskId = tasks.isNotEmpty ? tasks.first.taskId : 0;
        if (firstTaskId > 0) {
          final route = Uri(
            path: '/ota/${widget.deviceSN}/detail',
            queryParameters: {'task_id': '$firstTaskId'},
          );
          context.push(route.toString());
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final name = _firstValue(
      ['alias', 'name', 'model', 'device_model'],
      widget.deviceSN,
    );
    final model = _firstValue(['model', 'device_model']);
    final online = _online;
    final canCheckUpdate = _canUpgrade;
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    return Scaffold(
      backgroundColor: AppColor.surface(context),
      appBar: AppBar(title: Text(l10n.str('firmware_device_detail'))),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
            key: const Key('deviceFirmwareDetailList'),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: [
              if (_loadingDevice)
                const Center(
                    child: Padding(
                        padding: EdgeInsets.all(32),
                        child: CircularProgressIndicator()))
              else if (_deviceError != null)
                _ErrorCard(
                    text: l10n.str('firmware_device_load_failed'),
                    onRetry: _loadDevice)
              else ...[
                _DeviceHero(
                    name: name,
                    model: model,
                    serialNumber: widget.deviceSN,
                    online: online),
                const SizedBox(height: 24),
                _SectionTitle(l10n.str('firmware_device_information')),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColor.surfaceContainer(context),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColor.border(context)),
                  ),
                  child: GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: 4,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisExtent: 82 + (textScale - 1) * 32,
                    ),
                    itemBuilder: (context, index) => [
                      _InfoCell(label: l10n.str('device_model'), value: model),
                      _InfoCell(
                          label: l10n.str('firmware_device_name'), value: name),
                      _InfoCell(
                          label: l10n.str('firmware_device_sn'),
                          value: widget.deviceSN),
                      _InfoCell(
                          label: l10n.str('firmware_hardware_version'),
                          value: _value('hardware_version')),
                    ][index],
                  ),
                ),
                const SizedBox(height: 20),
                _SectionTitle(l10n.str('firmware_details')),
                if (_loadingOverview)
                  const Center(
                      child: Padding(
                          padding: EdgeInsets.all(24),
                          child: CircularProgressIndicator()))
                else if (_overviewError != null)
                  _ErrorCard(
                      text: l10n.str('firmware_device_load_failed'),
                      onRetry: _loadOverview)
                else
                  _buildModuleCards(l10n, textScale, online),
              ],
              const SizedBox(height: 20),
              Row(key: const Key('firmwareUpdateLogHeader'), children: [
                Expanded(child: _SectionTitle(l10n.str('firmware_update_log'))),
                TextButton(
                    onPressed: () => context.push(
                        '/ota/device/${Uri.encodeComponent(widget.deviceSN)}/history'),
                    child: Text(l10n.str('view_all'))),
              ]),
              if (_loadingHistory)
                const Center(
                    child: Padding(
                        padding: EdgeInsets.all(24),
                        child: CircularProgressIndicator()))
              else if (_historyError != null)
                _ErrorCard(
                    text: l10n.str('upgrade_history_load_failed'),
                    onRetry: _loadHistory)
              else if (_history.isEmpty)
                Card(
                    child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Center(
                            child: Text(l10n.str('upgrade_history_empty')))))
              else
                ..._history.indexed.map((entry) => DeviceFirmwareHistoryTile(
                    item: entry.$2,
                    isFirst: entry.$1 == 0,
                    isLast: entry.$1 == _history.length - 1)),
              const SizedBox(height: 24),
              if (_device != null && !online) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.cloud_off_rounded,
                        size: 18, color: AppColor.textSecondary(context)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.str('firmware_offline_check_hint'),
                        style: TextStyle(
                          color: AppColor.textSecondary(context),
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              // 全部升级：仅当存在多个可更新模块时显示
              if (_updatableModules.length > 1) ...[
                SizedBox(
                  key: const Key('firmwareUpgradeAllAction'),
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    onPressed: canCheckUpdate ? _triggerAll : null,
                    icon: const Icon(Icons.upgrade_rounded),
                    label: Text(
                      '${l10n.str('firmware_upgrade_all_modules')} '
                      '(${_updatableModules.length})',
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              SizedBox(
                key: const Key('firmwareUpdateAction'),
                width: double.infinity,
                child: FilledButton.icon(
                  // 原地刷新概览，避免 push 同一路由导致导航栈层层叠加
                  onPressed:
                      (_refreshing || _loadingOverview) ? null : _reloadOverview,
                  icon: (_refreshing || _loadingOverview)
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded),
                  label: Text(
                    l10n.str('firmware_check_update'),
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ]),
      ),
    );
  }

  Widget _buildModuleCards(
    AppLocalizations l10n,
    double textScale,
    bool online,
  ) {
    final overview = _overview;
    final modules = overview?.modules ?? const <FirmwareModuleOverview>[];
    if (modules.isEmpty) {
      // 回退：从设备字段展示四模块当前版本
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 4,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          mainAxisExtent: 160 + (textScale - 1) * 200,
        ),
        itemBuilder: (context, index) {
          final entry = const [
            ('firmware_esp', 'esp'),
            ('firmware_arm', 'arm'),
            ('firmware_dsp', 'dsp'),
            ('firmware_bms', 'bms'),
          ][index];
          return _FirmwareCard(
            module: FirmwareModulePresentation.fromTarget(entry.$2),
            currentVersion: _value(
              entry.$1,
              l10n.str('firmware_version_not_reported'),
            ),
          );
        },
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: modules.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        mainAxisExtent: 200 + (textScale - 1) * 220,
      ),
      itemBuilder: (context, index) {
        final m = modules[index];
        return _FirmwareCard(
          module: FirmwareModulePresentation.fromTarget(m.target),
          currentVersion: m.isUnreported
              ? l10n.str('firmware_version_not_reported')
              : (m.currentVersion.isEmpty
                  ? l10n.str('firmware_version_not_reported')
                  : m.currentVersion),
          latestVersion: m.latestVersion,
          changelog: FirmwareModulePresentation.sanitizeCustomerCopy(
            m.changelog,
            l10n,
          ),
          updateAvailable: m.updateAvailable,
          canUpgrade: online && m.canRemoteUpgrade,
          onUpgrade: () => _triggerSingle(m),
        );
      },
    );
  }
}

class _DeviceHero extends StatelessWidget {
  const _DeviceHero({
    required this.name,
    required this.model,
    required this.serialNumber,
    required this.online,
  });
  final String name;
  final String model;
  final String serialNumber;
  final bool online;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final onlineTextColor = Theme.of(context).brightness == Brightness.dark
        ? AppColors.successLight
        : AppColors.success;
    return Container(
      key: const Key('deviceFirmwareHero'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColor.primaryContainer(context),
            AppColor.surfaceContainer(context),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(children: [
        Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            color: AppColor.primarySoft(context),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Icon(Icons.solar_power_rounded,
              color: AppColor.primary(context), size: 30),
        ),
        const SizedBox(width: 16),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: AppColor.textPrimary(context),
                    fontSize: 19,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 5),
            Text(model,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppColor.textSecondary(context))),
            const SizedBox(height: 3),
            Text(serialNumber,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: AppColor.textHint(context), fontSize: 12)),
          ]),
        ),
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: online
                  ? AppColors.successLight.withValues(alpha: .12)
                  : AppColor.surfaceHover(context),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: online
                          ? AppColors.successLight
                          : AppColors.offline)),
              const SizedBox(width: 6),
              Flexible(
                child: Text(l10n.str(online ? 'online' : 'offline'),
                    key: const Key('deviceFirmwareStatusLabel'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: online
                            ? onlineTextColor
                            : AppColor.textSecondary(context),
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(text,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w700)));
}

class _InfoCell extends StatelessWidget {
  const _InfoCell({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12, color: AppColor.textSecondary(context))),
              const SizedBox(height: 5),
              Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ]),
      );
}

class _FirmwareCard extends StatelessWidget {
  const _FirmwareCard({
    required this.module,
    required this.currentVersion,
    this.latestVersion,
    this.changelog,
    this.updateAvailable = false,
    this.canUpgrade = false,
    this.onUpgrade,
  });
  final FirmwareModulePresentation module;
  final String currentVersion;
  final String? latestVersion;
  final String? changelog;
  final bool updateAvailable;
  final bool canUpgrade;
  final VoidCallback? onUpgrade;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final color = switch (module.kind) {
      FirmwareModuleKind.communication => AppColors.blue,
      FirmwareModuleKind.systemControl => AppColors.indigo,
      FirmwareModuleKind.powerControl => AppColors.orange,
      FirmwareModuleKind.batteryManagement => AppColors.teal,
      FirmwareModuleKind.generic => AppColors.purple,
    };
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColor.surfaceContainer(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: updateAvailable
              ? color.withValues(alpha: .45)
              : AppColor.border(context),
        ),
      ),
      child:
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .11),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(module.icon, color: color, size: 20),
          ),
          const Spacer(),
          if (updateAvailable)
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  l10n.str('firmware_latest_version'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: color),
                ),
              ),
            ),
        ]),
        const SizedBox(height: 8),
        Text(module.displayLabel(l10n),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        const SizedBox(height: 4),
        Text(
          '${l10n.str('firmware_current_version')}: $currentVersion',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontSize: 11, color: AppColor.textSecondary(context)),
        ),
        if (latestVersion != null && latestVersion!.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            '${l10n.str('firmware_latest_version')}: $latestVersion',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: updateAvailable ? color : AppColor.textSecondary(context),
            ),
          ),
        ],
        if (changelog != null && changelog!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Expanded(
            child: Text(
              changelog!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  height: 1.3,
                  fontSize: 11,
                  color: AppColor.textSecondary(context)),
            ),
          ),
        ] else
          const Spacer(),
        if (canUpgrade && onUpgrade != null)
          SizedBox(
            width: double.infinity,
            height: 30,
            child: FilledButton(
              style: FilledButton.styleFrom(
                padding: EdgeInsets.zero,
                textStyle: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w600),
              ),
              onPressed: onUpgrade,
              child: Text(l10n.str('firmware_upgrade_this_module')),
            ),
          ),
      ]),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.text, required this.onRetry});
  final String text;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(children: [
              Text(text),
              TextButton(onPressed: onRetry, child: Text(l10n.retry))
            ])));
  }
}
