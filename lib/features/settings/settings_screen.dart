/// ALOQA — settings (M19) with LANGUAGE SELECTOR (live switch, OTA i18n TZ §5).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/i18n_service.dart';
import '../auth/auth_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final i18n = ref.watch(i18nProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(ref.t('settings.title')),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/home'),
        ),
      ),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(ref.t('settings.profile')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/profile'),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.language),
            title: Text(ref.t('settings.language')),
            subtitle: Text(_nativeName(i18n)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showLanguageSheet(context, ref),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: Text(ref.t('settings.logout'),
                style: const TextStyle(color: Colors.red)),
            onTap: () => ref.read(authProvider.notifier).logout(),
          ),
        ],
      ),
    );
  }

  String _nativeName(I18nState s) {
    return s.languages
        .firstWhere(
          (l) => l.code == s.selected,
          orElse: () => s.languages.isNotEmpty
              ? s.languages.first
              : const LanguageMeta(
                  code: 'uz',
                  version: 0,
                  nameNative: 'O\'zbekcha',
                  direction: 'ltr'),
        )
        .nameNative;
  }

  void _showLanguageSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final i18n = ref.watch(i18nProvider);
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: i18n.languages
                .map((l) => RadioListTile<String>(
                      value: l.code,
                      groupValue: i18n.selected,
                      title: Text(l.nameNative),
                      subtitle: Text(l.code),
                      onChanged: (code) {
                        if (code != null) {
                          // Live switch — UI rebuilds via Riverpod.
                          ref.read(i18nProvider.notifier).setLanguage(code);
                          Navigator.pop(ctx);
                        }
                      },
                    ))
                .toList(),
          ),
        );
      },
    );
  }
}
