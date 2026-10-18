import 'package:flutter_test/flutter_test.dart';
import 'package:simcenter_app/features/sessions/domain/session_display.dart';
import 'package:simcenter_app/features/sessions/domain/session_models.dart';

import 'support/fakes.dart';

/// 레이스 기준 행(1위, 총 1598765 ms, 패널티 0, 15랩).
SessionResult _leader() => resultOf(1, totalRaceTimeMs: 1598765);

void main() {
  group('sessionKindLabel', () {
    test('sessionKindLabel maps every kind', () {
      const expected = {
        'Practice1': 'P1',
        'Practice2': 'P2',
        'Practice3': 'P3',
        'ShortPractice': 'P',
        'Qualifying1': 'Q1',
        'Qualifying2': 'Q2',
        'Qualifying3': 'Q3',
        'ShortQualifying': 'Q',
        'OneShotQualifying': 'OSQ',
        'SprintShootout1': 'SQ1',
        'SprintShootout2': 'SQ2',
        'SprintShootout3': 'SQ3',
        'ShortSprintShootout': 'SQ',
        'OneShotSprintShootout': 'OSSQ',
        'Race': 'R',
        'Race2': 'R2',
        'Race3': 'R3',
        'TimeTrial': 'TT',
        'Unknown': '-',
        'Weird': '-',
        '': '-',
      };
      for (final entry in expected.entries) {
        expect(sessionKindLabel(entry.key), entry.value, reason: entry.key);
      }
    });

    test('스프린트 주말이면 Race = S(스프린트), Race2 = R(레이스), 나머지는 그대로', () {
      expect(sessionKindLabel('Race', sprintWeekend: true), 'S');
      expect(sessionKindLabel('Race2', sprintWeekend: true), 'R');
      expect(sessionKindLabel('Qualifying1', sprintWeekend: true), 'Q1');
      expect(sessionKindLabel('Race'), 'R');
      expect(displaySessionKind('Race', sprintWeekend: true), 'Sprint');
      expect(displaySessionKind('Race2'), 'Race2');
    });
  });

  group('knownPosition / positionText', () {
    test('0 이하 = 모름 → null / -', () {
      expect(knownPosition(0), isNull);
      expect(knownPosition(-1), isNull);
      expect(knownPosition(null), isNull);
      expect(knownPosition(3), 3);
      expect(positionText(0), '-');
      expect(positionText(7), '7');
    });
  });

  group('resultStatusLabel / isRunningOrFinished', () {
    test('resultStatusLabel', () {
      const expected = {
        'DidNotFinish': 'DNF',
        'Disqualified': 'DSQ',
        'NotClassified': 'NC',
        'Retired': 'RET',
        'Unknown': '-',
        'Finished': '',
        'Active': '',
        'Weird': '-',
      };
      for (final entry in expected.entries) {
        expect(resultStatusLabel(entry.key), entry.value, reason: entry.key);
      }
    });

    test('isRunningOrFinished is true only for Finished and Active', () {
      expect(isRunningOrFinished('Finished'), isTrue);
      expect(isRunningOrFinished('Active'), isTrue);
      for (final status in ['DidNotFinish', 'Disqualified', 'NotClassified', 'Retired', 'Unknown', 'Weird']) {
        expect(isRunningOrFinished(status), isFalse, reason: status);
      }
    });
  });

  group('gameModeLabel', () {
    test('gameModeLabel maps every mode, anything else is Other', () {
      const expected = {
        'DriverCareer': 'Driver Career',
        'MyTeamCareer': 'My Team',
        'OnlineCareer': 'Online Career',
        'ChallengeCareer': 'Challenge Career',
        'GrandPrix': 'Grand Prix',
        'TimeTrial': 'Time Trial',
        'Online': 'Online',
        'Story': 'Story',
        'Other': 'Other',
        'Weird': 'Other',
      };
      for (final entry in expected.entries) {
        expect(gameModeLabel(entry.key), entry.value, reason: entry.key);
      }
    });
  });

  group('time formats', () {
    test('formatRaceTime_HourBoundary', () {
      expect(formatRaceTime(3599999), '59:59.999');
      expect(formatRaceTime(3600000), '1:00:00.000');
      expect(formatRaceTime(83456), '1:23.456');
      expect(formatRaceTime(0), '0:00.000');
      expect(formatRaceTime(5400123), '1:30:00.123');
    });

    test('formatGapMs_MinuteBoundary', () {
      expect(formatGapMs(16235), '+16.235');
      expect(formatGapMs(59999), '+59.999');
      expect(formatGapMs(60000), '+1:00.000');
      expect(formatGapMs(75123), '+1:15.123');
      expect(formatGapMs(5), '+0.005');
      expect(formatGapMs(0), '+0.000');
      expect(formatGapMs(-5), '+0.000');
    });
  });

  group('penaltyLabel', () {
    test('penaltyLabel', () {
      expect(penaltyLabel(0, 0), '-');
      expect(penaltyLabel(2, 5000), '+5s (2)');
      expect(penaltyLabel(1, 0), '(1)');
    });

    test('penaltyLabel keeps a fractional second visible', () {
      expect(penaltyLabel(1, 500), '+0.5s (1)');
    });
  });

  group('session filter', () {
    test('known filters map to the API sessionType, all is null', () {
      expect(sessionTypeForFilter('all'), isNull);
      expect(sessionTypeForFilter('race'), 'Race');
      expect(sessionTypeForFilter('qualifying'), 'Qualifying');
      expect(sessionTypeForFilter('practice'), 'Practice');
    });

    test('normalizeSessionFilter falls back to all for null and unknown values', () {
      expect(normalizeSessionFilter('race'), 'race');
      expect(normalizeSessionFilter('practice'), 'practice');
      for (final bad in [null, '', 'weird', 'Race', 'timetrial']) {
        expect(normalizeSessionFilter(bad), 'all', reason: '$bad');
      }
    });
  });

  group('referenceRow', () {
    test('referenceRow_SkipsNotRunningLeader', () {
      final results = [
        resultOf(1, resultStatus: 'DidNotFinish'),
        resultOf(2, resultStatus: 'Finished'),
        resultOf(3, resultStatus: 'Finished'),
      ];
      expect(referenceRow(results, isRace: true)?.position, 2);
    });

    test('referenceRow accepts an Active row as the race reference', () {
      final results = [resultOf(1, resultStatus: 'Retired'), resultOf(2, resultStatus: 'Active')];
      expect(referenceRow(results, isRace: true)?.position, 2);
    });

    test('referenceRow_AllNotRunning_IsNull', () {
      final results = [
        resultOf(1, resultStatus: 'DidNotFinish'),
        resultOf(2, resultStatus: 'Retired'),
      ];
      expect(referenceRow(results, isRace: true), isNull);
      expect(referenceRow(const [], isRace: true), isNull);
    });

    test('referenceRow picks the lowest position even if the list is unordered', () {
      final results = [resultOf(3), resultOf(1), resultOf(2)];
      expect(referenceRow(results, isRace: true)?.position, 1);
    });

    test('referenceRow_NonRace_IsFastestBestLapRegardlessOfStatusOrPosition', () {
      final results = [
        resultOf(1, bestLapTimeMs: 82000),
        resultOf(2, bestLapTimeMs: 81234, resultStatus: 'Retired'),
        resultOf(3),
      ];
      expect(referenceRow(results, isRace: false)?.position, 2);
    });

    test('referenceRow_NonRace_NoBestLaps_IsNull', () {
      expect(referenceRow([resultOf(1), resultOf(2)], isRace: false), isNull);
    });
  });

  group('timeOrGap (race)', () {
    test('timeOrGap_Race_Leader_ShowsTotalIncludingPenalties', () {
      final leader = resultOf(1, totalRaceTimeMs: 1598765, penaltiesTimeMs: 5000, numPenalties: 1);
      expect(timeOrGap(leader, leader, isRace: true), '26:43.765');
    });

    test('timeOrGap_Race_SameLap', () {
      final reference = _leader();
      final row = resultOf(2, totalRaceTimeMs: 1610000, penaltiesTimeMs: 5000, numPenalties: 1);
      expect(timeOrGap(row, reference, isRace: true), '+16.235'); // (1610000 + 5000) - 1598765
    });

    test('timeOrGap_Race_SameLap_NegativeDifferenceIsZeroGap', () {
      final reference = resultOf(1, totalRaceTimeMs: 1598765, penaltiesTimeMs: 10000);
      final row = resultOf(2, totalRaceTimeMs: 1600000);
      expect(timeOrGap(row, reference, isRace: true), '+0.000');
    });

    test('timeOrGap_Race_SameLap_OverAMinute', () {
      final row = resultOf(2, totalRaceTimeMs: 1598765 + 75123);
      expect(timeOrGap(row, _leader(), isRace: true), '+1:15.123');
    });

    test('timeOrGap_Race_Lapped', () {
      final reference = _leader();
      expect(timeOrGap(resultOf(2, numLaps: 14, totalRaceTimeMs: 1), reference, isRace: true), '+1 Lap');
      expect(timeOrGap(resultOf(3, numLaps: 13), reference, isRace: true), '+2 Laps');
    });

    test('timeOrGap_Race_NotRunning_ShowsStatus', () {
      final reference = _leader();
      expect(timeOrGap(resultOf(5, resultStatus: 'DidNotFinish'), reference, isRace: true), 'DNF');
      expect(timeOrGap(resultOf(6, resultStatus: 'Disqualified'), reference, isRace: true), 'DSQ');
      expect(timeOrGap(resultOf(7, resultStatus: 'NotClassified'), reference, isRace: true), 'NC');
      expect(timeOrGap(resultOf(8, resultStatus: 'Retired'), reference, isRace: true), 'RET');
      expect(timeOrGap(resultOf(9, resultStatus: 'Unknown'), reference, isRace: true), '-');
    });

    test('timeOrGap_Race_NullTotal_ShowsDash', () {
      final reference = _leader();
      expect(timeOrGap(resultOf(2), reference, isRace: true), '-'); // 행 total null
      final noTotalReference = resultOf(1);
      expect(timeOrGap(resultOf(2, totalRaceTimeMs: 1600000), noTotalReference, isRace: true), '-'); // 기준 null
      expect(timeOrGap(noTotalReference, noTotalReference, isRace: true), '-'); // 기준 자신
    });

    test('timeOrGap_Race_NoReference', () {
      expect(timeOrGap(resultOf(2), null, isRace: true), '-');
      expect(timeOrGap(resultOf(2, resultStatus: 'DidNotFinish'), null, isRace: true), 'DNF');
    });
  });

  group('timeOrGap (non-race)', () {
    test('timeOrGap_Qualifying', () {
      final fastest = resultOf(3, bestLapTimeMs: 81234);
      final results = [
        resultOf(1, bestLapTimeMs: 81500),
        resultOf(2),
        fastest,
        resultOf(4, resultStatus: 'Retired'),
      ];
      final reference = referenceRow(results, isRace: false);

      expect(reference?.position, 3);
      expect(timeOrGap(fastest, reference, isRace: false), '1:21.234');
      expect(timeOrGap(results[0], reference, isRace: false), '+0.266');
      expect(timeOrGap(results[1], reference, isRace: false), '-'); // best null & Finished
      expect(timeOrGap(results[3], reference, isRace: false), 'RET'); // best null & Retired
    });

    test('timeOrGap_Qualifying_ReferenceCanBeNotRunning', () {
      final retired = resultOf(5, bestLapTimeMs: 80000, resultStatus: 'Retired');
      final other = resultOf(1, bestLapTimeMs: 80500);
      final reference = referenceRow([other, retired], isRace: false);

      expect(timeOrGap(retired, reference, isRace: false), '1:20.000');
      expect(timeOrGap(other, reference, isRace: false), '+0.500');
    });

    test('timeOrGap_Qualifying_NoTimes', () {
      final results = [resultOf(1), resultOf(2, resultStatus: 'DidNotFinish')];
      final reference = referenceRow(results, isRace: false);

      expect(reference, isNull);
      expect(timeOrGap(results[0], reference, isRace: false), '-');
      expect(timeOrGap(results[1], reference, isRace: false), 'DNF');
    });
  });
}
