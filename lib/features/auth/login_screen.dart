/// ALOQA — kirish (gradient-mesh, web-mos).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/i18n_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/aloqa_input.dart';
import '../../core/widgets/aloqa_logo.dart';
import '../../core/widgets/error_banner.dart';
import '../../core/widgets/ghost_button.dart';
import '../../core/widgets/gradient_button.dart';
import '../../core/widgets/mesh_glow_background.dart';
import '../../core/widgets/reveal.dart';
import 'auth_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() ?? false) {
      ref.read(authProvider.notifier).loginWithEmail(_email.text.trim(), _password.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);

    return Scaffold(
      body: MeshGlowBackground(
        compact: true,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const RevealUp(delayMs: 0, child: Center(child: AloqaLogo(size: 64, showWordmark: true))),
                      const SizedBox(height: 20),
                      RevealUp(
                        delayMs: 60,
                        child: Text(ref.t('auth.login.title'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.slate900)),
                      ),
                      const SizedBox(height: 6),
                      RevealUp(
                        delayMs: 100,
                        child: Text(ref.t('auth.login.subtitle'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 14, color: AppColors.slate500)),
                      ),
                      const SizedBox(height: 24),
                      RevealUp(
                        delayMs: 140,
                        child: GhostButton(
                          label: ref.t('auth.google'),
                          leading: const GoogleMark(),
                          onPressed: auth.busy ? null : () => ref.read(authProvider.notifier).loginWithGoogle(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const _OrDivider(),
                      const SizedBox(height: 16),
                      RevealUp(
                        delayMs: 180,
                        child: AloqaInput(
                          controller: _email,
                          label: ref.t('auth.email'),
                          hint: ref.t('mobile.login.emailHint'),
                          prefixIcon: Icons.mail_outline,
                          keyboardType: TextInputType.emailAddress,
                          validator: (v) => (v == null || !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v))
                              ? ref.tt('mobile.validation.emailInvalid')
                              : null,
                        ),
                      ),
                      const SizedBox(height: 14),
                      RevealUp(
                        delayMs: 220,
                        child: AloqaInput(
                          controller: _password,
                          label: ref.t('auth.password'),
                          hint: ref.t('mobile.login.passwordHint'),
                          prefixIcon: Icons.lock_outline,
                          obscureText: _obscure,
                          suffixIcon: IconButton(
                            icon: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 150),
                              child: Icon(
                                _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                key: ValueKey(_obscure),
                                color: AppColors.slate400,
                                size: 20,
                              ),
                            ),
                            onPressed: () => setState(() => _obscure = !_obscure),
                          ),
                          validator: (v) => (v == null || v.length < 6) ? ref.tt('mobile.validation.passwordMin') : null,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () {
                            ScaffoldMessenger.of(context)
                              ..clearSnackBars()
                              ..showSnackBar(SnackBar(content: Text(ref.tt('common.soon'))));
                          },
                          child: Text(ref.t('auth.forgot'),
                              style: const TextStyle(fontSize: 13, color: AppColors.brand600, fontWeight: FontWeight.w500)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      InlineErrorBanner(
                          message:
                              auth.error == null ? null : ref.t(auth.error!)),
                      const SizedBox(height: 12),
                      GradientButton(label: ref.t('action.login'), busy: auth.busy, onPressed: _submit),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(ref.t('auth.noAccount'), style: const TextStyle(color: AppColors.slate500)),
                          GestureDetector(
                            onTap: () => context.go('/register'),
                            child: Text(ref.t('action.register'),
                                style: const TextStyle(color: AppColors.brand600, fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OrDivider extends ConsumerWidget {
  const _OrDivider();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(children: [
      const Expanded(child: Divider(color: AppColors.slate200)),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text(ref.t('auth.or'), style: const TextStyle(color: AppColors.slate400, fontSize: 12)),
      ),
      const Expanded(child: Divider(color: AppColors.slate200)),
    ]);
  }
}
