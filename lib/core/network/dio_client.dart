/// ALOQA — Dio HTTP client with Bearer auth + 401 refresh.
library;

import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../storage/secure_store.dart';

/// Thrown when refresh fails and the session must be dropped. The auth layer
/// listens for this to redirect to login.
typedef UnauthorizedCallback = void Function();

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

  late final Dio _dio;
  Dio get dio => _dio;

  final SecureStore _store = SecureStore.instance;

  /// Set by the auth layer; invoked when refresh fails (forces logout).
  UnauthorizedCallback? onUnauthorized;

  bool _refreshing = false;

  InterceptorsWrapper _authInterceptor() => InterceptorsWrapper(
        onRequest: (options, handler) async {
          // Skip auth header for the auth/refresh endpoints themselves.
          final isAuthFree = options.path.contains('/auth/login') ||
              options.path.contains('/auth/register') ||
              options.path.contains('/auth/google') ||
              options.path.contains('/auth/refresh') ||
              options.path.startsWith('/i18n');
          if (!isAuthFree) {
            final token = await _store.accessToken;
            if (token != null && token.isNotEmpty) {
              options.headers['Authorization'] = 'Bearer $token';
            }
          }
          handler.next(options);
        },
        onError: (error, handler) async {
          final response = error.response;
          final isAuthEndpoint =
              error.requestOptions.path.contains('/auth/refresh');
          if (response?.statusCode == 401 && !isAuthEndpoint) {
            final refreshed = await _tryRefresh();
            if (refreshed) {
              // Retry the original request with the new token.
              try {
                final retried = await _retry(error.requestOptions);
                return handler.resolve(retried);
              } catch (_) {
                // fall through to reject
              }
            } else {
              onUnauthorized?.call();
            }
          }
          handler.next(error);
        },
      );

  Future<bool> _tryRefresh() async {
    if (_refreshing) return false;
    _refreshing = true;
    try {
      final refresh = await _store.refreshToken;
      if (refresh == null || refresh.isEmpty) return false;
      // Bare Dio (no interceptors) to avoid recursion.
      final bare = Dio(BaseOptions(baseUrl: AppConfig.apiBaseUrl));
      final res = await bare.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refresh_token': refresh},
      );
      final data = res.data;
      final access = data?['access_token'] as String?;
      final newRefresh = (data?['refresh_token'] as String?) ?? refresh;
      if (access == null || access.isEmpty) return false;
      await _store.saveTokens(access: access, refresh: newRefresh);
      return true;
    } catch (_) {
      return false;
    } finally {
      _refreshing = false;
    }
  }

  Future<Response<dynamic>> _retry(RequestOptions requestOptions) async {
    final token = await _store.accessToken;
    final options = Options(
      method: requestOptions.method,
      headers: {
        ...requestOptions.headers,
        if (token != null) 'Authorization': 'Bearer $token',
      },
    );
    return _dio.request<dynamic>(
      requestOptions.path,
      data: requestOptions.data,
      queryParameters: requestOptions.queryParameters,
      options: options,
    );
  }
}
