import 'package:flutter_test/flutter_test.dart';
import 'package:simcenter_app/features/dashboard/domain/dashboard_season.dart';

import 'support/fakes.dart';

void main() {
  group('dashboardSeasonOf', () {
    final older = seasonOf('s1', lastSessionAt: DateTime(2026, 10, 10));
    final newer = seasonOf('s2', lastSessionAt: DateTime(2026, 10, 16));
    final done = seasonOf('s3', lastSessionAt: DateTime(2026, 10, 17), completedAt: DateTime(2026, 10, 17));
    final seasons = [older, done, newer];

    test('진행 중인 시즌은 최근 시즌 먼저, 완료된 시즌은 빼고', () {
      expect(activeSeasons(seasons).map((s) => s.seasonId), ['s2', 's1']);
    });

    test('고른 진행 중인 시즌, 고르지 않았거나 끝났거나 모르는 시즌이면 가장 최근 진행 중인 시즌', () {
      expect(dashboardSeasonOf(seasons, 's1')?.seasonId, 's1');
      expect(dashboardSeasonOf(seasons, null)?.seasonId, 's2');
      expect(dashboardSeasonOf(seasons, 's3')?.seasonId, 's2');
      expect(dashboardSeasonOf(seasons, 'gone')?.seasonId, 's2');
      expect(dashboardSeasonOf(const [], 's1'), isNull);
    });
  });

  group('nextCalendarRound', () {
    test('마지막으로 달린 라운드 다음의 달리지 않은 라운드', () {
      final calendar = [
        seasonCalendarRoundOf(1, firstSessionId: 'a'),
        seasonCalendarRoundOf(2),
        seasonCalendarRoundOf(3, firstSessionId: 'c'),
        seasonCalendarRoundOf(4),
      ];

      expect(nextCalendarRound(calendar)?.round, 4);
    });

    test('캘린더를 다 달렸으면 null', () {
      expect(nextCalendarRound([seasonCalendarRoundOf(1, firstSessionId: 'a')]), isNull);
    });

    test('아직 아무 라운드도 달리지 않았으면 첫 라운드', () {
      expect(nextCalendarRound([seasonCalendarRoundOf(1), seasonCalendarRoundOf(2)])?.round, 1);
    });
  });

  group('leaderGap', () {
    test('내가 선두면 2위와의 차(양수)', () {
      final gap = leaderGap([
        driverStandingOf(1, isPlayer: true, points: 100),
        driverStandingOf(2, name: 'NORRIS', points: 82),
      ]);

      expect(gap?.gap, 18);
      expect(gap?.rival.name, 'NORRIS');
    });

    test('내 결과가 없으면 null', () {
      expect(leaderGap([driverStandingOf(1, points: 10), driverStandingOf(2, points: 5)]), isNull);
    });
  });

  group('standingsPreview', () {
    test('내가 위쪽 5명 안이면 위쪽 5명만', () {
      final preview = standingsPreview([
        for (var p = 1; p <= 8; p++) driverStandingOf(p, isPlayer: p == 2),
      ]);

      expect([for (final d in preview) d.position], [1, 2, 3, 4, 5]);
    });

    test('내가 뒤쪽이면 위쪽 5명 + 내 앞뒤', () {
      final preview = standingsPreview([
        for (var p = 1; p <= 12; p++) driverStandingOf(p, isPlayer: p == 9),
      ]);

      expect([for (final d in preview) d.position], [1, 2, 3, 4, 5, 8, 9, 10]);
    });
  });

  test('recentCalendarRounds는 달린 라운드만 최근 순으로 정해진 개수까지', () {
    final calendar = [for (var r = 1; r <= 8; r++) seasonCalendarRoundOf(r, firstSessionId: r <= 7 ? 's$r' : null)];

    expect([for (final r in recentCalendarRounds(calendar)) r.round], [7, 6, 5, 4, 3]);
  });
}
