import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_provider.dart';
import '../domain/track_overview_models.dart';
import '../domain/track_sample_geometry.dart';

const int _httpNotFound = 404;

/// 트랙 개요 조회 REST 어댑터.
class TracksRepository {
  TracksRepository(this._dio);

  final Dio _dio;

  /// 트랙 하나의 개요(내 기록 요약 · Time Trial 상위 · 내 빠른 랩 · 트랙 정보). 없는 트랙이면 404 [ApiException].
  /// `GET /tracks/{trackId}/overview`.
  Future<TrackOverview> getOverview(String trackId) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/tracks/${Uri.encodeComponent(trackId)}/overview');
      return TrackOverview.fromJson(res.data!);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// 모든 차 표본으로 만든 트랙 형상(`GET /tracks/{trackId}/geometry?gameCode=`). 표본이 없거나(404) 형식이 틀리면 null.
  Future<TrackSampleGeometry?> getGeometry(String trackId, String gameCode) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/tracks/${Uri.encodeComponent(trackId)}/geometry',
        queryParameters: {'gameCode': gameCode},
      );
      return TrackSampleGeometry.fromJsonOrNull(res.data!);
    } on DioException catch (e) {
      if (e.response?.statusCode == _httpNotFound) {
        return null;
      }
      throw ApiException.fromDio(e);
    }
  }
}

final tracksRepositoryProvider = Provider<TracksRepository>(
  (ref) => TracksRepository(ref.watch(dioProvider)),
);
