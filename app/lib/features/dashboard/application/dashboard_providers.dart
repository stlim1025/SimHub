import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../laps/data/laps_repository.dart';
import '../../laps/domain/lap_models.dart';
import '../../seasons/application/seasons_providers.dart';
import '../../seasons/domain/season_display.dart';
import '../../seasons/domain/season_models.dart';

/// Dashboard에 보여줄 최근 랩 개수.
const int kRecentLapCount = 5;

/// 내 최근 랩(최신순 [kRecentLapCount]개).
final recentLapsProvider = FutureProvider.autoDispose<MyLaps>(
  (ref) => ref.watch(lapsRepositoryProvider).getMyLaps(pageSize: kRecentLapCount),
);

/// 대시보드 시즌 카드의 시즌 상세: `/seasons`가 처음 여는 시즌(가장 최근의 진행 중인 시즌, 없으면 가장 최근 시즌).
/// 시즌이 하나도 없으면 null.
final dashboardSeasonProvider = FutureProvider.autoDispose<SeasonDetail?>((ref) async {
  final season = landingSeason(await ref.watch(allSeasonsProvider.future));
  if (season == null) {
    return null;
  }
  return ref.watch(seasonDetailProvider(season.seasonId).future);
});
