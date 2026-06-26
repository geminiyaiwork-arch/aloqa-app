/// ALOQA — contacts: read device contacts (permission), let the user override a
/// saved name per phone, and resolve a conference participant's display name
/// from the local contact (override → device name → registered fallback).
///
/// Phone numbers are matched by their last 9 digits (Uzbekistan), so +99890…,
/// 998 90… and 90… all map to the same contact.
library;

import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/network/dio_client.dart';

String normalizePhone(String raw) {
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  return digits.length > 9 ? digits.substring(digits.length - 9) : digits;
}

class AppContact {
  AppContact({
    required this.id,
    required this.deviceName,
    required this.phone,
    required this.rawPhone,
    this.override,
  });

  final String id;
  final String deviceName;
  final String phone; // normalized (last 9)
  final String rawPhone; // as stored on device
  final String? override;

  String get displayName =>
      (override != null && override!.trim().isNotEmpty) ? override!.trim() : deviceName;
}

class ContactsStore {
  ContactsStore._();
  static final ContactsStore instance = ContactsStore._();
  static const _prefix = 'contact_override_';

  // normalized phone -> resolved display name (override or device name)
  final Map<String, String> _byPhone = {};
  bool loaded = false;

  /// Fast, non-blocking check of the saved flag — does NOT trigger a system
  /// permission dialog (so the screen never hangs on entry on MIUI).
  Future<bool> wasEnabled() async {
    try {
      final p = await SharedPreferences.getInstance();
      return p.getBool('contacts_enabled') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> hasPermission() async {
    try {
      final ok = await FlutterContacts.requestPermission(readonly: true)
          .timeout(const Duration(seconds: 20), onTimeout: () => false);
      if (ok) {
        final p = await SharedPreferences.getInstance();
        await p.setBool('contacts_enabled', true);
      }
      return ok;
    } catch (_) {
      return false;
    }
  }

  /// Silent load on startup — ONLY if the user previously enabled contacts (so we
  /// never prompt for the permission on first launch).
  Future<void> bootstrap() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (!(p.getBool('contacts_enabled') ?? false)) return;
      final granted = await FlutterContacts.requestPermission(readonly: true);
      if (granted) await load();
    } catch (_) {/* ignore */}
  }

  Future<List<AppContact>> load() async {
    final prefs = await SharedPreferences.getInstance();
    var raw = <Contact>[];
    try {
      raw = await FlutterContacts.getContacts(withProperties: true)
          .timeout(const Duration(seconds: 25), onTimeout: () => <Contact>[]);
    } catch (_) {/* permission denied / unavailable / timeout */}

    final out = <AppContact>[];
    _byPhone.clear();
    for (final c in raw) {
      for (final p in c.phones) {
        final norm = normalizePhone(p.number);
        if (norm.length < 7) continue;
        final ov = prefs.getString('$_prefix$norm');
        final name =
            (ov != null && ov.trim().isNotEmpty) ? ov.trim() : c.displayName;
        out.add(AppContact(
          id: c.id,
          deviceName: c.displayName,
          phone: norm,
          rawPhone: p.number,
          override: ov,
        ));
        _byPhone[norm] = name;
      }
    }
    // de-duplicate by phone (keep first)
    final seen = <String>{};
    final deduped = <AppContact>[];
    for (final c in out) {
      if (seen.add(c.phone)) deduped.add(c);
    }
    deduped.sort((a, b) =>
        a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
    loaded = true;
    return deduped;
  }

  /// (E13) Foydalanuvchi uchrashuvlaridан yig'ilган ishtirokchilar
  /// (backend /me/meeting-contacts) — saqlangan nom (override) bilan.
  Future<List<AppContact>> meetingContacts() async {
    try {
      final res = await DioClient.instance.dio
          .get<Map<String, dynamic>>('/me/meeting-contacts');
      final items = res.data?['contacts'];
      if (items is! List) return [];
      final prefs = await SharedPreferences.getInstance();
      final out = <AppContact>[];
      for (final c in items) {
        if (c is! Map) continue;
        final name = (c['name'] ?? 'Mehmon').toString();
        final rawPhone = (c['phone'] ?? '').toString();
        final norm = rawPhone.isNotEmpty ? normalizePhone(rawPhone) : '';
        final ov = norm.isNotEmpty ? prefs.getString('$_prefix$norm') : null;
        if (norm.isNotEmpty && ov != null && ov.trim().isNotEmpty) {
          _byPhone[norm] = ov.trim();
        }
        out.add(AppContact(
          id: norm.isNotEmpty ? norm : 'n_${out.length}_$name',
          deviceName: name,
          phone: norm,
          rawPhone: rawPhone.isNotEmpty ? rawPhone : '—',
          override: ov,
        ));
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  Future<void> setOverride(String phone, String? name) async {
    final prefs = await SharedPreferences.getInstance();
    final norm = normalizePhone(phone);
    if (name == null || name.trim().isEmpty) {
      await prefs.remove('$_prefix$norm');
    } else {
      await prefs.setString('$_prefix$norm', name.trim());
      _byPhone[norm] = name.trim();
    }
  }

  /// Resolve a participant's display name. If their phone is in the local
  /// contacts, returns the saved (override or device) name; otherwise the
  /// registered fallback name. Used by the conference tiles.
  String resolveName(String? phone, String fallback) {
    if (phone == null || phone.isEmpty) return fallback;
    final n = _byPhone[normalizePhone(phone)];
    return (n != null && n.isNotEmpty) ? n : fallback;
  }
}

final contactsProvider =
    FutureProvider.autoDispose<List<AppContact>>((ref) async {
  return ContactsStore.instance.load();
});
