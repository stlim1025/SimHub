import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simcenter_app/core/config/app_config.dart';
import 'package:simcenter_app/core/realtime/ranking_hub_client.dart';
import 'package:simcenter_app/features/auth/application/auth_controller.dart';
import 'package:simcenter_app/features/auth/domain/auth_models.dart';
import 'package:simcenter_app/features/auth/domain/user_preferences.dart';
import 'package:simcenter_app/features/laps/application/laps_providers.dart';
import 'package:simcenter_app/features/laps/data/laps_repository.dart';
import 'package:simcenter_app/features/profile/application/selected_game_provider.dart';
import 'package:simcenter_app/features/profile/domain/game_options.dart';
import 'package:simcenter_app/features/ranking/application/ranking_providers.dart';
import 'package:simcenter_app/features/ranking/data/ranking_repository.dart';
import 'package:simcenter_app/features/seasons/application/seasons_providers.dart';
import 'package:simcenter_app/features/seasons/data/seasons_repository.dart';
import 'package:simcenter_app/features/sessions/application/sessions_providers.dart';
import 'package:simcenter_app/features/sessions/data/sessions_repository.dart';

import 'support/fakes.dart';

const _f126 = 'F1_26';

AppUser _userPlaying(String gameCode) => AppUser(
      userId: 'u1',
      displayName: '홍길동',
      email: 'driver@simcenter.test',
      preferences: UserPreferences.defaults.copyWith(preferredGame: gameCode),
    );

void main() {
  late FakeRankingRepository ranking;
  late FakeLapsRepository laps;
  late FakeSeasonsRepository seasons;
  late FakeSessionsRepository sessions;

  ProviderContainer containerFor(AppUser? user) {
    ranking = FakeRankingRepository();
    laps = FakeLapsRepository();
    seasons = FakeSeasonsRepository();
    sessions = FakeSessionsRepository();
    final container = ProviderContainer(overrides: [
      fakeAuth(user),
      rankingRepositoryProvider.overrideWithValue(ranking),
      rankingHubClientProvider.overrideWithValue(FakeRankingHub()),
      lapsRepositoryProvider.overrideWithValue(laps),
      seasonsRepositoryProvider.overrideWithValue(seasons),
      sessionsRepositoryProvider.overrideWithValue(sessions),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  Future<void> readAll(ProviderContainer container) async {
    final subs = [
      container.listen(myTracksProvider, (_, _) {}),
      container.listen(allSeasonsProvider, (_, _) {}),
      container.listen(sessionsProvider(const SessionsQuery('all', 1)), (_, _) {}),
      container.listen(rankingControllerProvider(const RankingQuery(trackId: 't1')), (_, _) {}),
    ];
    addTearDown(() {
      for (final s in subs) {
        s.close();
      }
    });
    await container.read(tracksProvider.future);
    await container.read(myTracksProvider.future);
    await container.read(allSeasonsProvider.future);
    await container.read(sessionsProvider(const SessionsQuery('all', 1)).future);
    await container.read(rankingControllerProvider(const RankingQuery(trackId: 't1')).future);
  }

  test('게임 선택지에 F1 25와 F1 26이 있다', () {
    expect(gameChoices('F1_25'), ['F1_25', 'F1_26']);
    expect(gameLabelOf(_f126), 'F1 26');
  });

  test('선택한 게임 = 저장된 프로필의 선호 게임, 로그아웃이면 기본 게임', () async {
    final playing = containerFor(_userPlaying(_f126));
    await playing.read(authControllerProvider.future);
    expect(playing.read(selectedGameProvider), _f126);

    final signedOut = containerFor(null);
    await signedOut.read(authControllerProvider.future);
    expect(signedOut.read(selectedGameProvider), AppConfig.defaultGameCode);
  });

  test('리더보드·트랙·내 트랙·시즌·세션 조회가 선택한 게임 코드를 넘긴다', () async {
    final container = containerFor(_userPlaying(_f126));
    await container.read(authControllerProvider.future);

    await readAll(container);

    expect(ranking.trackGameCodes, [_f126]);
    expect(ranking.rankingGameCodes, [_f126]);
    expect(laps.myTracksGameCodes, [_f126]);
    expect(seasons.gameCodes, [_f126]);
    expect(sessions.gameCodes, [_f126]);
  });

  test('설정에서 다른 게임을 저장하면 그 게임으로 다시 읽는다', () async {
    final container = containerFor(_userPlaying(_f126));
    await container.read(authControllerProvider.future);
    await readAll(container);

    container.read(authControllerProvider.notifier).applyProfile(_userPlaying('F1_25'));
    await readAll(container);

    expect(ranking.trackGameCodes.last, 'F1_25');
    expect(ranking.rankingGameCodes.last, 'F1_25');
    expect(laps.myTracksGameCodes.last, 'F1_25');
    expect(seasons.gameCodes.last, 'F1_25');
    expect(sessions.gameCodes.last, 'F1_25');
  });
}
