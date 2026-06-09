import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:inv_app/features/device/presentation/bloc/device_bloc.dart';

class DeviceSharePage extends StatefulWidget {
  final String deviceSN;

  const DeviceSharePage({super.key, required this.deviceSN});

  @override
  State<DeviceSharePage> createState() => _DeviceSharePageState();
}

class _DeviceSharePageState extends State<DeviceSharePage> {
  final _phoneController = TextEditingController();
  String _permission = 'view';

  @override
  void initState() {
    super.initState();
    context.read<DeviceBloc>().add(DeviceDetailRequested(sn: widget.deviceSN));
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_phoneController.text.trim().isNotEmpty) {
      context.read<DeviceBloc>().add(DeviceControlRequested(
        sn: widget.deviceSN,
        cmdType: 'share',
        params: {'phone': _phoneController.text.trim(), 'permission': _permission},
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设备分享')),
      body: BlocBuilder<DeviceBloc, DeviceState>(
        builder: (context, state) {
          return Padding(
            padding: EdgeInsets.all(16.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('将设备 ${widget.deviceSN} 分享给其他用户', style: TextStyle(fontSize: 14.sp, color: Colors.grey)),
                SizedBox(height: 16.h),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: '对方手机号',
                    hintText: '请输入对方手机号',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.r)),
                    prefixIcon: const Icon(Icons.phone),
                  ),
                ),
                SizedBox(height: 16.h),
                Text('分享权限', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w500)),
                SizedBox(height: 8.h),
                Row(
                  children: [
                    ChoiceChip(
                      label: const Text('仅查看'),
                      selected: _permission == 'view',
                      onSelected: (v) => setState(() => _permission = 'view'),
                    ),
                    SizedBox(width: 12.w),
                    ChoiceChip(
                      label: const Text('可控制'),
                      selected: _permission == 'control',
                      onSelected: (v) => setState(() => _permission = 'control'),
                    ),
                  ],
                ),
                SizedBox(height: 24.h),
                SizedBox(
                  width: double.infinity,
                  height: 48.h,
                  child: ElevatedButton(
                    onPressed: _submit,
                    child: const Text('确认分享'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
