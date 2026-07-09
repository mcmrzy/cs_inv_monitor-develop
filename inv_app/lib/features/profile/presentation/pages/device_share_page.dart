import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:inv_app/features/device/presentation/bloc/device_bloc.dart';
import 'package:inv_app/l10n/app_localizations.dart';

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
      ),);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.deviceShare)),
      body: BlocBuilder<DeviceBloc, DeviceState>(
        builder: (context, state) {
          return Padding(
            padding: EdgeInsets.all(16.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.shareDeviceDesc(widget.deviceSN), style: TextStyle(fontSize: 14.sp, color: Colors.grey)),
                SizedBox(height: 16.h),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: l10n.otherPhone,
                    hintText: l10n.inputOtherPhone,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.r)),
                    prefixIcon: const Icon(Icons.phone),
                  ),
                ),
                SizedBox(height: 16.h),
                Text(l10n.sharePermission, style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w500)),
                SizedBox(height: 8.h),
                Row(
                  children: [
                    ChoiceChip(
                      label: Text(l10n.viewOnly),
                      selected: _permission == 'view',
                      onSelected: (v) => setState(() => _permission = 'view'),
                    ),
                    SizedBox(width: 12.w),
                    ChoiceChip(
                      label: Text(l10n.controllableLabel),
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
                    child: Text(l10n.confirmShare),
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
