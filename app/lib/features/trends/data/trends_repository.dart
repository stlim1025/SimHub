import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_provider.dart';
import '../../profile/application/selected_game_provider.dart';
import '../domain/trends_models.dart';

/// 내 성과 추세 REST 어댑터(`GET /me/trends`).
class TrendsRepository {
  TrendsRepository(this._dio);

  final Dio _dio;

  /// [gameCode]가 있으면 그 게임의 세션·랩만.
  Future<Trends> getMyTrends({String? gameCode}) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/me/trends', queryParameters: {'gameCode': ?gameCode});
      return Trends.fromJson(res.data!);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

final trendsRepositoryProvider = Provider<TrendsRepository>((ref) => TrendsRepository(ref.watch(dioProvider)));

/// 선택한 게임의 추세. 화면을 다시 열면 새로 불러온다.
final trendsProvider = FutureProvider.autoDispose<Trends>(
  (ref) => ref.watch(trendsRepositoryProvider).getMyTrends(gameCode: ref.watch(selectedGameProvider)),
);
