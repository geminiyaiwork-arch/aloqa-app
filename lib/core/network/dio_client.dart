/// ALOQA — Dio HTTP client with Bearer auth + 401 refresh.
library;

import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../storage/secure_store.dart';

/// Thrown when refresh fails and the session must be dropped. The auth layer
/// listens for this to redirect to login.
typedef UnauthorizedCallback = void Function();

/// Outcome of a token refresh attempt.
///  - [ok]        new tokens stored, the request can be retried;
///  - [expired]   the server said the session is gone (401/403) → log out;
///  - [transient] network / timeout / 5xx — keep the tokens, fail the request.
enum _RefreshResult { ok, expired, transient }

class DioClient {
  DioClient._() {
    _dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.apiBaseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
        headers: {'Accept': 'application/json'},
      ),
    );
    _dio.interceptors.add(_authInterceptor());
  }

  static final DioClient instance = DioClient._();

  /// Marks a request that was already re-sent after a refresh (never retried twice).
  static const _retriedKey = 'aloqa_retried';

  late final Dio _dio;
  Dio get dio => _dio;

  final SecureStore _store = SecureStore.instance;

  /// Set by the auth layer; invoked when refresh fails (forces logout).
  UnauthorizedCallback? onUnauthorized;

  /// In-flight refresh shared by concurrent 401s. Concurrent callers await the
  /// same future so a single refresh serves every queued request, and logout is
  /// only triggered when this shared refresh genuinely fails.
  Future<_RefreshResult>? _refreshFuture;

  /// Endpoints that never carry the access token.
  bool _isAuthFree(String path) =>
      path.contains('/auth/login') ||
      path.contains('/auth/register') ||
      path.contains('/auth/google') ||
      path.contains('/auth/refresh') ||
      path.startsWith('/i18n');

  /// A 401 from these is not a "session expired" signal → never refresh/retry.
  /// (Logout still sends the bearer when one exists, but must not start a
  /// refresh for a session that is being closed.)
  bool _skipsRefresh(String path) =>
      _isAuthFree(path) || path.contains('/auth/logout');

  InterceptorsWrapper _authInterceptor() => InterceptorsWrapper(
        onRequest: (options, handler) async {
          // Skip auth header for the auth/refresh endpoints themselves.
          if (!_isAuthFree(options.path)) {
            final token = await _store.accessToken;
            if (token != null && token.isNotEmpty) {
              options.headers['Authorization'] = 'Bearer $token';
            }
          }
          handler.next(options);
        },
        onError: (error, handler) async {
          final req = error.requestOptions;
          final alreadyRetried = req.extra[_retriedKey] == true;
          if (error.response?.statusCode == 401 &&
              !alreadyRetried &&
              !_skipsRefresh(req.path)) {
            final result = await _tryRefresh();
            if (result == _RefreshResult.ok) {
              // Retry the original request ONCE with the new token.
              try {
                final retried = await _retry(req);
                return handler.resolve(retried);
              } on DioException catch (e) {
                return handler.next(e);
              } catch (_) {
                // fall through to reject with the original error
              }
            } else if (result == _RefreshResult.expired) {
              onUnauthorized?.call();
            }
            // transient → tokens are kept; only this request fails.
          }
          handler.next(error);
        },
      );

  /// Refreshes the access token. Concurrent 401s share a single in-flight
  /// refresh: the first caller starts it, the rest await the same future and
  /// reuse its result. This prevents a second concurrent request from logging
  /// out while the first is successfully refreshing.
  Future<_RefreshResult> _tryRefresh() {
    return _refreshFuture ??= _doRefresh().whenComplete(() {
      _refreshFuture = null;
    });
  }

  Future<_RefreshResult> _doRefresh() async {
    try {
      var refresh = await _store.refreshToken;
      if (refresh == null || refresh.isEmpty) {
        // A transient keystore read error also yields null — give it one more
        // chance before deciding the session is really gone.
        await Future<void>.delayed(const Duration(milliseconds: 300));
        refresh = await _store.refreshToken;
      }
      if (refresh == null || refresh.isEmpty) return _RefreshResult.expired;

      // Bare Dio (no interceptors) to avoid recursion.
      final bare = Dio(BaseOptions(
        baseUrl: AppConfig.apiBaseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
        headers: {'Accept': 'application/json'},
      ));
      final res = await bare.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refresh_token': refresh},
      );
      final data = res.data;
      final access = data?['access_token'] as String?;
      final newRefresh = (data?['refresh_token'] as String?) ?? refresh;
      if (access == null || access.isEmpty) return _RefreshResult.transient;
      await _store.saveTokens(access: access, refresh: newRefresh);
      return _RefreshResult.ok;
    } on DioException catch (e) {
      // ONLY an explicit 401/403 from the refresh endpoint means the session is
      // gone. Timeouts, DNS failures, resets and 5xx are transient: the tokens
      // stay and the user is not logged out.
      final code = e.response?.statusCode;
      if (code == 401 || code == 403) return _RefreshResult.expired;
      return _RefreshResult.transient;
    } catch (_) {
      return _RefreshResult.transient;
    }
  }

  /// Re-sends [req] with the fresh token. Keeps method, query, response type
  /// and every other option; multipart bodies are cloned because a FormData
  /// can only be sent once.
  Future<Response<dynamic>> _retry(RequestOptions req) async {
    final token = await _store.accessToken;
    final data = req.data;
    final headers = Map<String, dynamic>.from(req.headers);
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    final extra = Map<String, dynamic>.from(req.extra);
    extra[_retriedKey] = true;
    final next = req.copyWith(
      headers: headers,
      extra: extra,
      data: data is FormData ? data.clone() : data,
    );
    return _dio.fetch<dynamic>(next);
  }
}
