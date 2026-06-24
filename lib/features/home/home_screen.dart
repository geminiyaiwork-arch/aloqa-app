/// ALOQA — home (M5). New / Join / Schedule + meetings list.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/i18n_service.dart';
import '../meeting/meeting_models.dart';

/// FutureProvider for the meetings list (refreshable).
final meetingsProvider = FutureProvider.autoDispose<List<Meeting>>((ref) async {
  return MeetingRepository.instance.list();
});

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meetings = ref.watch(meetingsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('ALOQA'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.go('/settings'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(meetingsProvider.future),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _ActionGrid(),
            const SizedBox(height: 24),
            Text(ref.t('home.meetings'),
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            meetings.when(
              data: (items) => items.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Center(child: Text(ref.t('home.empty'))),
                    )
                  : Column(
                      children: items
                          .map((m) => Card(
                                child: ListTile(
                                  leading:
                                      const Icon(Icons.video_call_outlined),
                                  title: Text(m.title),
                                  subtitle: m.scheduledAt != null
                                      ? Text(m.scheduledAt!.toLocal().toString())
                                      : Text(m.status ?? ''),
                                  trailing: FilledButton(
                                    onPressed: () =>
                                        context.go('/lobby/${m.id}'),
                                    child: Text(ref.t('home.join')),
                                  ),
                                ),
                              ))
                          .toList(),
                    ),
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              ),
              // Backend may not be up yet — show a friendly empty state, not a crash.
              error: (_, __) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Center(child: Text(ref.t('home.empty'))),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionGrid extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = [
      (Icons.add_circle, ref.t('home.new_meeting'), () => _newMeeting(context, ref)),
      (Icons.login, ref.t('home.join'), () => _joinDialog(context, ref)),
      (Icons.calendar_month, ref.t('home.schedule'),
          () => _newMeeting(context, ref, scheduled: true)),
    ];
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      children: actions
          .map((a) => _ActionTile(icon: a.$1, label: a.$2, onTap: a.$3))
          .toList(),
    );
  }

  Future<void> _newMeeting(BuildContext context, WidgetRef ref,
      {bool scheduled = false}) async {
    try {
      final meeting = await MeetingRepository.instance.create(
        title: scheduled ? 'ALOQA uchrashuv' : 'Tezkor uchrashuv',
        scheduledAt: scheduled ? DateTime.now().add(const Duration(hours: 1)) : null,
      );
      if (!context.mounted) return;
      if (!scheduled) {
        await _showCreatedDialog(context, ref, meeting);
      } else {
        ref.invalidate(meetingsProvider);
      }
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ref.t('common.error'))),
      );
    }
  }

  // Konferensiya yaratilgach ID'ni ko'rsatadi (ulashish + Boshlash).
  Future<void> _showCreatedDialog(BuildContext context, WidgetRef ref, Meeting meeting) async {
    final code = (meeting.code != null && meeting.code!.isNotEmpty) ? meeting.code! : meeting.id;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Konferensiya yaratildi'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Konferensiya ID', style: TextStyle(fontSize: 12, color: Colors.grey)),
            Row(
              children: [
                Expanded(
                  child: SelectableText(
                    code,
                    style: const TextStyle(
                        fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 3, fontFamily: 'monospace'),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy),
                  tooltip: 'Nusxalash',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: code));
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(content: Text('ID nusxalandi'), duration: Duration(seconds: 1)),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text('Boshqalar shu ID\'ni «Qo\'shilish»da kiritib qo\'shiladi.',
                style: TextStyle(fontSize: 13, color: Colors.grey)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ref.t('common.cancel'))),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.go('/lobby/$code');
            },
            child: const Text('Boshlash'),
          ),
        ],
      ),
    );
  }

  Future<void> _joinDialog(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final id = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ref.t('home.join')),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Konferensiya ID',
            helperText: 'Yaratuvchi bergan ID (masalan ABC123)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(ref.t('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(ref.t('home.join')),
          ),
        ],
      ),
    );
    if (id == null || id.isEmpty || !context.mounted) return;
    // ID bo'yicha konferensiyani topib tekshirish, so'ng qo'shilish
    try {
      final m = await MeetingRepository.instance.get(id);
      if (!context.mounted) return;
      final code = (m.code != null && m.code!.isNotEmpty) ? m.code! : m.id;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Topildi: ${m.title}'), duration: const Duration(seconds: 1)),
      );
      context.go('/lobby/$code');
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Konferensiya topilmadi — ID ni tekshiring')),
      );
    }
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: cs.primaryContainer.withOpacity(0.5),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 30, color: cs.primary),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}
