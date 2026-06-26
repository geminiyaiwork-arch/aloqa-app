/// ALOQA — video aloqa super-platformasi (entry point).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/app_config.dart';
import 'core/i18n/i18n_service.dart';
import 'core/router/app_router.dart';
import 'core/services/push_service.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/auth_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Push (FCM) — Android/iOS'да Firebase'ni ishga tushiradi; desktopда jim o'tadi.
  await PushService.instance.initFirebase();
  runApp(const ProviderScope(child: AloqaApp()));
}

class AloqaApp extends ConsumerWidget {
  const AloqaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final locale = ref.watch(localeProvider);
    final isRtl = ref.watch(i18nProvider.select((s) => s.isRtl));

    // Login bo'lgach FCM tokenни backendга yozamiz (push uchun).
    ref.listen(authProvider, (prev, next) {
      if (next.user != null) {
        PushService.instance.registerToken();
      }
    });

    return MaterialApp.router(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      locale: locale,
      routerConfig: router,
      // RTL languages (ar/he) flip the layout (TZ §5.5).
      builder: (context, child) => Directionality(
        textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}
