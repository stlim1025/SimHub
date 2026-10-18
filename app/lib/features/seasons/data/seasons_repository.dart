import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_provider.dart';
import '../domain/season_display.dart';
import '../domain/season_import_models.dart';
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

  /// 시즌 가져오기 미리보기(docs/15 §12, D-55). 형식 오류는 400 [ApiException](메시지에 줄 번호).
  Future<SeasonImportPreview> previewImport(String markdown) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>('/me/seasons/import/preview', data: {'markdown': markdown});
      return SeasonImportPreview.fromJson(res.data!);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// 시즌 가져오기. 만든 시즌 Id를 돌려준다. 이미 가져온 시즌이면 409 [ApiException].
  Future<String> importSeason(String markdown) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>('/me/seasons/import', data: {'markdown': markdown});
      return res.data!['seasonId'] as String;
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

final seasonsRepositoryProvider = Provider<SeasonsRepository>(
  (ref) => SeasonsRepository(ref.watch(dioProvider)),
);
