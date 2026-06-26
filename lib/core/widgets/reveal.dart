/// ALOQA — kinetic entrance/cascade (fade + slide up). Built-ins only.
library;

import 'package:flutter/material.dart';

class RevealUp extends StatelessWidget {
  const RevealUp({
    super.key,
    required this.child,
    this.delayMs = 0,
    this.dy = 16,
    this.durationMs = 520,
  });

  final Widget child;
  final int delayMs;
  final double dy;
  final int durationMs;

  @override
  Widget build(BuildContext context) {
    final total = durationMs + delayMs;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: total),
      curve: Interval(delayMs / total, 1.0, curve: Curves.easeOutCubic),
      builder: (_, t, c) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.translate(offset: Offset(0, (1 - t) * dy), child: c),
      ),
      child: child,
    );
  }
}
