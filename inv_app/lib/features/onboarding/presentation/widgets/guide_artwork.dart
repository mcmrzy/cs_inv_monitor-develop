import 'dart:math' as math;

import 'package:flutter/material.dart';

enum GuideAccent {
  solar(Color(0xFF10264B), Color(0xFF296BBA), Color(0xFFB7DCFF)),
  alert(Color(0xFF482723), Color(0xFFA05632), Color(0xFFFFD7AA)),
  device(Color(0xFF222A54), Color(0xFF5367AF), Color(0xFFCFD7FF)),
  connection(Color(0xFF092E3C), Color(0xFF1C777A), Color(0xFFB2F4E7));

  const GuideAccent(this.background, this.light, this.detail);

  final Color background;
  final Color light;
  final Color detail;
}

/// Illustration panel shared by the welcome carousel and setup guide.
class GuideArtwork extends StatelessWidget {
  const GuideArtwork({
    super.key,
    required this.asset,
    required this.icon,
    required this.accent,
    this.compact = false,
    this.borderRadius = const BorderRadius.all(Radius.circular(26)),
  });

  final String asset;
  final IconData icon;
  final GuideAccent accent;
  final bool compact;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          gradient: RadialGradient(
            center: const AlignmentDirectional(0.64, -0.36),
            radius: 0.92,
            colors: [accent.light, accent.background],
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(
              painter: _ArtworkBackdrop(
                accent: accent,
                compact: compact,
                direction: Directionality.of(context),
              ),
            ),
            Padding(
              padding: EdgeInsets.only(top: compact ? 8 : 12),
              child: Image.asset(
                asset,
                fit: compact ? BoxFit.contain : BoxFit.fitHeight,
                alignment: AlignmentDirectional(compact ? 0.61 : 0, 1),
                errorBuilder: (_, __, ___) => Icon(
                  icon,
                  color: accent.detail,
                  size: compact ? 42 : 72,
                ),
              ),
            ),
            PositionedDirectional(
              start: compact ? 18 : 22,
              top: compact ? 18 : 22,
              child: Container(
                width: compact ? 38 : 48,
                height: compact ? 38 : 48,
                decoration: BoxDecoration(
                  color: accent.detail.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(compact ? 11 : 14),
                  border: Border.all(
                    color: accent.detail.withValues(alpha: 0.33),
                  ),
                ),
                child: Icon(
                  icon,
                  color: accent.detail,
                  size: compact ? 21 : 24,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArtworkBackdrop extends CustomPainter {
  const _ArtworkBackdrop({
    required this.accent,
    required this.compact,
    required this.direction,
  });

  final GuideAccent accent;
  final bool compact;
  final TextDirection direction;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    if (direction == TextDirection.rtl) {
      canvas.translate(size.width, 0);
      canvas.scale(-1, 1);
    }
    final center = Offset(size.width * 0.72, size.height * 0.54);
    final radius = math.min(size.width * 0.38, size.height * 0.67);
    final ring = Paint()
      ..color = accent.detail.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawCircle(center, radius, ring);
    canvas.drawCircle(center, radius + (compact ? 18 : 25), ring);

    if (size.height >= 148) {
      final motifWidth = math.min(size.width * 0.32, compact ? 86.0 : 105.0);
      final motifBaseline = !compact && accent == GuideAccent.solar
          ? size.height * 0.63
          : size.height * 0.79;
      canvas.translate(compact ? 18 : 22, motifBaseline - motifWidth);
      canvas.scale(motifWidth / 100);
      _paintMotif(canvas);
    }
    canvas.restore();
  }

  // These illustrations are symbolic. They carry no device readings.
  void _paintMotif(Canvas canvas) {
    final fill = Paint()..color = accent.detail.withValues(alpha: 0.52);
    final stroke = Paint()
      ..color = accent.detail.withValues(alpha: 0.58)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    switch (accent) {
      case GuideAccent.solar:
        final path = Path()
          ..moveTo(3, 94)
          ..cubicTo(22, 94, 25, 82, 37, 68)
          ..cubicTo(52, 48, 62, 32, 78, 37)
          ..quadraticBezierTo(89, 40, 97, 52);
        final area = Path.from(path)
          ..lineTo(97, 98)
          ..lineTo(3, 98)
          ..close();
        canvas.drawPath(
          area,
          Paint()..color = accent.detail.withValues(alpha: 0.14),
        );
        canvas.drawPath(path, stroke);
        canvas.drawCircle(const Offset(78, 37), 3.3, fill);
      case GuideAccent.alert:
        canvas.drawPath(
          Path()
            ..moveTo(3, 76)
            ..lineTo(26, 76)
            ..lineTo(36, 60)
            ..lineTo(46, 89)
            ..lineTo(61, 44)
            ..lineTo(72, 76)
            ..lineTo(97, 76),
          stroke,
        );
        canvas.drawCircle(const Offset(61, 44), 3.3, fill);
      case GuideAccent.device:
        final brackets = Path()
          ..moveTo(10, 55)
          ..lineTo(10, 37)
          ..lineTo(28, 37)
          ..moveTo(72, 37)
          ..lineTo(90, 37)
          ..lineTo(90, 55)
          ..moveTo(90, 79)
          ..lineTo(90, 97)
          ..lineTo(72, 97)
          ..moveTo(28, 97)
          ..lineTo(10, 97)
          ..lineTo(10, 79)
          ..moveTo(21, 67)
          ..lineTo(79, 67);
        canvas.drawPath(brackets, stroke);
      case GuideAccent.connection:
        const origin = Offset(50, 95);
        for (final radius in [16.0, 31.0, 46.0]) {
          canvas.drawArc(
            Rect.fromCircle(center: origin, radius: radius),
            -math.pi * 0.77,
            math.pi * 0.54,
            false,
            stroke,
          );
        }
        canvas.drawCircle(origin, 3.3, fill);
    }
  }

  @override
  bool shouldRepaint(_ArtworkBackdrop oldDelegate) =>
      accent != oldDelegate.accent ||
      compact != oldDelegate.compact ||
      direction != oldDelegate.direction;
}
