/// ALOQA — ro'yxatdan o'tish (gradient-mesh, web-mos).
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
import '../../core/widgets/shake.dart';
import 'auth_provider.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscure = true;
  bool _agree = false;
  int _termsShake = 0;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  int _strength() {
    final p = _password.text;
    var s = 0;
    if (p.length >= 6) s++;
    if (RegExp(r'\d').hasMatch(p)) s++;
    if (p.length >= 8 && RegExp(r'[A-Z]').hasMatch(p) && RegExp(r'[a-z]').hasMatch(p)) s++;
    return s;
  }

  void _submit() {
    if (!_agree) {
      setState(() => _termsShake++);
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('Shartlarga rozilik bering')));
      return;
    }
    if (_formKey.currentState?.validate() ?? false) {
      ref.read(authProvider.notifier).register(
            _name.text.trim(), _email.text.trim(), _password.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final s = _strength();
    final strengthColor = s <= 1 ? AppColors.danger : (s == 2 ? AppColors.brand400 : AppColors.brand600);
    final strengthLabel = s <= 1 ? 'Zaif' : (s == 2 ? 'O\'rtacha' : 'Kuchli');
    final strengthFrac = _password.text.isEmpty ? 0.0 : (s <= 1 ? 0.33 : (s == 2 ? 0.66 : 1.0));

    return Scaffold(
      body: MeshGlowBackground(
        compact: true,
        child: SafeArea(
          child: Stack(
            children: [
              Positioned(
                left: 4,
                top: 4,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_rounded, color: AppColors.slate600),
                  onPressed: () => context.go('/login'),
                ),
              ),
              Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 56, 24, 24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const RevealUp(delayMs: 0, child: Center(child: AloqaLogo(size: 56, showWordmark: true))),
                          const SizedBox(height: 18),
                          const RevealUp(
                            delayMs: 60,
                            child: Text('Hisob yarating',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.slate900)),
                          ),
                          const SizedBox(height: 6),
                          const RevealUp(
                            delayMs: 100,
                            child: Text('ALOQA\'ga bir daqiqada qo\'shiling',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 14, color: AppColors.slate500)),
                          ),
                          const SizedBox(height: 22),
                          RevealUp(
                            delayMs: 140,
                            child: GhostButton(
                              label: 'Google bilan ro\'yxatdan o\'tish',
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
                              controller: _name,
                              label: 'To\'liq ism',
                              hint: 'Ismingiz',
                              prefixIcon: Icons.person_outline,
                              textCapitalization: TextCapitalization.words,
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) return 'Ismingizni kiriting';
                                if (v.trim().length < 2) return 'Ism juda qisqa';
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(height: 14),
                          RevealUp(
                            delayMs: 220,
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
                            delayMs: 260,
                            child: AloqaInput(
                              controller: _password,
                              label: 'Parol',
                              hint: 'Kamida 6 ta belgi',
                              prefixIcon: Icons.lock_outline,
                              obscureText: _obscure,
                              onChanged: (_) => setState(() {}),
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
                          const SizedBox(height: 10),
                          // strength
                          Row(
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(2),
                                  child: Container(
                                    height: 4,
                                    color: AppColors.slate200,
                                    alignment: Alignment.centerLeft,
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 300),
                                      height: 4,
                                      width: MediaQuery.of(context).size.width * strengthFrac,
                                      color: strengthColor,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(_password.text.isEmpty ? '' : strengthLabel,
                                  style: TextStyle(fontSize: 11, color: strengthColor, fontWeight: FontWeight.w500)),
                            ],
                          ),
                          const SizedBox(height: 14),
                          // terms
                          Shake(
                            shakeKey: _termsShake,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: Checkbox(
                                    value: _agree,
                                    activeColor: AppColors.brand600,
                                    onChanged: (v) => setState(() => _agree = v ?? false),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Expanded(
                                  child: Padding(
                                    padding: EdgeInsets.only(top: 2),
                                    child: Text.rich(
                                      TextSpan(
                                        style: TextStyle(fontSize: 12, color: AppColors.slate500),
                                        children: [
                                          TextSpan(text: 'Men '),
                                          TextSpan(text: 'Foydalanish shartlari', style: TextStyle(color: AppColors.brand600, fontWeight: FontWeight.w500)),
                                          TextSpan(text: ' va '),
                                          TextSpan(text: 'Maxfiylik siyosati', style: TextStyle(color: AppColors.brand600, fontWeight: FontWeight.w500)),
                                          TextSpan(text: 'ga roziman'),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          InlineErrorBanner(message: auth.error),
                          const SizedBox(height: 12),
                          GradientButton(
                            label: 'Ro\'yxatdan o\'tish',
                            busy: auth.busy,
                            onPressed: _submit,
                          ),
                          const SizedBox(height: 18),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text('Hisobingiz bormi? ', style: TextStyle(color: AppColors.slate500)),
                              GestureDetector(
                                onTap: () => context.go('/login'),
                                child: const Text('Kirish',
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
            ],
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
