/// ALOQA — OTA i18n service (THE USP, TZ §5).
///
/// Flow:
///  1. GET /i18n/manifest -> { languages:[{code,version,etag,name_native,
///     direction}], default }.
///  2. For the selected language, GET /i18n/{lang}/{namespace}?v={version}.
///  3. Cache each bundle in SharedPreferences keyed by lang+ns+version.
///  4. tr(key) resolves selected -> default -> uz -> key (fallback chain).
///
/// Admin can publish a new language and it propagates to ALL platforms with no
/// app re-deploy (TZ §5 central requirement). A bundled uz+en seed lets the UI
/// render offline / on first run before any network call.
library;

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../network/dio_client.dart';
import 'i18n_seed.dart';

/// One language entry from the manifest.
@immutable
class LanguageMeta {
  const LanguageMeta({
    required this.code,
    required this.version,
    required this.nameNative,
    required this.direction,
    this.etag,
  });

  final String code;
  final int version;
  final String nameNative;
  final String direction; // 'ltr' | 'rtl'
  final String? etag;

  bool get isRtl => direction.toLowerCase() == 'rtl';

  factory LanguageMeta.fromJson(Map<String, dynamic> j) => LanguageMeta(
        code: j['code'] as String,
        version: (j['version'] as num?)?.toInt() ?? 0,
        nameNative: (j['name_native'] as String?) ??
            (j['nameNative'] as String?) ??
            (j['code'] as String),
        direction: (j['direction'] as String?) ?? 'ltr',
        etag: j['etag'] as String?,
      );
}

/// Immutable snapshot the UI reads from.
@immutable
class I18nState {
  const I18nState({
    required this.selected,
    required this.defaultLang,
    required this.languages,
    required this.translations,
    required this.isRtl,
  });

  final String selected;
  final String defaultLang;
  final List<LanguageMeta> languages;

  /// lang -> (key -> value), merged from seed + fetched bundles.
  final Map<String, Map<String, String>> translations;
  final bool isRtl;

  I18nState copyWith({
    String? selected,
    String? defaultLang,
    List<LanguageMeta>? languages,
    Map<String, Map<String, String>>? translations,
    bool? isRtl,
  }) =>
      I18nState(
        selected: selected ?? this.selected,
        defaultLang: defaultLang ?? this.defaultLang,
        languages: languages ?? this.languages,
        translations: translations ?? this.translations,
        isRtl: isRtl ?? this.isRtl,
      );

  /// Resolve a key with the fallback chain: selected -> default -> uz -> key.
  String tr(String key) {
    return translations[selected]?[key] ??
        translations[defaultLang]?[key] ??
        translations['uz']?[key] ??
        key;
  }

  static I18nState initial() => I18nState(
        selected: 'uz',
        defaultLang: 'uz',
        languages: const [
          LanguageMeta(
              code: 'uz', version: 0, nameNative: 'O\'zbekcha', direction: 'ltr'),
          LanguageMeta(
              code: 'en', version: 0, nameNative: 'English', direction: 'ltr'),
        ],
        translations: {
          'uz': Map<String, String>.from(kI18nSeed['uz']!),
          'en': Map<String, String>.from(kI18nSeed['en']!),
        },
        isRtl: false,
      );
}

class I18nController extends StateNotifier<I18nState> {
  I18nController(this._dio) : super(I18nState.initial());

  final Dio _dio;
  static const _kSelectedPrefKey = 'aloqa_i18n_selected';
  static const _kNamespaces = ['common', 'mobile'];

  String _bundleCacheKey(String lang, String ns, int version) =>
      'aloqa_i18n_bundle_${lang}_${ns}_v$version';

  /// Call once at startup: restore selection, then refresh from server.
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_kSelectedPrefKey);
      if (saved != null && saved.isNotEmpty) {
        state = state.copyWith(selected: saved);
      }
      // Load any cached bundles for the saved language so we render localized
      // content before the network round-trip completes.
      await _loadCachedFor(state.selected);
    } catch (_) {
      // Seed already in state — safe to continue.
    }
    // Fire-and-forget network refresh (don't block first paint).
    unawaited(refresh());
  }

  /// Fetch manifest + bundles for the selected language.
  Future<void> refresh() async {
    final manifest = await _fetchManifest();
    if (manifest == null) return;

    final languages = manifest.$1;
    final defaultLang = manifest.$2;

    state = state.copyWith(languages: languages, defaultLang: defaultLang);

    // Ensure both selected and default languages are loaded.
    final toLoad = <String>{state.selected, defaultLang};
    for (final code in toLoad) {
      final meta = languages.firstWhere(
        (l) => l.code == code,
        orElse: () => LanguageMeta(
            code: code, version: 0, nameNative: code, direction: 'ltr'),
      );
      await _ensureLanguage(meta);
    }
    _recomputeRtl();
  }

  Future<(List<LanguageMeta>, String)?> _fetchManifest() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/i18n/manifest');
      final data = res.data;
      if (data == null) return null;
      final langs = (data['languages'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(LanguageMeta.fromJson)
          .toList();
      final def = (data['default'] as String?) ?? 'uz';
      if (langs.isEmpty) return null;
      return (langs, def);
    } catch (_) {
      return null;
    }
  }

  /// Fetch all namespaces for a language (cache-aware) and merge into state.
  Future<void> _ensureLanguage(LanguageMeta meta) async {
    final prefs = await SharedPreferences.getInstance();
    final merged = <String, String>{
      // start from seed if present so partial server bundles still fall back
      ...?(kI18nSeed[meta.code]),
      ...?(state.translations[meta.code]),
    };

    for (final ns in _kNamespaces) {
      final cacheKey = _bundleCacheKey(meta.code, ns, meta.version);
      final cached = prefs.getString(cacheKey);
      if (cached != null) {
        merged.addAll(_decode(cached));
        continue;
      }
      final fetched = await _fetchBundle(meta.code, ns, meta.version);
      if (fetched != null) {
        merged.addAll(fetched);
        await prefs.setString(cacheKey, jsonEncode(fetched));
      }
    }

    final next = Map<String, Map<String, String>>.from(state.translations);
    next[meta.code] = merged;
    state = state.copyWith(translations: next);
  }

  Future<Map<String, String>?> _fetchBundle(
      String lang, String ns, int version) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/i18n/$lang/$ns',
        queryParameters: {'v': version},
      );
      final data = res.data;
      if (data == null) return null;
      return data.map((k, v) => MapEntry(k, v.toString()));
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadCachedFor(String lang) async {
    final prefs = await SharedPreferences.getInstance();
    final merged = <String, String>{
      ...?(kI18nSeed[lang]),
      ...?(state.translations[lang]),
    };
    var found = false;
    // Try the most recent few versions opportunistically.
    for (final key in prefs.getKeys()) {
      if (key.startsWith('aloqa_i18n_bundle_${lang}_')) {
        final cached = prefs.getString(key);
        if (cached != null) {
          merged.addAll(_decode(cached));
          found = true;
        }
      }
    }
    if (found) {
      final next = Map<String, Map<String, String>>.from(state.translations);
      next[lang] = merged;
      state = state.copyWith(translations: next);
    }
  }

  Map<String, String> _decode(String raw) {
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return m.map((k, v) => MapEntry(k, v.toString()));
    } catch (_) {
      return {};
    }
  }

  /// Switch language live (UI rebuilds via Riverpod). Persists the choice and
  /// ensures the bundle is loaded.
  Future<void> setLanguage(String code) async {
    if (code == state.selected) return;
    state = state.copyWith(selected: code);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kSelectedPrefKey, code);
    } catch (_) {}
    // Ensure target language bundle is present.
    final meta = state.languages.firstWhere(
      (l) => l.code == code,
      orElse: () => LanguageMeta(
          code: code, version: 0, nameNative: code, direction: 'ltr'),
    );
    await _ensureLanguage(meta);
    _recomputeRtl();
  }

  void _recomputeRtl() {
    final meta = state.languages.firstWhere(
      (l) => l.code == state.selected,
      orElse: () => const LanguageMeta(
          code: 'uz', version: 0, nameNative: 'uz', direction: 'ltr'),
    );
    state = state.copyWith(isRtl: meta.isRtl);
  }
}

// ---------------------------------------------------------------------------
// Riverpod wiring
// ---------------------------------------------------------------------------

final i18nProvider =
    StateNotifierProvider<I18nController, I18nState>((ref) {
  return I18nController(DioClient.instance.dio);
});

/// `localeProvider` — current locale derived from i18n selection.
final localeProvider = Provider<Locale>((ref) {
  final code = ref.watch(i18nProvider.select((s) => s.selected));
  final parts = code.split('-');
  return parts.length > 1 ? Locale(parts[0], parts[1]) : Locale(parts[0]);
});

/// Convenience: read a translation reactively inside a build method.
///   final t = ref.t;  t('home.new_meeting')
extension I18nRef on WidgetRef {
  String t(String key) => watch(i18nProvider).tr(key);
}
