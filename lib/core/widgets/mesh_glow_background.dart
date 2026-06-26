/// ALOQA — signature backdrop: soft emerald radial glows on near-white.
/// RadialGradient (not blur) — MIUI-safe, cheap.
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class MeshGlowBackground extends StatelessWidget {
  const MeshGlowBackground({super.key, required this.child, this.compact = false});

  final Widget child;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final d = compact ? 544.0 : 640.0;
    return Container(
      color: AppColors.slate50,
      child: Stack(
        children: [
          // PRIMARY glow — top-center, brand700 @20%.
          Positioned(
            top: compact ? -210 : -240,
            left: 0,
            right: 0,
            child: Center(
              child: IgnorePointer(
                child: Container(
                  width: d,
                  height: d,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        AppColors.brand700.withOpacity(0.20),
                        AppColors.brand700.withOpacity(0.0),
                      ],
                      stops: const [0.0, 0.72],
                    ),
                  ),
                ),
              ),
            ),
          ),
          // SECONDARY accent — bottom-left, brand400 @10%.
          Positioned(
            bottom: -180,
            left: -120,
            child: IgnorePointer(
              child: Container(
                width: 460,
                height: 460,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.brand400.withOpacity(0.10),
                      AppColors.brand400.withOpacity(0.0),
                    ],
                    stops: const [0.0, 0.70],
                  ),
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}
