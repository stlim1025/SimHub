import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_provider.dart';
import '../domain/lap_compare.dart';
import '../domain/lap_detail_models.dart';

const int _httpNotFound = 404;

/// 랩 상세·트레이스 REST 어댑터(docs/15 §4.2, §10).
class LapDetailRepository {
  LapDetailRepository(this._dio);

  final Dio _dio;

  /// 내 랩 상세. [compare] = 비교 대상 선택(D-51, 기본값은 쿼리 없음). 남의 랩이거나 없으면 404 [ApiException](D-34와 같다).
  Future<LapDetail> getLapDetail(String lapId, {LapCompareSelection compare = LapCompareSelection.defaults}) async {
    try {
      final query = compare.toQuery();
      final res = await _dio.get<Map<String, dynamic>>(
        _lapPath(lapId),
        queryParameters: query.isEmpty ? null : query,
      );
      return LapDetail.fromJson(res.data!);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// 내 랩의 텔레메트리 트레이스. 트레이스가 없거나 남의 랩이면(404) null — 화면은 "저장되지 않았어요"를 보인다.
  Future<LapTrace?> getLapTrace(String lapId) => _traceOrNull('${_lapPath(lapId)}/trace');

  /// 비교 랩 트레이스(`GET /laps/{lapId}/trace`, D-51). 내 랩이거나 남의 랭킹 적격 랩만 — 그 밖·트레이스 없음(404)은 null.
  Future<LapTrace?> getComparisonTrace(String lapId) => _traceOrNull('/laps/${Uri.encodeComponent(lapId)}/trace');

  Future<LapTrace?> _traceOrNull(String path) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(path);
      return LapTrace.fromJson(res.data!);
    } on DioException catch (e) {
      if (e.response?.statusCode == _httpNotFound) {
        return null;
      }
      throw ApiException.fromDio(e);
    }
  }

  static String _lapPath(String lapId) => '/me/laps/${Uri.encodeComponent(lapId)}';
}

final lapDetailRepositoryProvider = Provider<LapDetailRepository>(
  (ref) => LapDetailRepository(ref.watch(dioProvider)),
);
