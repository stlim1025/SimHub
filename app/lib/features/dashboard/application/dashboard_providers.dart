import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../laps/data/laps_repository.dart';
import '../../laps/domain/lap_models.dart';
import '../../profile/application/selected_game_provider.dart';
import '../../seasons/application/seasons_providers.dart';
import '../../seasons/domain/season_models.dart';
import '../../sessions/application/sessions_providers.dart';
import '../../sessions/domain/session_display.dart';
import '../../sessions/domain/session_models.dart';
import '../data/dashboard_season_store.dart';
import '../domain/dashboard_home.dart';
import '../domain/dashboard_season.dart';

/// Dashboard에 보여줄 최근 랩 개수.
const int kRecentLapCount = 5;

/// 내 최근 랩(최신순 [kRecentLapCount]개).
final recentLapsProvider = FutureProvider.autoDispose<MyLaps>(
  (ref) => ref.watch(lapsRepositoryProvider).getMyLaps(pageSize: kRecentLapCount),
);

/// 대시보드에서 고른 시즌 id(선택한 게임별, 이 기기에 기억). 고른 적이 없으면 null.
class DashboardSeasonChoice extends AutoDisposeAsyncNotifier<String?> {
  @override
  Future<String?> build() => ref.watch(dashboardSeasonStoreProvider).read(ref.watch(selectedGameProvider));

  /// [seasonId] 시즌을 대시보드에 보이고 이 기기에 기억한다.
  Future<void> select(String seasonId) async {
    state = AsyncData(seasonId);
    await ref.read(dashboardSeasonStoreProvider).write(ref.read(selectedGameProvider), seasonId);
  }
}

final dashboardSeasonChoiceProvider =
    AsyncNotifierProvider.autoDispose<DashboardSeasonChoice, String?>(DashboardSeasonChoice.new);

/// 대시보드 시즌 카드의 시즌 상세: 고른 진행 중인 시즌, 고르지 않았거나 끝났으면 `/seasons`가 처음 여는 시즌
/// (가장 최근의 진행 중인 시즌, 없으면 가장 최근 시즌). 시즌이 하나도 없으면 null.
final dashboardSeasonProvider = FutureProvider.autoDispose<SeasonDetail?>((ref) async {
  final seasons = ref.watch(allSeasonsProvider.future);
  final choice = ref.watch(dashboardSeasonChoiceProvider.future);
  final season = dashboardSeasonOf(await seasons, await choice);
  if (season == null) {
    return null;
  }
  return ref.watch(seasonDetailProvider(season.seasonId).future);
});

/// 홈 Last Race 타일의 세션: 내 레이스 세션 목록 첫 페이지에서 가장 최근 레이스(선택한 게임만). 레이스가 없으면 null.
final lastRaceProvider = FutureProvider.autoDispose<SessionSummary?>((ref) async {
  final page = await ref.watch(sessionsProvider(const SessionsQuery(kSessionFilterRace, 1)).future);
  return latestSession(page.items);
});
