import 'dart:math';
import 'package:flutter/material.dart';

class SkyViewPainter extends CustomPainter {
  final double azimuth;
  final double elevation;
  final double observerLat;
  final double observerLon;

  SkyViewPainter({
    required this.azimuth,
    required this.elevation,
    required this.observerLat,
    required this.observerLon,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2 - 20;

    // Draw horizon circle
    final horizonPaint = Paint()
      ..color = Colors.blueGrey.shade800
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, radius, horizonPaint);

    // Draw elevation circles
    for (int i = 1; i <= 3; i++) {
      final elevPaint = Paint()
        ..color = Colors.blueGrey.shade700.withOpacity(0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      canvas.drawCircle(center, radius * (1 - i / 4), elevPaint);
    }

    // Draw cardinal directions
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    final directions = ['N', 'E', 'S', 'W'];
    for (int i = 0; i < 4; i++) {
      final angle = i * pi / 2;
      final pos = Offset(
        center.dx + cos(angle - pi / 2) * (radius + 15),
        center.dy + sin(angle - pi / 2) * (radius + 15),
      );

      textPainter.text = TextSpan(
        text: directions[i],
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(pos.dx - textPainter.width / 2, pos.dy - textPainter.height / 2),
      );
    }

    // Draw satellite position
    if (elevation >= 0) {
      final azRad = (azimuth - 90) * pi / 180;
      final elevFactor = 1 - (elevation / 90);
      final satRadius = radius * elevFactor;

      final satPos = Offset(
        center.dx + cos(azRad) * satRadius,
        center.dy + sin(azRad) * satRadius,
      );

      // Draw line from center to satellite
      final linePaint = Paint()
        ..color = Colors.cyanAccent.withOpacity(0.5)
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke;
      canvas.drawLine(center, satPos, linePaint);

      // Draw satellite
      final satPaint = Paint()..color = Colors.red;
      canvas.drawCircle(satPos, 8, satPaint);

      final satGlowPaint = Paint()
        ..color = Colors.red.withOpacity(0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
      canvas.drawCircle(satPos, 12, satGlowPaint);
    }

    // Draw observer position marker at center
    final observerPaint = Paint()..color = Colors.green;
    canvas.drawCircle(center, 4, observerPaint);
  }

  @override
  bool shouldRepaint(covariant SkyViewPainter oldDelegate) => true;
}