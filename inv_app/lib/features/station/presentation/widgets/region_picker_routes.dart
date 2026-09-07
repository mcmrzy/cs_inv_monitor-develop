import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:inv_app/core/data/china_regions.dart';
import 'package:inv_app/core/data/continents_data.dart';
import 'package:inv_app/core/data/country_name_mapping.dart';
import 'package:inv_app/core/data/province_name_mapping.dart';
import 'package:inv_app/core/data/regions_data.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/l10n/app_localizations.dart';

/// 地区选择器路由组件：创建电站页 / 编辑电站页共用
/// 两步流程：先选洲+国家（ContinentCountryPickerRoute），再选省/市/区（RegionPickerRoute）

/// 第一步：洲 + 国家选择器（底部弹出，双列滚轮 + 搜索）
class ContinentCountryPickerRoute
    extends PageRouteBuilder<Map<String, String>> {
  ContinentCountryPickerRoute()
      : super(
          pageBuilder: (context, animation, secondaryAnimation) =>
              const ContinentCountryPickerPage(),
          opaque: false,
          barrierColor: Colors.black54,
          transitionDuration: const Duration(milliseconds: 250),
          reverseTransitionDuration: const Duration(milliseconds: 200),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return SlideTransition(
              position:
                  Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
                      .animate(
                CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutCubic,
                ),
              ),
              child: child,
            );
          },
        );
}

class ContinentCountryPickerPage extends StatefulWidget {
  const ContinentCountryPickerPage({super.key});

  @override
  State<ContinentCountryPickerPage> createState() =>
      _ContinentCountryPickerPageState();
}

class _ContinentCountryPickerPageState
    extends State<ContinentCountryPickerPage> {
  late FixedExtentScrollController _continentCtrl;
  late FixedExtentScrollController _countryCtrl;
  late TextEditingController _searchCtrl;
  int _continentIdx = 0;
  int _countryIdx = 0;
  String _searchQuery = '';

  static const _itemH = 44.0;

  @override
  void initState() {
    super.initState();
    _continentCtrl = FixedExtentScrollController();
    _countryCtrl = FixedExtentScrollController();
    _searchCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _continentCtrl.dispose();
    _countryCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Map<String, String>> get _currentCountries {
    if (continents.isEmpty) return [];
    var countries = List<Map<String, String>>.from(
        continents[_continentIdx]['countries'] as List,
    );
    return countries;
  }

  /// 搜索国家/省市：国家命中则定位滚轮；省份命中则直达该国家省/市/区选择页（Q8）
  Future<void> _searchAndNavigate(String query) async {
    if (query.isEmpty) {
      setState(() {
        _searchQuery = '';
        _countryIdx = 0;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _countryCtrl.jumpToItem(0);
      });
      return;
    }

    setState(() {
      _searchQuery = query;
    });

    final lowerQuery = query.toLowerCase();

    // 1. 先搜索国家名
    for (int i = 0; i < continents.length; i++) {
      final continent = continents[i];
      final countries = continent['countries'] as List? ?? [];
      for (int j = 0; j < countries.length; j++) {
        final country = Map<String, String>.from(countries[j] as Map);
        final name = country['name'] ?? '';
        if (name.toLowerCase().contains(lowerQuery)) {
          setState(() {
            _continentIdx = i;
            _countryIdx = j;
          });
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _continentCtrl.jumpToItem(i);
            _countryCtrl.jumpToItem(j);
          });
          return;
        }
      }
    }

    // 2. 搜索省份/城市（在 globalRegions 中搜索）：命中省份直达该国家的省/市/区选择页
    for (final entry in globalRegions.entries) {
      final countryNameEn = entry.key;
      final provinces = entry.value;
      for (final province in provinces) {
        if (province.toLowerCase().contains(lowerQuery)) {
          final countryNameZh = _getChineseCountryName(countryNameEn);
          // 构造该国家的省份列表（与 edit_profile_page._provincesFor 同逻辑）
          final provList = countryNameZh == '中国'
              ? chinaRegions.keys.toList()
              : (globalRegions[countryNameEn] ?? [])
                  .map((p) => getLocalizedProvinceName(countryNameEn, p))
                  .toList();
          // 直达省/市/区选择页（复用两步流程的第二步组件）
          final result = await Navigator.push<Map<String, String>>(
            context,
            RegionPickerRoute(
              provinces: provList,
              citiesFn: (p) {
                if (countryNameZh != '中国') return [];
                final m = chinaRegions[p];
                if (m == null) return [];
                return m.keys.toList();
              },
              districtsFn: (p, c) {
                if (countryNameZh != '中国') return [];
                return chinaRegions[p]?[c] ?? [];
              },
            ),
          );
          if (result != null && mounted) {
            // 透传国家 + 省市区结果（与上层两步流程的消费结构一致）
            Navigator.of(context).pop({'country': countryNameZh, ...result});
          }
          return;
        }
      }
    }
  }

  /// 根据英文国家名获取中文名
  String _getChineseCountryName(String englishName) {
    for (final entry in countryNameZhToEn.entries) {
      if (entry.value == englishName) {
        return entry.key;
      }
    }
    return englishName;
  }

  void _onContinentChanged(int idx) {
    if (idx == _continentIdx) return;
    setState(() {
      _continentIdx = idx;
      _countryIdx = 0;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _countryCtrl.jumpToItem(0);
    });
  }

  void _onCountryChanged(int idx) {
    setState(() => _countryIdx = idx);
  }

  void _confirm() {
    final countries = _currentCountries;
    if (countries.isEmpty) return;
    final country = countries[_countryIdx];
    Navigator.of(context).pop({'country': country['name']!});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          const Spacer(),
          Container(
            decoration: BoxDecoration(
              color: AppColor.surfaceContainer(context),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                Container(
                  padding:
                      EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: AppColor.surfaceHover(context)),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(
                          AppLocalizations.of(context)!.cancel,
                          style: TextStyle(
                            fontSize: 15.sp,
                            color: AppColor.textHint(context),
                          ),
                        ),
                      ),
                      Text(
                        AppLocalizations.of(context)!.selectRegion,
                        style: TextStyle(
                          fontSize: 16.sp,
                          fontWeight: FontWeight.w600,
                          color: AppColor.textPrimary(context),
                        ),
                      ),
                      TextButton(
                        onPressed: _confirm,
                        child: Text(
                          AppLocalizations.of(context)!.confirm,
                          style: TextStyle(
                            fontSize: 15.sp,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // 搜索框
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: AppLocalizations.of(context)!.str('country_region_search_hint'),
                      prefixIcon: Icon(Icons.search, size: 20.sp, color: AppColor.textHint(context)),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.clear, size: 18.sp, color: AppColor.textHint(context)),
                              onPressed: () {
                                _searchCtrl.clear();
                                unawaited(_searchAndNavigate(''));
                              },
                            )
                          : null,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10.r),
                        borderSide: BorderSide(color: AppColor.surfaceHover(context)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10.r),
                        borderSide: BorderSide(color: AppColor.surfaceHover(context)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10.r),
                        borderSide: const BorderSide(color: AppColors.primary),
                      ),
                      filled: true,
                      fillColor: AppColor.surfaceHover(context),
                    ),
                    onChanged: (value) {
                      unawaited(_searchAndNavigate(value));
                    },
                  ),
                ),
                SizedBox(
                  height: _itemH * 7,
                  child: Row(
                    children: [
                      // 左列：洲列表
                      Expanded(
                        flex: 3,
                        child: _buildColumn(
                          continents.map((c) => c['name'] as String).toList(),
                          _continentCtrl,
                          _continentIdx,
                          _onContinentChanged,
                          colLabel: '洲',
                        ),
                      ),
                      Container(width: 1, color: AppColor.surfaceHover(context)),
                      // 右列：国家列表
                      Expanded(
                        flex: 4,
                        child: _buildColumn(
                          _currentCountries
                              .map((c) => c['name']!)
                              .toList(),
                          _countryCtrl,
                          _countryIdx,
                          _onCountryChanged,
                          colLabel: AppLocalizations.of(context)!.country,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildColumn(
    List<String> items,
    FixedExtentScrollController ctrl,
    int idx,
    ValueChanged<int> onChange, {
    String colLabel = '',
  }) {
    return Column(
      children: [
        Container(
          height: _itemH,
          color: AppColor.surfaceHover(context),
          alignment: Alignment.center,
          child: Text(
            colLabel,
            style: TextStyle(
              fontSize: 12.sp,
              color: AppColor.textHint(context),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? Center(
                  child: Text(
                    '—',
                    style: TextStyle(
                      fontSize: 14.sp,
                      color: AppColor.textHint(context),
                    ),
                  ),
                )
              : Stack(
                  children: [
                    Positioned.fill(
                      child: Column(
                        children: [
                          const Spacer(),
                          Container(
                            height: _itemH,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.06),
                              border: Border.symmetric(
                                horizontal:
                                    BorderSide(color: AppColor.border(context)),
                              ),
                            ),
                          ),
                          const Spacer(),
                        ],
                      ),
                    ),
                    ListWheelScrollView.useDelegate(
                      controller: ctrl,
                      itemExtent: _itemH,
                      diameterRatio: 1.2,
                      overAndUnderCenterOpacity: 0.4,
                      // 显式吸附物理：甩动后自动停在 item 正中
                      physics: const FixedExtentScrollPhysics(
                        parent: BouncingScrollPhysics(),
                      ),
                      onSelectedItemChanged: onChange,
                      childDelegate: ListWheelChildBuilderDelegate(
                        builder: (_, i) {
                          if (i < 0 || i >= items.length) {
                            return const SizedBox();
                          }
                          final selected = i == idx;
                          return Center(
                            child: Text(
                              items[i],
                              style: TextStyle(
                                fontSize: 15.sp,
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                                color: selected
                                    ? AppColor.textPrimary(context)
                                    : AppColor.textHint(context),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        },
                        childCount: items.length,
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// 第二步：省/市/区选择器（底部弹出，三列滚轮；provinceOnly 时仅显示省份列）
class RegionPickerRoute extends PageRouteBuilder<Map<String, String>> {
  final List<String> provinces;
  final List<String> Function(String province) citiesFn;
  final List<String> Function(String province, String city) districtsFn;

  /// 仅选省份模式（个人信息页地址到省即可）；默认 false 保持省/市/区三级（电站页）
  final bool provinceOnly;

  RegionPickerRoute({
    required this.provinces,
    required this.citiesFn,
    required this.districtsFn,
    this.provinceOnly = false,
  }) : super(
          pageBuilder: (context, animation, secondaryAnimation) =>
              RegionPickerPage(
            provinces: provinces,
            citiesFn: citiesFn,
            districtsFn: districtsFn,
            provinceOnly: provinceOnly,
          ),
          opaque: false,
          barrierColor: Colors.black54,
          transitionDuration: const Duration(milliseconds: 250),
          reverseTransitionDuration: const Duration(milliseconds: 200),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return SlideTransition(
              position:
                  Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
                      .animate(
                CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutCubic,
                ),
              ),
              child: child,
            );
          },
        );
}

class RegionPickerPage extends StatefulWidget {
  final List<String> provinces;
  final List<String> Function(String province) citiesFn;
  final List<String> Function(String province, String city) districtsFn;

  /// 仅选省份模式：只渲染省份列，选中省份后直接返回，市/区留空
  final bool provinceOnly;

  const RegionPickerPage({
    super.key,
    required this.provinces,
    required this.citiesFn,
    required this.districtsFn,
    this.provinceOnly = false,
  });

  @override
  State<RegionPickerPage> createState() => _RegionPickerPageState();
}

class _RegionPickerPageState extends State<RegionPickerPage> {
  late FixedExtentScrollController _provCtrl;
  late FixedExtentScrollController _cityCtrl;
  late FixedExtentScrollController _distCtrl;

  int _provIdx = 0;
  int _cityIdx = 0;
  int _distIdx = 0;

  late List<String> _cities;
  late List<String> _districts;

  static const _itemH = 44.0;

  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    if (widget.provinceOnly || widget.provinces.isEmpty) {
      _cities = [];
      _districts = [];
    } else {
      _cities = widget.citiesFn(widget.provinces[0]);
      _districts = _cities.isNotEmpty
          ? widget.districtsFn(widget.provinces[0], _cities[0])
          : [];
    }
    _provCtrl = FixedExtentScrollController();
    _cityCtrl = FixedExtentScrollController();
    _distCtrl = FixedExtentScrollController();
  }

  @override
  void dispose() {
    _provCtrl.dispose();
    _cityCtrl.dispose();
    _distCtrl.dispose();
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onProvChanged(int idx) {
    if (idx == _provIdx) return;
    setState(() {
      _provIdx = idx;
      _cities = widget.citiesFn(widget.provinces[idx]);
      _cityIdx = 0;
      _districts = _cities.isNotEmpty
          ? widget.districtsFn(widget.provinces[idx], _cities[0])
          : [];
      _distIdx = 0;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _cityCtrl.jumpToItem(0);
      _distCtrl.jumpToItem(0);
    });
  }

  void _onCityChanged(int idx) {
    if (idx == _cityIdx) return;
    setState(() {
      _cityIdx = idx;
      _districts = _cities.isNotEmpty
          ? widget.districtsFn(widget.provinces[_provIdx], _cities[idx])
          : [];
      _distIdx = 0;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _distCtrl.jumpToItem(0);
    });
  }

  void _onDistChanged(int idx) {
    setState(() => _distIdx = idx);
  }

  /// 搜索输入防抖 300ms
  void _onSearchChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() => _searchQuery = query);
      _searchAndNavigate(query);
    });
  }

  /// 搜索省/市/区并跳转匹配项
  void _searchAndNavigate(String query) {
    if (query.isEmpty) return;
    // 搜索省份
    final provIdx = widget.provinces.indexWhere((p) => p.contains(query));
    if (provIdx < 0) return;

    setState(() {
      _provIdx = provIdx;
      _cities = widget.citiesFn(widget.provinces[provIdx]);
      _cityIdx = 0;
      _districts = _cities.isNotEmpty
          ? widget.districtsFn(widget.provinces[provIdx], _cities[0])
          : [];
      _distIdx = 0;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_provCtrl.hasClients) _provCtrl.jumpToItem(provIdx);
      if (_cityCtrl.hasClients) _cityCtrl.jumpToItem(0);
      if (_distCtrl.hasClients) _distCtrl.jumpToItem(0);
    });

    if (widget.provinceOnly) return;

    // 搜索城市
    final cityIdx = _cities.indexWhere((c) => c.contains(query));
    if (cityIdx >= 0) {
      setState(() {
        _cityIdx = cityIdx;
        _districts = widget.districtsFn(widget.provinces[provIdx], _cities[cityIdx]);
        _distIdx = 0;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_cityCtrl.hasClients) _cityCtrl.jumpToItem(cityIdx);
        if (_distCtrl.hasClients) _distCtrl.jumpToItem(0);
      });
      return;
    }

    // 搜索区县
    for (final city in _cities) {
      final districts = widget.districtsFn(widget.provinces[provIdx], city);
      final distIdx = districts.indexWhere((d) => d.contains(query));
      if (distIdx >= 0) {
        final cityIdxForDist = _cities.indexOf(city);
        setState(() {
          _cityIdx = cityIdxForDist;
          _districts = districts;
          _distIdx = distIdx;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_cityCtrl.hasClients) _cityCtrl.jumpToItem(cityIdxForDist);
          if (_distCtrl.hasClients) _distCtrl.jumpToItem(distIdx);
        });
        return;
      }
    }
  }

  void _confirm() {
    if (widget.provinces.isEmpty) return;
    final prov = widget.provinces[_provIdx];
    // 仅省份模式：选中省份后直接返回，市/区留空
    if (widget.provinceOnly) {
      Navigator.of(context)
          .pop({'province': prov, 'city': '', 'district': ''});
      return;
    }
    String? city;
    String? dist;
    if (_cities.isNotEmpty && _cityIdx < _cities.length) {
      city = _cities[_cityIdx];
    }
    if (_districts.isNotEmpty && _distIdx < _districts.length) {
      dist = _districts[_distIdx];
    }
    Navigator.of(context)
        .pop({'province': prov, 'city': city ?? '', 'district': dist ?? ''});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          const Spacer(),
          Container(
            decoration: BoxDecoration(
              color: AppColor.surfaceContainer(context),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                Container(
                  padding:
                      EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: AppColor.surfaceHover(context)),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(
                          AppLocalizations.of(context)!.cancel,
                          style: TextStyle(
                            fontSize: 15.sp,
                            color: AppColor.textHint(context),
                          ),
                        ),
                      ),
                      Text(
                        AppLocalizations.of(context)!.selectRegion,
                        style: TextStyle(
                          fontSize: 16.sp,
                          fontWeight: FontWeight.w600,
                          color: AppColor.textPrimary(context),
                        ),
                      ),
                      TextButton(
                        onPressed: _confirm,
                        child: Text(
                          AppLocalizations.of(context)!.confirm,
                          style: TextStyle(
                            fontSize: 15.sp,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // 搜索框（对齐第一级搜索框风格）
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: _onSearchChanged,
                    cursorColor: AppColors.primary,
                    style: TextStyle(fontSize: 15.sp),
                    decoration: InputDecoration(
                      hintText: AppLocalizations.of(context)!.str('region_search_hint'),
                      hintStyle: TextStyle(fontSize: 14.sp, color: AppColor.textHint(context)),
                      prefixIcon: Icon(Icons.search, size: 20.sp, color: AppColor.textHint(context)),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.clear, size: 18.sp, color: AppColor.textHint(context)),
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
                      filled: true,
                      fillColor: AppColor.surfaceHover(context),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.r),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  height: _itemH * 7,
                  child: Row(
                    children: [
                      if (widget.provinceOnly) ...[
                        // 仅省份模式：单列铺满，不渲染市/区列
                        Expanded(
                          child: _buildColumn(
                            widget.provinces,
                            _provCtrl,
                            _provIdx,
                            _onProvChanged,
                            colLabel:
                                AppLocalizations.of(context)!.localProvince,
                          ),
                        ),
                      ] else ...[
                        // 省/市/区三列：省份列不可缺（provinceOnly 改造时曾误删，
                        // 导致无法切换省份、市/区恒为首省数据）
                        Expanded(
                          flex: 3,
                          child: _buildColumn(
                            widget.provinces,
                            _provCtrl,
                            _provIdx,
                            _onProvChanged,
                            colLabel:
                                AppLocalizations.of(context)!.localProvince,
                          ),
                        ),
                        Container(width: 1, color: AppColor.surfaceHover(context)),
                        Expanded(
                          flex: 3,
                          child: _buildColumn(
                            _cities,
                            _cityCtrl,
                            _cityIdx,
                            _onCityChanged,
                            colLabel: AppLocalizations.of(context)!.localCity,
                          ),
                        ),
                        Container(width: 1, color: AppColor.surfaceHover(context)),
                        Expanded(
                          flex: 3,
                          child: _buildColumn(
                            _districts,
                            _distCtrl,
                            _distIdx,
                            _onDistChanged,
                            colLabel: AppLocalizations.of(context)!.localDistrict,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildColumn(
    List<String> items,
    FixedExtentScrollController ctrl,
    int idx,
    ValueChanged<int> onChange, {
    String colLabel = '',
  }) {
    return Column(
      children: [
        Container(
          height: _itemH,
          color: AppColor.surfaceHover(context),
          alignment: Alignment.center,
          child: Text(
            colLabel,
            style: TextStyle(
              fontSize: 12.sp,
              color: AppColor.textHint(context),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? Center(
                  child: Text(
                    '—',
                    style: TextStyle(
                      fontSize: 14.sp,
                      color: AppColor.textHint(context),
                    ),
                  ),
                )
              : Stack(
                  children: [
                    Positioned.fill(
                      child: Column(
                        children: [
                          const Spacer(),
                          Container(
                            height: _itemH,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.06),
                              border: Border.symmetric(
                                horizontal:
                                    BorderSide(color: AppColor.border(context)),
                              ),
                            ),
                          ),
                          const Spacer(),
                        ],
                      ),
                    ),
                    ListWheelScrollView.useDelegate(
                      controller: ctrl,
                      itemExtent: _itemH,
                      diameterRatio: 1.2,
                      overAndUnderCenterOpacity: 0.4,
                      // 显式吸附物理：甩动后自动停在 item 正中
                      physics: const FixedExtentScrollPhysics(
                        parent: BouncingScrollPhysics(),
                      ),
                      onSelectedItemChanged: onChange,
                      childDelegate: ListWheelChildBuilderDelegate(
                        builder: (_, i) {
                          if (i < 0 || i >= items.length) {
                            return const SizedBox();
                          }
                          final selected = i == idx;
                          return Center(
                            child: Text(
                              items[i],
                              style: TextStyle(
                                fontSize: 15.sp,
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                                color: selected
                                    ? AppColor.textPrimary(context)
                                    : AppColor.textHint(context),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        },
                        childCount: items.length,
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}
