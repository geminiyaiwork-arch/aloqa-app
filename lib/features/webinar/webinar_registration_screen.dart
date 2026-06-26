/// ALOQA — public webinar registration (/w/:code). Mirrors the web flow.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:aloqa/core/i18n/i18n_service.dart';
import 'package:aloqa/core/theme/app_theme.dart';
import 'package:aloqa/core/widgets/aloqa_card.dart';
import 'package:aloqa/core/widgets/aloqa_input.dart';
import 'package:aloqa/core/widgets/aloqa_logo.dart';
import 'package:aloqa/core/widgets/gradient_button.dart';
import 'package:aloqa/core/widgets/mesh_glow_background.dart';
import 'package:aloqa/core/widgets/reveal.dart';
import 'package:aloqa/features/webinar/webinar_repository.dart';

class WebinarRegistrationScreen extends ConsumerStatefulWidget {
  const WebinarRegistrationScreen({super.key, required this.code});

  final String code;

  @override
  ConsumerState<WebinarRegistrationScreen> createState() =>
      _WebinarRegistrationScreenState();
}

class _WebinarRegistrationScreenState
    extends ConsumerState<WebinarRegistrationScreen> {
  final _nameCtl = TextEditingController();
  final _emailCtl = TextEditingController();
  final _phoneCtl = TextEditingController();

  bool _done = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _nameCtl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    _emailCtl.dispose();
    _phoneCtl.dispose();
    super.dispose();
  }

  Future<void> _submit(WebinarInfo info) async {
    final name = _nameCtl.text.trim();
    if (name.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      await WebinarRepository.instance.register(
        widget.code,
        name: name,
        email: _emailCtl.text,
        phone: _phoneCtl.text,
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _done = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
            SnackBar(content: Text(ref.tt('common.error'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(webinarProvider(widget.code));

    return Scaffold(
      body: MeshGlowBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: async.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 80),
                    child: Center(
                      child: CircularProgressIndicator(
                        color: AppColors.brand600,
                      ),
                    ),
                  ),
                  error: (_, __) => _NotFound(),
                  data: (info) => _content(info),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(WebinarInfo info) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const RevealUp(
          child: AloqaLogo(size: 36),
        ),
        const SizedBox(height: 24),
        RevealUp(
          delayMs: 80,
          child: AloqaCard(
            padding: EdgeInsets.zero,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(info),
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: _done ? _doneView(info) : _form(info),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _header(WebinarInfo info) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.brand500, AppColors.brand700],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ref.t('mobile.webinar.badge'),
            style: TextStyle(
              color: Colors.white.withOpacity(0.85),
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 2.0,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            info.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
              height: 1.2,
            ),
          ),
          if (info.hostName != null && info.hostName!.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.person_outline,
                    size: 16, color: Colors.white.withOpacity(0.9)),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    info.hostName!,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.95),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
          if (info.scheduledAt != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.schedule,
                    size: 16, color: Colors.white.withOpacity(0.9)),
                const SizedBox(width: 6),
                Text(
                  DateFormat('d-MMM, HH:mm').format(info.scheduledAt!),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.95),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.18),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.groups_outlined,
                    size: 14, color: Colors.white.withOpacity(0.95)),
                const SizedBox(width: 6),
                Text(
                  ref.t('mobile.webinar.registeredCount',
                      {'count': '${info.registered}'}),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _form(WebinarInfo info) {
    final nameEmpty = _nameCtl.text.trim().isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          ref.t('mobile.webinar.registerTitle'),
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.slate900,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          ref.t('mobile.webinar.registerSub'),
          style: const TextStyle(
            fontSize: 14,
            color: AppColors.slate500,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 20),
        AloqaInput(
          controller: _nameCtl,
          label: ref.t('mobile.webinar.nameLabel'),
          hint: ref.t('mobile.webinar.nameHint'),
          prefixIcon: Icons.person_outline,
          textCapitalization: TextCapitalization.words,
        ),
        const SizedBox(height: 14),
        AloqaInput(
          controller: _emailCtl,
          label: ref.t('auth.email'),
          hint: ref.t('mobile.webinar.emailHint'),
          prefixIcon: Icons.alternate_email,
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 14),
        AloqaInput(
          controller: _phoneCtl,
          label: ref.t('mobile.field.phone'),
          hint: ref.t('mobile.field.phoneHint'),
          prefixIcon: Icons.phone_outlined,
          keyboardType: TextInputType.phone,
        ),
        const SizedBox(height: 22),
        GradientButton(
          label: _busy ? ref.t('mobile.webinar.submitting') : ref.t('mobile.webinar.register'),
          icon: _busy ? null : Icons.how_to_reg_outlined,
          busy: _busy,
          onPressed: nameEmpty ? null : () => _submit(info),
        ),
      ],
    );
  }

  Widget _doneView(WebinarInfo info) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Center(
          child: Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
              color: AppColors.brand50,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Text('✅', style: TextStyle(fontSize: 36)),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          ref.t('mobile.webinar.doneTitle'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppColors.slate900,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          ref.t('mobile.webinar.doneSub'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            color: AppColors.slate500,
            fontWeight: FontWeight.w500,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 24),
        GradientButton(
          label: ref.t('mobile.webinar.join'),
          icon: Icons.video_call_outlined,
          onPressed: info.code.trim().isEmpty
              ? null
              : () => context.go('/lobby/${info.code}'),
        ),
      ],
    );
  }
}

class _NotFound extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 40),
        const RevealUp(child: AloqaLogo(size: 40)),
        const SizedBox(height: 24),
        RevealUp(
          delayMs: 80,
          child: AloqaCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: const BoxDecoration(
                    color: AppColors.slate100,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.event_busy_outlined,
                      size: 30, color: AppColors.slate400),
                ),
                const SizedBox(height: 16),
                Text(
                  ref.t('mobile.webinar.notFound'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.slate900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  ref.t('mobile.webinar.notFoundSub'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.slate500,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
