import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:inv_app/features/station/presentation/bloc/station_bloc.dart';

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
  final _capacityController = TextEditingController();
  final _panelCountController = TextEditingController();
  final _peakPriceController = TextEditingController();
  final _valleyPriceController = TextEditingController();
  final _latitudeController = TextEditingController();
  final _longitudeController = TextEditingController();
  bool _loaded = false;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    context.read<StationBloc>().add(StationDetailRequested(stationId: widget.stationId));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _provinceController.dispose();
    _cityController.dispose();
    _districtController.dispose();
    _addressController.dispose();
    _capacityController.dispose();
    _panelCountController.dispose();
    _peakPriceController.dispose();
    _valleyPriceController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
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
    _capacityController.text = '${station['capacity'] ?? ''}';
    _panelCountController.text = '${station['panel_count'] ?? ''}';
    _peakPriceController.text = '${station['peak_price'] ?? ''}';
    _valleyPriceController.text = '${station['valley_price'] ?? ''}';
    _latitudeController.text = '${station['latitude'] ?? ''}';
    _longitudeController.text = '${station['longitude'] ?? ''}';
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      setState(() => _isSubmitting = true);
      context.read<StationBloc>().add(StationUpdateRequested(
        stationId: widget.stationId,
        data: {
          'name': _nameController.text.trim(),
          'province': _provinceController.text.trim(),
          'city': _cityController.text.trim(),
          'district': _districtController.text.trim(),
          'address': _addressController.text.trim(),
          'capacity': double.tryParse(_capacityController.text) ?? 0,
          'panel_count': int.tryParse(_panelCountController.text) ?? 0,
          'peak_price': double.tryParse(_peakPriceController.text) ?? 0,
          'valley_price': double.tryParse(_valleyPriceController.text) ?? 0,
          'latitude': double.tryParse(_latitudeController.text) ?? 0,
          'longitude': double.tryParse(_longitudeController.text) ?? 0,
        },
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('编辑电站')),
      body: BlocConsumer<StationBloc, StationState>(
        listener: (context, state) {
          if (state is StationUpdateSuccess) {
            context.read<StationBloc>().add(StationDetailRequested(stationId: widget.stationId));
            context.pop();
          } else if (state is StationError) {
            setState(() => _isSubmitting = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.message), backgroundColor: Colors.red),
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
                  _buildField(_nameController, '电站名称'),
                  SizedBox(height: 12.h),
                  _buildField(_provinceController, '省份'),
                  SizedBox(height: 12.h),
                  _buildField(_cityController, '城市'),
                  SizedBox(height: 12.h),
                  _buildField(_districtController, '区/县'),
                  SizedBox(height: 12.h),
                  _buildField(_addressController, '详细地址'),
                  SizedBox(height: 12.h),
                  _buildField(_capacityController, '装机容量(kW)', inputType: TextInputType.number),
                  SizedBox(height: 12.h),
                  _buildField(_panelCountController, '组件数量', inputType: TextInputType.number),
                  SizedBox(height: 12.h),
                  _buildField(_peakPriceController, '峰时电价', inputType: TextInputType.number),
                  SizedBox(height: 12.h),
                  _buildField(_valleyPriceController, '谷时电价', inputType: TextInputType.number),
                  SizedBox(height: 12.h),
                  _buildField(_latitudeController, '纬度', inputType: TextInputType.number),
                  SizedBox(height: 12.h),
                  _buildField(_longitudeController, '经度', inputType: TextInputType.number),
                  SizedBox(height: 24.h),
                  SizedBox(
                    width: double.infinity,
                    height: 48.h,
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _submit,
                      child: _isSubmitting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('保存修改'),
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

  Widget _buildField(TextEditingController controller, String label, {TextInputType inputType = TextInputType.text}) {
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
