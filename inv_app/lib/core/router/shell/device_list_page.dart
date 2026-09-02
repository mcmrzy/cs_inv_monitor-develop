import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/theme/csergy_assets.dart';
import 'package:inv_app/core/widgets/device_action_sheet.dart';
import 'package:inv_app/core/widgets/device_list_view.dart';
import 'package:inv_app/core/widgets/skeleton_widgets.dart';
import 'package:inv_app/core/widgets/xiaoshuo_state_panel.dart';
import 'package:inv_app/features/device/domain/repositories/device_repository.dart';
import 'package:inv_app/features/device/presentation/bloc/device_bloc.dart';
import 'package:inv_app/features/device/presentation/pages/device_control_page.dart';
import 'package:inv_app/features/station/presentation/bloc/station_bloc.dart'
    as station_bloc;
import 'package:inv_app/l10n/app_localizations.dart';

/// 全局设备列表页（底部导航"设备"入口）。
/// 自 app_router.dart 拆分而来。
class DeviceListPage extends StatefulWidget {
  const DeviceListPage({super.key});

  @override
  State<DeviceListPage> createState() => _DeviceListPageState();
}

class _DeviceListPageState extends State<DeviceListPage> {
  // 全局设备拖动排序模式：由 AppBar 排序图标开启
  bool _sortMode = false;
  // 缓存最后一次列表数据：排序/更新产生其他状态时保持页面不闪 loading
  DeviceListLoaded? _cachedList;
  // 按 sn 缓存的设备详情（列表无 station_id 时按 sn 拉详情补全，供解绑/换绑使用）
  final Map<String, Map<String, dynamic>> _detailCache = {};

  // 获取设备所属电站 id：列表数据优先，缺失时按 sn 拉详情（含内存缓存）
  Future<int?> _stationIdForDevice(Map<String, dynamic> device) async {
    final sn = (device['sn'] ?? '').toString();
    final listed = device['station_id'];
    if (listed is int) return listed;
    if (listed is String) return int.tryParse(listed);
    final cached = _detailCache[sn];
    if (cached != null) {
      final id = cached['station_id'];
      return id is int ? id : (id is String ? int.tryParse(id) : null);
    }
    final detail = await getIt<DeviceRepository>().getDetail(sn);
    return detail.fold((_) => null, (data) {
      _detailCache[sn] = data;
      final id = data['station_id'];
      return id is int ? id : (id is String ? int.tryParse(id) : null);
    });
  }

  @override
  void initState() {
    super.initState();

    context.read<DeviceBloc>().add(const DeviceListRequested());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColor.surface(context),
      appBar: AppBar(
        title: Text(
          l10n.deviceManagement,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 17),
        ),
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        backgroundColor: AppColor.surfaceContainer(context),
        foregroundColor: AppColor.textPrimary(context),
        actions: [
          if (_sortMode)
            TextButton(
              onPressed: () => setState(() => _sortMode = false),
              child: Text(
                l10n.finishSorting,
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
      body:
          BlocListener<station_bloc.StationBloc, station_bloc.StationState>(
        listener: (context, state) {
          // 解绑/删除/绑定/换绑成功后刷新全局设备列表
          if (state is station_bloc.DeviceUnbindSuccess ||
              state is station_bloc.DeviceDeleteSuccess ||
              state is station_bloc.DeviceBindSuccess ||
              state is station_bloc.DeviceRebindSuccess) {
            context.read<DeviceBloc>().add(const DeviceListRequested());
          }
        },
        child: BlocConsumer<DeviceBloc, DeviceState>(
          listener: (context, state) {
            // 设备编辑页保存别名/备注后刷新列表
            if (state is DeviceUpdateSuccess) {
              context.read<DeviceBloc>().add(const DeviceListRequested());
            }
          },
          builder: (context, state) {
            if (state is DeviceListLoaded) _cachedList = state;
            final ds = _cachedList;

            if (state is DeviceError && ds == null) {
              // 小烁展示设备插画：加载失败/断网态（美术路由 C3/offline）
              return XiaoshuoStatePanel(
                asset: CsergyAssets.xiaoshuoDevice,
                title: l10n.translateError(state.message),
                message: l10n.loadFailed,
                size: 176,
                action: OutlinedButton(
                  onPressed: () => context
                      .read<DeviceBloc>()
                      .add(const DeviceListRequested()),
                  child: Text(l10n.retry),
                ),
              );
            }

            if (ds == null) {
              // 统一加载态：骨架屏替代裸 spinner
              return const PageSkeleton(cardCount: 4);
            }

            // 全局设备列表页：长按弹设备操作菜单（无电站上下文，仅编辑/排序）
            return DeviceListView(
              devices: ds.devices,
              whiteHeader: true,
              sortMode: _sortMode,
              onRefresh: () async {
                context
                    .read<DeviceBloc>()
                    .add(const DeviceListRequested());
                // 等待 Bloc 处理完请求：监听到第一个新状态即返回，
                // 让 RefreshIndicator 有足够时间完成动画
                await context
                    .read<DeviceBloc>()
                    .stream
                    .firstWhere(
                      (s) => s is DeviceListLoaded || s is DeviceError,
                    )
                    .timeout(
                      const Duration(seconds: 15),
                      onTimeout: () => context.read<DeviceBloc>().state,
                    );
              },
              onDeviceChanged: (order) {
                // 拖动即持久化全局设备顺序
                context
                    .read<DeviceBloc>()
                    .add(DeviceGlobalReorderRequested(deviceOrder: order));
              },
              onLongPressDevice: (sn) async {
                final device = ds.devices.firstWhere(
                  (d) => (d['sn'] ?? '').toString() == sn,
                  orElse: () => <String, dynamic>{'sn': sn},
                );
                // 列表无 station_id 时按 sn 拉详情补全（内存缓存），供解绑/换绑菜单使用
                final stationId = await _stationIdForDevice(device);
                if (!context.mounted) return;
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  builder: (ctx) => DeviceActionSheet(
                    device: device,
                    stationId: stationId,
                    onEnterSortMode: () {
                      if (mounted) setState(() => _sortMode = true);
                    },
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// 设备控制页路由包装器（保持路由表引用稳定）。
class DeviceControlPageWrapper extends StatelessWidget {
  final String deviceSN;

  const DeviceControlPageWrapper({super.key, required this.deviceSN});

  @override
  Widget build(BuildContext context) {
    return DeviceControlPage(deviceSN: deviceSN);
  }
}
