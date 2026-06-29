import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:inv_app/core/data/china_regions.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/features/station/presentation/bloc/station_bloc.dart';
import 'package:inv_app/l10n/app_localizations.dart';

class CreateStationPage extends StatefulWidget {
  const CreateStationPage({super.key});

  @override
  State<CreateStationPage> createState() => _CreateStationPageState();
}

class _CreateStationPageState extends State<CreateStationPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtl = TextEditingController();
  final _detailCtl = TextEditingController();

  String? _province;
  String? _city;
  String? _district;
  bool _submitting = false;

  List<String> get _provinces {
    final list = chinaRegions.keys.toList();
    list.sort();
    return list;
  }
  List<String> get _cities {
    if (_province == null) return [];
    final m = chinaRegions[_province];
    if (m == null) return [];
    final list = m.keys.toList();
    list.sort();
    return list;
  }
  List<String> get _districts {
    if (_province == null || _city == null) return [];
    return chinaRegions[_province]![_city]!;
  }

  String get _addressText {
    final buf = StringBuffer();
    if (_province != null) buf.write(_province!);
    if (_city != null) buf.write(' $_city');
    if (_district != null) buf.write(' $_district');
    final detail = _detailCtl.text.trim();
    if (detail.isNotEmpty) buf.write(' $detail');
    return buf.toString().trimLeft();
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    _detailCtl.dispose();
    super.dispose();
  }

  void _submit() {
    final l10n = AppLocalizations.of(context)!;
    if (_province == null) { _showErr(l10n.pleaseSelectProvince); return; }
    if (_city == null)     { _showErr(l10n.pleaseSelectCity); return; }
    if (_district == null) { _showErr(l10n.pleaseSelectDistrict); return; }
    if (!_formKey.currentState!.validate()) return;

    setState(() => _submitting = true);
    context.read<StationBloc>().add(StationCreateRequested(data: {
      'name': _nameCtl.text.trim(),
      'province': _province,
      'city': _city,
      'district': _district,
      'address': _addressText,
    }));
  }

  void _showErr(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.errorLight, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r))),
    );
  }

  Future<void> _openRegionPicker() async {
    final result = await Navigator.push<Map<String, String>>(
      context,
      _RegionPickerRoute(
        provinces: _provinces,
        citiesFn: (p) {
          final m = chinaRegions[p];
          if (m == null) return [];
          final list = m.keys.toList();
          list.sort();
          return list;
        },
        districtsFn: (p, c) => chinaRegions[p]?[c] ?? [],
      ),
    );
    if (result != null) {
      setState(() {
        _province = result['province'];
        _city = result['city'];
        _district = result['district'];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.newStation, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 18)),
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
      ),
      body: BlocConsumer<StationBloc, StationState>(
        listener: (context, state) {
          if (state is StationCreateSuccess) {
            context.read<StationBloc>().add(StationSummaryRequested());
            context.pop();
          } else if (state is StationError) {
            setState(() => _submitting = false);
            _showErr(AppLocalizations.of(context)!.translateError(state.message));
          }
        },
        builder: (context, state) {
          return SingleChildScrollView(
            padding: EdgeInsets.all(20.w),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  _buildSection(
                    icon: Icons.solar_power_rounded,
                    title: AppLocalizations.of(context)!.stationInfo,
                    subtitle: AppLocalizations.of(context)!.fillStationInfo,
                    child: Column(
                      children: [
                        _field(_nameCtl, AppLocalizations.of(context)!.stationName, AppLocalizations.of(context)!.stationNameHint, required: true),
                        SizedBox(height: 12.h),
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0F9FF),
                            borderRadius: BorderRadius.circular(12.r),
                            border: Border.all(color: const Color(0xFFBAE6FD)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline_rounded, size: 18.sp, color: const Color(0xFF0284C7)),
                              SizedBox(width: 10.w),
                              Expanded(
                                child: Text(
                                  AppLocalizations.of(context)!.capacityAutoCalculate,
                                  style: TextStyle(fontSize: 13.sp, color: const Color(0xFF0369A1)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 16.h),
                  _buildSection(
                    icon: Icons.location_on_outlined,
                    title: AppLocalizations.of(context)!.region,
                    subtitle: AppLocalizations.of(context)!.selectInstallLocation,
                    child: Column(
                      children: [
                        GestureDetector(
                          onTap: _openRegionPicker,
                          child: Container(
                            padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 14.h),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFB),
                              borderRadius: BorderRadius.circular(12.r),
                              border: Border.all(color: const Color(0xFFE5E7EB)),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.location_on_outlined, size: 20.sp, color: AppColors.primary),
                                SizedBox(width: 10.w),
                                Expanded(
                                  child: Text(
                                    _province != null ? _addressText : AppLocalizations.of(context)!.selectProvinceCityDistrict,
                                    style: TextStyle(
                                      fontSize: 14.sp,
                                      color: _province != null ? AppColors.textPrimary : AppColors.textHint,
                                      fontWeight: _province != null ? FontWeight.w500 : FontWeight.normal,
                                    ),
                                  ),
                                ),
                                Icon(Icons.chevron_right_rounded, size: 20.sp, color: AppColors.textHint),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(height: 12.h),
                        _field(_detailCtl, AppLocalizations.of(context)!.detailAddress, AppLocalizations.of(context)!.detailAddressHint),
                      ],
                    ),
                  ),
                  SizedBox(height: 32.h),
                  SizedBox(
                    width: double.infinity,
                    height: 50.h,
                    child: FilledButton(
                      onPressed: _submitting ? null : _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14.r)),
                        elevation: 0,
                      ),
                      child: _submitting
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                          : Text(AppLocalizations.of(context)!.createStationBtn, style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  SizedBox(height: 16.h),
                  TextButton(
                    onPressed: () => context.pop(),
                    child: Text(AppLocalizations.of(context)!.cancel, style: TextStyle(fontSize: 14.sp, color: AppColors.textHint)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSection({required IconData icon, required String title, required String subtitle, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(20.w),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16.r)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36.w, height: 36.w,
                decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(10.r)),
                child: Icon(icon, size: 18.sp, color: AppColors.primary),
              ),
              SizedBox(width: 10.w),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  SizedBox(height: 1.h),
                  Text(subtitle, style: TextStyle(fontSize: 11.sp, color: AppColors.textHint)),
                ],
              ),
            ],
          ),
          SizedBox(height: 20.h),
          child,
        ],
      ),
    );
  }

  Widget _field(TextEditingController ctl, String label, String hint, {bool required = false, TextInputType keyboard = TextInputType.text}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
            if (required) Text(' *', style: TextStyle(fontSize: 13.sp, color: AppColors.errorLight)),
          ],
        ),
        SizedBox(height: 8.h),
        TextFormField(
          controller: ctl,
          keyboardType: keyboard,
          cursorColor: AppColors.primary,
          style: TextStyle(fontSize: 14.sp, color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(fontSize: 14.sp, color: AppColors.textHint),
            filled: true,
            fillColor: const Color(0xFFF8FAFB),
            contentPadding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 13.h),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
            errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r), borderSide: const BorderSide(color: AppColors.errorLight)),
          ),
          validator: required ? (v) => (v == null || v.trim().isEmpty) ? '${AppLocalizations.of(context)!.pleaseInput}$label' : null : null,
        ),
      ],
    );
  }
}

class _RegionPickerRoute extends PageRouteBuilder<Map<String, String>> {
  final List<String> provinces;
  final List<String> Function(String province) citiesFn;
  final List<String> Function(String province, String city) districtsFn;

  _RegionPickerRoute({
    required this.provinces,
    required this.citiesFn,
    required this.districtsFn,
  }) : super(
          pageBuilder: (context, animation, secondaryAnimation) => _RegionPickerPage(
                provinces: provinces,
                citiesFn: citiesFn,
                districtsFn: districtsFn,
              ),
          opaque: false,
          barrierColor: Colors.black54,
          transitionDuration: const Duration(milliseconds: 250),
          reverseTransitionDuration: const Duration(milliseconds: 200),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return SlideTransition(
              position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
              child: child,
            );
          },
        );
}

class _RegionPickerPage extends StatefulWidget {
  final List<String> provinces;
  final List<String> Function(String province) citiesFn;
  final List<String> Function(String province, String city) districtsFn;

  const _RegionPickerPage({
    required this.provinces,
    required this.citiesFn,
    required this.districtsFn,
  });

  @override
  State<_RegionPickerPage> createState() => _RegionPickerPageState();
}

class _RegionPickerPageState extends State<_RegionPickerPage> {
  late FixedExtentScrollController _provCtrl;
  late FixedExtentScrollController _cityCtrl;
  late FixedExtentScrollController _distCtrl;

  int _provIdx = 0;
  int _cityIdx = 0;
  int _distIdx = 0;

  late List<String> _cities;
  late List<String> _districts;

  bool _scrolling = false;

  static const _itemH = 44.0;

  @override
  void initState() {
    super.initState();
    _cities = widget.citiesFn(widget.provinces[0]);
    _districts = _cities.isNotEmpty ? widget.districtsFn(widget.provinces[0], _cities[0]) : [];
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
      _districts = _cities.isNotEmpty ? widget.districtsFn(widget.provinces[idx], _cities[0]) : [];
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
      _districts = _cities.isNotEmpty ? widget.districtsFn(widget.provinces[_provIdx], _cities[idx]) : [];
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
    final prov = widget.provinces[_provIdx];
    String? city;
    String? dist;
    if (_cities.isNotEmpty && _cityIdx < _cities.length) city = _cities[_cityIdx];
    if (_districts.isNotEmpty && _distIdx < _districts.length) dist = _districts[_distIdx];
    if (city == null) return;
    Navigator.of(context).pop({'province': prov, 'city': city!, 'district': dist ?? ''});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          const Spacer(),
          Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
                  decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.surfaceHover))),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(AppLocalizations.of(context)!.cancel, style: TextStyle(fontSize: 15.sp, color: AppColors.textHint)),
                      ),
                      Text(AppLocalizations.of(context)!.selectRegion, style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                      TextButton(
                        onPressed: _confirm,
                        child: Text(AppLocalizations.of(context)!.confirm, style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600, color: AppColors.primary)),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: _itemH * 7,
                  child: Row(
                    children: [
                      Expanded(flex: 3, child: _buildColumn(widget.provinces, _provCtrl, _provIdx, _onProvChanged, colLabel: AppLocalizations.of(context)!.localProvince)),
                      Container(width: 1, color: AppColors.surfaceHover),
                      Expanded(flex: 3, child: _buildColumn(_cities, _cityCtrl, _cityIdx, _onCityChanged, colLabel: AppLocalizations.of(context)!.localCity)),
                      Container(width: 1, color: AppColors.surfaceHover),
                      Expanded(flex: 3, child: _buildColumn(_districts, _distCtrl, _distIdx, _onDistChanged, colLabel: AppLocalizations.of(context)!.localDistrict)),
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

  Widget _buildColumn(List<String> items, FixedExtentScrollController ctrl, int idx, ValueChanged<int> onChange, {String colLabel = ''}) {
    return Column(
      children: [
        Container(
          height: _itemH,
          color: const Color(0xFFF8FAFB),
          alignment: Alignment.center,
          child: Text(colLabel, style: TextStyle(fontSize: 12.sp, color: AppColors.textHint, fontWeight: FontWeight.w500)),
        ),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: Column(
                  children: [
                    const Spacer(),
                    Container(
                      height: _itemH,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.06),
                        border: Border.symmetric(horizontal: BorderSide(color: const Color(0xFFE5E7EB))),
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
                onSelectedItemChanged: onChange,
                childDelegate: ListWheelChildBuilderDelegate(
                  builder: (_, i) {
                    if (i < 0 || i >= items.length) return const SizedBox();
                    final selected = i == idx;
                    return Center(
                      child: Text(
                        items[i],
                        style: TextStyle(
                          fontSize: 15.sp,
                          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                          color: selected ? AppColors.textPrimary : AppColors.textHint,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  },
                  childCount: items.isEmpty ? 1 : items.length,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
