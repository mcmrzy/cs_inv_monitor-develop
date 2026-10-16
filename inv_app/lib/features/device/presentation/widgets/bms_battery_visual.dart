import 'package:flutter/material.dart';

/// A storage cabinet, with an accessible reading independent of painted details.
/// Null means unavailable; zero is a valid, empty battery. No synthetic animation.
class BmsBatteryVisual extends StatelessWidget {
  final double? soc;
  final String value;

  const BmsBatteryVisual({super.key, required this.soc, required this.value});

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'SOC $value',
        child: ExcludeSemantics(
          child: AspectRatio(
            aspectRatio: 240 / 330,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CustomPaint(
                  painter: _CabinetPainter(
                    soc:
                        soc != null && soc!.isFinite && soc! >= 0 && soc! <= 100
                            ? soc
                            : null,
                    dark: Theme.of(context).brightness == Brightness.dark,
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: .48,
                  heightFactor: .31,
                  alignment: const Alignment(-.13, -.05),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          value,
                          style: const TextStyle(
                            fontSize: 37,
                            height: 1.15,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -1.2,
                            color: Colors.white,
                            shadows: [
                              Shadow(color: Color(0xB300221A), blurRadius: 9),
                            ],
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

class _CabinetPainter extends CustomPainter {
  final double? soc;
  final bool dark;
  const _CabinetPainter({required this.soc, required this.dark});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 240, size.height / 330);
    final shadow = Paint()
      ..color = Colors.black.withValues(alpha: dark ? .4 : .15)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    canvas.drawOval(const Rect.fromLTWH(37, 288, 172, 15), shadow);

    Path polygon(List<Offset> points) => Path()..addPolygon(points, true);
    void surface(Path path, Rect bounds, List<Color> colors,
        {Alignment begin = Alignment.topLeft,
        Alignment end = Alignment.bottomRight,}) {
      canvas.drawPath(
          path,
          Paint()
            ..shader = LinearGradient(
              begin: begin,
              end: end,
              colors: colors,
            ).createShader(bounds),);
    }

    // Recessed base and feet anchor a floor-standing storage product.
    canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(57, 279, 20, 15),
          const Radius.circular(3),
        ),
        Paint()..color = const Color(0xFF343F46),);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(168, 270, 20, 16),
          const Radius.circular(3),
        ),
        Paint()..color = const Color(0xFF343F46),);
    final side = polygon(const [
      Offset(172, 44),
      Offset(210, 27),
      Offset(210, 260),
      Offset(172, 283),
    ]);
    surface(side, const Rect.fromLTWH(172, 27, 38, 256), const [
      Color(0xFFCAD2D5),
      Color(0xFF8E9BA3),
      Color(0xFF59666E),
    ]);
    final top = polygon(const [
      Offset(39, 44),
      Offset(78, 24),
      Offset(201, 24),
      Offset(210, 27),
      Offset(172, 47),
    ]);
    surface(top, const Rect.fromLTWH(39, 24, 171, 23), const [
      Color(0xFFF5F8F8),
      Color(0xFFBCC8CE),
      Color(0xFFE5EAEB),
    ]);
    final front = RRect.fromRectAndRadius(
      const Rect.fromLTWH(37, 43, 140, 244),
      const Radius.circular(12),
    );
    canvas.drawRRect(
        front,
        Paint()
          ..shader = const LinearGradient(
            colors: [Color(0xFFE8EFF0), Color(0xFFB5C1C7), Color(0xFF8B989F)],
            stops: [0, .6, 1],
          ).createShader(front.outerRect),);
    canvas.drawRRect(
        front.deflate(1),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Colors.white.withValues(alpha: .55),);
    final bezel = RRect.fromRectAndRadius(
      const Rect.fromLTWH(47, 54, 120, 209),
      const Radius.circular(9),
    );
    canvas.drawRRect(bezel, Paint()..color = const Color(0xFF3B484E));
    final glass = RRect.fromRectAndRadius(
      const Rect.fromLTWH(52, 59, 110, 199),
      const Radius.circular(6),
    );
    canvas.drawRRect(
        glass,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: soc == null
                ? const [Color(0xFF343E43), Color(0xFF1C262B)]
                : const [Color(0xFF133D34), Color(0xFF102B25)],
          ).createShader(glass.outerRect),);
    canvas.save();
    canvas.clipRRect(glass);
    if (soc != null && soc! > 0) {
      final y = 258 - 199 * soc! / 100;
      final fill = Rect.fromLTRB(52, y, 162, 259);
      canvas.drawRect(
          fill,
          Paint()
            ..shader = const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF55EBA5), Color(0xFF18B57C), Color(0xFF008865)],
            ).createShader(fill),);
      canvas.drawPath(
          polygon([
            Offset(52, y + 9),
            Offset(89, y - 6),
            Offset(162, y),
            Offset(162, y + 9),
          ]),
          Paint()..color = const Color(0xFF85F7C5).withValues(alpha: .5),);
      canvas.drawLine(
          Offset(52, y + 9),
          Offset(162, y + 9),
          Paint()
            ..color = const Color(0xFFBDFFE0).withValues(alpha: .55)
            ..strokeWidth = 1,);
    }
    canvas.drawRect(
        const Rect.fromLTWH(52, 59, 110, 199),
        Paint()
          ..shader = const LinearGradient(
            colors: [Color(0x29FFFFFF), Color(0x00FFFFFF), Color(0x0AFFFFFF)],
            stops: [0, .35, 1],
          ).createShader(glass.outerRect),);
    // Subtle module seams read as a cabinet, without implying a battery count.
    for (final y in [123.0, 189.0]) {
      canvas.drawLine(
          Offset(52, y),
          Offset(162, y),
          Paint()
            ..color = Colors.black.withValues(alpha: .13)
            ..strokeWidth = 1,);
    }
    canvas.restore();
    canvas.drawRRect(
        glass,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = const Color(0xFFBACCC6).withValues(alpha: .34),);
    // Lower ventilation grille and the side service-panel seam.
    for (var i = 0; i < 8; i++) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(71 + i * 9, 273, 5, 2), const Radius.circular(1),),
          Paint()..color = const Color(0xFF6D7C83),);
    }
    canvas.drawLine(
        const Offset(190, 66),
        const Offset(190, 240),
        Paint()
          ..color = Colors.white.withValues(alpha: .18)
          ..strokeWidth = 1,);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(194, 127, 3, 22), const Radius.circular(1.5),),
        Paint()..color = const Color(0xFF66767E),);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CabinetPainter oldDelegate) =>
      oldDelegate.soc != soc || oldDelegate.dark != dark;
}
