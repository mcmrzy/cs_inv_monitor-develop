part of 'station_detail_page.dart';

class _EnergyFlowPainter extends CustomPainter {
  final List<FlowEdge> flows;
  final double animValue;
  final Map<NodePosition, Offset> nodeCenters;
  final double nodeRadius;

  _EnergyFlowPainter({
    required this.flows,
    required this.animValue,
    required this.nodeCenters,
    required this.nodeRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = nodeCenters[NodePosition.center]!;
    for (final flow in flows) {
      final outer = flow.from == NodePosition.center ? flow.to : flow.from;
      final node = nodeCenters[outer]!;
      final path = Path();
      if (outer == NodePosition.left || outer == NodePosition.right) {
        final side = outer == NodePosition.left ? -1.0 : 1.0;
        final start = node + Offset(-side * nodeRadius, 0);
        final bend =
            min((start.dy - center.dy).abs(), (start.dx - center.dx).abs() / 2);
        final vertical = (center.dy - start.dy).sign;
        path.moveTo(start.dx, start.dy);
        path.lineTo(center.dx + side * bend, start.dy);
        path.quadraticBezierTo(
          center.dx,
          start.dy,
          center.dx,
          start.dy + vertical * bend,
        );
        path.lineTo(center.dx, center.dy);
      } else {
        final direction = (center - node) / (center - node).distance;
        final start = node + direction * nodeRadius;
        path.moveTo(start.dx, start.dy);
        path.lineTo(center.dx, center.dy);
      }
      final metric = path.computeMetrics().first;
      final inward = flow.to == NodePosition.center;
      final start =
          metric.getTangentForOffset(inward ? 0 : metric.length)!.position;
      final end =
          metric.getTangentForOffset(inward ? metric.length : 0)!.position;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 2.8;
      if (!flow.active) {
        paint.color =
            Color.lerp(flow.fromColor, flow.toColor, .5)!.withValues(alpha: .2);
        canvas.drawPath(path, paint);
        continue;
      }
      paint.shader =
          ui.Gradient.linear(start, end, [flow.fromColor, flow.toColor]);
      canvas.drawPath(path, paint);
      for (var i = 0; i < 6; i++) {
        final t = (i / 6 + animValue) % 1.0;
        final point = metric
            .getTangentForOffset(metric.length * (inward ? t : 1 - t))!
            .position;
        final color = Color.lerp(flow.fromColor, flow.toColor, t)!;
        final alpha = sin(t * pi) * .8;
        canvas.drawCircle(
          point,
          5.w,
          Paint()
            ..color = color.withValues(alpha: alpha * .3)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
        );
        canvas.drawCircle(
          point,
          2.3.w,
          Paint()..color = color.withValues(alpha: alpha),
        );
      }
      final tangent =
          metric.getTangentForOffset(metric.length * (inward ? .78 : .22))!;
      final direction = tangent.vector * (inward ? 1.0 : -1.0);
      final normal = Offset(-direction.dy, direction.dx);
      final tip = tangent.position;
      canvas.drawPath(
        Path()
          ..moveTo(tip.dx, tip.dy)
          ..lineTo(
            (tip - direction * 7 + normal * 3).dx,
            (tip - direction * 7 + normal * 3).dy,
          )
          ..lineTo(
            (tip - direction * 7 - normal * 3).dx,
            (tip - direction * 7 - normal * 3).dy,
          )
          ..close(),
        Paint()..color = flow.toColor.withValues(alpha: .85),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _EnergyFlowPainter old) =>
      animValue != old.animValue ||
      nodeRadius != old.nodeRadius ||
      NodePosition.values.any(
        (position) => nodeCenters[position] != old.nodeCenters[position],
      ) ||
      flows.length != old.flows.length ||
      Iterable<int>.generate(flows.length).any(
        (i) =>
            flows[i].from != old.flows[i].from ||
            flows[i].to != old.flows[i].to ||
            flows[i].active != old.flows[i].active ||
            flows[i].fromColor != old.flows[i].fromColor ||
            flows[i].toColor != old.flows[i].toColor,
      );
}

// 选择设备弹窗：主题自适应圆角面板 + 设备列表（选中态高亮、逐项入场动画）
class _DeviceSelectSheet extends StatefulWidget {
  final List<dynamic> devices;
  final String selectedSn;
  final ValueChanged<String> onSelected;

  const _DeviceSelectSheet({
    required this.devices,
    required this.selectedSn,
    required this.onSelected,
  });

  @override
  State<_DeviceSelectSheet> createState() => _DeviceSelectSheetState();
}

class _DeviceSelectSheetState extends State<_DeviceSelectSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctl;

  @override
  void initState() {
    super.initState();
    _ctl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    )..forward();
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  // 逐项入场动画（淡入 + 上移），间隔 0.12
  Widget _animatedItem(int i, Widget child) {
    final start = i * 0.12;
    final end = (start + 0.7).clamp(0.0, 1.0);
    final animation = CurvedAnimation(
      parent: _ctl,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    );
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.2),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    );
  }

  // 设备状态颜色：1=在线、2=故障、其他=离线
  Color _statusColor(int status) {
    if (status == 2) return AppColors.fault;
    if (status == 1) return AppColors.online;
    return AppColors.offline;
  }

  // 设备状态文案 key
  String _statusKey(int status) {
    if (status == 2) return 'fault';
    if (status == 1) return 'online';
    return 'offline';
  }

  Widget _buildOption({
    required int index,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return _animatedItem(
      index,
      Material(
        color: selected
            ? AppColors.primary.withValues(alpha: 0.06)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(14.r),
        child: InkWell(
          borderRadius: BorderRadius.circular(14.r),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
            child: Row(
              children: [
                Container(
                  width: 40.w,
                  height: 40.w,
                  decoration: BoxDecoration(
                    color: (selected ? AppColors.primary : color)
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Icon(
                    icon,
                    size: 20.sp,
                    color: selected ? AppColors.primary : color,
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 14.sp,
                          fontWeight: FontWeight.w600,
                          color: selected
                              ? AppColors.primary
                              : AppColor.textPrimary(context),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 2.h),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12.sp,
                          color: AppColor.textHint(context),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (selected)
                  Icon(
                    Icons.check_circle_rounded,
                    size: 20.sp,
                    color: AppColors.primary,
                  )
                else
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18.sp,
                    color: AppColor.textHint(context),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final options = <Widget>[
      _buildOption(
        index: 0,
        icon: Icons.devices,
        title: l10n.allDevices,
        subtitle: l10n.summaryHint,
        color: AppColors.primary,
        selected: widget.selectedSn == 'all',
        onTap: () => widget.onSelected('all'),
      ),
    ];
    var index = 1;
    for (final raw in widget.devices) {
      final d = raw as Map<String, dynamic>;
      final sn = d['sn'] as String? ?? '';
      final status = (d['status'] as num?)?.toInt() ?? 0;
      options.add(
        _buildOption(
          index: index++,
          icon: Icons.memory,
          title: sn,
          subtitle: l10n.str(_statusKey(status), {}),
          color: _statusColor(status),
          selected: widget.selectedSn == sn,
          onTap: () => widget.onSelected(sn),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColor.surfaceContainer(context),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
      ),
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 20.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 标题头：渐变图标 + 标题 + 设备数量
              Row(
                children: [
                  Container(
                    width: 44.w,
                    height: 44.w,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14.r),
                      gradient: LinearGradient(
                        colors: [
                          AppColors.primary.withValues(alpha: 0.08),
                          AppColors.primary.withValues(alpha: 0.18),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Icon(
                      Icons.devices_other,
                      size: 22.sp,
                      color: AppColors.primary,
                    ),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.selectDevice,
                          style: TextStyle(
                            fontSize: 16.sp,
                            fontWeight: FontWeight.w700,
                            color: AppColor.textPrimary(context),
                          ),
                        ),
                        SizedBox(height: 2.h),
                        Text(
                          l10n.deviceCountHint('${widget.devices.length}'),
                          style: TextStyle(
                            fontSize: 12.sp,
                            color: AppColor.textHint(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: 14.h),
              Divider(height: 1, color: AppColor.divider(context)),
              SizedBox(height: 6.h),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.5,
                ),
                child: ListView(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  children: options,
                ),
              ),
              SizedBox(height: 14.h),
              _animatedItem(
                options.length,
                Material(
                  color: AppColor.surfaceHover(context),
                  borderRadius: BorderRadius.circular(14.r),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14.r),
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      height: 48.h,
                      alignment: Alignment.center,
                      child: Text(
                        l10n.cancel,
                        style: TextStyle(
                          fontSize: 16.sp,
                          fontWeight: FontWeight.w600,
                          color: AppColor.textSecondary(context),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
