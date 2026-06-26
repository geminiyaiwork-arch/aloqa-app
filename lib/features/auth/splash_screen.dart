/// ALOQA — splash (M1). Emerald gradient + reveal while auth/i18n bootstrap.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/i18n_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/aloqa_logo.dart';
import '../contacts/contacts_service.dart';
import 'auth_provider.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..forward();
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    // Silently warm the local contacts (no prompt) so conference tiles can show
    // saved names. No-op unless the user already enabled contacts.
    ContactsStore.instance.bootstrap();
    await Future.wait([
      ref.read(i18nProvider.notifier).init(),
      ref.read(authProvider.notifier).bootstrap(),
      Future<void>.delayed(const Duration(milliseconds: 1200)),
    ]);
    if (!mounted) return;
    final status = ref.read(authProvider).status;
    if (status == AuthStatus.authenticated) {
      context.go('/home');
    } else {
      context.go('/onboarding');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.brand600, AppColors.brand700],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // badge: scale 0.82->1 easeOutBack + fade
              AnimatedBuilder(
                animation: _c,
                builder: (_, __) {
                  final t = Curves.easeOutBack.transform(_c.value.clamp(0.0, 1.0));
                  final f = (_c.value / 0.4).clamp(0.0, 1.0);
                  return Opacity(
                    opacity: f,
                    child: Transform.scale(scale: 0.82 + 0.18 * t, child: const AloqaLogo(size: 96, onDark: true)),
                  );
                },
              ),
              const SizedBox(height: 24),
              // wordmark: slide-up + fade in 0.25..0.75
              AnimatedBuilder(
                animation: _c,
                builder: (_, __) {
                  final p = ((_c.value - 0.25) / 0.5).clamp(0.0, 1.0);
                  return Opacity(
                    opacity: p,
                    child: Transform.translate(
                      offset: Offset(0, (1 - p) * 12),
                      child: const Text('ALOQA',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5)),
                    ),
                  );
                },
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white.withOpacity(0.7)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
