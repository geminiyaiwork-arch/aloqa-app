/// ALOQA — authentication state (Riverpod).
///
/// Calls /auth/google and /auth/login (TZ §9), stores JWT access + refresh in
/// secure storage. Exposes status the router watches to gate routes.
library;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../core/config/app_config.dart';
import '../../core/network/dio_client.dart';
import '../../core/storage/secure_store.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

@immutable
class AuthUser {
  const AuthUser({
    required this.id,
    required this.name,
    required this.email,
    this.avatar,
  });

  final String id;
  final String name;
  final String email;
  final String? avatar;

  factory AuthUser.fromJson(Map<String, dynamic> j) => AuthUser(
        id: (j['id'] ?? '').toString(),
        name: (j['name'] as String?) ?? '',
        email: (j['email'] as String?) ?? '',
        avatar: j['avatar'] as String?,
      );
}

@immutable
class AuthState {
  const AuthState({required this.status, this.user, this.error, this.busy = false});

  final AuthStatus status;
  final AuthUser? user;
  final String? error;
  final bool busy;

  AuthState copyWith({
    AuthStatus? status,
    AuthUser? user,
    String? error,
    bool? busy,
    bool clearError = false,
  }) =>
      AuthState(
        status: status ?? this.status,
        user: user ?? this.user,
        error: clearError ? null : (error ?? this.error),
        busy: busy ?? this.busy,
      );
}

class AuthController extends StateNotifier<AuthState> {
  AuthController(this._dio, this._store)
      : super(const AuthState(status: AuthStatus.unknown)) {
    // When the network layer fails to refresh, force logout state.
    DioClient.instance.onUnauthorized = () {
      _store.clearTokens();
      state = const AuthState(status: AuthStatus.unauthenticated);
    };
  }

  final Dio _dio;
  final SecureStore _store;

  final GoogleSignIn _google = GoogleSignIn(
    scopes: const ['email', 'profile'],
    serverClientId: AppConfig.googleServerClientId.isEmpty
        ? null
        : AppConfig.googleServerClientId,
  );

  /// Restore session on startup.
  Future<void> bootstrap() async {
    final token = await _store.accessToken;
    if (token == null || token.isEmpty) {
      state = const AuthState(status: AuthStatus.unauthenticated);
      return;
    }
    try {
      final res = await _dio.get<Map<String, dynamic>>('/auth/me');
      final user =
          res.data != null ? AuthUser.fromJson(res.data!) : null;
      state = AuthState(status: AuthStatus.authenticated, user: user);
    } catch (_) {
      // Token may still be valid for actions even if /me isn't wired yet;
      // treat presence of token as authenticated, but degrade gracefully.
      state = const AuthState(status: AuthStatus.authenticated);
    }
  }

  Future<void> loginWithEmail(String email, String password) async {
    state = state.copyWith(busy: true, clearError: true);
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/auth/login',
        data: {'email': email, 'password': password},
      );
      await _persistSession(res.data);
    } on DioException catch (e) {
      state = state.copyWith(
        busy: false,
        error: _messageFrom(e) ?? 'Kirishda xatolik',
      );
    } catch (_) {
      state = state.copyWith(busy: false, error: 'Kirishda xatolik');
    }
  }

  Future<void> loginWithGoogle() async {
    state = state.copyWith(busy: true, clearError: true);
    try {
      final account = await _google.signIn();
      if (account == null) {
        state = state.copyWith(busy: false); // user cancelled
        return;
      }
      final gauth = await account.authentication;
      final res = await _dio.post<Map<String, dynamic>>(
        '/auth/google',
        data: {
          'id_token': gauth.idToken,
          'access_token': gauth.accessToken,
          'email': account.email,
          'name': account.displayName,
          'avatar': account.photoUrl,
        },
      );
      await _persistSession(res.data);
    } on DioException catch (e) {
      state = state.copyWith(
          busy: false, error: _messageFrom(e) ?? 'Google kirishda xatolik');
    } catch (_) {
      state = state.copyWith(busy: false, error: 'Google kirishda xatolik');
    }
  }

  Future<void> logout() async {
    try {
      await _dio.post<dynamic>('/auth/logout');
    } catch (_) {
      // ignore network errors on logout
    }
    try {
      await _google.signOut();
    } catch (_) {}
    await _store.clearTokens();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  Future<void> _persistSession(Map<String, dynamic>? data) async {
    final access = data?['access_token'] as String?;
    final refresh = data?['refresh_token'] as String?;
    if (access == null || refresh == null) {
      state = state.copyWith(busy: false, error: 'Serverdan token kelmadi');
      return;
    }
    await _store.saveTokens(access: access, refresh: refresh);
    final userJson = data?['user'];
    final user = userJson is Map<String, dynamic>
        ? AuthUser.fromJson(userJson)
        : null;
    state = AuthState(status: AuthStatus.authenticated, user: user);
  }

  String? _messageFrom(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['message'] is String) {
      return data['message'] as String;
    }
    return null;
  }
}

final authProvider = StateNotifierProvider<AuthController, AuthState>((ref) {
  return AuthController(DioClient.instance.dio, SecureStore.instance);
});
