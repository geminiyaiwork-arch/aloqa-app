/// ALOQA — global configuration constants.
///
/// All endpoints are overridable at build time via --dart-define so the same
/// binary can target dev / staging / prod without code changes.
library;

class AppConfig {
  AppConfig._();

  static const String appName = 'ALOQA';

  /// Default API base. Android emulator reaches the host machine via 10.0.2.2;
  /// other platforms default to localhost. Override with:
  ///   --dart-define=ALOQA_API_BASE=https://api.aloqa.uz/api/v1
  static String get apiBaseUrl {
    const override = String.fromEnvironment('ALOQA_API_BASE');
    if (override.isNotEmpty) return override;
    return 'https://api.aloqa.ucms.uz/api/v1';
  }

  /// LiveKit SFU websocket URL (prod: rtc.aloqa.ucms.uz). Override with:
  ///   --dart-define=ALOQA_LIVEKIT_URL=wss://rtc.aloqa.ucms.uz
  static const String livekitUrl =
      String.fromEnvironment('ALOQA_LIVEKIT_URL', defaultValue: 'wss://rtc.aloqa.ucms.uz');

  /// Realtime signaling (Laravel Reverb / WS). Override with:
  ///   --dart-define=ALOQA_WS_URL=wss://api.aloqa.ucms.uz/ws
  static const String wsUrl =
      String.fromEnvironment('ALOQA_WS_URL', defaultValue: 'wss://api.aloqa.ucms.uz/ws');

  /// Google Sign-In server client id (web/backend OAuth client). Optional on
  /// mobile (uses google-services.json / GoogleService-Info.plist). Override:
  ///   --dart-define=ALOQA_GOOGLE_SERVER_CLIENT_ID=...
  static const String googleServerClientId = String.fromEnvironment(
    'ALOQA_GOOGLE_SERVER_CLIENT_ID',
    defaultValue:
        '619627564017-av9f293sovf16dnd5h0l5gvu9gcgf9se.apps.googleusercontent.com',
  );

  /// Public web origin (for shareable invite links: <origin>/m/<code>/lobby).
  ///   --dart-define=ALOQA_WEB_ORIGIN=https://aloqa.ucms.uz
  static const String webOrigin = String.fromEnvironment(
    'ALOQA_WEB_ORIGIN',
    defaultValue: 'https://aloqa.ucms.uz',
  );

  /// How often (ms) to re-check the i18n manifest for new published bundles.
  static const Duration i18nRefreshInterval = Duration(minutes: 30);
}
