/// ALOQA — Profil (redesign).
///
/// Foydalanuvchi profili: avatar (ko'rsatish + "Rasm tanlash" tez kunda),
/// ism/telefon tahrir, til tanlash, PMI (read-only). PATCH /me orqali saqlanadi.
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

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

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _phone = TextEditingController();

  bool _busy = false;
  bool _avatarBusy = false;
  bool _localeBusy = false;
  String? _error;
  bool _saved = false;
  bool _seeded = false;

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _seed(AuthUser user) {
    if (_seeded) return;
    _seeded = true;
    _firstName.text = user.firstName ?? '';
    _lastName.text = user.lastName ?? '';
    _phone.text = user.phone ?? '';
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _saved = false;
    });
    try {
      final updated = await ProfileRepository.instance.updateMe({
        'first_name': _firstName.text.trim(),
        'last_name': _lastName.text.trim(),
        'phone': _phone.text.trim(),
      });
      if (!mounted) return;
      ref.read(authProvider.notifier).setUser(updated);
      setState(() {
        _busy = false;
        _saved = true;
      });
      // "✓ Saqlandi" o'tkinchi xabarini 2.5s dan keyin yashir.
      Future.delayed(const Duration(milliseconds: 2500), () {
        if (mounted) setState(() => _saved = false);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Xatolik yuz berdi';
      });
    }
  }

  Future<void> _pickLanguage(String code, String currentSelected) async {
    if (_localeBusy || code == currentSelected) return;
    setState(() => _localeBusy = true);
    // Tilni darhol almashtir (UI darrov yangilanadi).
    await ref.read(i18nProvider.notifier).setLanguage(code);
    // Serverga locale'ni yozib qo'y (xatosini e'tiborsiz qoldiramiz).
    try {
      final updated =
          await ProfileRepository.instance.updateMe({'locale': code});
      if (mounted) ref.read(authProvider.notifier).setUser(updated);
    } catch (_) {
      // Locale saqlash muhim emas — jim o'tkazib yuboramiz.
    }
    if (mounted) setState(() => _localeBusy = false);
  }

  Future<void> _pickAndUploadAvatar() async {
    if (_avatarBusy) return;
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 92,
      );
      if (picked == null || !mounted) return;
      final bytes = await Navigator.of(context).push<Uint8List>(
        MaterialPageRoute(builder: (_) => _AvatarCropPage(File(picked.path))),
      );
      if (bytes == null || !mounted) return;
      setState(() => _avatarBusy = true);
      final updated = await ProfileRepository.instance.uploadAvatar(bytes);
      if (!mounted) return;
      ref.read(authProvider.notifier).setUser(updated);
      setState(() => _avatarBusy = false);
    } catch (_) {
      if (!mounted) return;
      setState(() => _avatarBusy = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Rasm yuklanmadi')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final i18n = ref.watch(i18nProvider);

    if (user == null) {
      return const AloqaAppShell(
        currentPath: '/profile',
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 64),
          child: Center(
            child: AloqaCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.person_off_outlined,
                      size: 48, color: AppColors.slate300),
                  SizedBox(height: 12),
                  Text(
                    'Foydalanuvchi topilmadi.',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.slate700),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    _seed(user);

    return AloqaAppShell(
      currentPath: '/profile',
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RevealUp(child: _profileCard(user)),
            const SizedBox(height: 20),
            RevealUp(delayMs: 80, child: _languageCard(i18n)),
            const SizedBox(height: 20),
            RevealUp(delayMs: 160, child: _pmiCard(user)),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  // ---- CARD 1: profil ----
  Widget _profileCard(AuthUser user) {
    return AloqaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeading('Shaxsiy ma\'lumotlar'),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _avatar(user),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      user.name.isEmpty ? 'Foydalanuvchi' : user.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.slate900),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      user.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(fontSize: 14, color: AppColors.slate400),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: _avatarBusy ? null : _pickAndUploadAvatar,
                        icon: _avatarBusy
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.brand600),
                              )
                            : const Icon(Icons.photo_camera_outlined,
                                size: 16, color: AppColors.brand600),
                        label: Text(
                          _avatarBusy ? 'Yuklanmoqda…' : 'Rasm tanlash',
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.brand600),
                        ),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 36),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          side: const BorderSide(color: AppColors.slate200),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          AloqaInput(
            controller: _firstName,
            label: 'Ism',
            hint: 'Ismingiz',
            prefixIcon: Icons.person_outline,
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 14),
          AloqaInput(
            controller: _lastName,
            label: 'Familiya',
            hint: 'Familiyangiz',
            prefixIcon: Icons.badge_outlined,
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 14),
          AloqaInput(
            controller: _phone,
            label: 'Telefon',
            hint: '+998 90 123 45 67',
            prefixIcon: Icons.phone_outlined,
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 16),
          InlineErrorBanner(message: _error),
          if (_error != null) const SizedBox(height: 12),
          GradientButton(
            label: 'Saqlash',
            busy: _busy,
            icon: Icons.check_rounded,
            onPressed: _busy ? null : _save,
          ),
          if (_saved) ...[
            const SizedBox(height: 12),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle_rounded,
                    size: 18, color: AppColors.brand600),
                SizedBox(width: 6),
                Text(
                  'Saqlandi',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.brand600),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _avatar(AuthUser user) {
    final url = user.avatar;
    const size = 80.0;
    final source = user.name.isNotEmpty ? user.name : user.email;
    final initial =
        source.isEmpty ? '?' : source.characters.first.toUpperCase();
    Widget fallback() => Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: AppColors.brand600,
            shape: BoxShape.circle,
          ),
          child: Text(
            initial,
            style: const TextStyle(
                color: Colors.white, fontSize: 30, fontWeight: FontWeight.bold),
          ),
        );

    if (url == null || url.isEmpty) {
      return fallback();
    }
    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        placeholder: (_, __) => Container(
          width: size,
          height: size,
          color: AppColors.slate100,
        ),
        errorWidget: (_, __, ___) => fallback(),
      ),
    );
  }

  // ---- CARD 2: til ----
  Widget _languageCard(I18nState i18n) {
    return AloqaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeading('Til'),
          const SizedBox(height: 4),
          const Text(
            'Ilova interfeysi tilini tanlang.',
            style: TextStyle(fontSize: 14, color: AppColors.slate400),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final lang in i18n.languages)
                _langButton(lang, i18n.selected),
            ],
          ),
        ],
      ),
    );
  }

  Widget _langButton(LanguageMeta lang, String selectedCode) {
    final selected = lang.code == selectedCode;
    return Material(
      color: selected ? AppColors.brand600 : Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _localeBusy ? null : () => _pickLanguage(lang.code, selectedCode),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.brand600 : AppColors.slate200,
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
                lang.nameNative,
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

  // ---- CARD 3: PMI (read-only) ----
  Widget _pmiCard(AuthUser user) {
    final pmi = user.pmi ?? '—';
    return AloqaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeading('Shaxsiy meeting ID (PMI)'),
          const SizedBox(height: 4),
          const Text(
            'Sizning doimiy shaxsiy konferensiya identifikatoringiz.',
            style: TextStyle(fontSize: 14, color: AppColors.slate400),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppColors.slate50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.slate200),
                  ),
                  child: Text(
                    pmi,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                      color: AppColors.brand700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.slate100,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock_outline,
                        size: 14, color: AppColors.slate500),
                    SizedBox(width: 6),
                    Text(
                      'qulflangan',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.slate500),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Ichki kvadrat qirqish (pure Dart — native cropper'siz). Foydalanuvchi
/// barmoq bilan suradi/kattalashtiradi; kvadrat oynaдаги ko'rinish ~256px PNG
/// bo'lib qaytariladi (ekran avatarni doira qilib ko'rsatadi).
class _AvatarCropPage extends StatefulWidget {
  const _AvatarCropPage(this.file);
  final File file;

  @override
  State<_AvatarCropPage> createState() => _AvatarCropPageState();
}

class _AvatarCropPageState extends State<_AvatarCropPage> {
  final _boundaryKey = GlobalKey();
  bool _saving = false;

  Future<void> _done() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final obj = _boundaryKey.currentContext?.findRenderObject();
      if (obj is! RenderRepaintBoundary) {
        if (mounted) Navigator.pop(context);
        return;
      }
      final pr = (256 / obj.size.width).clamp(0.5, 4.0);
      final image = await obj.toImage(pixelRatio: pr);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (!mounted) return;
      Navigator.pop(context, data?.buffer.asUint8List());
    } catch (_) {
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Rasmni qirqing'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _done,
            child: Text(
              _saving ? '...' : 'Tayyor',
              style: const TextStyle(
                  color: Color(0xFF34D399),
                  fontWeight: FontWeight.w700,
                  fontSize: 15),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          const Spacer(),
          Padding(
            padding: const EdgeInsets.all(20),
            child: AspectRatio(
              aspectRatio: 1,
              child: ClipOval(
                child: RepaintBoundary(
                  key: _boundaryKey,
                  child: ClipRect(
                    child: InteractiveViewer(
                      minScale: 0.8,
                      maxScale: 5,
                      child: Image.file(widget.file, fit: BoxFit.cover),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Barmoq bilan suring yoki kattalashtiring',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const Spacer(),
        ],
      ),
    );
  }
}
