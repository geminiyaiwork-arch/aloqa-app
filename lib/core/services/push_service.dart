/// ALOQA — push (FCM). Android/iOS: Firebase init + token registration with the
/// backend. On desktop/no-firebase platforms every call is a safe no-op.
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../network/dio_client.dart';
import 'profile_repository.dart';

/// Fon (ilova yopiq/orqada) xabar ishlovchisi — top-level bo'lishi SHART.
@pragma('vm:entry-point')
Future<void> _firebaseBgHandler(RemoteMessage message) async {
  // 'notification' turidagi xabarларни tizim avtomatik ko'rsatadi. Bu yerда
  // qo'shimcha ish kerak emas (data-only kelса keyin kengaytiramiz).
}

class PushService {
  PushService._();
  static final PushService instance = PushService._();

  bool _inited = false;
  bool _registering = false;
  String? _lastSent;

  /// Bitta obuna — registerToken() har auth o'zgarishida chaqiriladi, shuning
  /// uchun tinglovchi bir marta ulanadi (aks holda ular to'planib qolardi).
  StreamSubscription<String>? _refreshSub;

  /// Ilova ishga tushganда (main) chaqiriladi. Faqat mobilда Firebase'ni
  /// ishga tushiradi; desktopда jim o'tadi.
  Future<void> initFirebase() async {
    if (_inited) return;
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(_firebaseBgHandler);
      _inited = true;
    } catch (_) {
      // Firebase yo'q platforma (Linux/Windows/macOS) — e'tiborsiz.
    }
  }

  /// Login bo'lгач chaqiriladi — qurilma FCM tokenини backendга yozadi
  /// (server keyin shu tokenга push yuboradi).
  Future<void> registerToken() async {
    if (!_inited || _registering) return;
    _registering = true;
    try {
      final m = FirebaseMessaging.instance;
      if (_lastSent == null) {
        await m.requestPermission(alert: true, badge: true, sound: true);
      }
      final token = await m.getToken();
      if (token != null && token != _lastSent) {
        await ProfileRepository.instance
            .registerDeviceToken(token, _platform());
        _lastSent = token;
      }
      _refreshSub ??= m.onTokenRefresh.listen((t) async {
        try {
          await ProfileRepository.instance.registerDeviceToken(t, _platform());
          _lastSent = t;
        } catch (_) {/* ignore */}
      });
    } catch (_) {
      // ruxsat berilmadi / token yo'q — jim o'tamiz
    } finally {
      _registering = false;
    }
  }

  /// Chiqishda (logout) chaqiriladi — shu qurilma tokenini serverdan olib
  /// tashlaydi: `DELETE /push/register {token}`. Access token hali saqlangan
  /// paytda chaqirilishi kerak. Xato bo'lsa jim o'tadi.
  Future<void> unregisterToken() async {
    if (!_inited) return;
    await _refreshSub?.cancel();
    _refreshSub = null;
    try {
      final token = _lastSent ?? await FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) {
        await DioClient.instance.dio
            .delete<dynamic>('/push/register', data: {'token': token});
      }
    } catch (_) {
      // best-effort
    } finally {
      _lastSent = null;
    }
  }

  String _platform() {
    try {
      if (Platform.isIOS) return 'ios';
      if (Platform.isAndroid) return 'android';
    } catch (_) {/* ignore */}
    return 'other';
  }
}
