import 'dart:math';
import 'package:flutter/material.dart';

class RadarPainter extends CustomPainter {
  final double animationValue;
  final double pulseValue;
  final int targetCount;

  RadarPainter(this.animationValue, this.pulseValue, this.targetCount);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = min(size.width, size.height) / 2;

    for (int i = 1; i <= 3; i++) {
      final paint = Paint()
        ..color = Colors.cyanAccent.withOpacity(0.2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      canvas.drawCircle(center, maxRadius * i / 3, paint);
    }

    final sweepPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.cyanAccent.withOpacity(0.3),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: maxRadius));

    final sweepPath = Path()
      ..moveTo(center.dx, center.dy)
      ..arcTo(
        Rect.fromCircle(center: center, radius: maxRadius),
        -pi / 2 + animationValue * 2 * pi,
        pi / 3,
        false,
      )
      ..lineTo(center.dx, center.dy);

    canvas.drawPath(sweepPath, sweepPaint);

    for (int i = 0; i < targetCount && i < 5; i++) {
      final angle = (i / 5) * 2 * pi;
      final radius = maxRadius * 0.7;
      final targetPos = Offset(
        center.dx + cos(angle) * radius,
        center.dy + sin(angle) * radius,
      );

      final targetPaint = Paint()
        ..color = Colors.red.withOpacity(0.5 + 0.5 * sin(pulseValue * 2 * pi));
      canvas.drawCircle(targetPos, 4, targetPaint);
    }
  }

  @override
  bool shouldRepaint(covariant RadarPainter oldDelegate) => true;
}