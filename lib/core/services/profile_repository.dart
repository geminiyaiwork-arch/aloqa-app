/// ALOQA — profile / account: update me, avatar, password, sessions
/// (web /app/profile + /app/settings parity).
library;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/auth_provider.dart';
import '../network/dio_client.dart';

@immutable
class AccountSession {
  const AccountSession({
    required this.id,
    this.ip,
    this.userAgent,
    this.createdAt,
    this.expiresAt,
    this.isCurrent = false,
  });

  final String id;
  final String? ip;
  final String? userAgent;
  final DateTime? createdAt;
  final DateTime? expiresAt;
  final bool isCurrent;

  factory AccountSession.fromJson(Map<String, dynamic> j) => AccountSession(
        id: (j['id'] ?? '').toString(),
        ip: j['ip']?.toString(),
        userAgent: j['user_agent']?.toString(),
        createdAt: j['created_at'] != null
            ? DateTime.tryParse(j['created_at'].toString())
            : null,
        expiresAt: j['expires_at'] != null
            ? DateTime.tryParse(j['expires_at'].toString())
            : null,
        isCurrent: j['is_current'] == true,
      );
}

class ProfileRepository {
  ProfileRepository(this._dio);
  final Dio _dio;

  static final ProfileRepository instance =
      ProfileRepository(DioClient.instance.dio);

  AuthUser _user(Response<Map<String, dynamic>> res) {
    final body = res.data ?? <String, dynamic>{};
    final u = body['user'] is Map ? body['user'] as Map : body;
    return AuthUser.fromJson(Map<String, dynamic>.from(u));
  }

  Future<AuthUser> me() async {
    final res = await _dio.get<Map<String, dynamic>>('/me');
    return _user(res);
  }

  Future<AuthUser> updateMe(Map<String, dynamic> body) async {
    final res = await _dio.patch<Map<String, dynamic>>('/me', data: body);
    return _user(res);
  }

  Future<AuthUser> uploadAvatar(List<int> pngBytes) async {
    final form = FormData.fromMap({
      'avatar': MultipartFile.fromBytes(pngBytes, filename: 'avatar.png'),
    });
    final res = await _dio.post<Map<String, dynamic>>('/me/avatar', data: form);
    return _user(res);
  }

  /// PATCH /me/password → {ok, access_token, refresh_token}. The server revokes
  /// every OTHER session and returns fresh tokens for the current one; the
  /// caller must store them. Returns nulls when the server sent no tokens
  /// (then the current session is gone too). Throws DioException on failure.
  Future<({String? access, String? refresh})> changePassword({
    String? currentPassword,
    required String newPassword,
    required String confirm,
  }) async {
    final res = await _dio.patch<dynamic>('/me/password', data: {
      if (currentPassword != null && currentPassword.isNotEmpty)
        'current_password': currentPassword,
      'new_password': newPassword,
      'new_password_confirmation': confirm,
    });
    final data = res.data;
    String? pick(String key) {
      if (data is! Map) return null;
      final v = data[key];
      return (v is String && v.isNotEmpty) ? v : null;
    }

    return (access: pick('access_token'), refresh: pick('refresh_token'));
  }

  Future<List<AccountSession>> sessions() async {
    final res = await _dio.get<Map<String, dynamic>>('/auth/sessions');
    final items = res.data?['sessions'];
    if (items is List) {
      return items
          .whereType<Map<String, dynamic>>()
          .map(AccountSession.fromJson)
          .toList();
    }
    return [];
  }

  Future<void> revokeSession(String id) async {
    await _dio.delete<dynamic>('/auth/sessions/$id');
  }

  /// FCM qurilma tokenини backendга yozish (push yuborish uchun).
  Future<void> registerDeviceToken(String token, String platform) async {
    await _dio.post<dynamic>('/me/device-token',
        data: {'token': token, 'platform': platform});
  }
}

final sessionsProvider =
    FutureProvider.autoDispose<List<AccountSession>>((ref) async {
  return ProfileRepository.instance.sessions();
});
