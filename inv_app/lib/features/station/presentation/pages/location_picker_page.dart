import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:inv_app/core/config/app_config.dart';
import 'package:inv_app/l10n/app_localizations.dart';

/// WGS-84 → GCJ-02 coordinate conversion (for China map tiles)
class _Gcj02 {
  static const _a = 6378245.0;
  static const _ee = 0.00669342162296594323;

  static bool inChina(double lat, double lng) =>
      lng >= 72.004 && lng <= 137.8347 && lat >= 0.8293 && lat <= 55.8271;

  static LatLng fromWgs84(double lat, double lng) {
    if (!inChina(lat, lng)) return LatLng(lat, lng);
    double dLat = _transformLat(lng - 105.0, lat - 35.0);
    double dLng = _transformLng(lng - 105.0, lat - 35.0);
    final radLat = lat / 180.0 * pi;
    var magic = sin(radLat);
    magic = 1 - _ee * magic * magic;
    final sqrtMagic = sqrt(magic);
    dLat = (dLat * 180.0) / ((_a * (1 - _ee)) / (magic * sqrtMagic) * pi);
    dLng = (dLng * 180.0) / ((_a / sqrtMagic) * cos(radLat) * pi);
    return LatLng(lat + dLat, lng + dLng);
  }

  static double _transformLat(double x, double y) {
    var ret = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * sqrt(x.abs());
    ret += (20.0 * sin(6.0 * x * pi) + 20.0 * sin(2.0 * x * pi)) * 2.0 / 3.0;
    ret += (20.0 * sin(y * pi) + 40.0 * sin(y / 3.0 * pi)) * 2.0 / 3.0;
    ret += (160.0 * sin(y / 12.0 * pi) + 320.0 * sin(y * pi / 30.0)) * 2.0 / 3.0;
    return ret;
  }

  static double _transformLng(double x, double y) {
    var ret = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * sqrt(x.abs());
    ret += (20.0 * sin(6.0 * x * pi) + 20.0 * sin(2.0 * x * pi)) * 2.0 / 3.0;
    ret += (20.0 * sin(x * pi) + 40.0 * sin(x / 3.0 * pi)) * 2.0 / 3.0;
    ret += (150.0 * sin(x / 12.0 * pi) + 300.0 * sin(x / 30.0 * pi)) * 2.0 / 3.0;
    return ret;
  }
}

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
  late LatLng _selectedPoint; // WGS-84
  bool _hasSelection = false;
  bool _useAmap = true; // default to AMap (safe for China)
  bool _initialized = false;
  String _resolvedAddress = '';
  List<Map<String, dynamic>> _nearbyList = [];
  bool _loadingNearby = false;
  Timer? _reverseTimer;

  /// Cached region result across the entire app lifecycle
  static String? _cachedRegion;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _selectedPoint = const LatLng(30, 110);
    _detectRegion();
  }

  /// Call ipwho.is from client to detect user's actual network region
  Future<void> _detectRegion() async {
    if (_cachedRegion != null) {
      setState(() {
        _useAmap = _cachedRegion == 'CN';
        _initSelection();
      });
      return;
    }
    try {
      final resp = await http
          .get(Uri.parse('https://ipwho.is/?fields=country_code'))
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        _cachedRegion = data['country_code'] as String? ?? 'CN';
      } else {
        _cachedRegion = 'CN';
      }
    } catch (_) {
      _cachedRegion = 'CN';
    }
    if (mounted) {
      setState(() {
        _useAmap = _cachedRegion == 'CN';
        _initSelection();
      });
    }
  }

  void _initSelection() {
    if (_initialized) return;
    _initialized = true;
    final hasInitial =
        (widget.initialLat != null && widget.initialLat != 0) ||
            (widget.initialLng != null && widget.initialLng != 0);
    if (hasInitial) {
      _selectedPoint = LatLng(widget.initialLat ?? 0, widget.initialLng ?? 0);
      _hasSelection = true;
    }
  }

  /// Convert map camera center (GCJ-02) back to WGS-84
  LatLng _toWgs84(LatLng gcjCenter) {
    if (!_useAmap) return gcjCenter;
    final gcj = _Gcj02.fromWgs84(gcjCenter.latitude, gcjCenter.longitude);
    final dLat = gcj.latitude - gcjCenter.latitude;
    final dLng = gcj.longitude - gcjCenter.longitude;
    return LatLng(gcjCenter.latitude - dLat, gcjCenter.longitude - dLng);
  }

  /// Get display center (GCJ-02 for AMap, WGS-84 for OSM)
  LatLng get _displayCenter {
    if (!_useAmap) return _selectedPoint;
    return _Gcj02.fromWgs84(_selectedPoint.latitude, _selectedPoint.longitude);
  }

  void _onMapEvent(MapEvent event) {
    if (event is MapEventMoveEnd) {
      final wgs84 = _toWgs84(event.camera.center);
      setState(() {
        _selectedPoint = wgs84;
        _hasSelection = true;
      });
      // Debounced reverse geocoding
      _reverseTimer?.cancel();
      _reverseTimer = Timer(const Duration(milliseconds: 600), () {
        _reverseGeocode(wgs84.latitude, wgs84.longitude);
      });
    }
  }

  /// Reverse geocoding: coords → short address + nearby list
  Future<void> _reverseGeocode(double lat, double lng) async {
    setState(() => _loadingNearby = true);
    try {
      final resp = await http.get(
        Uri.parse('${AppConfig.apiBaseUrl}/geocode/reverse?lat=$lat&lng=$lng'),
      ).timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200 && mounted) {
        final data = jsonDecode(resp.body);
        final d = data['data'];
        if (d != null) {
          final addr = d['address'] as String? ?? '';
          if (addr.isNotEmpty) {
            setState(() => _resolvedAddress = addr);
          }
          // 附近地址列表
          final nearby = d['nearby'];
          if (nearby is List) {
            setState(() {
              _nearbyList = nearby
                  .whereType<Map<String, dynamic>>()
                  .take(6)
                  .toList();
            });
          } else {
            setState(() => _nearbyList = []);
          }
        }
      }
    } catch (_) {
      if (mounted) setState(() => _nearbyList = []);
    }
    if (mounted) setState(() => _loadingNearby = false);
  }

  /// 选择附近地址
  void _selectNearby(Map<String, dynamic> item) {
    final lat = (item['lat'] as num?)?.toDouble();
    final lng = (item['lng'] as num?)?.toDouble();
    final detail = item['detail'] as String? ?? '';
    final name = item['name'] as String? ?? '';
    if (lat != null && lng != null) {
      final point = LatLng(lat, lng);
      setState(() {
        _selectedPoint = point;
        _hasSelection = true;
        _resolvedAddress = detail.isNotEmpty ? detail : name;
        _nearbyList = [];
      });
      final display = _useAmap ? _Gcj02.fromWgs84(lat, lng) : point;
      _mapController.move(display, 16);
    }
  }

  void _confirm() {
    Navigator.of(context).pop(<String, dynamic>{
      'lat': _selectedPoint.latitude,
      'lng': _selectedPoint.longitude,
      'address': _resolvedAddress,
    });
  }

  @override
  void dispose() {
    _reverseTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      body: Stack(
        children: [
          // 地图
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _displayCenter,
              initialZoom: _hasSelection ? 15 : 4,
              onMapEvent: _onMapEvent,
              minZoom: 2,
              maxZoom: 18,
            ),
            children: [
              TileLayer(
                urlTemplate: _useAmap
                    ? 'https://webrd01.is.autonavi.com/appmaptile?lang=zh_cn&size=1&scale=1&style=8&x={x}&y={y}&z={z}'
                    : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.csinv.monitor',
              ),
              if (_hasSelection)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _displayCenter,
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

          // 顶部返回按钮
          Positioned(
            top: MediaQuery.of(context).padding.top + 8.h,
            left: 12.w,
            child: Container(
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
          ),

          // 地址显示（顶部居中）
          if (_resolvedAddress.isNotEmpty)
            Positioned(
              top: MediaQuery.of(context).padding.top + 60.h,
              left: 24.w,
              right: 24.w,
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: 14.w,
                  vertical: 8.h,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(16.r),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.location_on_outlined,
                        size: 16.sp, color: const Color(0xFFE53935)),
                    SizedBox(width: 6.w),
                    Flexible(
                      child: Text(
                        _resolvedAddress,
                        style: TextStyle(
                          fontSize: 13.sp,
                          color: const Color(0xFF333333),
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // 底部附近地址列表 + 确认按钮
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16.r)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 附近地址列表
                    if (_loadingNearby)
                      Padding(
                        padding: EdgeInsets.all(12.w),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 16.w,
                              height: 16.w,
                              child: const CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 8.w),
                            Text('搜索附近地址...',
                                style: TextStyle(fontSize: 13.sp, color: Colors.grey)),
                          ],
                        ),
                      ),
                    if (!_loadingNearby && _nearbyList.isNotEmpty)
                      ConstrainedBox(
                        constraints: BoxConstraints(maxHeight: 200.h),
                        child: ListView.separated(
                          shrinkWrap: true,
                          padding: EdgeInsets.symmetric(vertical: 4.h),
                          itemCount: _nearbyList.length,
                          separatorBuilder: (_, __) =>
                              Divider(height: 1, indent: 44.w, color: const Color(0xFFF0F0F0)),
                          itemBuilder: (context, idx) {
                            final item = _nearbyList[idx];
                            final name = item['name'] as String? ?? '';
                            final detail = item['detail'] as String? ?? '';
                            return ListTile(
                              dense: true,
                              leading: Icon(Icons.location_on_outlined,
                                  color: const Color(0xFF2563EB), size: 20.sp),
                              title: Text(name,
                                  style: TextStyle(
                                      fontSize: 14.sp, fontWeight: FontWeight.w500)),
                              subtitle: detail.isNotEmpty && detail != name
                                  ? Text(detail,
                                      style: TextStyle(
                                          fontSize: 12.sp, color: Colors.grey))
                                  : null,
                              onTap: () => _selectNearby(item),
                            );
                          },
                        ),
                      ),
                    // 确认按钮
                    Padding(
                      padding: EdgeInsets.fromLTRB(24.w, 8.h, 24.w, 12.h),
                      child: SizedBox(
                        width: double.infinity,
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
                            elevation: 2,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
