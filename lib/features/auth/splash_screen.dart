/// ALOQA — splash (M1). Shows logo while auth + i18n bootstrap, then routes.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/i18n_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/aloqa_logo.dart';
import 'auth_provider.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  Future<void> _boot() async {
    // Kick off i18n OTA refresh and auth restore in parallel.
    await Future.wait([
      ref.read(i18nProvider.notifier).init(),
      ref.read(authProvider.notifier).bootstrap(),
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
    return const Scaffold(
      backgroundColor: AppColors.brandIndigo,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AloqaLogo(size: 120),
            SizedBox(height: 24),
            Text('ALOQA',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2)),
            SizedBox(height: 28),
            SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                  strokeWidth: 2.4, color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}
