import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simcenter_app/core/realtime/ranking_hub_client.dart';
import 'package:simcenter_app/features/ranking/application/ranking_providers.dart';
import 'package:simcenter_app/features/ranking/data/ranking_repository.dart';

import 'support/fakes.dart';

void main() {
  late FakeRankingHub hub;
  late FakeRankingRepository repo;
  late ProviderContainer container;

  // REST 호출 순번마다 다른 1위가 나오도록 해서, 어느 경로로 화면이 갱신됐는지 구분한다.
  setUp(() {
    hub = FakeRankingHub();
    repo = FakeRankingRepository(
      entriesFor: (trackId, period, call) => [entryOf(1, 'rest-$period-$call', 80000)],
    );
    container = ProviderContainer(overrides: [
      rankingHubClientProvider.overrideWithValue(hub),
      rankingRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(container.dispose);
  });

  const monthly = RankingQuery(trackId: 't1', period: 'monthly');
  const daily = RankingQuery(trackId: 't1', period: 'daily');

  test('loads the snapshot for the query period over REST', () async {
    container.listen(rankingControllerProvider(daily), (_, _) {});

    final snapshot = await container.read(rankingControllerProvider(daily).future);

    expect(repo.requests.single, (trackId: 't1', period: 'daily'));
    expect(snapshot.entries.single.displayName, 'rest-daily-1');
  });

  test('monthly query applies a hub snapshot of the same track as-is, without REST', () async {
    container.listen(rankingControllerProvider(monthly), (_, _) {});
    await container.read(rankingControllerProvider(monthly).future);

    hub.updates.add(hubPayload('t1', [entryOf(1, '허브', 79000)]));
    await pumpEventQueue();

    final state = container.read(rankingControllerProvider(monthly)).requireValue;
    expect(state.entries.single.displayName, '허브');
    expect(repo.requests, hasLength(1));
  });

  test('ignores hub snapshots of other tracks', () async {
    container.listen(rankingControllerProvider(monthly), (_, _) {});
    await container.read(rankingControllerProvider(monthly).future);

    hub.updates.add(hubPayload('t2', [entryOf(1, '다른 트랙', 79000)]));
    await pumpEventQueue();

    final state = container.read(rankingControllerProvider(monthly)).requireValue;
    expect(state.entries.single.displayName, 'rest-monthly-1');
    expect(repo.requests, hasLength(1));
  });

  test('daily query re-reads over REST when the hub reports the same track', () async {
    container.listen(rankingControllerProvider(daily), (_, _) {});
    await container.read(rankingControllerProvider(daily).future);

    hub.updates.add(hubPayload('t1', [entryOf(1, '허브(월별)', 79000)]));
    await pumpEventQueue();

    final state = container.read(rankingControllerProvider(daily)).requireValue;
    expect(repo.requests, hasLength(2));
    expect(repo.requests.last, (trackId: 't1', period: 'daily'));
    expect(state.entries.single.displayName, 'rest-daily-2');
    expect(state.period, 'daily');
  });

  test('daily query does not re-read when the hub reports another track', () async {
    container.listen(rankingControllerProvider(daily), (_, _) {});
    await container.read(rankingControllerProvider(daily).future);

    hub.updates.add(hubPayload('t2', [entryOf(1, '다른 트랙', 79000)]));
    await pumpEventQueue();

    expect(repo.requests, hasLength(1));
  });

  test('switching period on the same track keeps the track subscribed until the last listener goes', () async {
    final monthlySub = container.listen(rankingControllerProvider(monthly), (_, _) {});
    await container.read(rankingControllerProvider(monthly).future);

    final dailySub = container.listen(rankingControllerProvider(daily), (_, _) {});
    await container.read(rankingControllerProvider(daily).future);
    monthlySub.close();
    await pumpEventQueue();

    expect(hub.subscribed, ['t1']);
    expect(hub.unsubscribed, isEmpty);

    dailySub.close();
    await pumpEventQueue();

    expect(hub.unsubscribed, ['t1']);
  });
}
