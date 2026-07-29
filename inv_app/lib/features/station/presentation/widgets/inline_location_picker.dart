import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:inv_app/core/config/app_config.dart';

/// WGS-84 → GCJ-02 coordinate conversion
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
    ret += (150.0 * sin(x / 12.0 * pi) + 300.0 * sin(x / 3.0 * pi)) * 2.0 / 3.0;
    return ret;
  }
}

/// 内联地图选点组件（嵌入式，非全屏）
/// 拖动地图选择位置，下方显示附近地址列表
class InlineLocationPicker extends StatefulWidget {
  final double? initialLat;
  final double? initialLng;
  final ValueChanged<Map<String, dynamic>>? onLocationChanged;

  const InlineLocationPicker({
    super.key,
    this.initialLat,
    this.initialLng,
    this.onLocationChanged,
  });

  @override
  State<InlineLocationPicker> createState() => InlineLocationPickerState();
}

class InlineLocationPickerState extends State<InlineLocationPicker> {
  late final MapController _mapController;
  late LatLng _selectedPoint;
  bool _useAmap = true;
  bool _initialized = false;
  String _resolvedAddress = '';
  List<Map<String, dynamic>> _nearbyList = [];
  bool _loadingNearby = false;
  Timer? _reverseTimer;

  static String? _cachedRegion;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _selectedPoint = const LatLng(30, 110);
    _detectRegion();
  }

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
      // 初始位置也做一次反向地理编码
      _reverseGeocode(_selectedPoint.latitude, _selectedPoint.longitude);
    }
  }

  LatLng _toWgs84(LatLng gcjCenter) {
    if (!_useAmap) return gcjCenter;
    final gcj = _Gcj02.fromWgs84(gcjCenter.latitude, gcjCenter.longitude);
    final dLat = gcj.latitude - gcjCenter.latitude;
    final dLng = gcj.longitude - gcjCenter.longitude;
    return LatLng(gcjCenter.latitude - dLat, gcjCenter.longitude - dLng);
  }

  LatLng get _displayCenter {
    if (!_useAmap) return _selectedPoint;
    return _Gcj02.fromWgs84(_selectedPoint.latitude, _selectedPoint.longitude);
  }

  void _onMapEvent(MapEvent event) {
    if (event is MapEventMoveEnd) {
      final wgs84 = _toWgs84(event.camera.center);
      setState(() => _selectedPoint = wgs84);
      _reverseTimer?.cancel();
      _reverseTimer = Timer(const Duration(milliseconds: 600), () {
        _reverseGeocode(wgs84.latitude, wgs84.longitude);
      });
    }
  }

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
          final nearby = d['nearby'];
          if (nearby is List) {
            setState(() {
              _nearbyList =
                  nearby.whereType<Map<String, dynamic>>().take(5).toList();
            });
          } else {
            setState(() => _nearbyList = []);
          }
          // 通知父组件
          widget.onLocationChanged?.call({
            'lat': lat,
            'lng': lng,
            'address': addr,
          });
        }
      }
    } catch (_) {
      if (mounted) setState(() => _nearbyList = []);
    }
    if (mounted) setState(() => _loadingNearby = false);
  }

  void _selectNearby(Map<String, dynamic> item) {
    final lat = (item['lat'] as num?)?.toDouble();
    final lng = (item['lng'] as num?)?.toDouble();
    final detail = item['detail'] as String? ?? '';
    final name = item['name'] as String? ?? '';
    if (lat != null && lng != null) {
      final point = LatLng(lat, lng);
      setState(() {
        _selectedPoint = point;
        _resolvedAddress = detail.isNotEmpty ? detail : name;
        _nearbyList = [];
      });
      final display = _useAmap ? _Gcj02.fromWgs84(lat, lng) : point;
      _mapController.move(display, 16);
      widget.onLocationChanged?.call({
        'lat': lat,
        'lng': lng,
        'address': _resolvedAddress,
      });
    }
  }

  /// 外部调用：根据地址搜索并飞到对应位置
  Future<void> searchAndFlyTo(String address) async {
    if (address.trim().isEmpty) return;
    try {
      final resp = await http.get(
        Uri.parse('${AppConfig.apiBaseUrl}/geocode?address=${Uri.encodeQueryComponent(address.trim())}'),
      ).timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200 && mounted) {
        final data = jsonDecode(resp.body);
        final d = data['data'];
        if (d != null) {
          final lat = double.tryParse('${d['lat']}');
          final lng = double.tryParse('${d['lng']}');
          if (lat != null && lng != null) {
            final point = LatLng(lat, lng);
            setState(() {
              _selectedPoint = point;
              _resolvedAddress = address.trim();
              _nearbyList = [];
            });
            final display = _useAmap ? _Gcj02.fromWgs84(lat, lng) : point;
            _mapController.move(display, 15);
            widget.onLocationChanged?.call({
              'lat': lat,
              'lng': lng,
              'address': address.trim(),
            });
            // 搜索到达后也做一次反向地理编码获取附近地址
            _reverseGeocode(lat, lng);
          }
        }
      }
    } catch (_) { /* ignore */ }
  }

  @override
  void dispose() {
    _reverseTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 地图区域
        ClipRRect(
          borderRadius: BorderRadius.circular(12.r),
          child: SizedBox(
            height: 180.h,
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _displayCenter,
                    initialZoom:
                        (widget.initialLat != null && widget.initialLat != 0)
                            ? 15
                            : 4,
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
                  ],
                ),
                // 中心准星
                Center(
                  child: IgnorePointer(
                    child: Icon(
                      Icons.location_on,
                      size: 32.sp,
                      color: const Color(0xFFE53935),
                    ),
                  ),
                ),
                // 当前地址标签
                if (_resolvedAddress.isNotEmpty)
                  Positioned(
                    bottom: 8.h,
                    left: 8.w,
                    right: 8.w,
                    child: Container(
                      padding: EdgeInsets.symmetric(
                          horizontal: 10.w, vertical: 5.h),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(8.r),
                      ),
                      child: Text(
                        _resolvedAddress,
                        style: TextStyle(
                            fontSize: 12.sp, color: const Color(0xFF333333)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),

        // 附近地址列表
        if (_loadingNearby)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 8.h),
            child: Row(
              children: [
                SizedBox(
                  width: 14.w,
                  height: 14.w,
                  child: const CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 8.w),
                Text('搜索附近地址...',
                    style: TextStyle(fontSize: 12.sp, color: Colors.grey)),
              ],
            ),
          ),
        if (!_loadingNearby && _nearbyList.isNotEmpty)
          Container(
            margin: EdgeInsets.only(top: 8.h),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFB),
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Column(
              children: [
                Padding(
                  padding:
                      EdgeInsets.fromLTRB(12.w, 8.h, 12.w, 4.h),
                  child: Row(
                    children: [
                      Icon(Icons.near_me,
                          size: 14.sp, color: const Color(0xFF2563EB)),
                      SizedBox(width: 6.w),
                      Text('附近地址',
                          style: TextStyle(
                              fontSize: 12.sp,
                              color: const Color(0xFF666666),
                              fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  itemCount: _nearbyList.length,
                  separatorBuilder: (_, __) => Divider(
                      height: 1, indent: 38.w, color: const Color(0xFFEEEEEE)),
                  itemBuilder: (context, idx) {
                    final item = _nearbyList[idx];
                    final name = item['name'] as String? ?? '';
                    final detail = item['detail'] as String? ?? '';
                    return InkWell(
                      onTap: () => _selectNearby(item),
                      borderRadius: BorderRadius.circular(8.r),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal: 12.w, vertical: 8.h),
                        child: Row(
                          children: [
                            Icon(Icons.location_on_outlined,
                                size: 16.sp,
                                color: const Color(0xFF2563EB)),
                            SizedBox(width: 8.w),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(name,
                                      style: TextStyle(
                                          fontSize: 13.sp,
                                          fontWeight: FontWeight.w500)),
                                  if (detail.isNotEmpty && detail != name)
                                    Text(detail,
                                        style: TextStyle(
                                            fontSize: 11.sp,
                                            color: Colors.grey)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                SizedBox(height: 4.h),
              ],
            ),
          ),
      ],
    );
  }
}
