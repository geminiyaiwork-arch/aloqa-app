import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:aloqa/core/config/app_config.dart';
import 'package:aloqa/core/theme/app_theme.dart';
import 'package:aloqa/core/widgets/aloqa_card.dart';
import 'package:aloqa/core/widgets/aloqa_input.dart';
import 'package:aloqa/core/widgets/app_shell.dart';
import 'package:aloqa/core/widgets/error_banner.dart';
import 'package:aloqa/core/widgets/ghost_button.dart';
import 'package:aloqa/core/widgets/gradient_button.dart';
import 'package:aloqa/core/widgets/reveal.dart';
import 'package:aloqa/features/meeting/meeting_models.dart';

class NewMeetingScreen extends ConsumerStatefulWidget {
  const NewMeetingScreen({super.key});

  @override
  ConsumerState<NewMeetingScreen> createState() => _NewMeetingScreenState();
}

class _NewMeetingScreenState extends ConsumerState<NewMeetingScreen> {
  final TextEditingController _title = TextEditingController();

  Meeting? _created;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  String get _code => _created == null
      ? ''
      : (_created!.code != null && _created!.code!.isNotEmpty
          ? _created!.code!
          : _created!.id);

  String get _inviteLink => '${AppConfig.webOrigin}/m/$_code/lobby';

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final title = _title.text.trim();
      final meeting = await MeetingRepository.instance
          .createInstant(title: title.isEmpty ? null : title);
      if (!mounted) return;
      setState(() {
        _created = meeting;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      // Server xabarini ko'rsatamiz (masalan tarif limiti)
      String msg = 'Xatolik yuz berdi';
      if (e is DioException && e.response?.data is Map) {
        final m = (e.response!.data as Map)['message'];
        if (m != null) msg = m.toString();
      }
      setState(() {
        _busy = false;
        _error = msg;
      });
    }
  }

  void _reset() {
    setState(() {
      _created = null;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final created = _created;
    return AloqaAppShell(
      currentPath: '/new',
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: created == null ? _buildForm() : _buildSuccess(created),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // FORM
  // ---------------------------------------------------------------------------
  Widget _buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RevealUp(
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.brand600,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.videocam, color: Colors.white, size: 26),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Yangi konferensiya',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppColors.slate900,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Bir zumda video uchrashuv yarating va havolani ulashing.',
                      style: TextStyle(fontSize: 14, color: AppColors.slate500),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        RevealUp(
          delayMs: 80,
          child: AloqaCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AloqaInput(
                  controller: _title,
                  label: 'Uchrashuv nomi',
                  hint: 'Uchrashuv nomi',
                  prefixIcon: Icons.title,
                  textCapitalization: TextCapitalization.sentences,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Nomi ixtiyoriy — bo\'sh qoldirsangiz standart nom beriladi.',
                  style: TextStyle(fontSize: 12, color: AppColors.slate400),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  InlineErrorBanner(message: _error),
                ],
                const SizedBox(height: 20),
                GradientButton(
                  label: 'Boshlash',
                  busy: _busy,
                  icon: Icons.play_arrow_rounded,
                  onPressed: _submit,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // SUCCESS
  // ---------------------------------------------------------------------------
  Widget _buildSuccess(Meeting created) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RevealUp(
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.brand600,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.check, color: Colors.white, size: 26),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Text(
                  'Konferensiya yaratildi',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppColors.slate900,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        RevealUp(
          delayMs: 80,
          child: AloqaCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // (A) Konferensiya ID
                const Text(
                  'Konferensiya ID',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.slate500,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        _code,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 30,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                          color: AppColors.brand700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    _CopyButton(text: _code),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Ushbu ID ni boshqalarga yuboring — ular uchrashuvga qo\'shilishi mumkin.',
                  style: TextStyle(fontSize: 12, color: AppColors.slate400),
                ),

                const SizedBox(height: 24),
                Container(height: 1, color: AppColors.slate200),
                const SizedBox(height: 24),

                // (B) Taklif havolasi
                const Text(
                  'Taklif havolasi',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.slate500,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.slate50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.slate200),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.link, size: 18, color: AppColors.slate400),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _inviteLink,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppColors.slate700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _CopyButton(text: _inviteLink, compact: true),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Havola orqali kirgan mehmonlar to\'g\'ridan-to\'g\'ri kutish xonasiga tushadi.',
                  style: TextStyle(fontSize: 12, color: AppColors.slate400),
                ),

                const SizedBox(height: 24),

                // (C) Actions
                LayoutBuilder(
                  builder: (context, constraints) {
                    final narrow = constraints.maxWidth < 420;
                    final joinBtn = GradientButton(
                      label: 'Uchrashuvga kirish',
                      icon: Icons.videocam,
                      onPressed: () => context.go('/lobby/$_code'),
                    );
                    final backBtn = GhostButton(
                      label: 'Orqaga',
                      leading: const Icon(Icons.arrow_back,
                          size: 18, color: AppColors.slate600),
                      onPressed: _reset,
                    );
                    if (narrow) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          joinBtn,
                          const SizedBox(height: 12),
                          backBtn,
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: joinBtn),
                        const SizedBox(width: 12),
                        Expanded(child: backBtn),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CopyButton extends StatefulWidget {
  const _CopyButton({required this.text, this.compact = false});

  final String text;
  final bool compact;

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  bool _copied = false;

  Future<void> _copy() async {
    try {
      await Clipboard.setData(ClipboardData(text: widget.text));
      if (!mounted) return;
      setState(() => _copied = true);
      await Future<void>.delayed(const Duration(milliseconds: 1800));
      if (!mounted) return;
      setState(() => _copied = false);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Xatolik yuz berdi')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = _copied ? 'Nusxalandi' : 'Nusxalash';
    final icon = _copied ? Icons.check : Icons.copy_rounded;
    final color = _copied ? AppColors.brand600 : AppColors.slate600;

    if (widget.compact) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _copy,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(icon, size: 20, color: color),
          ),
        ),
      );
    }

    return OutlinedButton.icon(
      onPressed: _copy,
      icon: Icon(icon, size: 18, color: color),
      label: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(120, 48),
        side: BorderSide(
          color: _copied ? AppColors.brand200 : AppColors.slate200,
        ),
        backgroundColor: _copied ? AppColors.brand50 : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}
