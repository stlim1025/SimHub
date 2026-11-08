import 'package:flutter_test/flutter_test.dart';
import 'package:simcenter_app/features/dashboard/domain/dashboard_home.dart';
import 'package:simcenter_app/features/laps/domain/lap_models.dart';

import 'support/fakes.dart';

MyTrack _track(String id, String name, {int? bestMs = 80000, required int day}) => MyTrack(
      trackId: id,
      trackName: name,
      gameCode: 'F1_25',
      lapCount: 3,
      bestValidLapTimeMs: bestMs,
      lastSetAt: DateTime.utc(2026, 10, day),
    );

void main() {
  group('latestSession', () {
    test('분류 시각이 가장 늦은 세션(목록 순서와 무관)', () {
      final latest = latestSession([
        sessionOf('a', classifiedAt: DateTime.utc(2026, 10, 1)),
        sessionOf('b', classifiedAt: DateTime.utc(2026, 10, 9)),
        sessionOf('c', classifiedAt: DateTime.utc(2026, 10, 5)),
      ]);

      expect(latest?.sessionId, 'b');
    });

    test('목록이 비면 null', () {
      expect(latestSession(const []), isNull);
    });
  });

  group('positionsGained', () {
    test('출발 - 결승, 하나라도 모르면 null', () {
      expect(positionsGained(grid: 7, finish: 3), 4);
      expect(positionsGained(grid: 2, finish: 5), -3);
      expect(positionsGained(grid: null, finish: 3), isNull);
      expect(positionsGained(grid: 7, finish: null), isNull);
    });

    test('글자: +4 · -3 · ±0', () {
      expect(positionsGainedText(4), '+4');
      expect(positionsGainedText(-3), '-3');
      expect(positionsGainedText(0), '±0');
    });
  });

  group('lastRaceExtrasOf', () {
    test('상세가 없으면 빈 값', () {
      final extras = lastRaceExtrasOf(null);

      expect(extras.round, isNull);
      expect(extras.pitStops, isNull);
      expect(extras.winnerGap, isNull);
      expect(extras.hasHighlights, isFalse);
    });

    test('라운드 · 내 피트 · 우승과 차이 · 최고 랩 · 하이라이트 여부', () {
      final extras = lastRaceExtrasOf(detailOf('r', round: 9, hasFieldSamples: true, results: [
        resultOf(1, totalRaceTimeMs: 5400000),
        resultOf(2, isPlayer: true, gapMs: 1904, numPitStops: 2, isFastestLap: true),
      ]));

      expect(extras.round, 9);
      expect(extras.pitStops, 2);
      expect(extras.winnerGap, '+0:01.904');
      expect(extras.fastestLap, isTrue);
      expect(extras.hasHighlights, isTrue);
    });

    test('내가 우승했거나 완주하지 못했으면 우승과 차이는 없다', () {
      final won = lastRaceExtrasOf(detailOf('r', results: [resultOf(1, isPlayer: true, totalRaceTimeMs: 5400000)]));
      final retired = lastRaceExtrasOf(detailOf('r', results: [
        resultOf(1, totalRaceTimeMs: 5400000),
        resultOf(2, isPlayer: true, resultStatus: 'DidNotFinish'),
      ]));

      expect(won.winnerGap, isNull);
      expect(retired.winnerGap, isNull);
    });

    test('모든 차 표본이 없거나 레이스가 아니면 하이라이트는 없다', () {
      expect(lastRaceExtrasOf(detailOf('r', hasFieldSamples: false)).hasHighlights, isFalse);
      expect(lastRaceExtrasOf(detailOf('r', sessionType: 'Qualifying', hasFieldSamples: true)).hasHighlights, isFalse);
    });
  });

  group('recentPersonalBests', () {
    test('최고 유효 랩이 있는 트랙만, 최근에 달린 순서로 count개', () {
      final bests = recentPersonalBests([
        _track('a', 'A', day: 1),
        _track('b', 'B', day: 9),
        _track('c', 'C', bestMs: null, day: 10),
        _track('d', 'D', day: 5),
      ], count: 2);

      expect([for (final t in bests) t.trackId], ['b', 'd']);
    });
  });

  group('gapToPersonalBest', () {
    final bests = personalBestByTrackName([_track('a', 'Spa', bestMs: 104311, day: 1), _track('b', 'Monza', bestMs: null, day: 2)]);

    test('트랙 이름 → 최고 랩(유효 랩이 없는 트랙은 빠진다)', () {
      expect(bests, {'Spa': 104311});
    });

    test('유효 랩은 최고 랩과의 차, 무효 랩이나 최고 랩을 모르는 트랙은 null', () {
      expect(gapToPersonalBest(lapOf('l1', 'Spa', 104709), bests), 398);
      expect(gapToPersonalBest(lapOf('l2', 'Spa', 104311), bests), 0);
      expect(gapToPersonalBest(lapOf('l3', 'Spa', 100000, isValid: false), bests), isNull);
      expect(gapToPersonalBest(lapOf('l4', 'Monza', 80000), bests), isNull);
    });
  });
}
