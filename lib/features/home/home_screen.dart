/// ALOQA — Dashboard (Asosiy). Emerald welcome hero + stat tiles + quick
/// actions + segmented tabs + compact meeting cards + security footer.
/// Matches the product mockup. Wrapped in [AloqaAppShell] (bottom nav).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:aloqa/core/config/app_config.dart';
import 'package:aloqa/core/theme/app_theme.dart';
import 'package:aloqa/core/widgets/app_shell.dart';
import 'package:aloqa/core/widgets/aloqa_card.dart';
import 'package:aloqa/core/widgets/gradient_button.dart';
import 'package:aloqa/core/widgets/reveal.dart';
import 'package:aloqa/features/auth/auth_provider.dart';
import 'package:aloqa/features/billing/billing_repository.dart';
import 'package:aloqa/features/meeting/meeting_models.dart';
import 'package:aloqa/features/meeting/meeting_providers.dart';
import 'package:aloqa/features/recordings/recordings_repository.dart';

const _green = AppColors.brand600; // primary emerald
const _greenSoft = AppColors.brand50;

const _months = [
  'Yan', 'Fev', 'Mar', 'Apr', 'May', 'Iyun',
  'Iyul', 'Avg', 'Sen', 'Okt', 'Noy', 'Dek',
];

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _tab = 0; // 0 = mening uchrashuvlarim, 1 = ishtirokchi bo'lganlarim

  @override
  Widget build(BuildContext context) {
    final meetingsAsync = ref.watch(meetingsProvider);

    return AloqaAppShell(
      currentPath: '/home',
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const RevealUp(child: _WelcomeHero()),
            const SizedBox(height: 16),
            const RevealUp(delayMs: 40, child: _StatsRow()),
            const SizedBox(height: 24),
            Row(
              children: [
                const Expanded(child: _SectionLabel('Tezkor amallar')),
                GestureDetector(
                  onTap: () => context.go('/new'),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Barchasi',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _green)),
                      Icon(Icons.chevron_right, size: 18, color: _green),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const RevealUp(delayMs: 80, child: _QuickActions()),
            const SizedBox(height: 22),
            RevealUp(
              delayMs: 100,
              child: _SegTabs(
                index: _tab,
                onChanged: (i) => setState(() => _tab = i),
              ),
            ),
            const SizedBox(height: 14),
            meetingsAsync.when(
              loading: () => const _LoadingBlock(),
              error: (_, __) => const _EmptyMeetings(),
              data: (items) {
                if (_tab == 1) return const _ParticipatedEmpty();
                if (items.isEmpty) return const _EmptyMeetings();
                return Column(
                  children: [
                    for (var i = 0; i < items.length; i++)
                      RevealUp(
                        delayMs: 40 * i,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _MeetingCard(meeting: items[i], showManage: true),
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            const RevealUp(child: _SecurityFooter()),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

// ── Welcome hero ────────────────────────────────────────────────────────────
class _WelcomeHero extends ConsumerWidget {
  const _WelcomeHero();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;
    final name = (user?.name.trim().isNotEmpty == true) ? user!.name.trim() : '';
    final hour = DateTime.now().hour;
    final greet = hour < 12
        ? 'Xayrli tong'
        : hour < 18
            ? 'Xayrli kun'
            : 'Xayrli kech';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$greet${name.isEmpty ? '' : ', $name'} 👋',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  color: AppColors.slate900,
                  letterSpacing: -0.5,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'ALOQA — bugungi uchrashuvlaringiz shu yerda.',
                style: TextStyle(fontSize: 14, color: AppColors.slate500),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        const _HeroArt(),
      ],
    );
  }
}

class _HeroArt extends StatelessWidget {
  const _HeroArt();
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 84,
      height: 84,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          const Positioned(top: 0, left: 2, child: Text('✨', style: TextStyle(fontSize: 15))),
          Positioned(
            top: 14,
            left: 12,
            child: Transform.rotate(
              angle: -0.12,
              child: Container(
                width: 58,
                height: 62,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.brand400, _green],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(color: _green.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4)),
                  ],
                ),
                child: const Center(child: Icon(Icons.event_note, color: Colors.white, size: 25)),
              ),
            ),
          ),
          Positioned(
            right: -2,
            bottom: 12,
            child: Container(
              width: 22,
              height: 22,
              decoration: const BoxDecoration(color: _green, shape: BoxShape.circle),
              child: const Icon(Icons.check, color: Colors.white, size: 15),
            ),
          ),
          const Positioned(bottom: -2, left: 0, child: Text('🪴', style: TextStyle(fontSize: 17))),
        ],
      ),
    );
  }
}

// ── Stat tiles ──────────────────────────────────────────────────────────────
class _StatsRow extends ConsumerWidget {
  const _StatsRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meetings = ref.watch(meetingsProvider).valueOrNull ?? const <Meeting>[];
    final recordings = ref.watch(recordingsProvider).valueOrNull;
    final wallet = ref.watch(billingProvider).valueOrNull?.wallet;

    final now = DateTime.now();
    final weekEnd = now.add(const Duration(days: 7));
    final weekCount = meetings.where((m) {
      final s = m.scheduledAt;
      return s != null && s.isAfter(now) && s.isBefore(weekEnd);
    }).length;

    final tiles = [
      _StatTile(
        icon: Icons.videocam_rounded,
        value: '${meetings.length}',
        label: 'Uchrashuvlar',
        sub: 'Jami uchrashuvlar',
        onTap: () => context.go('/home'),
      ),
      _StatTile(
        icon: Icons.event_available_rounded,
        value: '$weekCount',
        label: 'Bu hafta',
        sub: 'Uchrashuvlar',
        onTap: () => context.go('/schedule'),
      ),
      _StatTile(
        icon: Icons.groups_rounded,
        value: recordings == null ? '0' : '${recordings.length}',
        label: 'Yozuvlar',
        sub: 'Saqlangan',
        onTap: () => context.go('/recordings'),
      ),
      _StatTile(
        icon: Icons.account_balance_wallet_rounded,
        value: wallet == null ? '0' : _short(wallet.balance),
        label: 'Balans',
        sub: 'Hisobingiz',
        onTap: () => context.go('/billing'),
      ),
    ];

    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 560 ? 4 : 2;
        return GridView.count(
          crossAxisCount: cols,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: cols == 4 ? 0.92 : 1.2,
          children: tiles,
        );
      },
    );
  }

  static String _short(int v) {
    if (v >= 1000000) {
      final m = v / 1000000;
      return '${m.toStringAsFixed(m >= 10 ? 0 : 1)}M';
    }
    if (v >= 1000) return '${(v / 1000).round()}K';
    return '$v';
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.value,
    required this.label,
    required this.sub,
    required this.onTap,
  });

  final IconData icon;
  final String value;
  final String label;
  final String sub;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AloqaCard(
      padding: const EdgeInsets.all(13),
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: _greenSoft, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, size: 22, color: _green),
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: const TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                    color: AppColors.slate900,
                    letterSpacing: -0.5,
                    height: 1)),
          ),
          const SizedBox(height: 4),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.slate700)),
          Text(sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: AppColors.slate400)),
        ],
      ),
    );
  }
}

// ── Segmented tabs ──────────────────────────────────────────────────────────
class _SegTabs extends StatelessWidget {
  const _SegTabs({required this.index, required this.onChanged});
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.slate200),
      ),
      child: Row(
        children: [
          _seg(0, Icons.person_rounded, 'Mening uchrashuvlarim'),
          _seg(1, Icons.groups_rounded, 'Ishtirokchi bo\'lganlarim'),
        ],
      ),
    );
  }

  Widget _seg(int i, IconData icon, String label) {
    final active = index == i;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(i),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 8),
          decoration: BoxDecoration(
            color: active ? _greenSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 17, color: active ? _green : AppColors.slate500),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: active ? _green : AppColors.slate500,
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

// ── Quick actions ───────────────────────────────────────────────────────────
class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    const actions = [
      (Icons.videocam_rounded, 'Yangi uchrashuv', 'Darhol konferensiya boshlang', '/new'),
      (Icons.call_rounded, 'Qo\'shilish', 'ID yoki havola orqali kiring', '/join'),
      (Icons.event_available_rounded, 'Rejalashtirish', 'Kelajakdagi uchrashuvni belgilang', '/schedule'),
    ];
    return Column(
      children: [
        for (var i = 0; i < actions.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          _ActionCard(a: actions[i]),
        ],
      ],
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.a});
  final (IconData, String, String, String) a;

  @override
  Widget build(BuildContext context) {
    return AloqaCard(
      onTap: () => context.go(a.$4),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: _green, borderRadius: BorderRadius.circular(14)),
            child: Icon(a.$1, color: Colors.white, size: 25),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(a.$2,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.slate900)),
                const SizedBox(height: 2),
                Text(a.$3,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, color: AppColors.slate400)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(color: AppColors.slate100, borderRadius: BorderRadius.circular(9)),
            child: const Icon(Icons.arrow_forward, size: 16, color: AppColors.slate500),
          ),
        ],
      ),
    );
  }
}

// ── Meeting card (compact, mockup-matched) ──────────────────────────────────
class _MeetingCard extends StatelessWidget {
  const _MeetingCard({required this.meeting, this.showManage = true});
  final Meeting meeting;
  final bool showManage;

  ({String day, String mon, String rel}) _badge() {
    final s = meeting.scheduledAt?.toLocal();
    final base = s ?? DateTime.now();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(base.year, base.month, base.day);
    final diff = d.difference(today).inDays;
    final rel = diff == 0
        ? 'Bugun'
        : diff == 1
            ? 'Ertaga'
            : diff == -1
                ? 'Kecha'
                : '';
    return (day: '${base.day}', mon: _months[base.month - 1], rel: rel);
  }

  String? _countdown() {
    final s = meeting.scheduledAt;
    if (s == null) return null;
    final diff = s.difference(DateTime.now());
    if (diff.isNegative) return null;
    if (diff.inMinutes < 60) return 'Boshlanishiga ${diff.inMinutes} daqiqa';
    if (diff.inHours < 24) {
      final m = diff.inMinutes % 60;
      return 'Boshlanishiga ${diff.inHours} soat${m > 0 ? ' $m daqiqa' : ''}';
    }
    return 'Boshlanishiga ${diff.inDays} kun';
  }

  String _timeRange() {
    final s = meeting.scheduledAt?.toLocal();
    if (s == null) return 'Darhol';
    String hm(DateTime t) =>
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    final end = meeting.autoEndAt?.toLocal() ?? s.add(const Duration(hours: 1));
    return '${hm(s)} – ${hm(end)}';
  }

  @override
  Widget build(BuildContext context) {
    final badge = _badge();
    final countdown = _countdown();
    final live = meeting.status == 'live';
    final dotColor = live ? _green : const Color(0xFF3B82F6);
    final title = meeting.title.isEmpty ? 'Uchrashuv #${meeting.id}' : meeting.title;
    final code = meeting.code ?? meeting.id;
    final count = meeting.participantsCount ?? 0;

    void copy(String text, String toast) {
      Clipboard.setData(ClipboardData(text: text));
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(toast), duration: const Duration(seconds: 1)));
    }

    return AloqaCard(
      padding: const EdgeInsets.all(12),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── sana bloki: gradient, TO'LIQ balandlik, katta "25" (keng) ──
            Container(
              width: 96,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFE8F8F0), Color(0xFFCBEEDD)],
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(badge.day,
                      style: const TextStyle(
                          fontSize: 46,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF059669),
                          height: 1)),
                  const SizedBox(height: 3),
                  Text(badge.mon,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF059669))),
                  if (badge.rel.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(badge.rel,
                          style: const TextStyle(
                              fontSize: 10.5, fontWeight: FontWeight.w500, color: AppColors.slate400)),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // ── o'ng: kontent (tepada) + tugmalar (pastki-o'ng) ──
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(right: 7),
                        decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
                      ),
                      Expanded(
                        child: Text(title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.slate900)),
                      ),
                      SizedBox(
                        width: 26,
                        height: 24,
                        child: PopupMenuButton<String>(
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.more_vert, size: 18, color: AppColors.slate400),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          onSelected: (v) {
                            if (v == 'link') {
                              copy('${AppConfig.webOrigin}/m/$code/lobby', 'Havola nusxalandi');
                            } else if (v == 'id') {
                              copy(code, 'ID nusxalandi');
                            } else if (v == 'manage') {
                              context.go('/meeting/${meeting.id}');
                            }
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(value: 'link', child: Text('🔗  Havolani nusxalash')),
                            const PopupMenuItem(value: 'id', child: Text('🆔  ID nusxalash')),
                            if (showManage)
                              const PopupMenuItem(value: 'manage', child: Text('⚙️  Boshqaruv')),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (countdown != null) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6366F1).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(countdown,
                          style: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF6366F1))),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _meta(Icons.access_time, _timeRange()),
                      const SizedBox(width: 14),
                      _meta(Icons.people_outline, '$count ishtirokchi'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: () => copy(code, 'ID nusxalandi'),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('ID: $code',
                            style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.slate500)),
                        const SizedBox(width: 5),
                        const Icon(Icons.copy, size: 12, color: AppColors.slate400),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  // ── tugmalar: pastki-o'ng burchak ──
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (showManage) ...[
                        _cardIconBtn(
                          onTap: () => context.go('/meeting/${meeting.id}'),
                          bg: Colors.white,
                          border: const Color(0xFFD6DEE8),
                          icon: Icons.settings,
                          iconColor: AppColors.slate600,
                        ),
                        const SizedBox(width: 10),
                      ],
                      _cardIconBtn(
                        onTap: () => context.go('/lobby/$code'),
                        bg: _green,
                        border: _green,
                        icon: Icons.videocam,
                        iconColor: Colors.white,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cardIconBtn({
    required VoidCallback onTap,
    required Color bg,
    required Color border,
    required IconData icon,
    required Color iconColor,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Container(
          width: 52,
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: border),
          ),
          child: Icon(icon, size: 21, color: iconColor),
        ),
      ),
    );
  }

  Widget _meta(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.slate400),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(fontSize: 12.5, color: AppColors.slate500)),
      ],
    );
  }
}

// ── small pieces ────────────────────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: const TextStyle(
            fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.slate900));
  }
}

class _SecurityFooter extends StatelessWidget {
  const _SecurityFooter();

  @override
  Widget build(BuildContext context) {
    final links = [
      (Icons.people_outline, 'Ishtirokchilar', '/employees'),
      (Icons.play_circle_outline, 'Yozuvlar', '/recordings'),
      (Icons.settings_outlined, 'Sozlamalar', '/settings'),
      (Icons.bar_chart_rounded, 'Hisobotlar', '/billing'),
    ];
    return AloqaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: _greenSoft, borderRadius: BorderRadius.circular(13)),
                child: const Icon(Icons.verified_user, color: _green, size: 24),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Xavfsiz uchrashuvlar',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.slate900)),
                    SizedBox(height: 2),
                    Text('Barcha ma\'lumotlaringiz himoyalangan.',
                        style: TextStyle(fontSize: 12.5, color: AppColors.slate400)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text('Boshqaruv',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.slate500)),
          const SizedBox(height: 10),
          Row(
            children: [
              for (var i = 0; i < links.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: () => context.go(links[i].$3),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.slate50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.slate200),
                      ),
                      child: Column(
                        children: [
                          Icon(links[i].$1, size: 20, color: AppColors.slate600),
                          const SizedBox(height: 5),
                          Text(links[i].$2,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 10.5, fontWeight: FontWeight.w500, color: AppColors.slate600)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _LoadingBlock extends StatelessWidget {
  const _LoadingBlock();
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 40),
      child: Center(child: CircularProgressIndicator(strokeWidth: 3, color: _green)),
    );
  }
}

class _EmptyMeetings extends StatelessWidget {
  const _EmptyMeetings();
  @override
  Widget build(BuildContext context) {
    return AloqaCard(
      padding: const EdgeInsets.symmetric(vertical: 44, horizontal: 24),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: _greenSoft, borderRadius: BorderRadius.circular(20)),
            child: const Icon(Icons.groups_outlined, size: 32, color: _green),
          ),
          const SizedBox(height: 16),
          const Text('Hozircha uchrashuvlar yo\'q.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.slate700)),
          const SizedBox(height: 6),
          const Text('Yangi konferensiya yaratib ishni boshlang.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: AppColors.slate400)),
          const SizedBox(height: 18),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: GradientButton(
              label: 'Hozir boshlash',
              icon: Icons.videocam,
              onPressed: () => context.go('/new'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ParticipatedEmpty extends StatelessWidget {
  const _ParticipatedEmpty();
  @override
  Widget build(BuildContext context) {
    return const AloqaCard(
      padding: EdgeInsets.symmetric(vertical: 44, horizontal: 24),
      child: Column(
        children: [
          Icon(Icons.history_rounded, size: 44, color: AppColors.slate300),
          SizedBox(height: 12),
          Text('Siz ishtirok etgan uchrashuvlar shu yerda ko\'rinadi.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: AppColors.slate500)),
        ],
      ),
    );
  }
}
