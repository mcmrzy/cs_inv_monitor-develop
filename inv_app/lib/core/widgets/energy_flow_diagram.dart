import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/l10n/app_localizations.dart';

class EnergyFlowDiagram extends StatefulWidget {
  final double pvPower;
  final double batteryPower;
  final double loadPower;
  final double gridPower;
  final double batterySoc;

  const EnergyFlowDiagram({
    super.key,
    this.pvPower = 0,
    this.batteryPower = 0,
    this.loadPower = 0,
    this.gridPower = 0,
    this.batterySoc = 0,
  });

  @override
  State<EnergyFlowDiagram> createState() => _EnergyFlowDiagramState();
}

class _EnergyFlowDiagramState extends State<EnergyFlowDiagram>
    with TickerProviderStateMixin {
  late AnimationController _particleController;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _particleController = AnimationController(
      duration: const Duration(milliseconds: 3000),
      vsync: this,
    )..repeat();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _particleController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.energyFlow,
            style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 12.h),
          SizedBox(
            width: 280.w,
            height: 280.h,
            child: AnimatedBuilder(
              animation: Listenable.merge([_particleController, _pulseController]),
              builder: (context, _) {
                return CustomPaint(
                  painter: _EnergyFlowPainter(
                    pvPower: widget.pvPower.isNaN ? 0 : widget.pvPower,
                    batteryPower: widget.batteryPower.isNaN ? 0 : widget.batteryPower,
                    loadPower: widget.loadPower.isNaN ? 0 : widget.loadPower,
                    gridPower: widget.gridPower.isNaN ? 0 : widget.gridPower,
                    batterySoc: widget.batterySoc.isNaN ? 0 : widget.batterySoc,
                    progress: _particleController.value,
                    pulseProgress: _pulseController.value,
                    pvColor: Colors.orange,
                    batteryChargeColor: AppColors.success,
                    batteryDischargeColor: Colors.blue,
                    loadColor: Colors.purple,
                    gridColor: Colors.blue,
                    inverterLabel: l10n.inverterLabel,
                    batteryLabel: l10n.batteryLabel,
                    loadLabel: l10n.loadLabel,
                    gridLabel: l10n.gridLabel,
                  ),
                  size: Size(280.w, 280.h),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Path definition for orthogonal line routing.
///
/// A path is either a straight segment or two segments forming an L-shape.
/// The L-shape is defined by a corner point that the path turns at.
class _PathDef {
  final Offset start;
  final Offset corner; // == end for straight paths
  final Offset end;

  const _PathDef(this.start, this.corner, this.end);

  /// Straight line path (no turn).
  factory _PathDef.straight(Offset a, Offset b) => _PathDef(a, b, b);

  double get length {
    final d1 = (corner - start).distance;
    final d2 = (end - corner).distance;
    return d1 + d2;
  }

  /// Interpolate a point along the path at parameter t in [0, 1].
  Offset pointAt(double t) {
    final d1 = (corner - start).distance;
    final d2 = (end - corner).distance;
    final total = d1 + d2;
    if (total == 0 || total.isNaN) return start;
    final dist = t * total;
    if (dist <= d1) {
      return d1 > 0 ? start + (corner - start) * (dist / d1) : corner;
    }
    return d2 > 0 ? corner + (end - corner) * ((dist - d1) / d2) : corner;
  }

  /// Unit direction vector at parameter t.
  Offset directionAt(double t) {
    final d1 = (corner - start).distance;
    final d2 = (end - corner).distance;
    final total = d1 + d2;
    if (total == 0 || total.isNaN) return const Offset(1, 0);
    final dist = t * total;
    if (dist < d1) {
      return d1 > 0 ? (corner - start) / d1 : (end - corner) / d2;
    }
    return d2 > 0 ? (end - corner) / d2 : (corner - start) / d1;
  }
}

class _EnergyFlowPainter extends CustomPainter {
  final double pvPower;
  final double batteryPower;
  final double loadPower;
  final double gridPower;
  final double batterySoc;
  final double progress;
  final double pulseProgress;
  final Color pvColor;
  final Color batteryChargeColor;
  final Color batteryDischargeColor;
  final Color loadColor;
  final Color gridColor;
  final String inverterLabel;
  final String batteryLabel;
  final String loadLabel;
  final String gridLabel;

  static const double _nodeRadius = 28.0;
  static const double _lineInset = 32.0;

  _EnergyFlowPainter({
    required this.pvPower,
    required this.batteryPower,
    required this.loadPower,
    required this.gridPower,
    required this.batterySoc,
    required this.progress,
    required this.pulseProgress,
    required this.pvColor,
    required this.batteryChargeColor,
    required this.batteryDischargeColor,
    required this.loadColor,
    required this.gridColor,
    required this.inverterLabel,
    required this.batteryLabel,
    required this.loadLabel,
    required this.gridLabel,
  });

  // ── Node positions (cross layout) ──
  //
  //           [PV]
  //            |
  //   [电池] — [逆变器] — [电网]
  //            |
  //          [负载]

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final pvCenter = Offset(w * 0.50, h * 0.15);
    final invCenter = Offset(w * 0.50, h * 0.45);
    final battCenter = Offset(w * 0.15, h * 0.45);
    final loadCenter = Offset(w * 0.50, h * 0.75);
    final gridCenter = Offset(w * 0.85, h * 0.45);

    // ── Draw nodes ──
    _drawIconCircle(canvas, pvCenter, _nodeRadius, pvColor, Icons.wb_sunny);
    _drawIconCircle(canvas, invCenter, _nodeRadius, AppColors.primary, Icons.power);

    final battColor = batteryPower >= 0 ? batteryChargeColor : batteryDischargeColor;
    if (batteryPower != 0) {
      _drawPulseEffect(canvas, battCenter, battColor);
    }
    _drawIconCircle(canvas, battCenter, _nodeRadius, battColor,
        batteryPower >= 0 ? Icons.battery_charging_full : Icons.battery_alert);
    _drawIconCircle(canvas, loadCenter, _nodeRadius, loadColor, Icons.home);
    _drawIconCircle(canvas, gridCenter, _nodeRadius, gridColor, Icons.electrical_services);

    // ── Labels ──
    _drawNodeLabel(canvas, pvCenter, 'PV', pvColor, below: true);
    _drawNodeLabel(canvas, invCenter, l10n.inverterOutput, AppColors.primary, below: true);
    _drawNodeLabel(canvas, battCenter, l10n.battery, battColor, below: true);
    _drawNodeLabel(canvas, loadCenter, l10n.load, loadColor, below: true);
    _drawNodeLabel(canvas, gridCenter, l10n.grid, gridColor, below: true);

    // ── Flow paths ──
    //
    // PV → 逆变器:  vertical (top to center)
    // 逆变器 ↔ 电池:  horizontal (same Y level)
    // 逆变器 → 负载:  vertical (center to bottom)
    // 逆变器 ↔ 电网:  horizontal (same Y level)

    final invEdgeTop = Offset(invCenter.dx, invCenter.dy - _lineInset);
    final invEdgeLeft = Offset(invCenter.dx - _lineInset, invCenter.dy);
    final invEdgeRight = Offset(invCenter.dx + _lineInset, invCenter.dy);
    final invEdgeBottom = Offset(invCenter.dx, invCenter.dy + _lineInset);
    final pvEdgeBottom = Offset(pvCenter.dx, pvCenter.dy + _lineInset);
    final battEdgeRight = Offset(battCenter.dx + _lineInset, battCenter.dy);
    final gridEdgeLeft = Offset(gridCenter.dx - _lineInset, gridCenter.dy);
    final loadEdgeTop = Offset(loadCenter.dx, loadCenter.dy - _lineInset);

    // PV → 逆变器 (straight vertical)
    if (pvPower > 0) {
      final path = _PathDef.straight(pvEdgeBottom, invEdgeTop);
      _drawActiveFlow(canvas, path, pvColor, pvPower, 'pv');
    } else {
      _drawInactivePath(canvas, _PathDef.straight(pvEdgeBottom, invEdgeTop));
    }

    // 逆变器 ↔ 电池 (straight horizontal — same Y level)
    if (batteryPower > 0) {
      _drawActiveFlow(canvas, _PathDef.straight(invEdgeLeft, battEdgeRight), batteryChargeColor, batteryPower, 'bat_c');
    } else if (batteryPower < 0) {
      _drawActiveFlow(canvas, _PathDef.straight(battEdgeRight, invEdgeLeft), batteryDischargeColor, -batteryPower, 'bat_d');
    } else {
      _drawInactivePath(canvas, _PathDef.straight(invEdgeLeft, battEdgeRight));
    }

    // 逆变器 → 负载 (straight vertical)
    if (loadPower > 0) {
      final path = _PathDef.straight(invEdgeBottom, loadEdgeTop);
      _drawActiveFlow(canvas, path, loadColor, loadPower, 'load');
    } else {
      _drawInactivePath(canvas, _PathDef.straight(invEdgeBottom, loadEdgeTop));
    }

    // 逆变器 ↔ 电网 (straight horizontal — same Y level)
    if (gridPower > 0) {
      _drawActiveFlow(canvas, _PathDef.straight(invEdgeRight, gridEdgeLeft), gridColor, gridPower, 'grid_e');
    } else if (gridPower < 0) {
      _drawActiveFlow(canvas, _PathDef.straight(gridEdgeLeft, invEdgeRight), gridColor, -gridPower, 'grid_i');
    } else {
      _drawInactivePath(canvas, _PathDef.straight(invEdgeRight, gridEdgeLeft));
    }

    _drawBatteryInfo(canvas, battCenter);
  }

  // ── Active flow: dashed line + particles + label ──

  void _drawActiveFlow(Canvas canvas, _PathDef path, Color color, double power, String tag) {
    if (path.length <= 0) return;
    _drawDashedPath(canvas, path, color);
    _drawParticles(canvas, path, color, power);
    _drawPowerLabel(canvas, path, '${power.toStringAsFixed(0)}W', color);
  }

  // ── Dashed line along an L-shaped or straight path ──

  void _drawDashedPath(Canvas canvas, _PathDef path, Color color) {
    final totalLen = path.length;
    if (totalLen == 0 || totalLen.isNaN) return;

    const dashW = 8.0;
    const dashGap = 4.0;
    const pattern = dashW + dashGap;
    final offset = (progress * totalLen) % pattern;

    final paint = Paint()
      ..color = color.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final count = ((totalLen + offset) / pattern).ceil() + 1;
    for (int i = -1; i < count; i++) {
      final s = i * pattern - offset;
      final e = s + dashW;
      if (e <= 0 || s >= totalLen) continue;

      final cs = math.max(0.0, s);
      final ce = math.min(totalLen, e);
      canvas.drawLine(
        path.pointAt(cs / totalLen),
        path.pointAt(ce / totalLen),
        paint,
      );
    }
  }

  // ── Inactive (grey dashed) path ──

  void _drawInactivePath(Canvas canvas, _PathDef path) {
    final totalLen = path.length;
    if (totalLen == 0 || totalLen.isNaN) return;

    const dashW = 6.0;
    const dashGap = 6.0;
    const pattern = dashW + dashGap;

    final paint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    final count = (totalLen / pattern).ceil();
    for (int i = 0; i < count; i++) {
      final s = i * pattern;
      final e = s + dashW;
      if (e > totalLen) break;
      canvas.drawLine(
        path.pointAt(s / totalLen),
        path.pointAt(e / totalLen),
        paint,
      );
    }
  }

  // ── Animated particles ──

  void _drawParticles(Canvas canvas, _PathDef path, Color color, double power) {
    if (path.length <= 0) return;
    final totalLen = path.length;
    if (totalLen == 0) return;

    final count = (power / 300.0).clamp(4, 16).toInt();
    final speed = (0.3 + power / 1000.0 * 0.05).clamp(0.3, 1.0);
    final rng = math.Random(42);

    for (int i = 0; i < count; i++) {
      final baseT = i / count;
      final t = (baseT + progress * speed) % 1.0;
      final pos = path.pointAt(t);

      final sz = 2.0 + rng.nextDouble() * 3.0;
      final alpha = 0.2 + 0.7 * t;

      // Glow
      canvas.drawCircle(pos, sz + 2, Paint()
        ..color = color.withValues(alpha: alpha * 0.4)
        ..style = PaintingStyle.fill);
      // Core
      canvas.drawCircle(pos, sz, Paint()
        ..color = color.withValues(alpha: alpha)
        ..style = PaintingStyle.fill);
    }
  }

  // ── Power label perpendicular to path at midpoint ──

  void _drawPowerLabel(Canvas canvas, _PathDef path, String text, Color color) {
    if (path.length <= 0) return;
    final mid = path.pointAt(0.5);
    if (mid.dx.isNaN || mid.dy.isNaN) return;
    final dir = path.directionAt(0.5);
    final perp = Offset(-dir.dy, dir.dx);
    final labelPos = mid + perp * 18;
    if (labelPos.dx.isNaN || labelPos.dy.isNaN) return;

    final paragraph = (ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: TextAlign.center, fontSize: 10))
          ..pushStyle(ui.TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600))
          ..addText(text))
        .build()
      ..layout(const ui.ParagraphConstraints(width: 100));
    canvas.drawParagraph(paragraph, Offset(labelPos.dx - 50, labelPos.dy - paragraph.height / 2));
  }

  // ── Decorations ──

  void _drawPulseEffect(Canvas canvas, Offset center, Color color) {
    final r1 = _nodeRadius + 12.0 * pulseProgress;
    canvas.drawCircle(
      center,
      r1,
      Paint()
        ..color = color.withValues(alpha: 0.3 * (1.0 - pulseProgress))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0 + 2.0 * pulseProgress,
    );
    canvas.drawCircle(
      center,
      _nodeRadius + 6.0 * pulseProgress,
      Paint()
        ..color = color.withValues(alpha: 0.15 * (1.0 - pulseProgress))
        ..style = PaintingStyle.fill,
    );
  }

  void _drawIconCircle(Canvas canvas, Offset center, double radius, Color color, IconData icon) {
    canvas.drawCircle(center, radius, Paint()
      ..color = color.withValues(alpha: 0.15)
      ..style = PaintingStyle.fill);
    canvas.drawCircle(center, radius, Paint()
      ..color = color.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2);

    final paragraph = (ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: TextAlign.center, fontSize: 20))
          ..pushStyle(ui.TextStyle(color: color, fontSize: 20))
          ..addText(String.fromCharCode(icon.codePoint)))
        .build()
      ..layout(const ui.ParagraphConstraints(width: 40));
    canvas.drawParagraph(paragraph, Offset(center.dx - 20, center.dy - paragraph.height / 2));
  }

  void _drawNodeLabel(Canvas canvas, Offset center, String text, Color color, {required bool below}) {
    final y = below ? center.dy + _nodeRadius + 8 : center.dy - _nodeRadius - 20;
    final paragraph = (ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: TextAlign.center, fontSize: 11))
          ..pushStyle(ui.TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600))
          ..addText(text))
        .build()
      ..layout(const ui.ParagraphConstraints(width: 80));
    canvas.drawParagraph(paragraph, Offset(center.dx - 40, y));
  }

  void _drawBatteryInfo(Canvas canvas, Offset battCenter) {
    final socText = '${batterySoc.toStringAsFixed(0)}%';
    final isCharging = batteryPower > 0;
    final stateIcon = isCharging ? '↑' : (batteryPower < 0 ? '↓' : '-');
    final color = isCharging
        ? batteryChargeColor
        : (batteryPower < 0 ? batteryDischargeColor : Colors.grey);

    final paragraph = (ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: TextAlign.center, fontSize: 10))
          ..pushStyle(ui.TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600))
          ..addText('$socText $stateIcon'))
        .build()
      ..layout(const ui.ParagraphConstraints(width: 60));
    canvas.drawParagraph(paragraph, Offset(battCenter.dx - 30, battCenter.dy - 48));
  }

  @override
  bool shouldRepaint(covariant _EnergyFlowPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.pulseProgress != pulseProgress ||
        oldDelegate.pvPower != pvPower ||
        oldDelegate.batteryPower != batteryPower ||
        oldDelegate.loadPower != loadPower ||
        oldDelegate.gridPower != gridPower ||
        oldDelegate.batterySoc != batterySoc;
  }
}
