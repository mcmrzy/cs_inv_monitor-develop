import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:inv_app/core/data/continents_data.dart';
import 'package:inv_app/core/data/country_name_mapping.dart';
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

  /// 搜索国家/省市并自动滚动到对应位置
  void _searchAndNavigate(String query) {
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

    // 2. 搜索省份/城市（在 globalRegions 中搜索）
    for (final entry in globalRegions.entries) {
      final countryNameEn = entry.key;
      final provinces = entry.value;
      for (final province in provinces) {
        if (province.toLowerCase().contains(lowerQuery)) {
          // 找到匹配的省份，找到对应的国家在哪个洲
          final countryNameZh = _getChineseCountryName(countryNameEn);
          for (int i = 0; i < continents.length; i++) {
            final continent = continents[i];
            final countries = continent['countries'] as List? ?? [];
            for (int j = 0; j < countries.length; j++) {
              final country = Map<String, String>.from(countries[j] as Map);
              if (country['name'] == countryNameZh) {
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
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: AppColors.surfaceHover),
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
                            color: AppColors.textHint,
                          ),
                        ),
                      ),
                      Text(
                        AppLocalizations.of(context)!.selectRegion,
                        style: TextStyle(
                          fontSize: 16.sp,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
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
                      hintText: '搜索国家/地区...',
                      prefixIcon: Icon(Icons.search, size: 20.sp, color: AppColors.textHint),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.clear, size: 18.sp, color: AppColors.textHint),
                              onPressed: () {
                                _searchCtrl.clear();
                                _searchAndNavigate('');
                              },
                            )
                          : null,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10.r),
                        borderSide: const BorderSide(color: AppColors.surfaceHover),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10.r),
                        borderSide: const BorderSide(color: AppColors.surfaceHover),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10.r),
                        borderSide: const BorderSide(color: AppColors.primary),
                      ),
                      filled: true,
                      fillColor: AppColor.surfaceHover(context),
                    ),
                    onChanged: (value) {
                      _searchAndNavigate(value);
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
                      Container(width: 1, color: AppColors.surfaceHover),
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
              color: AppColors.textHint,
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
                      color: AppColors.textHint,
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
                                    ? AppColors.textPrimary
                                    : AppColors.textHint,
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

  @override
  void initState() {
    super.initState();
    if (widget.provinceOnly || widget.provinces.isEmpty) {
      // 仅省份模式（或数据缺失）：不计算市/区列表
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
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: AppColors.surfaceHover),
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
                            color: AppColors.textHint,
                          ),
                        ),
                      ),
                      Text(
                        AppLocalizations.of(context)!.selectRegion,
                        style: TextStyle(
                          fontSize: 16.sp,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
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
                      Container(width: 1, color: AppColors.surfaceHover),
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
                      Container(width: 1, color: AppColors.surfaceHover),
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
              color: AppColors.textHint,
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
                      color: AppColors.textHint,
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
                                    ? AppColors.textPrimary
                                    : AppColors.textHint,
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
