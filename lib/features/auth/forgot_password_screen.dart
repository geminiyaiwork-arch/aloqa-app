/// ALOQA — parolni tiklash (PUBLIC, gradient-mesh, web-mos stub).
///
/// Eslatma: bu ekran web bilan bir xil STUB — haqiqiy API chaqiruvi yo'q.
/// Yuborilgandan keyin "agar email ro'yxatdan o'tgan bo'lsa..." xabari ko'rsatiladi.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:aloqa/core/i18n/i18n_service.dart';
import 'package:aloqa/core/theme/app_theme.dart';
import 'package:aloqa/core/widgets/aloqa_card.dart';
import 'package:aloqa/core/widgets/aloqa_input.dart';
import 'package:aloqa/core/widgets/aloqa_logo.dart';
import 'package:aloqa/core/widgets/error_banner.dart';
import 'package:aloqa/core/widgets/gradient_button.dart';
import 'package:aloqa/core/widgets/mesh_glow_background.dart';
import 'package:aloqa/core/widgets/reveal.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _email = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _sent = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    if (email.isEmpty) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      // STUB — web bilan bir xil: haqiqiy so'rov yuborilmaydi.
      await Future<void>.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;
      setState(() {
        _sent = true;
        _busy = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = ref.tt('common.error');
      });
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(ref.tt('common.error'))));
    }
  }

  @override
  Widget build(BuildContext context) {
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
                        child: _sent ? _buildSent() : _buildForm(),
                      ),
                    ),
                    const SizedBox(height: 18),
                    if (!_sent)
                      RevealUp(
                        delayMs: 140,
                        child: Center(
                          child: TextButton.icon(
                            onPressed: _busy ? null : () => context.go('/login'),
                            icon: const Icon(Icons.arrow_back, size: 18, color: AppColors.brand600),
                            label: Text(
                              ref.t('mobile.forgot.backToLogin'),
                              style: const TextStyle(
                                color: AppColors.brand600,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
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

  // ── FORM (yuborilmagan holat) ──────────────────────────────────────────────
  Widget _buildForm() {
    return Form(
      key: _formKey,
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
          const SizedBox(height: 8),
          Center(
            child: Text(
              ref.t('mobile.forgot.subtitle'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: AppColors.slate500, height: 1.4),
            ),
          ),
          const SizedBox(height: 22),
          AloqaInput(
            controller: _email,
            label: ref.t('auth.email'),
            hint: ref.t('mobile.login.emailHint'),
            prefixIcon: Icons.mail_outline,
            keyboardType: TextInputType.emailAddress,
            validator: (v) => (v == null || !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim()))
                ? ref.tt('mobile.validation.emailInvalid')
                : null,
          ),
          const SizedBox(height: 12),
          InlineErrorBanner(message: _error),
          if (_error != null && _error!.isNotEmpty) const SizedBox(height: 12),
          GradientButton(
            label: ref.t('mobile.forgot.submit'),
            icon: Icons.send_outlined,
            busy: _busy,
            onPressed: _busy ? null : _submit,
          ),
        ],
      ),
    );
  }

  // ── SENT (yuborilgan holat) ─────────────────────────────────────────────────
  Widget _buildSent() {
    final email = _email.text.trim();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.brand50,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.brand200),
            ),
            alignment: Alignment.center,
            child: const Text('📧', style: TextStyle(fontSize: 34)),
          ),
        ),
        const SizedBox(height: 18),
        Center(
          child: Text(
            ref.t('mobile.forgot.sentTitle'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.slate900,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: Text.rich(
            TextSpan(
              style: const TextStyle(fontSize: 14, color: AppColors.slate600, height: 1.5),
              children: [
                TextSpan(text: ref.t('mobile.forgot.sentPrefix')),
                TextSpan(
                  text: email.isEmpty ? ref.t('mobile.forgot.sentEmailFallback') : email,
                  style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.slate900),
                ),
                TextSpan(
                  text: ref.t('mobile.forgot.sentSuffix'),
                ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 24),
        GradientButton(
          label: ref.t('action.login'),
          icon: Icons.login_outlined,
          onPressed: () => context.go('/login'),
        ),
      ],
    );
  }
}
