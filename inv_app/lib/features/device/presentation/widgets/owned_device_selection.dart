import 'dart:async';
import 'package:flutter/material.dart';
import 'package:inv_app/core/widgets/app_toast.dart';
import 'package:inv_app/features/device/presentation/pages/owned_device_selection_service.dart';
import 'package:inv_app/l10n/app_localizations.dart';

class OwnedDeviceSelection extends StatefulWidget {
  final OwnedDeviceSelectionService service;
  final int? stationId;
  final Future<int?> Function() selectStation;
  final ValueChanged<int> onAdded;

  const OwnedDeviceSelection({
    super.key,
    required this.service,
    required this.stationId,
    required this.selectStation,
    required this.onAdded,
  });

  @override
  State<OwnedDeviceSelection> createState() => _OwnedDeviceSelectionState();
}

class _OwnedDeviceSelectionState extends State<OwnedDeviceSelection> {
  final _search = TextEditingController();
  final _items = <Map<String, dynamic>>[];
  Timer? _debounce;
  int _generation = 0;
  int _page = 0;
  bool _loading = false;
  bool _hasMore = false;
  String? _addingSn;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  @override
  void dispose() {
    _generation++;
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading && !reset) return;
    final generation = reset ? ++_generation : _generation;
    final page = reset ? 1 : _page + 1;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _items.clear();
        _page = 0;
        _hasMore = false;
      }
    });
    try {
      final result =
          await widget.service.load(page: page, keyword: _search.text);
      if (!mounted || generation != _generation) return;
      setState(() {
        final seen = _items.map((device) => device['sn']).toSet();
        _items.addAll(result.items.where((device) => seen.add(device['sn'])));
        _page = page;
        _hasMore = result.hasMore;
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = error);
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  void _searchChanged(String _) {
    _debounce?.cancel();
    // Invalidate in-flight results immediately, before the debounce fires.
    _generation++;
    setState(() {
      _items.clear();
      _loading = true;
      _error = null;
      _hasMore = false;
    });
    _debounce =
        Timer(const Duration(milliseconds: 300), () => _load(reset: true));
  }

  Future<void> _add(Map<String, dynamic> device) async {
    if (_addingSn != null || _loading) return;
    final sn = device['sn'] as String;
    setState(() => _addingSn = sn);
    final l10n = AppLocalizations.of(context)!;
    try {
      final stationId = widget.stationId ?? await widget.selectStation();
      if (!mounted || stationId == null) return;
      final result = await widget.service.associate(sn, stationId);
      if (!mounted) return;
      if (result == OwnedDeviceAssociation.added) {
        widget.onAdded(stationId);
        AppToast.show(
          context,
          l10n.str('add_device_station_success'),
          type: ToastType.success,
        );
      } else {
        AppToast.show(
          context,
          l10n.str('add_device_already_assigned'),
          type: ToastType.info,
        );
      }
      await _load(reset: true);
    } catch (error) {
      if (mounted) {
        AppToast.show(
          context,
          l10n.translateError(error.toString()),
          type: ToastType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _addingSn = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _search,
                  onChanged: _searchChanged,
                  decoration: InputDecoration(
                    labelText: l10n.str('search_device_hint'),
                    prefixIcon: const Icon(Icons.search),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              IconButton(
                onPressed: _loading || _addingSn != null
                    ? null
                    : () => _load(reset: true),
                tooltip: l10n.str('refresh_label'),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        if (_loading) const LinearProgressIndicator(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => _load(reset: true),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                if (_items.isEmpty && !_loading && _error == null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Text(
                      l10n.str(
                        _search.text.trim().isEmpty
                            ? 'no_devices'
                            : 'no_search_results',
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                for (final device in _items) ...[
                  _deviceRow(device, l10n),
                  const Divider(height: 1),
                ],
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Column(
                      children: [
                        Text(
                          l10n.translateError(_error.toString()),
                          textAlign: TextAlign.center,
                        ),
                        TextButton.icon(
                          onPressed: () => _load(reset: _page == 0),
                          icon: const Icon(Icons.refresh),
                          label: Text(l10n.str('retry')),
                        ),
                      ],
                    ),
                  )
                else if (_hasMore)
                  TextButton.icon(
                    onPressed: _loading ? null : () => _load(),
                    icon: const Icon(Icons.expand_more),
                    label: Text(l10n.str('load_more')),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _deviceRow(Map<String, dynamic> device, AppLocalizations l10n) {
    final sn = device['sn'] as String;
    final alias = (device['alias'] ?? '').toString().trim();
    final name =
        alias.isEmpty ? (device['name'] ?? '').toString().trim() : alias;
    final stationId = device['station_id'];
    final assigned = stationId != null && stationId != 0;
    final stationName = (device['station_name'] ?? '').toString().trim();
    final location = (device['location'] ?? '').toString().trim();
    final status = device['status'];
    final statusKey = switch (status) {
      0 => 'offline',
      1 => 'online',
      2 => 'fault',
      _ => 'unknown',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isEmpty ? sn : name,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Text('SN: $sn'),
                Text(l10n.str(statusKey)),
                Text(
                  assigned
                      ? (stationName.isEmpty
                          ? l10n.str(
                              'add_device_station_id',
                              {'id': '$stationId'},
                            )
                          : stationName)
                      : l10n.str('add_device_unassigned'),
                ),
                if (location.isNotEmpty) Text(location),
                if (assigned) Text(l10n.str('add_device_already_assigned')),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (_addingSn == sn)
            const SizedBox(
              width: 48,
              height: 48,
              child: Center(
                child: SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            IconButton(
              key: ValueKey('associate-$sn'),
              tooltip: l10n.str(
                assigned
                    ? 'add_device_already_assigned'
                    : 'add_device_to_station',
              ),
              onPressed: assigned || _addingSn != null || _loading
                  ? null
                  : () => _add(device),
              icon: Icon(assigned ? Icons.check_circle_outline : Icons.add),
            ),
        ],
      ),
    );
  }
}
