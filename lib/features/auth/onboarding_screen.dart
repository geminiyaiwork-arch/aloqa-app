/// ALOQA — onboarding (3-page, gradient-mesh, web-mos).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/i18n_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/floating_node_motif.dart';
import '../../core/widgets/gradient_button.dart';
import '../../core/widgets/hero_call_card.dart';
import '../../core/widgets/mesh_glow_background.dart';
import '../../core/widgets/reveal.dart';

class _Page {
  const _Page(this.titleKey, this.subKey);
  final String titleKey;
  final String subKey;
}

const _pages = [
  _Page('mobile.onboarding.p1.title', 'mobile.onboarding.p1.sub'),
  _Page('mobile.onboarding.p2.title', 'mobile.onboarding.p2.sub'),
  _Page('mobile.onboarding.p3.title', 'mobile.onboarding.p3.sub'),
];

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_index >= _pages.length - 1) {
      context.go('/login');
    } else {
      _controller.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    }
  }

  Widget _illustration(int i) {
    if (i == 0) {
      return LayoutBuilder(
        builder: (_, c) => HeroCallCard(width: (c.maxWidth * 0.82).clamp(220.0, 300.0)),
      );
    }
    return FloatingNodeMotif(size: 220, seed: i);
  }

  @override
  Widget build(BuildContext context) {
    final last = _index == _pages.length - 1;
    return Scaffold(
      body: MeshGlowBackground(
        compact: false,
        child: SafeArea(
          child: Column(
            children: [
              // skip
              SizedBox(
                height: 48,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (!last)
                      TextButton(
                        onPressed: () => context.go('/login'),
                        child: Text(ref.t('mobile.onboarding.skip'),
                            style: const TextStyle(color: AppColors.slate500, fontSize: 14, fontWeight: FontWeight.w500)),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: _pages.length,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (_, i) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(height: 260, child: Center(child: _illustration(i))),
                        const SizedBox(height: 36),
                        RevealUp(
                          key: ValueKey('h$_index'),
                          durationMs: 420,
                          child: Column(
                            children: [
                              Text(ref.t(_pages[i].titleKey),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.slate900, letterSpacing: -0.5)),
                              const SizedBox(height: 14),
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 320),
                                child: Text(ref.t(_pages[i].subKey),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(fontSize: 16, color: AppColors.slate500, height: 1.5)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // dots
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_pages.length, (i) {
                  final active = i == _index;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOut,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    height: 8,
                    width: active ? 24 : 8,
                    decoration: BoxDecoration(
                      color: active ? AppColors.brand600 : AppColors.slate300,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: GradientButton(
                  label: last ? ref.t('landing.cta.start') : ref.t('action.continue'),
                  icon: last ? null : Icons.arrow_forward_rounded,
                  onPressed: _next,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(ref.t('auth.noAccount'), style: const TextStyle(color: AppColors.slate500, fontSize: 14)),
                  GestureDetector(
                    onTap: () => context.go('/register'),
                    child: Text(ref.t('action.register'),
                        style: const TextStyle(color: AppColors.brand600, fontWeight: FontWeight.w600, fontSize: 14)),
                  ),
                ],
              ),
              const SizedBox(height: 14),
            ],
          ),
        ),
      ),
    );
  }
}
