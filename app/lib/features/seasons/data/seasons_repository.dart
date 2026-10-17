import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_provider.dart';
import '../domain/season_display.dart';
import '../domain/season_models.dart';

/// 내 시즌 조회 REST 어댑터(docs/12 §7.1).
class SeasonsRepository {
  SeasonsRepository(this._dio);

  final Dio _dio;

  /// 내 시즌 목록(마지막 세션 시각 내림차순).
  Future<SeasonSummaryPage> getMySeasons({int page = 1, int pageSize = kSeasonsPageSize}) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/me/seasons',
        queryParameters: {'page': page, 'pageSize': pageSize},
      );
      return SeasonSummaryPage.fromJson(res.data!);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// 내 시즌 상세(헤더 + 라운드 + Standings). 남의 시즌이거나 없으면 404 [ApiException].
  Future<SeasonDetail> getMySeason(String seasonId) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/me/seasons/${Uri.encodeComponent(seasonId)}');
      return SeasonDetail.fromJson(res.data!);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

final seasonsRepositoryProvider = Provider<SeasonsRepository>(
  (ref) => SeasonsRepository(ref.watch(dioProvider)),
);
