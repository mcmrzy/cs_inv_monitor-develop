part of 'station_detail_page.dart';

class _EnergyFlowPainter extends CustomPainter {
  final List<FlowEdge> flows;
  final double animValue;
  final Color gridColor;

  _EnergyFlowPainter({
    required this.flows,
    required this.animValue,
    required this.gridColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // 动态计算：80.w / 2 = 40 * size.width / 375
    final nodeR = 40.0 * size.width / 375.0;
    // 标签12.sp + 间距4.h 导致圆心偏移
    final labelOff = (12.0 * size.width / 375.0 + size.height / 100.0) / 2.0;

    // 旧版本的节点位置计算（与 Align 布局精确对齐）
    final pvC = Offset(cx, size.height * 0.125 + labelOff);
    final loadC = Offset(cx, size.height * 0.875 - labelOff);
    final battC = Offset(size.width * 0.125, cy + labelOff);
    final gridC = Offset(size.width * 0.875, cy + labelOff);

    const pvColor = AppColors.orange;
    const loadColor = AppColors.blue;
    const battColor = AppColors.successLight;
    const r = 16.0;
    const offset = 8.0;

    bool hasEdge(NodePosition a, NodePosition b) => flows
        .any((f) => (f.from == a && f.to == b) || (f.from == b && f.to == a));

    // ── 光伏 ↔ 负载：中心竖直线（完全保留，走cx） ──
    if (hasEdge(NodePosition.top, NodePosition.bottom)) {
      final a = Offset(pvC.dx, pvC.dy + nodeR);
      final b = Offset(loadC.dx, loadC.dy - nodeR);
      _line(canvas, a, b, pvColor, loadColor);
      _particles(canvas, a, b, pvColor, loadColor);
      _drawArrow(canvas, b.dx, b.dy + 12, loadColor);
    }

    // ── 储能 ↔ 光伏：向右 → 拐弯 → 走 cx-offset 竖线 → 到光伏中心左侧 ──
    if (hasEdge(NodePosition.left, NodePosition.top)) {
      final battRight = Offset(battC.dx + nodeR, battC.dy);
      final pvTarget = Offset(pvC.dx - offset, pvC.dy + nodeR);
      final bY = battC.dy;
      final pvToBatt = flows
          .any((f) => f.from == NodePosition.top && f.to == NodePosition.left);

      // pvToBatt=true：PV→储能，粒子reverse=true，从pv到batt移动 → 颜色顺序也要反过来
      final lineStartColor = pvToBatt ? pvColor : battColor;
      final lineEndColor = pvToBatt ? battColor : pvColor;

      _solidLine(canvas, battRight, Offset(cx - offset - r, bY), lineEndColor);

      _curvedArcOnly(
        canvas,
        Offset(cx - offset - r, bY),
        Offset(cx - offset, bY),
        Offset(cx - offset, bY - r),
        lineEndColor,
        lineStartColor,
        reverse: !pvToBatt,
      );

      _solidLine(canvas, Offset(cx - offset, bY - r), pvTarget, lineStartColor);

      _curvedParticlesV(
        canvas,
        battRight,
        Offset(cx - offset - r, bY),
        Offset(cx - offset, bY),
        Offset(cx - offset, bY - r),
        pvTarget,
        battColor,
        pvColor,
        reverse: pvToBatt,
      );
      if (pvToBatt) {
        _drawArrow(
          canvas,
          battRight.dx - 12,
          bY,
          battColor,
          pointingLeft: true,
        );
      } else {
        _drawArrow(
          canvas,
          pvTarget.dx,
          pvTarget.dy - 12,
          pvColor,
          pointingUp: true,
        );
      }
    }

    // ── 储能 ↔ 负载：向右 → 拐弯 → 走 cx-offset 竖线 → 到负载中心左侧 ──
    if (hasEdge(NodePosition.left, NodePosition.bottom)) {
      final battRight = Offset(battC.dx + nodeR, battC.dy);
      final loadTarget = Offset(loadC.dx - offset, loadC.dy - nodeR);
      final bY = battC.dy;

      _solidLine(canvas, battRight, Offset(cx - offset - r, bY), battColor);

      _curvedArcOnly(
        canvas,
        Offset(cx - offset - r, bY),
        Offset(cx - offset, bY),
        Offset(cx - offset, bY + r),
        battColor,
        loadColor,
      );

      _solidLine(canvas, Offset(cx - offset, bY + r), loadTarget, loadColor);

      _curvedParticlesV(
        canvas,
        battRight,
        Offset(cx - offset - r, bY),
        Offset(cx - offset, bY),
        Offset(cx - offset, bY + r),
        loadTarget,
        battColor,
        loadColor,
      );
      _drawArrow(canvas, loadTarget.dx, loadTarget.dy - 12, loadColor);
    }

    // ── 电网 ↔ 光伏：向左 → 拐弯 → 走 cx+offset 竖线 → 到光伏中心右侧 ──
    if (hasEdge(NodePosition.right, NodePosition.top)) {
      final gridLeft = Offset(gridC.dx - nodeR, gridC.dy);
      final pvTarget = Offset(pvC.dx + offset, pvC.dy + nodeR);
      final gY = gridC.dy;
      final pvToGrid = flows
          .any((f) => f.from == NodePosition.top && f.to == NodePosition.right);

      final lineStartColor = pvToGrid ? pvColor : gridColor;
      final lineEndColor = pvToGrid ? gridColor : pvColor;

      _solidLine(canvas, gridLeft, Offset(cx + offset + r, gY), lineEndColor);

      _curvedArcOnly(
        canvas,
        Offset(cx + offset + r, gY),
        Offset(cx + offset, gY),
        Offset(cx + offset, gY - r),
        lineEndColor,
        lineStartColor,
        reverse: !pvToGrid,
      );

      _solidLine(canvas, Offset(cx + offset, gY - r), pvTarget, lineStartColor);

      _curvedParticlesV(
        canvas,
        gridLeft,
        Offset(cx + offset + r, gY),
        Offset(cx + offset, gY),
        Offset(cx + offset, gY - r),
        pvTarget,
        gridColor,
        pvColor,
        reverse: pvToGrid,
      );
      if (pvToGrid) {
        _drawArrow(
          canvas,
          gridLeft.dx + 12,
          gY,
          gridColor,
          pointingLeft: false,
        );
      } else {
        _drawArrow(
          canvas,
          pvTarget.dx,
          pvTarget.dy - 12,
          pvColor,
          pointingUp: true,
        );
      }
    }

    // ── 电网 ↔ 负载：向左 → 拐弯 → 走 cx+offset 竖线 → 到负载中心右侧 ──
    if (hasEdge(NodePosition.right, NodePosition.bottom)) {
      final gridLeft = Offset(gridC.dx - nodeR, gridC.dy);
      final loadTarget = Offset(loadC.dx + offset, loadC.dy - nodeR);
      final gY = gridC.dy;
      final loadToGrid = flows.any(
        (f) => f.from == NodePosition.bottom && f.to == NodePosition.right,
      );

      final lineStartColor = loadToGrid ? loadColor : gridColor;
      final lineEndColor = loadToGrid ? gridColor : loadColor;

      _solidLine(canvas, gridLeft, Offset(cx + offset + r, gY), lineEndColor);

      _curvedArcOnly(
        canvas,
        Offset(cx + offset + r, gY),
        Offset(cx + offset, gY),
        Offset(cx + offset, gY + r),
        lineEndColor,
        lineStartColor,
        reverse: !loadToGrid,
      );

      _solidLine(
        canvas,
        Offset(cx + offset, gY + r),
        loadTarget,
        lineStartColor,
      );

      _curvedParticlesV(
        canvas,
        gridLeft,
        Offset(cx + offset + r, gY),
        Offset(cx + offset, gY),
        Offset(cx + offset, gY + r),
        loadTarget,
        gridColor,
        loadColor,
        reverse: loadToGrid,
      );
      if (loadToGrid) {
        _drawArrow(
          canvas,
          gridLeft.dx + 12,
          gY,
          gridColor,
          pointingLeft: false,
        );
      } else {
        _drawArrow(canvas, loadTarget.dx, loadTarget.dy - 12, loadColor);
      }
    }
  }

  void _drawArrow(
    Canvas canvas,
    double x,
    double y,
    Color c, {
    bool pointingLeft = false,
    bool pointingUp = false,
  }) {
    const s = 6.0;
    final path = Path();
    if (pointingUp) {
      path.moveTo(x, y - s);
      path.lineTo(x - s, y + s);
      path.lineTo(x + s, y + s);
    } else if (pointingLeft) {
      path.moveTo(x - s, y);
      path.lineTo(x + s, y - s);
      path.lineTo(x + s, y + s);
    } else {
      path.moveTo(x, y + s);
      path.lineTo(x - s, y - s);
      path.lineTo(x + s, y - s);
    }
    path.close();
    canvas.drawPath(
      path,
      Paint()
        ..color = c
        ..style = PaintingStyle.fill,
    );
  }

  void _line(Canvas canvas, Offset a, Offset b, Color ca, Color cb) {
    final dx = b.dx - a.dx, dy = b.dy - a.dy;
    final len = sqrt(dx * dx + dy * dy);
    if (len < 1) return;

    const segments = 20;

    for (int i = 0; i < segments; i++) {
      final t1 = i / segments;
      final t2 = (i + 1) / segments;

      final x1 = a.dx + dx * t1;
      final y1 = a.dy + dy * t1;
      final x2 = a.dx + dx * t2;
      final y2 = a.dy + dy * t2;

      final color1 = _lerp3(ca, cb, t1);
      final color2 = _lerp3(ca, cb, t2);

      final shader = ui.Gradient.linear(
        Offset(x1, y1),
        Offset(x2, y2),
        [color1, color2],
        [0.0, 1.0],
      );

      canvas.drawLine(
        Offset(x1, y1),
        Offset(x2, y2),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.8
          ..strokeCap = StrokeCap.round
          ..shader = shader,
      );
    }
  }

  void _solidLine(Canvas canvas, Offset a, Offset b, Color color) {
    canvas.drawLine(
      a,
      b,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.8
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  void _curvedArcOnly(
    Canvas canvas,
    Offset cornerStart,
    Offset control,
    Offset cornerEnd,
    Color ca,
    Color cb, {
    bool reverse = false,
  }) {
    final path = Path();
    path.moveTo(cornerStart.dx, cornerStart.dy);
    path.quadraticBezierTo(control.dx, control.dy, cornerEnd.dx, cornerEnd.dy);

    final shader = ui.Gradient.linear(
      cornerStart,
      cornerEnd,
      [reverse ? cb : ca, reverse ? ca : cb],
      [0.0, 1.0],
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.8
        ..strokeCap = StrokeCap.round
        ..shader = shader,
    );
  }

  void _particles(Canvas canvas, Offset a, Offset b, Color ca, Color cb) {
    final dx = b.dx - a.dx, dy = b.dy - a.dy;
    final len = sqrt(dx * dx + dy * dy);
    if (len < 1) return;
    const n = 8;
    for (int i = 0; i < n; i++) {
      final t = ((i / n) + animValue) % 1.0;
      final px = a.dx + dx * t, py = a.dy + dy * t;
      final alpha = (sin(t * pi) * 0.7).clamp(0.0, 0.8);
      _dot(canvas, px, py, 0, alpha, _lerp3(ca, cb, t));
    }
  }

  void _curvedParticlesV(
    Canvas canvas,
    Offset start,
    Offset cornerStart,
    Offset control,
    Offset cornerEnd,
    Offset end,
    Color ca,
    Color cb, {
    bool reverse = false,
  }) {
    final s1 = (cornerStart - start).distance;
    final bChord = (cornerEnd - cornerStart).distance;
    final bCtrl1 = (control - cornerStart).distance;
    final bCtrl2 = (cornerEnd - control).distance;
    final s2 = (bChord + bCtrl1 + bCtrl2) / 2;
    final s3 = (end - cornerEnd).distance;
    final total = s1 + s2 + s3;
    if (total < 1) return;

    const n = 8;
    for (int i = 0; i < n; i++) {
      final t = ((i / n) + animValue) % 1.0;
      final tp = reverse ? 1.0 - t : t;
      final alpha = (sin(tp * pi) * 0.7).clamp(0.0, 0.8);
      final d = tp * total;
      double px, py;
      if (d < s1) {
        final lt = d / s1;
        px = start.dx + (cornerStart.dx - start.dx) * lt;
        py = start.dy + (cornerStart.dy - start.dy) * lt;
      } else if (d < s1 + s2) {
        final bt = (d - s1) / s2;
        final tInv = 1 - bt;
        px = tInv * tInv * cornerStart.dx +
            2 * tInv * bt * control.dx +
            bt * bt * cornerEnd.dx;
        py = tInv * tInv * cornerStart.dy +
            2 * tInv * bt * control.dy +
            bt * bt * cornerEnd.dy;
      } else {
        final lt = (d - s1 - s2) / s3;
        px = cornerEnd.dx + (end.dx - cornerEnd.dx) * lt;
        py = cornerEnd.dy + (end.dy - cornerEnd.dy) * lt;
      }
      _dot(canvas, px, py, 0, alpha, _lerp3(ca, cb, tp));
    }
  }

  Color _lerp3(Color ca, Color cb, double t) {
    if (t < 0.33) return ca;
    if (t < 0.67) return Color.lerp(ca, cb, (t - 0.33) / 0.34)!;
    return cb;
  }

  void _dot(
    Canvas canvas,
    double x,
    double y,
    double angle,
    double alpha,
    Color c,
  ) {
    canvas.drawCircle(
      Offset(x, y),
      5.0,
      Paint()
        ..color = c.withValues(alpha: alpha * 0.5)
        ..style = PaintingStyle.fill
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawCircle(
      Offset(x, y),
      3.0,
      Paint()
        ..color = c.withValues(alpha: alpha)
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant _EnergyFlowPainter old) =>
      flows.length != old.flows.length ||
      animValue != old.animValue ||
      gridColor != old.gridColor;
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
                    color:
                        (selected ? AppColors.primary : color)
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
