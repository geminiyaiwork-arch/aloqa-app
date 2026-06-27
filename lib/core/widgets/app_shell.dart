/// ALOQA — authenticated app shell (mirrors web sidebar + topbar).
///
/// Each /app screen returns its content (NO Scaffold) wrapped in
/// `AloqaAppShell(currentPath: '/x', child: content)`. Responsive: static
/// 256px sidebar at width >= 768, off-canvas Drawer below.
library;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/auth_provider.dart';
import '../i18n/i18n_service.dart';
import '../services/announcements.dart';
import '../theme/app_theme.dart';
import 'aloqa_logo.dart';

class _NavItem {
  const _NavItem(this.path, this.icon, this.labelKey);
  final String path;
  final IconData icon;

  /// i18n key — resolved with `ref.t(labelKey)` at render time.
  final String labelKey;
}

const _navItems = [
  _NavItem('/home', Icons.home_outlined, 'mobile.nav.myMeetings'),
  _NavItem('/new', Icons.videocam_outlined, 'mobile.nav.new'),
  _NavItem('/schedule', Icons.calendar_today_outlined, 'mobile.nav.schedule'),
  _NavItem('/recordings', Icons.video_library_outlined, 'mobile.nav.recordings'),
  _NavItem('/contacts', Icons.contacts_outlined, 'mobile.nav.contacts'),
  _NavItem('/employees', Icons.people_outline, 'mobile.nav.attendance'),
  _NavItem('/billing', Icons.account_balance_wallet_outlined, 'mobile.nav.billing'),
  _NavItem('/profile', Icons.person_outline, 'mobile.nav.profile'),
  _NavItem('/settings', Icons.settings_outlined, 'mobile.nav.settings'),
];

// Route -> title i18n key (resolved per-render via `ref.t`). Brand fallback.
const _titleKeys = {
  '/home': 'mobile.nav.myMeetings',
  '/new': 'mobile.title.new',
  '/join': 'mobile.title.join',
  '/schedule': 'mobile.title.schedule',
  '/recordings': 'mobile.nav.recordings',
  '/contacts': 'mobile.nav.contacts',
  '/employees': 'mobile.nav.attendance',
  '/billing': 'mobile.title.billing',
  '/profile': 'mobile.nav.profile',
  '/settings': 'mobile.nav.settings',
  '/meeting/:id': 'mobile.title.manage',
};

/// Resolved screen title for [path] (falls back to the ALOQA brand).
String _titleFor(WidgetRef ref, String path) {
  final key = _titleKeys[path];
  return key == null ? 'ALOQA' : ref.t(key);
}

bool _isActive(String itemPath, String currentPath) {
  if (itemPath == '/home') return currentPath == '/home';
  return currentPath == itemPath || currentPath.startsWith('$itemPath/');
}

class AloqaAppShell extends StatelessWidget {
  const AloqaAppShell({super.key, required this.child, required this.currentPath});

  final Widget child;
  final String currentPath;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 768;

    final Widget inner = wide
        ? Scaffold(
            backgroundColor: AppColors.slate50,
            body: SafeArea(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                      width: 256, child: _SideNav(currentPath: currentPath)),
                  Expanded(
                    child: Column(
                      children: [
                        _TopBar(currentPath: currentPath, showMenu: false),
                        Expanded(child: _Body(child: child)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          )
        : Scaffold(
            backgroundColor: AppColors.slate50,
            drawer: Drawer(
              backgroundColor: Colors.white,
              child: SafeArea(child: _SideNav(currentPath: currentPath)),
            ),
            body: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  _TopBar(currentPath: currentPath, showMenu: true),
                  Expanded(child: _Body(child: child)),
                ],
              ),
            ),
            bottomNavigationBar: _BottomNav(currentPath: currentPath),
          );

    // Android orqaga tugmasi: asosiy ekranda emas bo'lsa — ilovadan chiqib
    // ketmasdan Asosiy sahifaga qaytaradi (go_router stack'ni almashtirgani uchun).
    return PopScope(
      canPop: currentPath == '/home',
      onPopInvoked: (didPop) {
        if (!didPop && currentPath != '/home') {
          GoRouter.of(context).go('/home');
        }
      },
      child: inner,
    );
  }
}

class _BottomTab {
  const _BottomTab(this.path, this.icon, this.labelKey);
  final String path;
  final IconData icon;

  /// i18n key — resolved with `ref.t(labelKey)` at render time.
  final String labelKey;
}

const _bottomTabs = [
  _BottomTab('/home', Icons.home_rounded, 'mobile.tab.home'),
  _BottomTab('/schedule', Icons.event_rounded, 'mobile.tab.meetings'),
  _BottomTab('/new', Icons.add, 'mobile.tab.new'), // center FAB
  _BottomTab('/messages', Icons.forum_outlined, 'mobile.tab.messages'),
  _BottomTab('/settings', Icons.settings_rounded, 'mobile.tab.settings'),
];

class _BottomNav extends ConsumerWidget {
  const _BottomNav({required this.currentPath});
  final String currentPath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return SizedBox(
      height: 64 + bottomInset,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // bar
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              height: 64 + bottomInset,
              padding: EdgeInsets.only(bottom: bottomInset),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: AppColors.slate200)),
                boxShadow: [
                  BoxShadow(color: Color(0x0F000000), blurRadius: 12, offset: Offset(0, -2)),
                ],
              ),
              child: Row(
                children: [
                  for (var i = 0; i < _bottomTabs.length; i++)
                    Expanded(
                      child: i == 2
                          ? const SizedBox.shrink()
                          : _tab(context, ref, _bottomTabs[i]),
                    ),
                ],
              ),
            ),
          ),
          // center FAB
          Positioned(
            top: -14,
            left: 0,
            right: 0,
            child: Center(child: _fab(context, ref)),
          ),
        ],
      ),
    );
  }

  Widget _tab(BuildContext context, WidgetRef ref, _BottomTab t) {
    final active = _isActive(t.path, currentPath);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () {
        if (t.path != currentPath) context.go(t.path);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(t.icon,
                size: 24,
                color: active ? AppColors.brand600 : AppColors.slate400),
            const SizedBox(height: 3),
            Text(ref.t(t.labelKey),
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    color: active ? AppColors.brand600 : AppColors.slate400)),
          ],
        ),
      ),
    );
  }

  Widget _fab(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () => context.go('/new'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.brand500, AppColors.brand700],
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.brand600.withOpacity(0.4),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
              border: Border.all(color: Colors.white, width: 3),
            ),
            child: const Icon(Icons.add, color: Colors.white, size: 28),
          ),
          const SizedBox(height: 2),
          Text(ref.t('mobile.nav.new'),
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.slate500)),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.of(context).size.width >= 768 ? 24.0 : 16.0;
    // Bounded, NON-scrolling area: each screen owns its own scroll (ListView /
    // SingleChildScrollView). The banner is pinned at the top.
    return Container(
      color: AppColors.slate50,
      padding: EdgeInsets.all(pad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _AnnouncementBanner(),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _SideNav extends ConsumerWidget {
  const _SideNav({required this.currentPath});
  final String currentPath;

  void _go(BuildContext context, String path) {
    final scaffold = Scaffold.maybeOf(context);
    if (scaffold?.hasDrawer ?? false) {
      if (scaffold!.isDrawerOpen) Navigator.of(context).pop();
    }
    if (path != currentPath) context.go(path);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final i18n = ref.watch(i18nProvider);
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: AppColors.slate200)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 20, top: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: AloqaLogo(size: 34, showWordmark: true),
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                for (final item in _navItems)
                  _NavTile(
                    icon: item.icon,
                    label: ref.t(item.labelKey),
                    active: _isActive(item.path, currentPath),
                    onTap: () => _go(context, item.path),
                  ),
              ],
            ),
          ),
          const Divider(color: AppColors.slate200, height: 24),
          // Language switch
          if (i18n.languages.length > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final lang in i18n.languages)
                    _LangChip(
                      label: lang.nameNative,
                      active: lang.code == i18n.selected,
                      onTap: () =>
                          ref.read(i18nProvider.notifier).setLanguage(lang.code),
                    ),
                ],
              ),
            ),
          _LogoutTile(
            label: ref.t('mobile.action.signOut'),
            onTap: () async {
              await ref.read(authProvider.notifier).logout();
              if (context.mounted) context.go('/login');
            },
          ),
        ],
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: active ? AppColors.brand600.withOpacity(0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                Icon(icon,
                    size: 20,
                    color: active ? AppColors.brand700 : AppColors.slate600),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                      color: active ? AppColors.brand700 : AppColors.slate700,
                    ),
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

class _LangChip extends StatelessWidget {
  const _LangChip({required this.label, required this.active, required this.onTap});
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? AppColors.brand600 : AppColors.slate100,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: active ? Colors.white : AppColors.slate600,
            ),
          ),
        ),
      ),
    );
  }
}

class _LogoutTile extends StatelessWidget {
  const _LogoutTile({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              const Icon(Icons.logout, size: 20, color: AppColors.danger),
              const SizedBox(width: 12),
              Text(label,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.danger)),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends ConsumerWidget {
  const _TopBar({required this.currentPath, required this.showMenu});
  final String currentPath;
  final bool showMenu;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.slate200)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          if (showMenu)
            IconButton(
              icon: const Icon(Icons.menu, color: AppColors.slate700),
              onPressed: () => Scaffold.of(context).openDrawer(),
            ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(left: showMenu ? 0 : 8),
              child: Text(
                _titleFor(ref, currentPath),
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.slate900),
              ),
            ),
          ),
          const _UserMenu(),
        ],
      ),
    );
  }
}

class _UserMenu extends ConsumerWidget {
  const _UserMenu();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;
    final name =
        user?.name.isNotEmpty == true ? user!.name : ref.t('mobile.user.fallback');
    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';
    final avatar = user?.avatar;

    return PopupMenuButton<String>(
      tooltip: name,
      offset: const Offset(0, 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onSelected: (v) async {
        switch (v) {
          case 'billing':
            context.go('/billing');
            break;
          case 'settings':
            context.go('/settings');
            break;
          case 'profile':
            context.go('/profile');
            break;
          case 'logout':
            await ref.read(authProvider.notifier).logout();
            if (context.mounted) context.go('/login');
            break;
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, color: AppColors.slate900)),
              if (user?.email.isNotEmpty == true)
                Text(user!.email,
                    style: const TextStyle(fontSize: 12, color: AppColors.slate400)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(value: 'billing', child: Text(ref.t('mobile.menu.balance'))),
        PopupMenuItem(value: 'settings', child: Text(ref.t('mobile.nav.settings'))),
        PopupMenuItem(value: 'profile', child: Text(ref.t('mobile.nav.profile'))),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'logout',
          child: Text(ref.t('mobile.action.signOut'),
              style: const TextStyle(color: AppColors.danger)),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.slate100,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipOval(
              child: SizedBox(
                width: 28,
                height: 28,
                child: (avatar != null && avatar.isNotEmpty)
                    ? CachedNetworkImage(
                        imageUrl: avatar,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => _InitialChip(initial: initial),
                      )
                    : _InitialChip(initial: initial),
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.keyboard_arrow_down, size: 18, color: AppColors.slate400),
          ],
        ),
      ),
    );
  }
}

class _InitialChip extends StatelessWidget {
  const _InitialChip({required this.initial});
  final String initial;
  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.brand600,
      alignment: Alignment.center,
      child: Text(initial,
          style: const TextStyle(
              color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
    );
  }
}

class _AnnouncementBanner extends ConsumerStatefulWidget {
  const _AnnouncementBanner();
  @override
  ConsumerState<_AnnouncementBanner> createState() => _AnnouncementBannerState();
}

class _AnnouncementBannerState extends ConsumerState<_AnnouncementBanner> {
  final _dismissed = <int>{};

  Color _bg(String level) {
    switch (level) {
      case 'success':
        return AppColors.brand50;
      case 'warning':
        return const Color(0xFFFFFBEB); // amber-50
      default:
        return const Color(0xFFEFF6FF); // blue-50
    }
  }

  Color _fg(String level) {
    switch (level) {
      case 'success':
        return AppColors.brand700;
      case 'warning':
        return const Color(0xFFB45309); // amber-700
      default:
        return const Color(0xFF1D4ED8); // blue-700
    }
  }

  @override
  Widget build(BuildContext context) {
    final ann = ref.watch(announcementsProvider);
    return ann.maybeWhen(
      data: (items) {
        final visible = items.where((a) => !_dismissed.contains(a.id)).toList();
        if (visible.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            children: [
              for (final a in visible)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: _bg(a.level),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _fg(a.level).withOpacity(0.2)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(a.title,
                                style: TextStyle(
                                    fontWeight: FontWeight.w600, color: _fg(a.level))),
                            if (a.body != null && a.body!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(a.body!,
                                    style: TextStyle(
                                        fontSize: 13,
                                        color: _fg(a.level).withOpacity(0.85))),
                              ),
                          ],
                        ),
                      ),
                      InkWell(
                        onTap: () => setState(() => _dismissed.add(a.id)),
                        child: Icon(Icons.close, size: 18, color: _fg(a.level)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}
