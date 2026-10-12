/// ALOQA — parolni tiklash (PUBLIC, gradient-mesh).
///
/// Serverda parolni email orqali tiklash endpointi YO'Q. Shuning uchun bu ekran
/// soxta "havola yuborildi" demaydi: holatni ochiq aytadi va haqiqiy yo'llarni
/// ko'rsatadi — Google orqali kirish (akkaunt bog'langan bo'lsa) yoki
/// qo'llab-quvvatlash xizmati.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:aloqa/core/i18n/i18n_service.dart';
import 'package:aloqa/core/theme/app_theme.dart';
import 'package:aloqa/core/widgets/aloqa_card.dart';
import 'package:aloqa/core/widgets/aloqa_logo.dart';
import 'package:aloqa/core/widgets/error_banner.dart';
import 'package:aloqa/core/widgets/ghost_button.dart';
import 'package:aloqa/core/widgets/gradient_button.dart';
import 'package:aloqa/core/widgets/mesh_glow_background.dart';
import 'package:aloqa/core/widgets/reveal.dart';
import 'package:aloqa/features/auth/auth_provider.dart';

class ForgotPasswordScreen extends ConsumerWidget {
  const ForgotPasswordScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final rawError = auth.error;
    // Auth xatosi i18n kaliti yoki server matni bo'lishi mumkin (login ekrani kabi:
    // kalit topilmasa matnning o'zi qaytadi).
    final error =
        (rawError == null || rawError.isEmpty) ? null : ref.t(rawError);

    return Scaffold(
      body: MeshGlowBackground(
        compact: true,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const RevealUp(
                      delayMs: 0,
                      child: Center(child: AloqaLogo(size: 64, showWordmark: true)),
                    ),
                    const SizedBox(height: 20),
                    RevealUp(
                      delayMs: 60,
                      child: AloqaCard(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Center(
                              child: Text(
                                ref.t('mobile.forgot.title'),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.slate900,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              ref.t('mobile.forgot.unavailable'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  fontSize: 14,
                                  color: AppColors.slate600,
                                  height: 1.5),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              googleSignInAvailable
                                  ? ref.t('mobile.forgot.googleHint')
                                  : ref.t('mobile.forgot.supportHint'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  fontSize: 14,
                                  color: AppColors.slate500,
                                  height: 1.5),
                            ),
                            const SizedBox(height: 18),
                            InlineErrorBanner(message: error),
                            if (error != null) const SizedBox(height: 12),
                            if (googleSignInAvailable) ...[
                              GhostButton(
                                label: ref.t('auth.google'),
                                leading: const GoogleMark(),
                                onPressed: auth.busy
                                    ? null
                                    : () => ref
                                        .read(authProvider.notifier)
                                        .loginWithGoogle(),
                              ),
                              const SizedBox(height: 12),
                            ],
                            GradientButton(
                              label: ref.t('mobile.forgot.backToLogin'),
                              icon: Icons.login_outlined,
                              onPressed: () => context.go('/login'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
