import 'package:flutter/material.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/features/ota/domain/entities/device_firmware_history.dart';
import 'package:inv_app/features/ota/domain/repositories/ota_repository.dart';
import 'package:inv_app/features/ota/presentation/widgets/device_firmware_history_tile.dart';
import 'package:inv_app/l10n/app_localizations.dart';

class DeviceFirmwareHistoryPage extends StatefulWidget {
  const DeviceFirmwareHistoryPage(
      {super.key, required this.deviceSN, this.repository});
  final String deviceSN;
  final OtaRepository? repository;
  @override
  State<DeviceFirmwareHistoryPage> createState() =>
      _DeviceFirmwareHistoryPageState();
}

class _DeviceFirmwareHistoryPageState extends State<DeviceFirmwareHistoryPage> {
  late final OtaRepository _repository =
      widget.repository ?? getIt<OtaRepository>();
  final List<DeviceFirmwareHistory> _items = [];
  int _page = 1;
  bool _loading = true;
  bool _hasMore = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      _page = 1;
      _items.clear();
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final result =
        await _repository.getDeviceHistory(widget.deviceSN, page: _page);
    if (!mounted) return;
    result.match(
      (failure) => setState(() {
        if (!reset && _page > 1) _page--;
        _loading = false;
        _error = failure.message;
      }),
      (data) => setState(() {
        _loading = false;
        _items.addAll(data.items);
        _hasMore = data.hasMore;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColor.surface(context),
      appBar: AppBar(title: Text(l10n.str('firmware_update_log'))),
      body: RefreshIndicator(
          onRefresh: () => _load(reset: true),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_items.isEmpty && _loading)
                const Center(
                    child: Padding(
                        padding: EdgeInsets.all(32),
                        child: CircularProgressIndicator()))
              else if (_items.isEmpty && _error != null)
                Center(
                    child: Column(children: [
                  Text(l10n.str('upgrade_history_load_failed')),
                  TextButton(
                      onPressed: () => _load(reset: true),
                      child: Text(l10n.retry))
                ]))
              else if (_items.isEmpty)
                Padding(
                    padding: const EdgeInsets.all(32),
                    child:
                        Center(child: Text(l10n.str('upgrade_history_empty'))))
              else
                ..._items.indexed.map((entry) => DeviceFirmwareHistoryTile(
                    item: entry.$2,
                    isFirst: entry.$1 == 0,
                    isLast: entry.$1 == _items.length - 1)),
              if (_items.isNotEmpty && _error != null)
                Text(l10n.str('upgrade_history_load_failed'),
                    textAlign: TextAlign.center),
              if (_hasMore)
                TextButton(
                    onPressed: _loading
                        ? null
                        : () {
                            _page++;
                            _load();
                          },
                    child: _loading
                        ? const CircularProgressIndicator()
                        : Text(l10n.str('load_more'))),
            ],
          )),
    );
  }
}
