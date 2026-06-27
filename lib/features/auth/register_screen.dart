/// ALOQA — ro'yxatdan o'tish (gradient-mesh, web-mos).
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
        ..showSnackBar(SnackBar(content: Text(ref.tt('mobile.register.agreeRequired'))));
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
    final strengthLabel = s <= 1
        ? ref.t('mobile.strength.weak')
        : (s == 2 ? ref.t('mobile.strength.medium') : ref.t('mobile.strength.strong'));
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
                          RevealUp(
                            delayMs: 60,
                            child: Text(ref.t('auth.register.title'),
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.slate900)),
                          ),
                          const SizedBox(height: 6),
                          RevealUp(
                            delayMs: 100,
                            child: Text(ref.t('mobile.register.subtitle'),
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 14, color: AppColors.slate500)),
                          ),
                          const SizedBox(height: 22),
                          RevealUp(
                            delayMs: 140,
                            child: GhostButton(
                              label: ref.t('mobile.register.googleSignup'),
                              leading: const GoogleMark(),
                              onPressed: auth.busy ? null : () => ref.read(authProvider.notifier).loginWithGoogle(),
                            ),
                          ),
                          const SizedBox(height: 16),
                          _OrDivider(ref: ref),
                          const SizedBox(height: 16),
                          RevealUp(
                            delayMs: 180,
                            child: AloqaInput(
                              controller: _name,
                              label: ref.t('auth.name'),
                              hint: ref.t('mobile.register.nameHint'),
                              prefixIcon: Icons.person_outline,
                              textCapitalization: TextCapitalization.words,
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) return ref.tt('mobile.validation.nameRequired');
                                if (v.trim().length < 2) return ref.tt('mobile.validation.nameShort');
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(height: 14),
                          RevealUp(
                            delayMs: 220,
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
                            delayMs: 260,
                            child: AloqaInput(
                              controller: _password,
                              label: ref.t('auth.password'),
                              hint: ref.t('mobile.register.passwordHint'),
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
                              validator: (v) => (v == null || v.length < 6) ? ref.tt('mobile.validation.passwordMin') : null,
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
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text.rich(
                                      TextSpan(
                                        style: const TextStyle(fontSize: 12, color: AppColors.slate500),
                                        children: [
                                          TextSpan(text: ref.t('mobile.register.agreePrefix')),
                                          TextSpan(text: ref.t('mobile.register.terms'), style: const TextStyle(color: AppColors.brand600, fontWeight: FontWeight.w500)),
                                          TextSpan(text: ref.t('mobile.register.and')),
                                          TextSpan(text: ref.t('mobile.register.privacy'), style: const TextStyle(color: AppColors.brand600, fontWeight: FontWeight.w500)),
                                          TextSpan(text: ref.t('mobile.register.agreeSuffix')),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          InlineErrorBanner(
                              message: auth.error == null
                                  ? null
                                  : ref.t(auth.error!)),
                          const SizedBox(height: 12),
                          GradientButton(
                            label: ref.t('action.register'),
                            busy: auth.busy,
                            onPressed: _submit,
                          ),
                          const SizedBox(height: 18),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(ref.t('auth.haveAccount'), style: const TextStyle(color: AppColors.slate500)),
                              GestureDetector(
                                onTap: () => context.go('/login'),
                                child: Text(ref.t('action.login'),
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
            ],
          ),
        ),
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider({required this.ref});
  final WidgetRef ref;
  @override
  Widget build(BuildContext context) {
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
