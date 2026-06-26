/// ALOQA — drifting connection-node constellation (echoes the logo).
/// Built-ins only: AnimationController + CustomPaint.
library;

import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class FloatingNodeMotif extends StatefulWidget {
  const FloatingNodeMotif({super.key, this.size = 220, this.seed = 1});

  final double size;
  final int seed;

  @override
  State<FloatingNodeMotif> createState() => _FloatingNodeMotifState();
}

class _FloatingNodeMotifState extends State<FloatingNodeMotif>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final List<Offset> _base;
  late final List<double> _phase;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 6))
      ..repeat(reverse: true);
    final r = math.Random(widget.seed);
    _base = List.generate(5, (_) => Offset(0.12 + r.nextDouble() * 0.76, 0.12 + r.nextDouble() * 0.76));
    _phase = List.generate(5, (_) => r.nextDouble() * math.pi * 2);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) => CustomPaint(
            painter: _NodeMeshPainter(_c.value, _base, _phase),
          ),
        ),
      ),
    );
  }
}

class _NodeMeshPainter extends CustomPainter {
  _NodeMeshPainter(this.t, this.base, this.phase);
  final double t;
  final List<Offset> base;
  final List<double> phase;

  @override
  void paint(Canvas canvas, Size size) {
    final pts = <Offset>[];
    for (var i = 0; i < base.length; i++) {
      final dy = math.sin(t * 2 * math.pi + phase[i]) * 6;
      pts.add(Offset(base[i].dx * size.width, base[i].dy * size.height + dy));
    }
    final edge = Paint()
      ..color = AppColors.brand500.withOpacity(0.12)
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round;
    final maxD = size.width * 0.5;
    for (var i = 0; i < pts.length; i++) {
      for (var j = i + 1; j < pts.length; j++) {
        if ((pts[i] - pts[j]).distance < maxD) {
          canvas.drawLine(pts[i], pts[j], edge);
        }
      }
    }
    final node = Paint()..color = AppColors.brand500.withOpacity(0.18);
    final halo = Paint()..color = AppColors.brand400.withOpacity(0.25);
    final core = Paint()..color = AppColors.brand600.withOpacity(0.9);
    for (var i = 0; i < pts.length; i++) {
      if (i == 0 || i == 2) {
        canvas.drawCircle(pts[i], 9, halo);
        canvas.drawCircle(pts[i], 4.5, core);
      } else {
        canvas.drawCircle(pts[i], 4, node);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _NodeMeshPainter old) => old.t != t;
}
