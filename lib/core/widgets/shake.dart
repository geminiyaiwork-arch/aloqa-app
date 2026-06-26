/// ALOQA — shake-on-invalid (graft D). Bump [shakeKey] to re-trigger.
library;

import 'dart:math' as math;
import 'package:flutter/material.dart';

class Shake extends StatelessWidget {
  const Shake({super.key, required this.child, required this.shakeKey});

  final Widget child;
  final int shakeKey; // increment to fire a shake

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey(shakeKey),
      tween: Tween(begin: shakeKey == 0 ? 0 : 1, end: 0),
      duration: const Duration(milliseconds: 300),
      builder: (_, t, c) {
        final dx = math.sin(t * math.pi * 4) * 8 * t;
        return Transform.translate(offset: Offset(dx, 0), child: c);
      },
      child: child,
    );
  }
}
