import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/features/device/domain/repositories/device_repository.dart';
import 'package:inv_app/l10n/app_localizations.dart';

class OtaTabPage extends StatefulWidget {
  const OtaTabPage({super.key, this.repository});
  final DeviceRepository? repository;
  @override
  State<OtaTabPage> createState() => _OtaTabPageState();
}

class _OtaTabPageState extends State<OtaTabPage> {
  late final DeviceRepository _repository =
      widget.repository ?? getIt<DeviceRepository>();
  List<Map<String, dynamic>> _devices = const [];
  bool _loading = true;
  String? _error;
  int _page = 1;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) _page = 1;
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await _repository.getList(page: _page, pageSize: 20);
    if (!mounted) return;
    result.match(
      (failure) => setState(() {
        if (!reset && _page > 1) _page--;
        _loading = false;
        _error = failure.message;
      }),
      (data) => setState(() {
        _loading = false;
        final items = (data['items'] as List? ?? const [])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
        _devices = reset ? items : [..._devices, ...items];
        _total = (data['total'] as num?)?.toInt() ?? _devices.length;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final onlineCount = _devices.where(_isOnline).length;
    return Scaffold(
      backgroundColor: AppColor.surface(context),
      appBar: AppBar(title: Text(l10n.str('ota_title')), centerTitle: true),
      body: RefreshIndicator(
        onRefresh: () => _load(reset: true),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: [
            _OverviewCard(
              total: _total,
              online: onlineCount,
            ),
            const SizedBox(height: 24),
            Text(l10n.str('firmware_my_devices'),
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(l10n.str('firmware_my_devices_hint'),
                style: TextStyle(color: AppColor.textSecondary(context))),
            const SizedBox(height: 14),
            if (_loading && _devices.isEmpty)
              const Center(
                  child: Padding(
                      padding: EdgeInsets.all(32),
                      child: CircularProgressIndicator()))
            else if (_error != null && _devices.isEmpty)
              _MessageCard(
                  icon: Icons.cloud_off_rounded,
                  text: l10n.str('firmware_devices_load_failed'),
                  action: l10n.retry,
                  onTap: () => _load(reset: true))
            else if (_devices.isEmpty)
              _MessageCard(
                  icon: Icons.devices_other_rounded,
                  text: l10n.str('ota_picker_empty'))
            else
              ..._devices.map((device) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _DeviceCard(device: device))),
            if (_error != null && _devices.isNotEmpty)
              Text(
                l10n.str('firmware_devices_load_failed'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.error),
              ),
            if (_devices.length < _total)
              TextButton(
                onPressed: _loading
                    ? null
                    : () {
                        _page++;
                        _load();
                      },
                child: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l10n.str('load_more')),
              ),
            const SizedBox(height: 18),
            Text(l10n.str('firmware_more_tools'),
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.18,
              children: [
                _ToolCard(
                    icon: Icons.cloud_sync_rounded,
                    color: AppColors.blue,
                    title: l10n.str('ota_check_update'),
                    subtitle: l10n.str('ota_check_update_hint'),
                    onTap: () => context.push('/ota/check-all')),
                _ToolCard(
                    icon: Icons.wifi_tethering_rounded,
                    color: AppColors.teal,
                    title: l10n.str('ota_local_upgrade'),
                    subtitle: l10n.str('ota_local_upgrade_hint'),
                    onTap: () => context.push('/local-upgrade')),
                _ToolCard(
                    icon: Icons.inventory_2_outlined,
                    color: AppColors.orange,
                    title: l10n.str('ota_firmware_library'),
                    subtitle: l10n.str('ota_firmware_library_hint'),
                    onTap: () => context.push('/firmware-library')),
                _ToolCard(
                    icon: Icons.history_rounded,
                    color: AppColors.purple,
                    title: l10n.str('ota_upgrade_history'),
                    subtitle: l10n.str('ota_upgrade_history_hint'),
                    onTap: () => context.push('/upgrade-history')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static bool _isOnline(Map<String, dynamic> device) =>
      device['online'] == true ||
      device['status'] == 1 ||
      device['status'] == 2;
}

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({required this.total, required this.online});
  final int total;
  final int online;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0D47A1), Color(0xFF1976D2), Color(0xFF42A5F5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: .24),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(children: [
        Positioned(
          right: -18,
          top: -26,
          child: Icon(Icons.system_update_alt_rounded,
              size: 116, color: Colors.white.withValues(alpha: .10)),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .16),
              borderRadius: BorderRadius.circular(14),
            ),
            child:
                const Icon(Icons.developer_board_rounded, color: Colors.white),
          ),
          const SizedBox(height: 18),
          Text(l10n.str('firmware_overview'),
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
          const SizedBox(height: 5),
          Text(l10n.str('firmware_my_devices_hint'),
              style: TextStyle(color: Colors.white.withValues(alpha: .78))),
          const SizedBox(height: 20),
          Row(children: [
            _OverviewStat(
                value: '$total', label: l10n.str('firmware_device_count')),
            Container(
                width: 1,
                height: 34,
                margin: const EdgeInsets.symmetric(horizontal: 22),
                color: Colors.white.withValues(alpha: .24)),
            _OverviewStat(
                value: '$online', label: l10n.str('firmware_online_count')),
          ]),
        ]),
      ]),
    );
  }
}

class _OverviewStat extends StatelessWidget {
  const _OverviewStat({required this.value, required this.label});
  final String value;
  final String label;
  @override
  Widget build(BuildContext context) => Row(children: [
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w700)),
        const SizedBox(width: 8),
        Text(label,
            style: TextStyle(color: Colors.white.withValues(alpha: .72))),
      ]);
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.device});
  final Map<String, dynamic> device;
  @override
  Widget build(BuildContext context) {
    final sn = device['sn']?.toString() ?? '';
    final alias = (device['alias'] ?? device['name'])?.toString().trim() ?? '';
    final model =
        (device['model'] ?? device['device_model'])?.toString().trim() ?? '';
    final name = alias.isNotEmpty ? alias : (model.isNotEmpty ? model : sn);
    final online = device['online'] == true ||
        device['status'] == 1 ||
        device['status'] == 2;
    final l10n = AppLocalizations.of(context)!;
    return Material(
      color: AppColor.surfaceContainer(context),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: sn.isEmpty
            ? null
            : () => context.push('/ota/device/${Uri.encodeComponent(sn)}'),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColor.border(context)),
          ),
          child: Row(children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppColor.primarySoft(context),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(Icons.solar_power_rounded,
                  color: AppColor.primary(context)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                        child: Text(name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700)),
                      ),
                      _StatusPill(
                          online: online,
                          label: l10n.str(online ? 'online' : 'offline')),
                    ]),
                    const SizedBox(height: 7),
                    Text(model.isEmpty ? sn : model,
                        style: TextStyle(
                            color: AppColor.textSecondary(context),
                            fontWeight: FontWeight.w500)),
                    if (model.isNotEmpty && sn.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(sn,
                          style: TextStyle(
                              fontSize: 12, color: AppColor.textHint(context))),
                    ],
                  ]),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right_rounded,
                color: AppColor.textHint(context)),
          ]),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.online, required this.label});
  final bool online;
  final String label;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color:
              online ? AppColors.badgeNormalBg : AppColor.surfaceHover(context),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: online ? AppColors.successLight : AppColors.offline)),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: online
                      ? AppColors.badgeNormalText
                      : AppColor.textSecondary(context))),
        ]),
      );
}

class _ToolCard extends StatelessWidget {
  const _ToolCard(
      {required this.icon,
      required this.color,
      required this.title,
      required this.subtitle,
      required this.onTap});
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
        color: AppColor.surfaceContainer(context),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColor.border(context)),
            ),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .11),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const Spacer(),
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text(subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12, color: AppColor.textSecondary(context))),
            ]),
          ),
        ),
      );
}

class _MessageCard extends StatelessWidget {
  const _MessageCard(
      {required this.icon, required this.text, this.action, this.onTap});
  final IconData icon;
  final String text;
  final String? action;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Card(
          child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(children: [
          Icon(icon, size: 38, color: AppColor.textHint(context)),
          const SizedBox(height: 10),
          Text(text),
          if (action != null) TextButton(onPressed: onTap, child: Text(action!))
        ]),
      ));
}
