import 'package:flutter_test/flutter_test.dart';
import 'package:simcenter_app/features/seasons/domain/season_display.dart';

import 'support/fakes.dart';

void main() {
  test('시즌 상수는 스펙 값이다', () {
    expect(kSeasonsPageSize, 20);
    expect(kResultsRowHeight, 40);
    expect(kResultsNameColumnWidth, 180);
  });

  group('normalizeSeasonTab', () {
    test('season·results·standings는 그대로 둔다', () {
      expect(normalizeSeasonTab('season'), 'season');
      expect(normalizeSeasonTab('results'), 'results');
      expect(normalizeSeasonTab('standings'), 'standings');
    });

    test('없거나 모르는 값(대소문자 포함)은 season이다', () {
      expect(normalizeSeasonTab(null), 'season');
      expect(normalizeSeasonTab(''), 'season');
      expect(normalizeSeasonTab('weird'), 'season');
      expect(normalizeSeasonTab('Results'), 'season');
    });
  });

  group('seasonPeriodLabel', () {
    test('시작·끝 날짜를 yyyy.MM.dd ~ yyyy.MM.dd로 보인다', () {
      final season = seasonOf(
        's',
        firstSessionAt: DateTime(2026, 10, 17, 12),
        lastSessionAt: DateTime(2026, 11, 2, 12),
      );

      expect(seasonPeriodLabel(season), '2026.10.17 ~ 2026.11.02');
    });

    test('같은 날이면 날짜 하나만 보인다', () {
      final season = seasonOf(
        's',
        firstSessionAt: DateTime(2026, 10, 17, 9),
        lastSessionAt: DateTime(2026, 10, 17, 20),
      );

      expect(seasonPeriodLabel(season), '2026.10.17');
    });
  });

  test('myStandingLabel', () {
    expect(myStandingLabel(3, 87), 'P3 · 87 pts');
    expect(myStandingLabel(12, 0), 'P12 · 0 pts');
    expect(myStandingLabel(null, null), '-');
    expect(myStandingLabel(3, null), 'P3');
  });

  test('leaderLabel', () {
    expect(leaderLabel('VERSTAPPEN', 120), 'VERSTAPPEN 120');
    expect(leaderLabel(null, null), '-');
    expect(leaderLabel('VERSTAPPEN', null), 'VERSTAPPEN');
  });

  test('roundsLabel', () {
    expect(roundsLabel(6), '6 rounds');
    expect(roundsLabel(24), '24 rounds');
  });

  group('standingCellText', () {
    test('끝까지 달린 칸은 순위 숫자다', () {
      expect(standingCellText(standingCellOf(1, position: 1, resultStatus: 'Finished')), '1');
      expect(standingCellText(standingCellOf(1, position: 14, resultStatus: 'Active')), '14');
    });

    test('완주하지 못한 칸은 순위와 상관없이 상태 라벨이다', () {
      expect(standingCellText(standingCellOf(1, position: 20, resultStatus: 'DidNotFinish')), 'DNF');
      expect(standingCellText(standingCellOf(1, position: 21, resultStatus: 'Disqualified')), 'DSQ');
      expect(standingCellText(standingCellOf(1, position: 22, resultStatus: 'NotClassified')), 'NC');
      expect(standingCellText(standingCellOf(1, position: 19, resultStatus: 'Retired')), 'RET');
    });

    test('기록이 없는 칸은 -다', () {
      expect(standingCellText(null), '-');
      expect(standingCellText(standingCellOf(1, points: 8)), '-'); // 본 레이스 기록 없음(스프린트 점수만)
      expect(standingCellText(standingCellOf(1, position: 5, resultStatus: 'Unknown')), '-');
    });
  });

  group('standingCellShowsPosition', () {
    test('본 레이스 기록이 있고 끝까지 달린 칸만 순위를 보인다', () {
      expect(standingCellShowsPosition(standingCellOf(1, position: 4, resultStatus: 'Finished')), isTrue);
      expect(standingCellShowsPosition(standingCellOf(1, position: 4, resultStatus: 'Active')), isTrue);
      expect(standingCellShowsPosition(standingCellOf(1, position: 20, resultStatus: 'DidNotFinish')), isFalse);
      expect(standingCellShowsPosition(standingCellOf(1, resultStatus: 'Finished')), isFalse); // 순위 없음
      expect(standingCellShowsPosition(standingCellOf(1, points: 3)), isFalse);
      expect(standingCellShowsPosition(null), isFalse);
    });
  });

  group('standingCellPodiumPlace', () {
    test('끝까지 달린 1·2·3위만 시상대 순위다', () {
      expect(standingCellPodiumPlace(standingCellOf(1, position: 1, resultStatus: 'Finished')), 1);
      expect(standingCellPodiumPlace(standingCellOf(1, position: 3, resultStatus: 'Finished')), 3);
      expect(standingCellPodiumPlace(standingCellOf(1, position: 4, resultStatus: 'Finished')), isNull);
    });

    test('상태 칸·기록 없음은 시상대가 아니다', () {
      expect(standingCellPodiumPlace(standingCellOf(1, position: 2, resultStatus: 'DidNotFinish')), isNull);
      expect(standingCellPodiumPlace(standingCellOf(1)), isNull);
      expect(standingCellPodiumPlace(null), isNull);
    });
  });

  group('sessionChipResult', () {
    test('순위가 있으면 P순위', () {
      expect(sessionChipResult(4, 'Finished'), 'P4');
      expect(sessionChipResult(2, null), 'P2');
    });

    test('완주하지 못했으면 상태 라벨', () {
      expect(sessionChipResult(20, 'DidNotFinish'), 'DNF');
      expect(sessionChipResult(null, 'Retired'), 'RET');
    });

    test('내 결과가 없거나 상태를 모르면 null', () {
      expect(sessionChipResult(null, null), isNull);
      expect(sessionChipResult(null, 'Unknown'), isNull);
    });
  });
}
