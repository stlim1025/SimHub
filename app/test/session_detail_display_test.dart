import 'package:flutter_test/flutter_test.dart';
import 'package:simcenter_app/features/sessions/domain/session_detail_display.dart';
import 'package:simcenter_app/features/sessions/domain/session_models.dart';
import 'package:simcenter_app/features/sessions/domain/setup_display.dart';

import 'support/fakes.dart';

void main() {
  group('sessionKindName·gameModeLine', () {
    test('세션 종류 전체 이름, 모르면 -', () {
      expect(sessionKindName('Qualifying3'), 'Qualifying 3');
      expect(sessionKindName('Race'), 'Race');
      expect(sessionKindName('SprintShootout1'), 'Sprint Shootout 1');
      expect(sessionKindName('Weird'), '-');
    });

    test('스프린트 주말이면 Race → Sprint, Race2 → Race', () {
      expect(sessionKindName('Race', sprintWeekend: true), 'Sprint');
      expect(sessionKindName('Race2', sprintWeekend: true), 'Race');
      expect(sessionKindName('Race2'), 'Race 2');
      expect(sessionKindName('ShortQualifying', sprintWeekend: true), 'Short Qualifying');
    });

    test('시즌이면 Season N을 붙이고 아니면 모드만', () {
      expect(gameModeLine('DriverCareer', 1), 'Driver Career Season 1');
      expect(gameModeLine('GrandPrix', null), 'Grand Prix');
    });
  });

  group('formatClassificationGap', () {
    test('분을 항상 붙인다', () {
      expect(formatClassificationGap(2309), '+0:02.309');
      expect(formatClassificationGap(65432), '+1:05.432');
      expect(formatClassificationGap(3723456), '+1:02:03.456');
    });

    test('음수는 0', () => expect(formatClassificationGap(-5), '+0:00.000'));
  });

  group('classificationGapText', () {
    final leader = resultOf(1, totalRaceTimeMs: 1598765, bestLapTimeMs: 90000);

    test('레이스: 1위는 총 시간, 나머지는 서버 gapMs', () {
      final second = resultOf(2, totalRaceTimeMs: 1601074, gapMs: 2309);
      expect(classificationGapText(leader, leader, isRace: true), '26:38.765');
      expect(classificationGapText(second, leader, isRace: true), '+0:02.309');
    });

    test('gapMs가 없으면 패널티 포함 총 시간 차로 계산', () {
      final second = resultOf(2, totalRaceTimeMs: 1600000, penaltiesTimeMs: 5000);
      expect(classificationGapText(second, leader, isRace: true), '+0:06.235');
    });

    test('랩이 뒤처지면 +n Lap, 끝내지 못했으면 상태', () {
      expect(classificationGapText(resultOf(3, numLaps: 14), leader, isRace: true), '+1 Lap');
      expect(classificationGapText(resultOf(3, numLaps: 12), leader, isRace: true), '+3 Laps');
      expect(classificationGapText(resultOf(4, resultStatus: 'DidNotFinish'), leader, isRace: true), 'DNF');
    });

    test('예선: 최고 랩 차', () {
      final second = resultOf(2, bestLapTimeMs: 90418);
      expect(classificationGapText(leader, leader, isRace: false), '1:30.000');
      expect(classificationGapText(second, leader, isRace: false), '+0:00.418');
      expect(classificationGapText(resultOf(3), leader, isRace: false), '-');
    });

    test('기준 행이 없으면 -', () => expect(classificationGapText(leader, null, isRace: true), '-'));
  });

  group('positionChangeOf', () {
    test('양수 ↑, 음수 ↓, 0은 -, null은 null', () {
      expect(positionChangeOf(1), (trend: PositionTrend.up, text: '1'));
      expect(positionChangeOf(-9), (trend: PositionTrend.down, text: '9'));
      expect(positionChangeOf(0), (trend: PositionTrend.same, text: '-'));
      expect(positionChangeOf(null), isNull);
    });
  });

  group('formatSectorTime', () {
    test('1분 미만 s.SSS, 이상 m:ss.SSS, 없으면 -', () {
      expect(formatSectorTime(30123), '30.123');
      expect(formatSectorTime(62345), '1:02.345');
      expect(formatSectorTime(null), '-');
    });
  });

  group('lapGapText', () {
    test('최고 랩·0·null은 -, 그 밖은 +s.SSS', () {
      expect(lapGapText(const SessionLap(lapNumber: 1, gapToBestMs: 418)), '+0.418');
      expect(lapGapText(const SessionLap(lapNumber: 2, gapToBestMs: 0)), '-');
      expect(lapGapText(const SessionLap(lapNumber: 3, isBestLap: true, gapToBestMs: 10)), '-');
      expect(lapGapText(const SessionLap(lapNumber: 4)), '-');
      expect(lapGapText(const SessionLap(lapNumber: 5, gapToBestMs: -123, isValid: false)), '-0.123');
    });
  });

  group('스틴트 그래프', () {
    const stints = [
      SessionTyreStint(visualCompound: 'Medium', startLap: 1, endLap: 3, laps: [
        StintLap(lapInStint: 2, lapTimeMs: 91000, tyreLifeRemaining: 94),
        StintLap(lapInStint: 1, lapTimeMs: 92000, tyreLifeRemaining: 97),
        StintLap(lapInStint: 3, lapTimeMs: 90500),
      ]),
      SessionTyreStint(visualCompound: 'Soft', laps: [StintLap(lapInStint: 1)]),
      SessionTyreStint(visualCompound: 'Hard', startLap: 4, endLap: 9, laps: [
        StintLap(lapInStint: 1, lapTimeMs: 90000, tyreLifeRemaining: 41.5),
      ]),
    ];

    test('tyreLifeLines: 값이 있는 랩만, x 순서대로, 값이 없는 스틴트는 뺀다', () {
      final lines = tyreLifeLines(stints);
      expect(lines, hasLength(2));
      expect(lines[0].label, 'Stint 1 · Medium (L1–L3)');
      expect(lines[0].compound, 'Medium');
      expect(lines[0].points, [(x: 1, y: 97.0), (x: 2, y: 94.0)]);
      expect(lines[1].label, 'Stint 3 · Hard (L4–L9)');
    });

    test('lapTimeLines: 랩타임(ms)', () {
      final lines = lapTimeLines(stints);
      expect(lines.first.points.map((p) => p.y), [92000, 91000, 90500]);
      expect(stintChartMaxX(lines), 3);
      expect(stintChartMaxX(const []), 1);
    });

    test('tyreLifeRange: 위 100, 아래 10 단위 내림', () {
      expect(tyreLifeRange(tyreLifeLines(stints)), (min: 40.0, max: 100.0));
      expect(tyreLifeRange(const []), (min: 0.0, max: 100.0));
    });

    test('lapTimeRange: 여백 + 0.5초 단위', () {
      expect(lapTimeRange(lapTimeLines(stints)), (min: 89500.0, max: 92500.0));
    });
  });

  group('engineWearItems·penaltyText', () {
    test('F1Laps 순서 8개', () {
      final items = engineWearItems(const EngineWear(ice: 12, gearbox: 22));
      expect(items.map((i) => i.label), [
        'ICE',
        'Turbo Charger',
        'MGU-H',
        'MGU-K',
        'Energy Store',
        'Control Electronics',
        'Gearbox',
        'Engine Damage',
      ]);
      expect(items.first.value, 12);
      expect(items[1].value, isNull);
    });

    test('시간 벌칙이면 초를 덧붙인다', () {
      expect(penaltyText(const SessionPenalty(penalty: 'Warning')), 'Warning');
      expect(penaltyText(const SessionPenalty(penalty: 'Time Penalty', timeS: 5)), 'Time Penalty (5s)');
      expect(penaltyText(const SessionPenalty()), '-');
    });
  });

  group('setupGroups', () {
    test('알려진 키는 묶음·이름·단위, 모르는 키는 Other에 그대로', () {
      final groups = setupGroups({
        'rearWing': 8,
        'frontWing': 10,
        'onThrottle': 50,
        'frontCamber': -3.5,
        'tyrePressureFL': 22.5,
        'fuelLoad': 10.0,
        'mystery': 'x',
        'nested': {'a': 1},
        'gone': null,
      });
      expect(groups.map((g) => g.title), ['Aerodynamics', 'Transmission', 'Suspension Geometry', 'Tyres', 'Fuel', 'Other']);
      expect(groups.first.items, [(label: 'Front Wing Aero', value: '10'), (label: 'Rear Wing Aero', value: '8')]);
      expect(groups[1].items.single, (label: 'Differential On Throttle', value: '50%'));
      expect(groups[2].items.single.value, '-3.5°');
      expect(groups[3].items.single, (label: 'Front Left Tyre Pressure', value: '22.5 psi'));
      expect(groups[4].items.single.value, '10 kg');
      expect(groups.last.items.single, (label: 'mystery', value: 'x'));
    });

    test('formatSetupValue: 소수 둘째 자리, 참/거짓', () {
      expect(formatSetupValue(0.123), '0.12');
      expect(formatSetupValue(true), 'Yes');
      expect(formatSetupValue(null), '-');
    });

    test('빈 셋업은 빈 묶음', () => expect(setupGroups(const {}), isEmpty));
  });
}
