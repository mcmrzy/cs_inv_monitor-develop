import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/features/station/presentation/bloc/station_bloc.dart';
import 'package:inv_app/features/station/presentation/widgets/inline_location_picker.dart';
import 'package:inv_app/l10n/app_localizations.dart';

class EditStationPage extends StatefulWidget {
  final int stationId;

  const EditStationPage({super.key, required this.stationId});

  @override
  State<EditStationPage> createState() => _EditStationPageState();
}

class _EditStationPageState extends State<EditStationPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _provinceController = TextEditingController();
  final _cityController = TextEditingController();
  final _districtController = TextEditingController();
  final _addressController = TextEditingController();
  // 地图 key：供地址搜索时定位
  final _mapKey = GlobalKey<InlineLocationPickerState>();
  // 经纬度仅用于地图初始定位与提交，不展示输入框
  double? _latitude;
  double? _longitude;
  bool _loaded = false;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    context
        .read<StationBloc>()
        .add(StationDetailRequested(stationId: widget.stationId));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _provinceController.dispose();
    _cityController.dispose();
    _districtController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  void _loadData(dynamic station) {
    if (_loaded || station == null) return;
    _loaded = true;
    _nameController.text = station['name'] ?? '';
    _provinceController.text = station['province'] ?? '';
    _cityController.text = station['city'] ?? '';
    _districtController.text = station['district'] ?? '';
    _addressController.text = station['address'] ?? '';
    _latitude = (station['latitude'] as num?)?.toDouble();
    _longitude = (station['longitude'] as num?)?.toDouble();
  }

  // 搜索地址：拼接省市区+详细地址让地图定位（onLocationChanged 会自动同步经纬度）
  void _searchAddress() {
    final buf = StringBuffer();
    if (_provinceController.text.isNotEmpty) buf.write(_provinceController.text);
    if (_cityController.text.isNotEmpty) buf.write(' ${_cityController.text}');
    if (_districtController.text.isNotEmpty) buf.write(' ${_districtController.text}');
    if (_addressController.text.isNotEmpty) buf.write(' ${_addressController.text}');
    _mapKey.currentState?.searchAndFlyTo(
      buf.toString().trim(),
      displayAddress: _addressController.text,
    );
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      setState(() => _isSubmitting = true);
      final data = <String, dynamic>{
        'name': _nameController.text.trim(),
        'province': _provinceController.text.trim(),
        'city': _cityController.text.trim(),
        'district': _districtController.text.trim(),
        'address': _addressController.text.trim(),
      };
      // 地图选点后提交坐标；未选点时后端会按地址自动地理编码
      if ((_latitude ?? 0) != 0 || (_longitude ?? 0) != 0) {
        data['latitude'] = _latitude ?? 0;
        data['longitude'] = _longitude ?? 0;
      }
      context.read<StationBloc>().add(
            StationUpdateRequested(
              stationId: widget.stationId,
              data: data,
            ),
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context)!.editStation)),
      body: BlocConsumer<StationBloc, StationState>(
        listener: (context, state) {
          if (state is StationUpdateSuccess) {
            context
                .read<StationBloc>()
                .add(StationDetailRequested(stationId: widget.stationId));
            context.pop();
          } else if (state is StationError) {
            setState(() => _isSubmitting = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  AppLocalizations.of(context)!.translateError(state.message),
                ),
                backgroundColor: Colors.red,
              ),
            );
          }
        },
        builder: (context, state) {
          if (state is StationDetailLoaded) {
            _loadData(state.station);
          }

          return SingleChildScrollView(
            padding: EdgeInsets.all(16.w),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  _buildField(
                    _nameController,
                    AppLocalizations.of(context)!.stationName,
                  ),
                  SizedBox(height: 12.h),
                  _buildField(
                    _provinceController,
                    AppLocalizations.of(context)!.provinceLabel,
                  ),
                  SizedBox(height: 12.h),
                  _buildField(
                    _cityController,
                    AppLocalizations.of(context)!.cityLabel,
                  ),
                  SizedBox(height: 12.h),
                  _buildField(
                    _districtController,
                    AppLocalizations.of(context)!.districtLabel,
                  ),
                  SizedBox(height: 12.h),
                  // 详细地址 + 搜索按钮
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _buildField(
                          _addressController,
                          AppLocalizations.of(context)!.detailAddress,
                        ),
                      ),
                      SizedBox(width: 8.w),
                      Padding(
                        padding: EdgeInsets.only(top: 8.h),
                        child: IconButton(
                          onPressed: _searchAddress,
                          icon: const Icon(Icons.search, size: 20),
                          style: IconButton.styleFrom(
                            foregroundColor: const Color(0xFF2563EB),
                            backgroundColor: const Color(0xFFF0F9FF),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8.r),
                            ),
                          ),
                          tooltip: '搜索地址',
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 12.h),
                  // 内联地图选点（经纬度不展示输入框，仅用于初始定位与提交）
                  InlineLocationPicker(
                    key: _mapKey,
                    initialLat: _latitude,
                    initialLng: _longitude,
                    onLocationChanged: (result) {
                      final lat = (result['lat'] as num?)?.toDouble();
                      final lng = (result['lng'] as num?)?.toDouble();
                      if (lat != null && lng != null) {
                        _latitude = lat;
                        _longitude = lng;
                      }
                      final addr = result['address'] as String?;
                      if (addr != null && addr.isNotEmpty) {
                        _addressController.text = addr;
                      }
                    },
                  ),
                  SizedBox(height: 24.h),
                  // 保存按钮：渐变 + 圆角 + 阴影
                  SizedBox(
                    width: double.infinity,
                    height: 52.h,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [
                            AppColors.primaryLight,
                            AppColors.primary,
                            AppColors.primaryDark,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16.r),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.35),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16.r),
                          onTap: _isSubmitting ? null : _submit,
                          child: Center(
                            child: _isSubmitting
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.save_rounded,
                                        size: 18,
                                        color: Colors.white,
                                      ),
                                      SizedBox(width: 8.w),
                                      Text(
                                        AppLocalizations.of(context)!
                                            .saveChanges,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white,
                                          letterSpacing: 1,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildField(
    TextEditingController controller,
    String label, {
    TextInputType inputType = TextInputType.text,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: inputType,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.r)),
      ),
    );
  }
}
