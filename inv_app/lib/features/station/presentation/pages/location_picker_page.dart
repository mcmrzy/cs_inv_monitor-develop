import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:latlong2/latlong.dart';
import 'package:inv_app/l10n/app_localizations.dart';

/// 地图选点页面：用户拖动地图选择精确位置
/// 返回 Map<String, double> 包含 lat 和 lng
class LocationPickerPage extends StatefulWidget {
  final double? initialLat;
  final double? initialLng;

  const LocationPickerPage({
    super.key,
    this.initialLat,
    this.initialLng,
  });

  @override
  State<LocationPickerPage> createState() => _LocationPickerPageState();
}

class _LocationPickerPageState extends State<LocationPickerPage> {
  late final MapController _mapController;
  late LatLng _selectedPoint;
  bool _hasSelection = false;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    final hasInitial = (widget.initialLat != null && widget.initialLat != 0) ||
        (widget.initialLng != null && widget.initialLng != 0);
    if (hasInitial) {
      _selectedPoint =
          LatLng(widget.initialLat ?? 0, widget.initialLng ?? 0);
      _hasSelection = true;
    } else {
      _selectedPoint = const LatLng(30, 110);
    }
  }

  void _onMapEvent(MapEvent event) {
    if (event is MapEventMoveEnd) {
      setState(() {
        _selectedPoint = event.camera.center;
        _hasSelection = true;
      });
    }
  }

  void _confirm() {
    Navigator.of(context).pop({
      'lat': _selectedPoint.latitude,
      'lng': _selectedPoint.longitude,
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final hasInitial = (widget.initialLat != null && widget.initialLat != 0) ||
        (widget.initialLng != null && widget.initialLng != 0);

    return Scaffold(
      body: Stack(
        children: [
          // 地图
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: hasInitial
                  ? LatLng(widget.initialLat!, widget.initialLng!)
                  : const LatLng(30, 110),
              initialZoom: hasInitial ? 15 : 4,
              onMapEvent: _onMapEvent,
              minZoom: 2,
              maxZoom: 18,
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.csinv.monitor',
              ),
              if (_hasSelection)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _selectedPoint,
                      width: 40,
                      height: 40,
                      child: const Icon(
                        Icons.location_on,
                        color: Colors.red,
                        size: 36,
                      ),
                    ),
                  ],
                ),
            ],
          ),

          // 顶部十字准星提示
          Center(
            child: IgnorePointer(
              child: Icon(
                Icons.add,
                size: 28.sp,
                color: Colors.red.withValues(alpha: 0.7),
              ),
            ),
          ),

          // 顶部返回按钮 + 坐标显示
          Positioned(
            top: MediaQuery.of(context).padding.top + 8.h,
            left: 12.w,
            right: 12.w,
            child: Row(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20.r),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                SizedBox(width: 8.w),
                Expanded(
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 12.w,
                      vertical: 8.h,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(20.r),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Text(
                      _hasSelection
                          ? '${_selectedPoint.latitude.toStringAsFixed(6)}, ${_selectedPoint.longitude.toStringAsFixed(6)}'
                          : l10n.stationSelectLocationHint,
                      style: TextStyle(
                        fontSize: 13.sp,
                        color: const Color(0xFF333333),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 底部确认按钮
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 20.h,
            left: 24.w,
            right: 24.w,
            child: SizedBox(
              height: 48.h,
              child: FilledButton.icon(
                onPressed: _hasSelection ? _confirm : null,
                icon: const Icon(Icons.check, size: 20),
                label: Text(
                  l10n.confirm,
                  style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24.r),
                  ),
                  elevation: 4,
                ),
              ),
            ),
          ),

          // 底部提示文字
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 76.h,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: 12.w,
                  vertical: 4.h,
                ),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Text(
                  l10n.stationDragToSelect,
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
