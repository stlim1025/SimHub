import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_provider.dart';
import '../domain/ranking_models.dart';

/// 랭킹/트랙 REST 어댑터(04 §3.7~3.8).
class RankingRepository {
  RankingRepository(this._dio);

  final Dio _dio;

  Future<List<Track>> getTracks() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/tracks');
      final items = (res.data!['items'] as List<dynamic>);
      return items.map((e) => Track.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// 트랙·기간별 TOP N. period 기본 monthly(D-8a).
  Future<RankingSnapshot> getRanking(
    String trackId, {
    String period = 'monthly',
    String gameCode = AppConfig.defaultGameCode,
  }) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/rankings',
        queryParameters: {'trackId': trackId, 'period': period, 'gameCode': gameCode},
      );
      return RankingSnapshot.fromJson(res.data!);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

final rankingRepositoryProvider = Provider<RankingRepository>(
  (ref) => RankingRepository(ref.watch(dioProvider)),
);
