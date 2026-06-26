/// ALOQA — kirish (gradient-mesh, web-mos).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
                      const RevealUp(
                        delayMs: 60,
                        child: Text('Xush kelibsiz',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.slate900)),
                      ),
                      const SizedBox(height: 6),
                      const RevealUp(
                        delayMs: 100,
                        child: Text('Hisobingizga kiring',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 14, color: AppColors.slate500)),
                      ),
                      const SizedBox(height: 24),
                      RevealUp(
                        delayMs: 140,
                        child: GhostButton(
                          label: 'Google bilan kirish',
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
                          label: 'Email',
                          hint: 'siz@example.com',
                          prefixIcon: Icons.mail_outline,
                          keyboardType: TextInputType.emailAddress,
                          validator: (v) => (v == null || !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v))
                              ? 'Email noto\'g\'ri'
                              : null,
                        ),
                      ),
                      const SizedBox(height: 14),
                      RevealUp(
                        delayMs: 220,
                        child: AloqaInput(
                          controller: _password,
                          label: 'Parol',
                          hint: '••••••••',
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
                          validator: (v) => (v == null || v.length < 6) ? 'Parol kamida 6 ta belgi' : null,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () {
                            ScaffoldMessenger.of(context)
                              ..clearSnackBars()
                              ..showSnackBar(const SnackBar(content: Text('Tez kunda')));
                          },
                          child: const Text('Parolni unutdingizmi?',
                              style: TextStyle(fontSize: 13, color: AppColors.brand600, fontWeight: FontWeight.w500)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      InlineErrorBanner(message: auth.error),
                      const SizedBox(height: 12),
                      GradientButton(label: 'Kirish', busy: auth.busy, onPressed: _submit),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('Hisobingiz yo\'qmi? ', style: TextStyle(color: AppColors.slate500)),
                          GestureDetector(
                            onTap: () => context.go('/register'),
                            child: const Text('Ro\'yxatdan o\'tish',
                                style: TextStyle(color: AppColors.brand600, fontWeight: FontWeight.w600)),
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

class _OrDivider extends StatelessWidget {
  const _OrDivider();
  @override
  Widget build(BuildContext context) {
    return const Row(children: [
      Expanded(child: Divider(color: AppColors.slate200)),
      Padding(
        padding: EdgeInsets.symmetric(horizontal: 12),
        child: Text('yoki', style: TextStyle(color: AppColors.slate400, fontSize: 12)),
      ),
      Expanded(child: Divider(color: AppColors.slate200)),
    ]);
  }
}
