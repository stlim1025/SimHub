import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_provider.dart';
import '../domain/session_models.dart';

/// 세션 REST 어댑터(04 §3.4~3.6).
class SessionRepository {
  SessionRepository(this._dio);

  final Dio _dio;

  Future<DriveSession> checkIn(String rigCode, String gameCode) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/sessions/check-in',
        data: {'rigCode': rigCode, 'gameCode': gameCode},
      );
      return DriveSession.fromJson(res.data!);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<void> checkOut(String sessionId) async {
    try {
      await _dio.post<Map<String, dynamic>>('/sessions/$sessionId/check-out');
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<DriveSession?> getActive() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/sessions/active');
      final data = res.data;
      return data == null ? null : DriveSession.fromJson(data);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

final sessionRepositoryProvider = Provider<SessionRepository>(
  (ref) => SessionRepository(ref.watch(dioProvider)),
);
