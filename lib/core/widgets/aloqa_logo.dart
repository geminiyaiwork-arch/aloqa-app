/// ALOQA — bundled logo widget (header/login/lobby/splash).
library;

import 'package:flutter/material.dart';

class AloqaLogo extends StatelessWidget {
  const AloqaLogo({super.key, this.size = 96, this.rounded = true});

  final double size;
  final bool rounded;

  @override
  Widget build(BuildContext context) {
    final img = Image.asset(
      'assets/images/logo.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => Icon(Icons.videocam_rounded,
          size: size * 0.7, color: Theme.of(context).colorScheme.primary),
    );
    if (!rounded) return img;
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.22),
      child: img,
    );
  }
}
