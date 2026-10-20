import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_provider.dart';
import '../domain/lap_detail_models.dart';
import '../domain/shared_lap.dart';

const int _httpNotFound = 404;

/// 공유 링크 랩 REST 어댑터(`/public/laps/{lapId}`, 로그인 없음). 없는 랩은 404 [ApiException].
class PublicLapRepository {
  PublicLapRepository(this._dio);

  final Dio _dio;

  /// 공유 랩 상세. 없거나 지운 랩이면 404 [ApiException].
  Future<SharedLap> getLap(String lapId) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(_lapPath(lapId));
      return SharedLap.fromJson(res.data!);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// 공유 랩의 텔레메트리 트레이스. 트레이스가 없으면(404) null.
  Future<LapTrace?> getTrace(String lapId) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('${_lapPath(lapId)}/trace');
      return LapTrace.fromJson(res.data!);
    } on DioException catch (e) {
      if (e.response?.statusCode == _httpNotFound) {
        return null;
      }
      throw ApiException.fromDio(e);
    }
  }

  static String _lapPath(String lapId) => '/public/laps/${Uri.encodeComponent(lapId)}';
}

final publicLapRepositoryProvider = Provider<PublicLapRepository>(
  (ref) => PublicLapRepository(ref.watch(dioProvider)),
);
