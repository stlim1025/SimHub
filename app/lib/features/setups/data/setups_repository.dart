import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_provider.dart';
import '../domain/setup_models.dart';

/// 셋업 모음 조회 REST 어댑터(F1Laps 상위 셋업을 서버가 가져와 둔 것).
class SetupsRepository {
  SetupsRepository(this._dio);

  final Dio _dio;

  /// 게임의 트랙 목록(캘린더 순서, 역방향·옛 레이아웃은 뒤). `GET /setups/tracks?gameCode=`.
  Future<List<SetupTrackSummary>> getTracks({required String gameCode}) async {
    try {
      final res = await _dio.get<List<dynamic>>('/setups/tracks', queryParameters: {'gameCode': gameCode});
      return [for (final item in res.data ?? const []) SetupTrackSummary.fromJson(item as Map<String, dynamic>)];
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// 한 트랙·조건(`Dry`·`Wet`)의 상위 셋업. `GET /setups?trackId=&condition=`.
  Future<SetupList> getSetups({required String trackId, required String condition}) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/setups',
        queryParameters: {'trackId': trackId, 'condition': condition},
      );
      return SetupList.fromJson(res.data!);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// 셋업 하나. 없으면 404 [ApiException]. `GET /setups/{id}`.
  Future<SetupDetail> getSetup(String setupId) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/setups/${Uri.encodeComponent(setupId)}');
      return SetupDetail.fromJson(res.data!);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

final setupsRepositoryProvider = Provider<SetupsRepository>(
  (ref) => SetupsRepository(ref.watch(dioProvider)),
);
