import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../storage/token_store.dart';
import 'auth_events.dart';

/// 인증 인터셉터: 요청에 Bearer 토큰 부착, 401이면 토큰 폐기 후 세션 무효 신호(무한 재시도 금지).
/// 토큰 값은 로깅하지 않는다(헌장 Security).
class AuthInterceptor extends Interceptor {
  AuthInterceptor({required this.tokenStore, required this.authEvents});

  final TokenStore tokenStore;
  final AuthEvents authEvents;

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final token = await tokenStore.readToken();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode == 401) {
      await tokenStore.clear();
      authEvents.signalUnauthorized();
    }
    handler.next(err);
  }
}

final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(
      baseUrl: '${AppConfig.apiBaseUrl}${AppConfig.apiPrefix}',
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      contentType: Headers.jsonContentType,
    ),
  );

  dio.interceptors.add(AuthInterceptor(
    tokenStore: ref.watch(tokenStoreProvider),
    authEvents: ref.watch(authEventsProvider),
  ));

  return dio;
});
