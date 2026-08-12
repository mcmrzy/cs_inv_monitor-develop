import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:inv_app/core/data/china_regions.dart';
import 'package:inv_app/core/data/regions_data.dart';
import 'package:inv_app/core/data/country_name_mapping.dart';
import 'package:inv_app/core/data/province_name_mapping.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/network/api_client.dart';
import 'package:inv_app/features/station/presentation/widgets/region_picker_routes.dart';
import 'package:inv_app/features/station/presentation/bloc/station_bloc.dart';
import 'package:inv_app/features/station/presentation/widgets/inline_location_picker.dart';
import 'package:inv_app/features/station/data/station_image_upload_service.dart';
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
  final _mapKey = GlobalKey<InlineLocationPickerState>();

  String _country = '中国';
  String? _province;
  String? _city;
  String? _district;
  double? _latitude;
  double? _longitude;
  bool _submitting = false;
  File? _cardImage;
  String? _cardImageUrl;
  bool _uploadingImage = false;

  List<String> get _provinces {
    if (_country == '中国') {
      return chinaRegions.keys.toList();
    }
    // 将中文国家名映射到英文名，然后从 globalRegions 获取省份数据
    final englishName = getEnglishCountryName(_country);
    final provincesList = globalRegions[englishName] ?? [];
    // 将英文省份名翻译为中文
    return provincesList.map((p) => getLocalizedProvinceName(englishName, p)).toList();
  }

  String get _addressText {
    final buf = StringBuffer();
    if (_country != '中国') buf.write(_country);
    if (_province != null) buf.write(' $_province');
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

  Future<void> _pickAndUploadImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (picked == null) return;

    setState(() => _uploadingImage = true);
    try {
      final apiClient = getIt<ApiClient>();
      final uploadService = StationImageUploadService(apiClient);
      final url = await uploadService.uploadStationImage(File(picked.path));
      if (mounted) {
        setState(() {
          _cardImage = File(picked.path);
          _cardImageUrl = url;
          _uploadingImage = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _uploadingImage = false);
        _showErr(e.toString());
      }
    }
  }

  void _submit() {
    final l10n = AppLocalizations.of(context)!;
    if (_province == null) {
      _showErr(l10n.pleaseSelectProvince);
      return;
    }
    if (_country == '中国') {
      if (_city == null) {
        _showErr(l10n.pleaseSelectCity);
        return;
      }
      if (_district == null) {
        _showErr(l10n.pleaseSelectDistrict);
        return;
      }
    }
    if (!_formKey.currentState!.validate()) return;

    setState(() => _submitting = true);
    final data = {
      'name': _nameCtl.text.trim(),
      'country': _country,
      'province': _province,
      'city': _city ?? '',
      'district': _district ?? '',
      'address': _addressText,
      'latitude': _latitude ?? 0,
      'longitude': _longitude ?? 0,
    };
    if (_cardImageUrl != null) {
      data['card_image_url'] = _cardImageUrl!;
    }
    context.read<StationBloc>().add(
          StationCreateRequested(data: data),
        );
  }

  void _showErr(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10.r),
        ),
      ),
    );
  }

  Future<void> _openRegionPicker() async {
    // 第一步：选择洲+国家
    final countryResult = await Navigator.push<Map<String, String>>(
      context,
      ContinentCountryPickerRoute(),
    );
    if (countryResult == null || !mounted) return;

    final selectedCountry = countryResult['country'] ?? '中国';
    setState(() {
      _country = selectedCountry;
      _province = null;
      _city = null;
      _district = null;
    });

    // 第二步：选择省/市/区
    final regionResult = await Navigator.push<Map<String, String>>(
      context,
      RegionPickerRoute(
        provinces: _provinces,
        citiesFn: (p) {
          if (_country != '中国') return [];
          final m = chinaRegions[p];
          if (m == null) return [];
          return m.keys.toList();
        },
        districtsFn: (p, c) {
          if (_country != '中国') return [];
          return chinaRegions[p]?[c] ?? [];
        },
      ),
    );
    if (regionResult != null) {
      setState(() {
        _province = regionResult['province'];
        _city = regionResult['city']?.isNotEmpty == true ? regionResult['city'] : null;
        _district = regionResult['district']?.isNotEmpty == true ? regionResult['district'] : null;
      });
      // 选择省市区后自动地理编码获取坐标
      _autoGeocode();
    }
  }

  Future<void> _autoGeocode() async {
    final addr = _addressText;
    if (addr.isEmpty) return;
    try {
      final dio = getIt<Dio>();
      final res = await dio.get(
        '/geocode',
        queryParameters: {
          'address': addr,
          'country': _country,
        },
      );
      final data = res.data['data'];
      if (data != null && data['lat'] != null && data['lng'] != null) {
        final lat = (data['lat'] as num).toDouble();
        final lng = (data['lng'] as num).toDouble();
        setState(() {
          _latitude = lat;
          _longitude = lng;
        });
        // 地图飞到对应位置（等待 InlineLocationPicker didUpdateWidget 生效）
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _mapKey.currentState?.searchAndFlyTo(addr);
        });
      }
    } catch (_) {
      // 地理编码失败不阻断流程
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColor.surface(context),
      appBar: AppBar(
        title: Text(
          AppLocalizations.of(context)!.newStation,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
        ),
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        backgroundColor: AppColor.surfaceContainer(context),
        foregroundColor: AppColor.textPrimary(context),
      ),
      body: BlocConsumer<StationBloc, StationState>(
        listener: (context, state) {
          if (state is StationCreateSuccess) {
            context.read<StationBloc>().add(StationSummaryRequested());
            context.pop();
          } else if (state is StationError) {
            setState(() => _submitting = false);
            _showErr(
              AppLocalizations.of(context)!.translateError(state.message),
            );
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
                        // 电站卡片图片
                        _buildImagePicker(),
                        SizedBox(height: 12.h),
                        _field(
                          _nameCtl,
                          AppLocalizations.of(context)!.stationName,
                          AppLocalizations.of(context)!.stationNameHint,
                          required: true,
                        ),
                        SizedBox(height: 12.h),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 14.w,
                            vertical: 12.h,
                          ),
                          decoration: BoxDecoration(
                            color: AppColor.primarySoft(context),
                            borderRadius: BorderRadius.circular(12.r),
                            border: Border.all(
                              color: AppColor.primary(context)
                                  .withValues(alpha: 0.2),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.info_outline_rounded,
                                size: 18.sp,
                                color: AppColor.primary(context),
                              ),
                              SizedBox(width: 10.w),
                              Expanded(
                                child: Text(
                                  AppLocalizations.of(context)!
                                      .capacityAutoCalculate,
                                  style: TextStyle(
                                    fontSize: 13.sp,
                                    color: AppColor.primary(context),
                                  ),
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
                    title: AppLocalizations.of(context)!.stationRegion,
                    subtitle:
                        AppLocalizations.of(context)!.selectInstallLocation,
                    child: Column(
                      children: [
                        // 地区选择按钮（洲+国家 -> 省/市/区）
                        GestureDetector(
                          onTap: _openRegionPicker,
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 14.w,
                              vertical: 14.h,
                            ),
                            decoration: BoxDecoration(
                              color: AppColor.surfaceHover(context),
                              borderRadius: BorderRadius.circular(12.r),
                              border: Border.all(color: AppColor.border(context)),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.location_on_outlined,
                                  size: 20.sp,
                                  color: AppColors.primary,
                                ),
                                SizedBox(width: 10.w),
                                Expanded(
                                  child: Text(
                                    _province != null
                                        ? _addressText
                                        : AppLocalizations.of(context)!
                                            .selectRegion,
                                    style: TextStyle(
                                      fontSize: 14.sp,
                                      color: _province != null
                                          ? AppColors.textPrimary
                                          : AppColors.textHint,
                                      fontWeight: _province != null
                                          ? FontWeight.w500
                                          : FontWeight.normal,
                                    ),
                                  ),
                                ),
                                Icon(
                                  Icons.chevron_right_rounded,
                                  size: 20.sp,
                                  color: AppColors.textHint,
                                ),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(height: 12.h),
                        // 详细地址 + 搜索按钮
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _field(
                                _detailCtl,
                                AppLocalizations.of(context)!.detailAddress,
                                AppLocalizations.of(context)!.detailAddressHint,
                              ),
                            ),
                            SizedBox(width: 8.w),
                            Padding(
                              padding: EdgeInsets.only(top: 28.h),
                              child: IconButton(
                                onPressed: () async {
                                  final ok = await _mapKey.currentState
                                          ?.searchAndFlyTo(
                                        _addressText,
                                        displayAddress: _detailCtl.text,
                                      ) ??
                                      false;
                                  if (!ok && context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          AppLocalizations.of(context)!
                                              .addressNotFound,
                                        ),
                                      ),
                                    );
                                  }
                                },
                                icon: Icon(Icons.search, size: 20.sp),
                                style: IconButton.styleFrom(
                                  foregroundColor: AppColors.primary,
                                  backgroundColor: AppColor.primarySoft(context),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10.r),
                                  ),
                                ),
                                tooltip: '搜索地址',
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 12.h),
                        // 内联地图选点
                        InlineLocationPicker(
                          key: _mapKey,
                          initialLat: _latitude,
                          initialLng: _longitude,
                          onLocationChanged: (result) {
                            setState(() {
                              _latitude = (result['lat'] as num?)?.toDouble();
                              _longitude = (result['lng'] as num?)?.toDouble();
                            });
                            final addr = result['address'] as String?;
                            if (addr != null && addr.isNotEmpty) {
                              _detailCtl.text = addr;
                            }
                          },
                        ),
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
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14.r),
                        ),
                        elevation: 0,
                      ),
                      child: _submitting
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              AppLocalizations.of(context)!.createStationBtn,
                              style: TextStyle(
                                fontSize: 16.sp,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),
                  SizedBox(height: 16.h),
                  TextButton(
                    onPressed: () => context.pop(),
                    child: Text(
                      AppLocalizations.of(context)!.cancel,
                      style: TextStyle(
                        fontSize: 14.sp,
                        color: AppColors.textHint,
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

  Widget _buildSection({
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(20.w),
      decoration: BoxDecoration(
        color: AppColor.surfaceContainer(context),
        borderRadius: BorderRadius.circular(16.r),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36.w,
                height: 36.w,
                decoration: BoxDecoration(
                  color: AppColor.primarySoft(context),
                  borderRadius: BorderRadius.circular(10.r),
                ),
                child: Icon(icon, size: 18.sp, color: AppColors.primary),
              ),
              SizedBox(width: 10.w),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15.sp,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  SizedBox(height: 1.h),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11.sp,
                      color: AppColors.textHint,
                    ),
                  ),
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

  Widget _buildImagePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              AppLocalizations.of(context)!.stationCardImage,
              style: TextStyle(
                fontSize: 13.sp,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
            SizedBox(width: 4.w),
            Text(
              '(可选)',
              style: TextStyle(
                fontSize: 11.sp,
                color: AppColors.textHint,
              ),
            ),
          ],
        ),
        SizedBox(height: 8.h),
        GestureDetector(
          onTap: _uploadingImage ? null : _pickAndUploadImage,
          child: Container(
            width: double.infinity,
            height: 160.h,
            decoration: BoxDecoration(
              color: AppColor.surfaceHover(context),
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(
                color: _cardImage != null
                    ? AppColors.primary.withValues(alpha: 0.3)
                    : AppColor.border(context),
              ),
            ),
            child: _uploadingImage
                ? Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: AppColors.primary,
                    ),
                  )
                : _cardImage != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(12.r),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.file(
                              _cardImage!,
                              fit: BoxFit.cover,
                            ),
                            Positioned(
                              top: 8,
                              right: 8,
                              child: GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _cardImage = null;
                                    _cardImageUrl = null;
                                  });
                                },
                                child: Container(
                                  padding: EdgeInsets.all(4.w),
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.close,
                                    size: 16.sp,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.add_photo_alternate_outlined,
                            size: 36.sp,
                            color: AppColors.textHint,
                          ),
                          SizedBox(height: 8.h),
                          Text(
                            '点击上传电站卡片图片',
                            style: TextStyle(
                              fontSize: 13.sp,
                              color: AppColors.textHint,
                            ),
                          ),
                          SizedBox(height: 4.h),
                          Text(
                            '支持 JPEG、PNG、GIF、WebP，最大 5MB',
                            style: TextStyle(
                              fontSize: 11.sp,
                              color: AppColors.textHint.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
          ),
        ),
      ],
    );
  }

  Widget _field(
    TextEditingController ctl,
    String label,
    String hint, {
    bool required = false,
    TextInputType keyboard = TextInputType.text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13.sp,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
            if (required)
              Text(
                ' *',
                style: TextStyle(fontSize: 13.sp, color: AppColors.errorLight),
              ),
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
            fillColor: AppColor.surfaceHover(context),
            contentPadding:
                EdgeInsets.symmetric(horizontal: 14.w, vertical: 13.h),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12.r),
              borderSide: BorderSide(color: AppColor.border(context)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12.r),
              borderSide: BorderSide(color: AppColor.border(context)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12.r),
              borderSide:
                  const BorderSide(color: AppColors.primary, width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12.r),
              borderSide: const BorderSide(color: AppColors.errorLight),
            ),
          ),
          validator: required
              ? (v) => (v == null || v.trim().isEmpty)
                  ? '${AppLocalizations.of(context)!.pleaseInput}$label'
                  : null
              : null,
        ),
      ],
    );
  }
}

