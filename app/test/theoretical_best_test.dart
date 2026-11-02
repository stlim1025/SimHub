import 'package:flutter_test/flutter_test.dart';
import 'package:simcenter_app/features/tracks/domain/theoretical_best.dart';

Map<String, dynamic> _segment(int index, int startM, int endM, String lapId, int timeMs, int bestMs,
        {double? deploy, double? harvest, double? bestDeploy, double? bestHarvest}) =>
    {
      'index': index,
      'startM': startM,
      'endM': endM,
      'lapId': lapId,
      'lapSetAt': '2026-10-30T10:00:00Z',
      'timeMs': timeMs,
      'bestLapTimeMs': bestMs,
      'deployKj': deploy,
      'harvestKj': harvest,
      'bestLapDeployKj': bestDeploy,
      'bestLapHarvestKj': bestHarvest,
    };

void main() {
  final json = {
    'groups': [
      {
        'sessionType': 'Qualifying',
        'visualTyreCompound': 16,
        'isWet': true,
        'lapCount': 7,
        'lapLengthM': 1000,
        'bestLapId': 'best',
        'bestLapMs': 73994,
        'theoreticalMs': 73653,
        'unlimitedMs': 73531,
        'hasBattery': true,
        'segments': [
          _segment(0, 0, 270, 'l4', 7560, 7536, deploy: 616, harvest: 67, bestDeploy: 616, bestHarvest: 67),
          _segment(1, 270, 670, 'l2', 7451, 7592, deploy: 1770, harvest: 948, bestDeploy: 731, bestHarvest: 33),
          _segment(2, 670, 1000, 'l3', 6029, 6060, deploy: 508, harvest: 173, bestDeploy: 398, bestHarvest: 111),
        ],
      },
      {'sessionType': 'TimeTrial', 'segments': []},
    ],
  };

  test('조건을 읽고 형식이 틀린 조건은 버린다', () {
    final groups = parseTheoreticalBest(json);

    expect(groups, hasLength(1));
    final group = groups.single;
    expect((group.sessionType, group.visualTyreCompound, group.isWet, group.lapCount, group.hasBattery), ('Qualifying', 16, true, 7, true));
    expect((group.gainMs, group.batteryLimitMs), (-341, 122));
    expect(group.segments[1].lapSetAt, DateTime.utc(2026, 10, 30, 10));
  });

  test('최고 랩과 10ms 이상 다른 구간을 많이 줄어드는 순으로, 배터리를 아끼느라 느려지는 구간은 뒤에', () {
    final group = parseTheoreticalBest(json).single;

    expect(group.changes.map((s) => (s.index, s.gainMs)), [(1, -141), (2, -31), (0, 24)]);
  });

  test('구간 이름은 그 안의 공식 코너, 없으면 구간 번호', () {
    final group = parseTheoreticalBest(json).single;
    const corners = [
      (number: 1, letter: '', fraction: 0.30),
      (number: 2, letter: '', fraction: 0.45),
      (number: 3, letter: 'A', fraction: 0.62),
    ];

    expect(theoreticalSegmentLabels(group, corners), ['구간 1', 'T1~T3A', '구간 3']);
    expect(theoreticalSegmentLabels(group, null), ['구간 1', '구간 2', '구간 3']);
  });

  test('배터리 차이는 한 통 대비 %, 2.5% 안쪽은 같음', () {
    final segments = parseTheoreticalBest(json).single.segments;

    expect(theoreticalBatteryDelta(segments[1]), '씀 +26% · 채움 +23%');
    expect(theoreticalBatteryDelta(segments[2]), '씀 +3%');
    expect(theoreticalBatteryDelta(segments[0]), '같음');
  });
}
