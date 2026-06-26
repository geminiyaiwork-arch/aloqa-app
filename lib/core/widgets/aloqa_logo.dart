/// ALOQA — logo widget (CustomPaint connection-node badge + optional wordmark).
/// V2 glyph rendered 1:1 from design/logo.svg (60x60 authoring box).
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class AloqaLogo extends StatelessWidget {
  const AloqaLogo({
    super.key,
    this.size = 96,
    this.rounded = true, // retained for API compat (badge is already rounded)
    this.showWordmark = false,
    this.onDark = false,
  });

  final double size;
  final bool rounded;
  final bool showWordmark;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final badge = SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _AloqaBadgePainter()),
    );
    if (!showWordmark) return badge;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        badge,
        SizedBox(width: size * 0.20),
        Text(
          'ALOQA',
          style: TextStyle(
            fontSize: size * 0.50,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            height: 1.0,
            color: onDark ? Colors.white : AppColors.slate900,
          ),
        ),
      ],
    );
  }
}

class _AloqaBadgePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 60.0; // SVG box is 60x60
    Offset p(double x, double y) => Offset(x * k, y * k);

    // Badge: rect(2,2,56,56) rx15, diagonal brand500 -> brand700 (TL->BR).
    final rect = Rect.fromLTWH(2 * k, 2 * k, 56 * k, 56 * k);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(15 * k)),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.brand500, AppColors.brand700],
        ).createShader(rect),
    );

    // 2 lines (before nodes), white @70%, w3, round.
    final line = Paint()
      ..color = Colors.white.withOpacity(0.7)
      ..strokeWidth = 3 * k
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(p(20, 30), p(40, 19), line);
    canvas.drawLine(p(20, 30), p(40, 41), line);

    // 3 white nodes: A(20,30,r6) B(41,19,r5) C(41,41,r5).
    final dot = Paint()..color = Colors.white;
    canvas.drawCircle(p(20, 30), 6 * k, dot);
    canvas.drawCircle(p(41, 19), 5 * k, dot);
    canvas.drawCircle(p(41, 41), 5 * k, dot);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
