import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:inv_app/features/device/presentation/bloc/device_bloc.dart';

class DeviceParamsPage extends StatefulWidget {
  final String deviceSN;

  const DeviceParamsPage({super.key, required this.deviceSN});

  @override
  State<DeviceParamsPage> createState() => _DeviceParamsPageState();
}

class _DeviceParamsPageState extends State<DeviceParamsPage> {
  @override
  void initState() {
    super.initState();
    context.read<DeviceBloc>().add(DeviceParamsRequested(sn: widget.deviceSN));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('参数设置')),
      body: BlocBuilder<DeviceBloc, DeviceState>(
        builder: (context, state) {
          if (state is DeviceLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state is DeviceError) {
            return Center(child: Text(state.message));
          }

          if (state is DeviceParamsLoaded) {
            final params = state.params;
            if (params.isEmpty) {
              return const Center(child: Text('暂无参数'));
            }

            return RefreshIndicator(
              onRefresh: () async {
                context.read<DeviceBloc>().add(DeviceParamsRequested(sn: widget.deviceSN));
              },
              child: ListView.builder(
                padding: EdgeInsets.all(16.w),
                itemCount: params.length,
                itemBuilder: (context, index) {
                  final key = params.keys.elementAt(index);
                  final value = params[key];
                  return Card(
                    child: ListTile(
                      title: Text(key.toString()),
                      subtitle: Text(value?.toString() ?? '-'),
                    ),
                  );
                },
              ),
            );
          }

          return const Center(child: CircularProgressIndicator());
        },
      ),
    );
  }
}
