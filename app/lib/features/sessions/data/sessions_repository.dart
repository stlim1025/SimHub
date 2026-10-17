import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_provider.dart';
import '../domain/session_display.dart';
import '../domain/session_models.dart';

/// 내 세션 조회 REST 어댑터(docs/12 §7.1).
class SessionsRepository {
  SessionsRepository(this._dio);

  final Dio _dio;

  /// 내 세션 목록(분류 시각 내림차순). [sessionType]은 `Race`·`Qualifying`·`Practice`, null이면 전체.
  Future<SessionSummaryPage> getMySessions({
    String? sessionType,
    int page = 1,
    int pageSize = kSessionsPageSize,
  }) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/me/sessions',
        queryParameters: {
          'sessionType': ?sessionType,
          'page': page,
          'pageSize': pageSize,
        },
      );
      return SessionSummaryPage.fromJson(res.data!);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// 내 세션 상세(헤더 + 결과). 남의 세션이거나 없으면 404 [ApiException].
  Future<SessionDetail> getMySession(String sessionId) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/me/sessions/${Uri.encodeComponent(sessionId)}');
      return SessionDetail.fromJson(res.data!);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

final sessionsRepositoryProvider = Provider<SessionsRepository>(
  (ref) => SessionsRepository(ref.watch(dioProvider)),
);
