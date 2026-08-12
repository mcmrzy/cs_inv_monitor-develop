import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:inv_app/core/data/china_regions.dart';
import 'package:inv_app/core/data/country_name_mapping.dart';
import 'package:inv_app/core/data/province_name_mapping.dart';
import 'package:inv_app/core/data/regions_data.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/network/api_client.dart';
import 'package:inv_app/features/station/data/station_image_upload_service.dart';
import 'package:inv_app/features/station/presentation/bloc/station_bloc.dart';
import 'package:inv_app/features/station/presentation/widgets/inline_location_picker.dart';
import 'package:inv_app/features/station/presentation/widgets/region_picker_routes.dart';
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
  final _addressController = TextEditingController();
  // 地图 key：供地址搜索时定位
  final _mapKey = GlobalKey<InlineLocationPickerState>();
  // 地区选择（与创建电站页一致：国家 + 省/市/区）
  String _country = '中国';
  String? _province;
  String? _city;
  String? _district;
  // 用户是否改过地区（改过则提交时重新拼接完整地址）
  bool _regionEdited = false;
  // 经纬度仅用于地图初始定位与提交，不展示输入框
  double? _latitude;
  double? _longitude;
  bool _loaded = false;
  bool _isSubmitting = false;
  File? _cardImage;
  String? _cardImageUrl;
  bool _uploadingImage = false;

  /// 当前国家的省份列表（中国用内置数据，其他国家用全球数据并翻译）
  List<String> get _provinces {
    if (_country == '中国') {
      return chinaRegions.keys.toList();
    }
    final englishName = getEnglishCountryName(_country);
    final provincesList = globalRegions[englishName] ?? [];
    return provincesList
        .map((p) => getLocalizedProvinceName(englishName, p))
        .toList();
  }

  /// 已选地区文本（国家 + 省/市/区），不含详细地址
  String get _regionText {
    final buf = StringBuffer();
    if (_country != '中国') buf.write(_country);
    if (_province != null) buf.write(' $_province');
    if (_city != null) buf.write(' $_city');
    if (_district != null) buf.write(' $_district');
    return buf.toString().trim();
  }

  /// 完整地址（地区 + 详细地址）
  String get _addressText {
    final region = _regionText;
    final detail = _addressController.text.trim();
    return detail.isEmpty ? region : '$region $detail';
  }

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
    _addressController.dispose();
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  void _loadData(dynamic station) {
    if (_loaded || station == null) return;
    _loaded = true;
    _nameController.text = station['name'] ?? '';
    _country = (station['country'] as String?)?.isNotEmpty == true
        ? station['country'] as String
        : '中国';
    _province = (station['province'] as String?)?.isNotEmpty == true
        ? station['province'] as String
        : null;
    _city = (station['city'] as String?)?.isNotEmpty == true
        ? station['city'] as String
        : null;
    _district = (station['district'] as String?)?.isNotEmpty == true
        ? station['district'] as String
        : null;
    _addressController.text = station['address'] ?? '';
    _latitude = (station['latitude'] as num?)?.toDouble();
    _longitude = (station['longitude'] as num?)?.toDouble();
    // 加载卡片图片URL
    final cardImageUrl = station['card_image_url'] as String?;
    if (cardImageUrl != null && cardImageUrl.isNotEmpty) {
      _cardImageUrl = cardImageUrl;
    }
  }

  // 搜索地址：拼接地区+详细地址让地图定位（onLocationChanged 会自动同步经纬度）
  void _searchAddress() {
    final addr = _addressText;
    if (addr.isEmpty) return;
    _mapKey.currentState?.searchAndFlyTo(
      addr,
      displayAddress: _addressController.text,
    );
  }

  // 两步选择地区：先选洲+国家，再选省/市/区（与创建电站页一致）
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
    if (regionResult != null && mounted) {
      setState(() {
        _regionEdited = true;
        _province = regionResult['province'];
        _city = regionResult['city']?.isNotEmpty == true
            ? regionResult['city']
            : null;
        _district = regionResult['district']?.isNotEmpty == true
            ? regionResult['district']
            : null;
      });
      // 选择新地区后让地图定位到该地区
      _searchAddress();
    }
  }

  void _submit() {
    final l10n = AppLocalizations.of(context)!;
    if (!_formKey.currentState!.validate()) return;
    // 与创建电站页一致的地区校验
    if (_province == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.pleaseSelectProvince),
        ),
      );
      return;
    }
    if (_country == '中国' && _city == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.pleaseSelectCity),
        ),
      );
      return;
    }
    setState(() => _isSubmitting = true);
    final data = <String, dynamic>{
      'name': _nameController.text.trim(),
      'country': _country,
      'province': _province,
      'city': _city ?? '',
      'district': _district ?? '',
      // 改过地区则重新拼接完整地址；未改则保持原地址不变
      'address': _regionEdited ? _addressText : _addressController.text.trim(),
    };
    // 地图选点后提交坐标；未选点时后端会按地址自动地理编码
    if ((_latitude ?? 0) != 0 || (_longitude ?? 0) != 0) {
      data['latitude'] = _latitude ?? 0;
      data['longitude'] = _longitude ?? 0;
    }
    // 电站卡片图片
    if (_cardImageUrl != null) {
      data['card_image_url'] = _cardImageUrl;
    }
    context.read<StationBloc>().add(
          StationUpdateRequested(
            stationId: widget.stationId,
            data: data,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColor.surface(context),
      appBar: AppBar(title: Text(AppLocalizations.of(context)!.editStation)),
      body: BlocConsumer<StationBloc, StationState>(
        listener: (context, state) {
          if (state is StationUpdateSuccess) {
            context
                .read<StationBloc>()
                .add(StationDetailRequested(stationId: widget.stationId));
            context.pop();
          } else if (state is StationDeleteSuccess) {
            // 详情页同时监听该状态并 pop 回首页（SnackBar 由其展示）
            context.pop();
          } else if (state is StationError) {
            setState(() => _isSubmitting = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  AppLocalizations.of(context)!.translateError(state.message),
                ),
              ),
            );
          }
        },
        builder: (context, state) {
          if (state is StationDetailLoaded) {
            _loadData(state.station);
          }

          return SingleChildScrollView(
            padding: EdgeInsets.all(20.w),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 基本信息：电站名称
                  _buildSection(
                    icon: Icons.solar_power_rounded,
                    title: AppLocalizations.of(context)!.stationInfo,
                    subtitle: AppLocalizations.of(context)!.fillStationInfo,
                    child: Column(
                      children: [
                        // 电站卡片图片
                        _buildImagePicker(),
                        SizedBox(height: 12.h),
                        _buildField(
                          _nameController,
                          AppLocalizations.of(context)!.stationName,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 16.h),
                  // 位置信息：地区选择 + 详细地址 + 地图选点
                  _buildSection(
                    icon: Icons.location_on_outlined,
                    title: AppLocalizations.of(context)!.stationRegion,
                    subtitle: AppLocalizations.of(context)!.selectInstallLocation,
                    child: Column(
                      children: [
                        // 地区选择按钮（国家 + 省/市/区，与创建电站页一致）
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
                                        ? _regionText
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
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
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
                              child: _buildField(
                                _addressController,
                                AppLocalizations.of(context)!.detailAddress,
                              ),
                            ),
                            SizedBox(width: 8.w),
                            Padding(
                              padding: EdgeInsets.only(top: 28.h),
                              child: IconButton(
                                onPressed: _searchAddress,
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
                      ],
                    ),
                  ),
                  SizedBox(height: 32.h),
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
                  SizedBox(height: 8.h),
                  // 删除电站入口（自详情页三点菜单迁入）
                  Center(
                    child: TextButton.icon(
                      onPressed: _isSubmitting
                          ? null
                          : () => _confirmDelete(AppLocalizations.of(context)!),
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        size: 18,
                        color: AppColors.error,
                      ),
                      label: Text(
                        AppLocalizations.of(context)!.deleteStation,
                        style: TextStyle(
                          fontSize: 14.sp,
                          color: AppColors.error,
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

  // 删除电站确认弹窗，确认后由 BlocListener 处理后续跳栈
  Future<void> _confirmDelete(AppLocalizations l10n) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.delete),
        content: Text(l10n.str('confirm_delete_station', {})),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              l10n.delete,
              style: const TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    context
        .read<StationBloc>()
        .add(StationDeleteRequested(stationId: widget.stationId));
  }

  Widget _buildImagePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '电站卡片图片',
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
                color: (_cardImage != null || _cardImageUrl != null)
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
                    : _cardImageUrl != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(12.r),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.network(
                                  _cardImageUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Center(
                                    child: Icon(
                                      Icons.broken_image_outlined,
                                      size: 36.sp,
                                      color: AppColors.textHint,
                                    ),
                                  ),
                                ),
                                Positioned(
                                  top: 8,
                                  right: 8,
                                  child: GestureDetector(
                                    onTap: () {
                                      setState(() {
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

  /// 分区卡片：图标圆底 + 标题 + 副标题 + 内容（与创建电站页风格一致）
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

  Widget _buildField(
    TextEditingController controller,
    String label, {
    TextInputType inputType = TextInputType.text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13.sp,
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary,
          ),
        ),
        SizedBox(height: 8.h),
        TextFormField(
          controller: controller,
          keyboardType: inputType,
          cursorColor: AppColors.primary,
          style: TextStyle(fontSize: 14.sp, color: AppColors.textPrimary),
          decoration: InputDecoration(
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
          ),
        ),
      ],
    );
  }
}
