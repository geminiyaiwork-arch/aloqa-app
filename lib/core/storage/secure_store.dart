/// ALOQA — secure token storage wrapper.
///
/// IMPORTANT (known bug from sister projects, e.g. ZipGo): a transient keystore
/// read error on MIUI/Android used to trigger `deleteAll()`, which wiped the
/// whole session and logged the user out. We NEVER deleteAll on a read error —
/// we just return null and retry once. Only explicit logout clears tokens.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStore {
  SecureStore._();
  static final SecureStore instance = SecureStore._();

  static const _accessKey = 'aloqa_access_token';
  static const _refreshKey = 'aloqa_refresh_token';
  static const _deviceKey = 'aloqa_device_id';

  // Isolated keystore namespace so unrelated apps / clears don't collide.
  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  /// Read a key. On a transient read error: retry ONCE, then return null.
  /// Never deletes anything here.
  Future<String?> _safeRead(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (_) {
      // Single retry — do NOT deleteAll (that was the session-wipe bug).
      try {
        return await _storage.read(key: key);
      } catch (_) {
        return null;
      }
    }
  }

  Future<void> _safeWrite(String key, String? value) async {
    try {
      if (value == null) {
        await _storage.delete(key: key);
      } else {
        await _storage.write(key: key, value: value);
      }
    } catch (_) {
      // Swallow — storage write failures must not crash auth flows.
    }
  }

  Future<String?> get accessToken => _safeRead(_accessKey);
  Future<String?> get refreshToken => _safeRead(_refreshKey);
  Future<String?> get deviceId => _safeRead(_deviceKey);

  Future<void> saveTokens({required String access, required String refresh}) async {
    await _safeWrite(_accessKey, access);
    await _safeWrite(_refreshKey, refresh);
  }

  Future<void> saveDeviceId(String id) => _safeWrite(_deviceKey, id);

  /// Only call on explicit logout — clears tokens, keeps deviceId.
  Future<void> clearTokens() async {
    await _safeWrite(_accessKey, null);
    await _safeWrite(_refreshKey, null);
  }
}
