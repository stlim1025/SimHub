import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_provider.dart';
import '../domain/lap_models.dart';

/// 내 랩 기록 REST 어댑터(04 §3.9).
class LapsRepository {
  LapsRepository(this._dio);

  final Dio _dio;

  Future<MyLaps> getMyLaps({String? trackId, String? sessionType, int page = 1, int pageSize = 20}) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/me/laps',
        queryParameters: {
          'trackId': ?trackId,
          'sessionType': ?sessionType,
          'page': page,
          'pageSize': pageSize,
        },
      );
      return MyLaps.fromJson(res.data!);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

final lapsRepositoryProvider = Provider<LapsRepository>(
  (ref) => LapsRepository(ref.watch(dioProvider)),
);
