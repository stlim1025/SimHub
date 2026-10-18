import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_provider.dart';
import '../domain/lap_detail_models.dart';

const int _httpNotFound = 404;

/// 랩 상세·트레이스 REST 어댑터(docs/15 §4.2).
class LapDetailRepository {
  LapDetailRepository(this._dio);

  final Dio _dio;

  /// 내 랩 상세. 남의 랩이거나 없으면 404 [ApiException](D-34와 같다).
  Future<LapDetail> getLapDetail(String lapId) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(_lapPath(lapId));
      return LapDetail.fromJson(res.data!);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// 내 랩의 텔레메트리 트레이스. 트레이스가 없거나 남의 랩이면(404) null — 화면은 "저장되지 않았어요"를 보인다.
  Future<LapTrace?> getLapTrace(String lapId) async {
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

  static String _lapPath(String lapId) => '/me/laps/${Uri.encodeComponent(lapId)}';
}

final lapDetailRepositoryProvider = Provider<LapDetailRepository>(
  (ref) => LapDetailRepository(ref.watch(dioProvider)),
);
