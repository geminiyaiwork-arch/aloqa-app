import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:aloqa/core/i18n/i18n_service.dart';
import 'package:aloqa/core/theme/app_theme.dart';
import 'package:aloqa/core/widgets/app_shell.dart';
import 'package:aloqa/core/widgets/aloqa_card.dart';
import 'package:aloqa/core/widgets/aloqa_input.dart';
import 'package:aloqa/core/widgets/gradient_button.dart';
import 'package:aloqa/core/widgets/ghost_button.dart';
import 'package:aloqa/core/widgets/error_banner.dart';
import 'package:aloqa/core/widgets/reveal.dart';
import 'package:aloqa/features/meeting/meeting_models.dart';

class JoinMeetingScreen extends ConsumerStatefulWidget {
  const JoinMeetingScreen({super.key});

  @override
  ConsumerState<JoinMeetingScreen> createState() => _JoinMeetingScreenState();
}

class _JoinMeetingScreenState extends ConsumerState<JoinMeetingScreen> {
  final TextEditingController _mid = TextEditingController();

  Meeting? _found;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _mid.dispose();
    super.dispose();
  }

  /// Parses a meeting id from a raw id, an invite link (.../m/<id>/lobby),
  /// or a sanitized code.
  String _parseMeetingId(String v) {
    final m = RegExp(r'/m/([^/?#]+)').firstMatch(v);
    if (m != null) return m.group(1)!;
    return v.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '');
  }

  Future<void> _submit() async {
    final id = _parseMeetingId(_mid.text.trim());
    if (id.isEmpty) {
      setState(() => _error = ref.tt('common.required'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final meeting = await MeetingRepository.instance.get(id);
      if (!mounted) return;
      setState(() {
        _found = meeting;
        _busy = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = ref.tt('join.notFound');
        _busy = false;
      });
    }
  }

  void _reset() {
    setState(() {
      _found = null;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final found = _found;

    return AloqaAppShell(
      currentPath: '/join',
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              RevealUp(
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.brand50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.brand500.withOpacity(0.35),
                        ),
                      ),
                      child: const Icon(
                        Icons.call,
                        color: AppColors.brand600,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            ref.t('mobile.join.title'),
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: AppColors.slate900,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            ref.t('mobile.join.subtitle'),
                            style: const TextStyle(
                              fontSize: 14,
                              color: AppColors.slate400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              if (found == null) _buildForm() else _buildFound(found),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return RevealUp(
      delayMs: 80,
      child: AloqaCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AloqaInput(
              controller: _mid,
              label: ref.t('mobile.join.idLabel'),
              hint: ref.t('join.idPlaceholder'),
              prefixIcon: Icons.tag,
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
            const SizedBox(height: 14),
            InlineErrorBanner(message: _error),
            if (_error != null) const SizedBox(height: 14),
            GradientButton(
              label: ref.t('join.find'),
              icon: Icons.search,
              busy: _busy,
              onPressed: _busy ? null : _submit,
            ),
            const SizedBox(height: 12),
            Text(
              ref.t('mobile.join.linkHint'),
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.slate400,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFound(Meeting found) {
    final idText = found.code ?? found.id;
    final isLive = found.status == 'live';
    final title = (found.title.isEmpty)
        ? ref.t('mobile.join.untitled', {'id': found.id})
        : found.title;

    return RevealUp(
      delayMs: 80,
      child: AloqaCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.brand600,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.videocam,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: AppColors.slate900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              'ID: $idText',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                fontFamily: 'monospace',
                                color: AppColors.brand700,
                              ),
                            ),
                          ),
                          if (isLive) ...[
                            const SizedBox(width: 8),
                            Text(
                              '● ${ref.t('join.live')}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.brand600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            GradientButton(
              label: ref.t('action.join'),
              icon: Icons.login,
              onPressed: () => context.go('/lobby/$idText'),
            ),
            const SizedBox(height: 12),
            GhostButton(
              label: ref.t('action.back'),
              leading: const Icon(
                Icons.arrow_back,
                size: 18,
                color: AppColors.slate600,
              ),
              onPressed: _reset,
            ),
          ],
        ),
      ),
    );
  }
}
