/// ALOQA — animated video-call illustration (onboarding page 1). Built-ins only.
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class HeroCallCard extends StatefulWidget {
  const HeroCallCard({super.key, this.width = 300});
  final double width;

  @override
  State<HeroCallCard> createState() => _HeroCallCardState();
}

class _HeroCallCardState extends State<HeroCallCard>
    with TickerProviderStateMixin {
  late final AnimationController _float;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _float = AnimationController(vsync: this, duration: const Duration(seconds: 4))
      ..repeat(reverse: true);
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _float.dispose();
    _pulse.dispose();
    super.dispose();
  }

  static const _tiles = [
    ['🧑‍💻', 0xFFD1FAE5, 0xFFA7F3D0, true],
    ['👩', 0xFFFEF3C7, 0xFFFDE68A, false],
    ['🧑', 0xFFFFE4E6, 0xFFFECDD3, false],
    ['👨', 0xFFE0F2FE, 0xFFBAE6FD, true],
  ];

  Widget _tile(List t) {
    return AspectRatio(
      aspectRatio: 4 / 3,
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(t[1] as int), Color(t[2] as int)],
              ),
            ),
            alignment: Alignment.center,
            child: Text(t[0] as String, style: const TextStyle(fontSize: 30)),
          ),
          if (t[3] == true)
            const Positioned(right: 4, top: 2, child: Text('✋', style: TextStyle(fontSize: 14))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      child: AnimatedBuilder(
        animation: _float,
        builder: (_, child) => Transform.translate(
          offset: Offset(0, -6 * Curves.easeInOut.transform(_float.value)),
          child: child,
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // glow blob behind
            Positioned(
              left: -8,
              right: -8,
              top: -8,
              bottom: -8,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(48),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.brand100, AppColors.brand50],
                  ),
                ),
              ),
            ),
            Column(
              children: [
                // laptop frame
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22.4),
                    border: Border.all(color: AppColors.slate200),
                    boxShadow: const [
                      BoxShadow(
                          color: Color(0x40000000),
                          blurRadius: 50,
                          spreadRadius: -12,
                          offset: Offset(0, 25)),
                    ],
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Row(children: [
                          Expanded(child: _tile(_tiles[0])),
                          const SizedBox(width: 8),
                          Expanded(child: _tile(_tiles[1])),
                        ]),
                        const SizedBox(height: 8),
                        Row(children: [
                          Expanded(child: _tile(_tiles[2])),
                          const SizedBox(width: 8),
                          Expanded(child: _tile(_tiles[3])),
                        ]),
                        const SizedBox(height: 8),
                        // control bar
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.slate900.withOpacity(0.70),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.mic_rounded, size: 16, color: Colors.white.withOpacity(0.8)),
                              const SizedBox(width: 12),
                              Icon(Icons.videocam_rounded, size: 16, color: Colors.white.withOpacity(0.8)),
                              const SizedBox(width: 12),
                              Icon(Icons.chat_bubble_rounded, size: 16, color: Colors.white.withOpacity(0.8)),
                              const SizedBox(width: 12),
                              Icon(Icons.people_rounded, size: 16, color: Colors.white.withOpacity(0.8)),
                              const SizedBox(width: 12),
                              Container(
                                width: 24,
                                height: 24,
                                alignment: Alignment.center,
                                decoration: const BoxDecoration(
                                    color: Color(0xFFEF4444), shape: BoxShape.circle),
                                child: const Icon(Icons.call_end_rounded, size: 14, color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // laptop base
                Container(
                  height: 10,
                  width: widget.width * 0.62,
                  decoration: const BoxDecoration(
                    borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
                    gradient: LinearGradient(colors: [Color(0xFFCBD5E1), Color(0xFFE2E8F0)]),
                  ),
                ),
              ],
            ),
            // floating badges
            _badge(left: -16, top: 56, icon: Icons.videocam_rounded, pulse: true),
            _badge(right: -12, top: 8, icon: Icons.chat_bubble_rounded, pulse: false),
            _badge(right: -20, bottom: 40, icon: Icons.calendar_today_rounded, pulse: true),
          ],
        ),
      ),
    );
  }

  Widget _badge({double? left, double? right, double? top, double? bottom, required IconData icon, required bool pulse}) {
    final card = Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.slate100),
        boxShadow: const [
          BoxShadow(color: Color(0x1A000000), blurRadius: 15, spreadRadius: -3, offset: Offset(0, 10)),
          BoxShadow(color: Color(0x1A000000), blurRadius: 6, spreadRadius: -4, offset: Offset(0, 4)),
        ],
      ),
      child: Icon(icon, size: 24, color: AppColors.brand600),
    );
    final w = pulse
        ? AnimatedBuilder(
            animation: _pulse,
            builder: (_, child) => Opacity(opacity: 0.55 + 0.45 * _pulse.value, child: child),
            child: card,
          )
        : card;
    return Positioned(left: left, right: right, top: top, bottom: bottom, child: w);
  }
}
