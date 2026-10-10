import 'package:flutter/material.dart';
import 'package:inv_app/l10n/app_localizations.dart';

class AddDeviceTabs extends StatefulWidget {
  final String? stationName;
  final int? stationId;
  final VoidCallback onSelectStation;
  final ValueChanged<bool> onScanVisibilityChanged;
  final Widget scan;
  final Widget manual;
  final Widget nearby;
  final Widget owned;

  const AddDeviceTabs({
    super.key,
    required this.stationName,
    required this.stationId,
    required this.onSelectStation,
    required this.onScanVisibilityChanged,
    required this.scan,
    required this.manual,
    required this.nearby,
    required this.owned,
  });

  @override
  State<AddDeviceTabs> createState() => _AddDeviceTabsState();
}

class _AddDeviceTabsState extends State<AddDeviceTabs>
    with TickerProviderStateMixin {
  late final _mode = TabController(length: 2, vsync: this);
  late final _newSource = TabController(length: 2, vsync: this);
  late final _existingSource = TabController(length: 2, vsync: this);
  bool _scanVisible = true;

  @override
  void initState() {
    super.initState();
    for (final controller in [_mode, _newSource, _existingSource]) {
      controller.addListener(_changed);
    }
  }

  void _changed() {
    final visible = _mode.index == 0 && _newSource.index == 0;
    if (visible != _scanVisible) {
      _scanVisible = visible;
      widget.onScanVisibilityChanged(visible);
    }
    setState(() {});
  }

  @override
  void dispose() {
    for (final controller in [_mode, _newSource, _existingSource]) {
      controller.removeListener(_changed);
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isNew = _mode.index == 0;
    final labels = [l10n.str('add_device_new'), l10n.str('select_device')];
    final style = Theme.of(context).textTheme.labelLarge!;
    final labelWidth =
        (MediaQuery.sizeOf(context).width / 2 - 32).clamp(1.0, double.infinity);
    var tabHeight = 48.0;
    for (final label in labels) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout(maxWidth: labelWidth);
      if (painter.height + 16 > tabHeight) tabHeight = painter.height + 16;
      painter.dispose();
    }
    return Column(
      children: [
        ListTile(
          key: const ValueKey('add-device-station'),
          leading: const Icon(Icons.solar_power_outlined),
          title: Text(
            widget.stationId == null
                ? l10n.str('select_station')
                : widget.stationName ??
                    l10n.str('add_device_station_id', {
                      'id': '${widget.stationId}',
                    }),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: const Icon(Icons.expand_more),
          onTap: widget.onSelectStation,
        ),
        TabBar(
          controller: _mode,
          labelStyle: style,
          unselectedLabelStyle: style,
          tabs: [
            Tab(
              height: tabHeight,
              child: Text(labels[0], textAlign: TextAlign.center),
            ),
            Tab(
              height: tabHeight,
              child: Text(labels[1], textAlign: TextAlign.center),
            ),
          ],
        ),
        TabBar(
          controller: isNew ? _newSource : _existingSource,
          isScrollable: true,
          tabAlignment: TabAlignment.center,
          tabs: isNew
              ? [
                  Tab(text: l10n.str('scan_code')),
                  Tab(text: l10n.str('add_device_manual')),
                ]
              : [
                  Tab(text: l10n.str('add_device_nearby')),
                  Tab(text: l10n.str('my_devices')),
                ],
        ),
        Expanded(
          child: isNew
              ? (_newSource.index == 0 ? widget.scan : widget.manual)
              : (_existingSource.index == 0 ? widget.nearby : widget.owned),
        ),
      ],
    );
  }
}
