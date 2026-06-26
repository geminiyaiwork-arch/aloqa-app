/// ALOQA — Settings (redesign): personal info, password, language, sessions.
/// Web parity: /app/settings.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:aloqa/core/i18n/i18n_service.dart';
import 'package:aloqa/core/services/profile_repository.dart';
import 'package:aloqa/core/theme/app_theme.dart';
import 'package:aloqa/core/widgets/aloqa_card.dart';
import 'package:aloqa/core/widgets/aloqa_input.dart';
import 'package:aloqa/core/widgets/app_shell.dart';
import 'package:aloqa/core/widgets/error_banner.dart';
import 'package:aloqa/core/widgets/gradient_button.dart';
import 'package:aloqa/core/widgets/reveal.dart';
import 'package:aloqa/features/auth/auth_provider.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  // Personal info controllers.
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _birthday = TextEditingController();
  String? _gender; // 'male' | 'female' | null

  // Password controllers.
  final _currentPw = TextEditingController();
  final _newPw = TextEditingController();
  final _confirmPw = TextEditingController();
  bool _showCurrent = false;
  bool _showNew = false;
  bool _showConfirm = false;

  bool _loading = true;
  bool _savingPersonal = false;
  bool _savingPassword = false;
  bool _switchingLang = false;

  String? _loadError;
  String? _personalError;
  String? _passwordError;
  String _personalNote = '';
  String _passwordNote = '';

  // Locally-tracked has_password (refreshed via /me on mount, set after change).
  bool _hasPassword = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _birthday.dispose();
    _currentPw.dispose();
    _newPw.dispose();
    _confirmPw.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      // Refresh has_password + personal fields from the server.
      final fresh = await ProfileRepository.instance.me();
      if (!mounted) return;
      ref.read(authProvider.notifier).setUser(fresh);
      _firstName.text = fresh.firstName ?? '';
      _lastName.text = fresh.lastName ?? '';
      _birthday.text = fresh.birthday ?? '';
      _gender = (fresh.gender == 'male' || fresh.gender == 'female')
          ? fresh.gender
          : null;
      _hasPassword = fresh.hasPassword;
      // Warm up the sessions list.
      ref.invalidate(sessionsProvider);
      setState(() => _loading = false);
    } catch (_) {
      // Fall back to the cached auth user so the form still renders.
      final cached = ref.read(authProvider).user;
      if (cached != null) {
        _firstName.text = cached.firstName ?? '';
        _lastName.text = cached.lastName ?? '';
        _birthday.text = cached.birthday ?? '';
        _gender = (cached.gender == 'male' || cached.gender == 'female')
            ? cached.gender
            : null;
        _hasPassword = cached.hasPassword;
      }
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = cached == null ? ref.tt('common.error') : null;
      });
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  void _transient(void Function(String) setter, String text, Duration d) {
    setter(text);
    Future.delayed(d, () {
      if (!mounted) return;
      setter('');
    });
  }

  // ─── Section 1: personal info ─────────────────────────────────────────────
  Future<void> _savePersonal() async {
    if (_savingPersonal) return;
    setState(() {
      _savingPersonal = true;
      _personalError = null;
    });
    final bday = _birthday.text.trim();
    final body = <String, dynamic>{
      'first_name': _firstName.text.trim(),
      'last_name': _lastName.text.trim(),
      if (_gender != null) 'gender': _gender,
      'birthday': bday.isEmpty ? null : bday,
    };
    try {
      final updated = await ProfileRepository.instance.updateMe(body);
      if (!mounted) return;
      ref.read(authProvider.notifier).setUser(updated);
      setState(() => _savingPersonal = false);
      _transient((v) => setState(() => _personalNote = v), ref.tt('mobile.settings.savedNote'),
          const Duration(milliseconds: 2500));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _savingPersonal = false;
        _personalError = ref.tt('common.error');
      });
      _snack(ref.tt('common.error'));
    }
  }

  // ─── Section 2: password ──────────────────────────────────────────────────
  Future<void> _savePassword() async {
    if (_savingPassword) return;
    setState(() => _passwordError = null);

    final cur = _currentPw.text;
    final next = _newPw.text;
    final confirm = _confirmPw.text;

    // Client validation BEFORE the call.
    if (next.length < 8) {
      setState(() => _passwordError = ref.tt('mobile.validation.newPasswordMin'));
      return;
    }
    if (next != confirm) {
      setState(() => _passwordError = ref.tt('mobile.validation.passwordMismatch'));
      return;
    }

    setState(() => _savingPassword = true);
    try {
      await ProfileRepository.instance.changePassword(
        currentPassword: _hasPassword ? cur : null,
        newPassword: next,
        confirm: confirm,
      );
      if (!mounted) return;
      _currentPw.clear();
      _newPw.clear();
      _confirmPw.clear();
      setState(() {
        _savingPassword = false;
        _hasPassword = true;
      });
      _transient((v) => setState(() => _passwordNote = v), ref.tt('mobile.settings.passwordUpdatedNote'),
          const Duration(seconds: 3));
    } on DioException catch (e) {
      if (!mounted) return;
      final data = e.response?.data;
      final msg = (data is Map && data['message'] != null)
          ? data['message'].toString()
          : ref.tt('mobile.settings.passwordChangeFailed');
      setState(() {
        _savingPassword = false;
        _passwordError = msg;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _savingPassword = false;
        _passwordError = ref.tt('mobile.settings.passwordChangeFailed');
      });
    }
  }

  // ─── Section 3: language ──────────────────────────────────────────────────
  Future<void> _pickLanguage(String code) async {
    if (_switchingLang) return;
    final current = ref.read(i18nProvider).selected;
    if (code == current) return;
    setState(() => _switchingLang = true);
    try {
      await ref.read(i18nProvider.notifier).setLanguage(code);
    } catch (_) {
      // Switching is best-effort; ignore.
    }
    // Persist preference; ignore server error per spec.
    try {
      final updated =
          await ProfileRepository.instance.updateMe({'locale': code});
      if (mounted) ref.read(authProvider.notifier).setUser(updated);
    } catch (_) {
      // ignore
    }
    if (mounted) setState(() => _switchingLang = false);
  }

  // ─── Section 4: sessions ──────────────────────────────────────────────────
  Future<void> _revokeSession(String id) async {
    try {
      await ProfileRepository.instance.revokeSession(id);
      if (!mounted) return;
      ref.invalidate(sessionsProvider);
    } catch (_) {
      _snack(ref.tt('common.error'));
    }
  }

  Future<void> _logout() async {
    try {
      await ref.read(authProvider.notifier).logout();
    } catch (_) {
      // logout swallows network errors internally
    }
    if (!mounted) return;
    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;

    Widget content;
    if (_loading) {
      content = const Padding(
        padding: EdgeInsets.only(top: 80),
        child: Center(
          child: CircularProgressIndicator(color: AppColors.brand600),
        ),
      );
    } else {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RevealUp(
            child: Text(
              ref.t('settings.title'),
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppColors.slate900,
              ),
            ),
          ),
          const SizedBox(height: 6),
          RevealUp(
            delayMs: 40,
            child: Text(
              ref.t('mobile.settings.subtitle'),
              style: const TextStyle(fontSize: 14, color: AppColors.slate500),
            ),
          ),
          const SizedBox(height: 20),
          if (_loadError != null) ...[
            InlineErrorBanner(message: _loadError),
            const SizedBox(height: 16),
          ],
          RevealUp(delayMs: 80, child: _personalCard()),
          const SizedBox(height: 20),
          RevealUp(delayMs: 140, child: _passwordCard(user)),
          const SizedBox(height: 20),
          RevealUp(delayMs: 200, child: _languageCard()),
          const SizedBox(height: 20),
          RevealUp(delayMs: 260, child: _sessionsCard()),
          const SizedBox(height: 24),
          RevealUp(
            delayMs: 320,
            child: SizedBox(
              width: double.infinity,
              child: _DangerGhostButton(
                label: ref.t('action.logout'),
                icon: Icons.logout_rounded,
                onPressed: _logout,
              ),
            ),
          ),
          const SizedBox(height: 40),
        ],
      );
    }

    return AloqaAppShell(
      currentPath: '/settings',
      child: SingleChildScrollView(child: content),
    );
  }

  // ── Personal card ──────────────────────────────────────────────────────────
  Widget _personalCard() {
    return AloqaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeading(ref.t('mobile.settings.personalHeading')),
          const SizedBox(height: 4),
          Text(
            ref.t('mobile.settings.personalSub'),
            style: const TextStyle(fontSize: 13, color: AppColors.slate500),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, c) {
              final twoCol = c.maxWidth >= 520;
              final firstField = AloqaInput(
                controller: _firstName,
                label: ref.t('mobile.field.firstName'),
                hint: ref.t('mobile.field.firstNameHint'),
                prefixIcon: Icons.person_outline_rounded,
                textCapitalization: TextCapitalization.words,
              );
              final lastField = AloqaInput(
                controller: _lastName,
                label: ref.t('mobile.field.lastName'),
                hint: ref.t('mobile.field.lastNameHint'),
                prefixIcon: Icons.badge_outlined,
                textCapitalization: TextCapitalization.words,
              );
              if (twoCol) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: firstField),
                    const SizedBox(width: 14),
                    Expanded(child: lastField),
                  ],
                );
              }
              return Column(
                children: [
                  firstField,
                  const SizedBox(height: 14),
                  lastField,
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          Text(
            ref.t('mobile.field.gender'),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.slate700,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _GenderToggle(
                  label: ref.t('mobile.gender.male'),
                  icon: Icons.male_rounded,
                  selected: _gender == 'male',
                  onTap: () => setState(() => _gender = 'male'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _GenderToggle(
                  label: ref.t('mobile.gender.female'),
                  icon: Icons.female_rounded,
                  selected: _gender == 'female',
                  onTap: () => setState(() => _gender = 'female'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          AloqaInput(
            controller: _birthday,
            label: ref.t('mobile.field.birthday'),
            hint: ref.t('mobile.field.birthdayHint'),
            prefixIcon: Icons.cake_outlined,
            keyboardType: TextInputType.datetime,
            suffixIcon: IconButton(
              icon: const Icon(Icons.calendar_today_rounded,
                  size: 18, color: AppColors.slate400),
              onPressed: _pickBirthday,
            ),
          ),
          const SizedBox(height: 20),
          if (_personalError != null) ...[
            InlineErrorBanner(message: _personalError),
            const SizedBox(height: 12),
          ],
          GradientButton(
            label: ref.t('action.save'),
            icon: Icons.check_rounded,
            busy: _savingPersonal,
            onPressed: _savingPersonal ? null : _savePersonal,
          ),
          if (_personalNote.isNotEmpty) ...[
            const SizedBox(height: 10),
            _SavedNote(text: _personalNote),
          ],
        ],
      ),
    );
  }

  Future<void> _pickBirthday() async {
    DateTime initial = DateTime(2000, 1, 1);
    final parsed = DateTime.tryParse(_birthday.text.trim());
    if (parsed != null) initial = parsed;
    final now = DateTime.now();
    if (initial.isAfter(now)) initial = now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1920),
      lastDate: now,
      helpText: ref.tt('mobile.settings.pickBirthday'),
    );
    if (picked == null) return;
    final m = picked.month.toString().padLeft(2, '0');
    final d = picked.day.toString().padLeft(2, '0');
    setState(() => _birthday.text = '${picked.year}-$m-$d');
  }

  // ── Password card ───────────────────────────────────────────────────────────
  Widget _passwordCard(AuthUser? user) {
    return AloqaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeading(ref.t('mobile.settings.passwordHeading')),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.slate100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.alternate_email_rounded,
                    size: 18, color: AppColors.slate500),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ref.t('mobile.settings.loginEmail'),
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.slate500),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        (user?.email ?? '').isEmpty ? '—' : user!.email,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.slate900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_hasPassword) ...[
            AloqaInput(
              controller: _currentPw,
              label: ref.t('mobile.field.currentPassword'),
              hint: ref.t('mobile.login.passwordHint'),
              prefixIcon: Icons.lock_outline_rounded,
              obscureText: !_showCurrent,
              suffixIcon: _eyeToggle(
                _showCurrent,
                () => setState(() => _showCurrent = !_showCurrent),
              ),
            ),
            const SizedBox(height: 14),
          ],
          AloqaInput(
            controller: _newPw,
            label: ref.t('mobile.field.newPassword'),
            hint: ref.t('mobile.field.newPasswordHint'),
            prefixIcon: Icons.lock_reset_rounded,
            obscureText: !_showNew,
            suffixIcon: _eyeToggle(
              _showNew,
              () => setState(() => _showNew = !_showNew),
            ),
          ),
          const SizedBox(height: 14),
          AloqaInput(
            controller: _confirmPw,
            label: ref.t('mobile.field.confirmPassword'),
            hint: ref.t('mobile.field.confirmPasswordHint'),
            prefixIcon: Icons.lock_outline_rounded,
            obscureText: !_showConfirm,
            suffixIcon: _eyeToggle(
              _showConfirm,
              () => setState(() => _showConfirm = !_showConfirm),
            ),
          ),
          const SizedBox(height: 20),
          if (_passwordError != null) ...[
            InlineErrorBanner(message: _passwordError),
            const SizedBox(height: 12),
          ],
          GradientButton(
            label: _hasPassword
                ? ref.t('mobile.settings.updatePassword')
                : ref.t('mobile.settings.setPassword'),
            icon: Icons.shield_outlined,
            busy: _savingPassword,
            onPressed: _savingPassword ? null : _savePassword,
          ),
          if (_passwordNote.isNotEmpty) ...[
            const SizedBox(height: 10),
            _SavedNote(text: _passwordNote),
          ],
        ],
      ),
    );
  }

  Widget _eyeToggle(bool visible, VoidCallback onTap) {
    return IconButton(
      icon: Icon(
        visible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
        size: 18,
        color: AppColors.slate400,
      ),
      onPressed: onTap,
    );
  }

  // ── Language card ───────────────────────────────────────────────────────────
  Widget _languageCard() {
    final i18n = ref.watch(i18nProvider);
    final languages = i18n.languages;
    final selected = i18n.selected;

    return AloqaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeading(ref.t('mobile.settings.languageHeading')),
          const SizedBox(height: 4),
          Text(
            ref.t('mobile.settings.languageSub'),
            style: const TextStyle(fontSize: 13, color: AppColors.slate500),
          ),
          const SizedBox(height: 16),
          if (languages.isEmpty)
            const Text(
              '—',
              style: TextStyle(fontSize: 14, color: AppColors.slate400),
            )
          else
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final lang in languages)
                  _LangChip(
                    label: lang.nameNative,
                    code: lang.code,
                    selected: lang.code == selected,
                    disabled: _switchingLang,
                    onTap: () => _pickLanguage(lang.code),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  // ── Sessions card ───────────────────────────────────────────────────────────
  Widget _sessionsCard() {
    final sessionsAsync = ref.watch(sessionsProvider);
    return AloqaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeading(
            ref.t('mobile.settings.sessionsHeading'),
            trailing: IconButton(
              icon: const Icon(Icons.refresh_rounded,
                  size: 18, color: AppColors.slate400),
              tooltip: ref.t('mobile.settings.sessionsRefresh'),
              onPressed: () => ref.invalidate(sessionsProvider),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            ref.t('mobile.settings.sessionsSub'),
            style: const TextStyle(fontSize: 13, color: AppColors.slate500),
          ),
          const SizedBox(height: 16),
          sessionsAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.4, color: AppColors.brand600),
                ),
              ),
            ),
            error: (_, __) =>
                InlineErrorBanner(message: ref.t('common.error')),
            data: (sessions) {
              if (sessions.isEmpty) {
                return const Text(
                  '—',
                  style: TextStyle(fontSize: 14, color: AppColors.slate400),
                );
              }
              return Column(
                children: [
                  for (var i = 0; i < sessions.length; i++) ...[
                    _SessionRow(
                      title: (sessions[i].userAgent ?? '').isEmpty
                          ? ref.t('mobile.settings.deviceFallback')
                          : sessions[i].userAgent!,
                      subtitle: (sessions[i].ip ?? '').isEmpty
                          ? null
                          : sessions[i].ip,
                      isCurrent: sessions[i].isCurrent,
                      thisDeviceLabel: ref.t('mobile.settings.thisDevice'),
                      revokeLabel: ref.t('mobile.settings.revoke'),
                      onRevoke: sessions[i].isCurrent
                          ? null
                          : () => _revokeSession(sessions[i].id),
                    ),
                    if (i != sessions.length - 1)
                      const Divider(
                        height: 20,
                        thickness: 1,
                        color: AppColors.slate100,
                      ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

// ─── Reusable bits ───────────────────────────────────────────────────────────

class _SavedNote extends StatelessWidget {
  const _SavedNote({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.check_circle_rounded, size: 16, color: AppColors.brand600),
        const SizedBox(width: 6),
        Text(
          text,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.brand600,
          ),
        ),
      ],
    );
  }
}

class _GenderToggle extends StatelessWidget {
  const _GenderToggle({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
          decoration: BoxDecoration(
            color: selected ? AppColors.brand600 : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.brand600 : AppColors.slate200,
              width: 1.4,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected ? Colors.white : AppColors.slate500,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : AppColors.slate700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LangChip extends StatelessWidget {
  const _LangChip({
    required this.label,
    required this.code,
    required this.selected,
    required this.disabled,
    required this.onTap,
  });

  final String label;
  final String code;
  final bool selected;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: disabled && !selected ? 0.6 : 1.0,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: disabled ? null : onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
            decoration: BoxDecoration(
              color: selected ? AppColors.brand600 : Colors.white,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: selected ? AppColors.brand600 : AppColors.slate200,
                width: 1.4,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selected) ...[
                  const Icon(Icons.check_rounded, size: 16, color: Colors.white),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: selected ? Colors.white : AppColors.slate700,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  code.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: selected
                        ? Colors.white.withOpacity(0.8)
                        : AppColors.slate400,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({
    required this.title,
    required this.onRevoke,
    required this.thisDeviceLabel,
    required this.revokeLabel,
    this.subtitle,
    this.isCurrent = false,
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onRevoke;
  final bool isCurrent;
  final String thisDeviceLabel;
  final String revokeLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppColors.brand50,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.devices_rounded,
              size: 20, color: AppColors.brand600),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.slate900,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: AppColors.slate400),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        if (isCurrent)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.brand50,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              thisDeviceLabel,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.brand700),
            ),
          )
        else
          TextButton(
            onPressed: onRevoke,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.danger,
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              revokeLabel,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
      ],
    );
  }
}

/// Red-bordered ghost button for the destructive "Chiqish" action.
class _DangerGhostButton extends StatefulWidget {
  const _DangerGhostButton({
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback onPressed;
  final IconData? icon;

  @override
  State<_DangerGhostButton> createState() => _DangerGhostButtonState();
}

class _DangerGhostButtonState extends State<_DangerGhostButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: widget.onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        height: 52,
        decoration: BoxDecoration(
          color: _down ? AppColors.danger.withOpacity(0.06) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.danger.withOpacity(0.45)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (widget.icon != null) ...[
              Icon(widget.icon, size: 18, color: AppColors.danger),
              const SizedBox(width: 8),
            ],
            Text(
              widget.label,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.danger,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
