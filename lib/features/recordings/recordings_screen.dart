/// ALOQA — Recordings (bulutli yozuvlar ro'yxati). Web /app/recordings parity.
///
/// Wrapped in [AloqaAppShell] (currentPath: '/recordings'). Reads
/// [recordingsProvider] (GET /recordings via RecordingsRepository) and renders
/// loading / empty / error / data states with the premium emerald surface.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:aloqa/core/i18n/i18n_service.dart';
import 'package:aloqa/core/theme/app_theme.dart';
import 'package:aloqa/core/widgets/app_shell.dart';
import 'package:aloqa/core/widgets/aloqa_card.dart';
import 'package:aloqa/core/widgets/error_banner.dart';
import 'package:aloqa/core/widgets/reveal.dart';
import 'package:aloqa/features/recordings/recordings_repository.dart';

class RecordingsScreen extends ConsumerWidget {
  const RecordingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recordings = ref.watch(recordingsProvider);

    return AloqaAppShell(
      currentPath: '/recordings',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
        children: [
          const RevealUp(child: _Header()),
          const SizedBox(height: 24),
          recordings.when(
            loading: () => const RevealUp(delayMs: 60, child: _LoadingState()),
            error: (_, __) => const RevealUp(delayMs: 60, child: _ErrorState()),
            data: (rows) {
              if (rows.isEmpty) {
                return const RevealUp(delayMs: 60, child: _EmptyState());
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  RevealUp(
                    delayMs: 60,
                    child: SectionHeading(
                      ref.t('stub.recordings'),
                      trailing: Text(
                        ref.t('mobile.recordings.count',
                            {'count': '${rows.length}'}),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.slate500,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  RevealUp(
                    delayMs: 120,
                    child: AloqaCard(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          for (var i = 0; i < rows.length; i++) ...[
                            if (i > 0) const SizedBox(height: 8),
                            _RecordingRowTile(row: rows[i]),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Page title + subtitle.
class _Header extends ConsumerWidget {
  const _Header();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.brand50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.movie_creation_outlined,
                color: AppColors.brand600,
                size: 24,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                ref.t('mobile.recordings.headerTitle'),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppColors.slate900,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          ref.t('mobile.recordings.headerSub'),
          style: const TextStyle(
            fontSize: 14,
            color: AppColors.slate500,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

/// Single recording entry — spec: rounded12 bg slate100, meeting id + type·status,
/// duration on the right.
class _RecordingRowTile extends ConsumerWidget {
  const _RecordingRowTile({required this.row});

  final RecordingRow row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final durationLabel = row.duration != null
        ? ref.t('mobile.recordings.durationLabel',
            {'minutes': '${(row.duration! / 60).round()}'})
        : '';

    final ready = row.url != null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: ready
            ? () async {
                final uri = Uri.tryParse(row.url!);
                if (uri != null) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              }
            : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.slate100,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.slate200),
                ),
                child: Icon(
                  Icons.play_circle_outline,
                  color: ready ? AppColors.brand600 : AppColors.slate300,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      ref.t('mobile.recordings.meetingNum',
                          {'id': '${row.meetingId}'}),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.slate700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      ready
                          ? ref.t('mobile.recordings.tapToView',
                              {'type': '${row.type ?? "cloud"}'})
                          : ref.t('mobile.recordings.recordingStatus', {
                              'type': '${row.type ?? "cloud"}',
                              'status': row.status == "recording"
                                  ? ref.t('mobile.recordings.statusRecording')
                                  : ref.t('mobile.recordings.statusProcessing'),
                            }),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: ready ? AppColors.brand600 : AppColors.slate400,
                      ),
                    ),
                  ],
                ),
              ),
              if (durationLabel.isNotEmpty) ...[
                const SizedBox(width: 10),
                Text(
                  durationLabel,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.slate500,
                  ),
                ),
              ],
              if (ready) ...[
                const SizedBox(width: 8),
                const Icon(Icons.open_in_new,
                    size: 18, color: AppColors.brand600),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Empty state — spec: centered AloqaCard, 🎬 + headline + hint.
class _EmptyState extends ConsumerWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AloqaCard(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 64),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.brand50,
              borderRadius: BorderRadius.circular(20),
            ),
            alignment: Alignment.center,
            child: const Text('🎬', style: TextStyle(fontSize: 34)),
          ),
          const SizedBox(height: 20),
          Text(
            ref.t('mobile.recordings.emptyTitle'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: AppColors.slate700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            ref.t('mobile.recordings.emptySub'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.slate500,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

/// Loading state — branded spinner inside a card.
class _LoadingState extends ConsumerWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AloqaCard(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 64),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 30,
            height: 30,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: AppColors.brand600,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            ref.t('common.loading'),
            style: const TextStyle(fontSize: 14, color: AppColors.slate400),
          ),
        ],
      ),
    );
  }
}

/// Error state — friendly banner + empty card so the page never crashes.
class _ErrorState extends ConsumerWidget {
  const _ErrorState();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InlineErrorBanner(message: ref.t('common.error')),
        const SizedBox(height: 16),
        const _EmptyState(),
      ],
    );
  }
}
