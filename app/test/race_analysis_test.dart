import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simcenter_app/features/lap_detail/domain/lap_corners.dart';
import 'package:simcenter_app/features/sessions/domain/race_analysis.dart';
import 'package:simcenter_app/features/sessions/domain/race_review.dart';
import 'package:simcenter_app/features/sessions/presentation/race_review_card.dart';

/// 1km 트랙: 메인 직선(900→100m) · T1–T2(110~300m) · 직선(310~500m) · T3(510~700m) · T4(710~890m).
/// 두 Soft 스틴트(1–5·6–10랩): 앞스틴트는 메인 직선에서 배터리가 세 랩 모두 바닥나고 T4에서 AI보다 많이 쓴다.
Map<String, dynamic> _segment(int index, {List<double>? work, Map<String, dynamic> more = const {}}) => {
      'index': index,
      'timeMs': 10000,
      'steerPct': 20,
      'trailBrakeM': 0,
      'throttleSteerM': 0,
      'minSpeedKph': 150,
      'endSpeedKph': 200,
      'wheelWorkKj': ?work,
      ...more,
    };

/// [aiT4TimeMs] = AI가 T4를 지나는 시간(ms, 내 T4는 3.450초).
RaceAnalysis _build({int aiT4TimeMs = 3400}) => RaceAnalysis.fromJson({
  'trackLengthM': 1000,
  'referenceLap': 2,
  'wearPctPerMj': 5.0,
  'segments': [
    {'index': 0, 'kind': 'Straight', 'startM': 900, 'endM': 100, 'apexM': 900, 'minSpeedKph': 250},
    {'index': 1, 'kind': 'Corner', 'startM': 110, 'endM': 300, 'apexM': 200, 'minSpeedKph': 120},
    {'index': 2, 'kind': 'Straight', 'startM': 310, 'endM': 500, 'apexM': 310, 'minSpeedKph': 230},
    {'index': 3, 'kind': 'Corner', 'startM': 510, 'endM': 700, 'apexM': 600, 'minSpeedKph': 140},
    {'index': 4, 'kind': 'Corner', 'startM': 710, 'endM': 890, 'apexM': 800, 'minSpeedKph': 220},
  ],
  'stints': [
    {
      'compound': 'Soft', 'startLap': 1, 'endLap': 5, 'laps': [2, 3, 4],
      'wheelWorkKj': [500, 300, 400, 300], 'wheelWearPerLapPct': [4.0, 2.0, 3.0, 2.0], 'peakSurfaceTempC': [140, 100, 110, 100],
      'segments': [
        _segment(0, work: [5, 5, 40, 40], more: {'deployKj': 1200, 'harvestKj': 300, 'overtakeM': 300, 'fastOvertakeM': 150, 'emptyM': 150, 'emptyLaps': 3, 'storeEndKj': 400}),
        _segment(1, work: [200, 100, 150, 100], more: {
          'understeerDeg': 2.5, 'trailBrakeM': 30, 'throttleSteerM': 50, 'lockupM': 12, 'kerbM': 20, 'timeTrendMsPerLap': 40,
          'deployKj': 100, 'harvestKj': 800, 'brakeM': 60, 'storeEndKj': 1100,
        }),
        _segment(2, work: [5, 5, 30, 30], more: {'deployKj': 900, 'harvestKj': 50, 'overtakeM': 200, 'fastOvertakeM': 60, 'storeEndKj': 250}),
        _segment(3, work: [150, 80, 120, 90], more: {'understeerDeg': 1.0, 'throttleSteerM': 45, 'deployKj': 200, 'harvestKj': 700, 'brakeM': 50, 'storeEndKj': 750}),
        _segment(4, work: [100, 70, 80, 60], more: {
          'understeerDeg': 3.0, 'deployKj': 400, 'harvestKj': 50, 'overtakeM': 60, 'storeEndKj': 600, 'timeMs': 3450,
        }),
      ],
    },
    {
      'compound': 'Soft', 'startLap': 6, 'endLap': 10, 'laps': [7, 8, 9],
      'wheelWorkKj': [450, 290, 390, 290], 'wheelWearPerLapPct': [3.6, 2.0, 3.0, 2.0], 'peakSurfaceTempC': [138, 100, 110, 100],
      'segments': [
        _segment(0, work: [5, 5, 40, 40], more: {'deployKj': 1250, 'harvestKj': 300, 'overtakeM': 100, 'emptyM': 0, 'emptyLaps': 0, 'storeEndKj': 1000}),
        _segment(1, work: [170, 100, 150, 100], more: {'understeerDeg': 2.0, 'trailBrakeM': 20, 'throttleSteerM': 30, 'deployKj': 100, 'harvestKj': 800, 'brakeM': 60, 'storeEndKj': 1700}),
        _segment(2, work: [5, 5, 30, 30], more: {'deployKj': 400, 'harvestKj': 50, 'overtakeM': 0, 'storeEndKj': 1350}),
        _segment(3, work: [140, 80, 120, 90], more: {'understeerDeg': 1.0, 'throttleSteerM': 35, 'deployKj': 200, 'harvestKj': 700, 'brakeM': 50, 'storeEndKj': 1850}),
        _segment(4, work: [95, 70, 80, 60], more: {
          'understeerDeg': 2.6, 'deployKj': 380, 'harvestKj': 50, 'overtakeM': 40, 'storeEndKj': 1400, 'timeMs': 3450,
        }),
      ],
    },
  ],
  'fieldErs': [
    {'index': 0, 'harvestKj': 800, 'deployKj': 1300, 'cars': 19},
    {'index': 1, 'harvestKj': 900, 'deployKj': 300, 'cars': 19},
    {'index': 2, 'harvestKj': 100, 'deployKj': 900, 'cars': 19},
    {'index': 3, 'harvestKj': 800, 'deployKj': 300, 'cars': 19},
    {'index': 4, 'harvestKj': 300, 'deployKj': 100, 'cars': 19, 'liftM': 80, 'timeMs': aiT4TimeMs},
  ],
  'strategy': {
    'totalLaps': 10, 'idealLap': 5, 'latestLap': 8, 'pitLossMs': 20000,
    'stops': [
      {'lap': 5, 'idealLap': 5, 'latestLap': 8, 'wearPct': 40, 'lifeLapsLeft': 3, 'fromCompound': 'Soft', 'toCompound': 'Soft', 'newSetGainMs': 2000},
    ],
    'compounds': [
      {'compound': 'Soft', 'offsetMs': -400, 'degMsPerLap': 250, 'usableLaps': 9, 'sets': 3},
    ],
    'options': [
      {'stints': [{'compound': 'Soft', 'laps': 5}, {'compound': 'Soft', 'laps': 5}], 'deltaMs': 0, 'isActual': true},
      {'stints': [{'compound': 'Soft', 'laps': 4}, {'compound': 'Soft', 'laps': 3}, {'compound': 'Soft', 'laps': 3}], 'deltaMs': 3000, 'isActual': false},
    ],
  },
  'lapPace': [
    for (var lap = 1; lap <= 10; lap++)
      {
        'lap': lap,
        'lapTimeMs': 80000,
        'fieldSameLapMs': lap <= 5 ? 79800 : 80300,
        'fieldSameTyreMs': lap <= 5 ? 79500 : 80100,
        'compound': 'Soft',
        'tyreAge': lap <= 5 ? lap - 1 : lap - 6,
        'isClean': lap != 1 && lap != 5 && lap != 6,
      },
  ],
});

final RaceAnalysis _analysis = _build();

const List<OfficialCorner> _corners = [
  (number: 1, letter: '', fraction: 0.2),
  (number: 2, letter: '', fraction: 0.28),
  (number: 3, letter: '', fraction: 0.6),
  (number: 4, letter: '', fraction: 0.8),
];

const List<RaceStintReview> _stints = [
  RaceStintReview(compound: 'Soft', startLap: 1, endLap: 5, medianMs: 80000, fieldMedianMs: 79800, trendMsPerLap: 200, fieldTrendMsPerLap: 100),
  RaceStintReview(compound: 'Soft', startLap: 6, endLap: 10, medianMs: 80000, fieldMedianMs: 80300, trendMsPerLap: 0, fieldTrendMsPerLap: 100),
];

const Map<String, Object?> _setup = {'frontWing': 40, 'frontAntiRollBar': 7, 'brakeBias': 54, 'frontCamber': -3.5};

void main() {
  final labels = segmentLabels(_analysis, _corners);

  test('JSON → 심층 분석, 구간 이름(공식 코너는 한 구간에만, 없으면 순서 번호)', () {
    expect(_analysis.segments.where((s) => s.isCorner).length, 3);
    expect(_analysis.stints.first.segment(0)!.emptyLaps, 3);
    expect(_analysis.strategy!.options.last.plan, '소프트 4랩, 소프트 3랩, 소프트 3랩');
    expect(labels, ['메인 직선', 'T1~T2', 'T2→T3 직선', 'T3', 'T4']);
    expect(segmentLabels(_analysis, null), ['메인 직선', '코너 1', '직선 1', '코너 2', '코너 3']);
    // 두 구간 사이 빈틈(700~710m)의 코너는 앞뒤 여유 안 첫 구간 하나에만 든다.
    final between = segmentLabels(_analysis, const [(number: 9, letter: '', fraction: 0.705)]);
    expect(between.where((l) => l == 'T9').length, 1);
  });

  test('타이어: 리미터 바퀴, 부담 큰 코너의 원인과 할 것, 그립이 빠진 코너, 같은 컴파운드 비교, 세팅', () {
    final lines = deepTyreLines(_stints, _analysis, labels, _setup);
    expect(lines.first, '가장 빨리 닳는 건 앞왼 타이어야. 한 랩에 3.8%씩 닳아. 그다음은 뒤왼 타이어로 3.0%야');
    // T1~T2: 앞왼 (200 + 170) / 2 = 185kJ, 랩의 39%, 마모 ≈ 0.185MJ × 5%/MJ.
    expect(lines[1], startsWith('T1~T2: 앞왼 타이어가 여기서 랩마다 0.9%쯤 닳아. 한 랩에 닳는 양의 39%가 이 구간이야. 핸들을 평균 20% 꺾은 상태에서 앞바퀴가'));
    expect(lines[1], endsWith('→ 진입 속도를 조금 줄여. 핸들을 감은 채로 버티지 말고, 앞바퀴가 다시 노면을 잡으면 그때 돌려'));
    expect(lines[2], contains('T3: 앞왼 타이어가 여기서 랩마다 0.7%쯤 닳아'));
    // (45 + 35) / 2 = 문턱 40m
    expect(lines[2], endsWith('스로틀을 끝까지 밟은 채로 핸들을 꺾은 거리가 40m야 → 코너를 나갈 때 핸들을 먼저 풀고, 그다음에 스로틀을 끝까지 밟아'));
    expect(lines, contains('소프트(1~5랩): 랩이 지날수록 AI보다 랩당 0.100초씩 더 느려졌어. 특히 T1~T2에서 랩마다 0.040초씩 늘었어'));
    expect(
      lines,
      contains(startsWith('소프트(1~5랩)에는 소프트(6~10랩)보다 앞왼 타이어가 랩마다 0.3% 더 닳았어. '
          'T1~T2에서는 스로틀을 끝까지 밟은 채로 핸들을 꺾은 거리가 길었어(50m, 그때는 30m)')),
    );
    expect(lines, contains('세팅: 앞 캠버가 -3.50도면 코너 그립에는 좋지만 앞 타이어가 더 뜨거워져 → 레이스에서는 캠버를 0.1~0.2도 세워 봐(마이너스 값을 줄이는 쪽)'));
    // 부담 큰 코너(T1~T2 2.25° · T3 1.0° · T4 2.8°)의 평균 언더스티어 2.0° → 앞 날개·안티롤바.
    expect(
      lines,
      contains('세팅: 부담이 큰 코너들에서 앞바퀴가 뒷바퀴보다 평균 2.0도 더 미끄러져 → 앞 날개를 1~2 올리거나 앞 안티롤바를 낮춰서 앞쪽 그립을 높여 봐(지금 앞 날개 40, 앞 안티롤바 7)'),
    );
    // 트레이스로 분석한 스틴트가 없으면 줄이 없다.
    expect(deepTyreLines(_stints, RaceAnalysis.fromJson(const {}), const [], _setup), isEmpty);
  });

  test('배터리: 바닥난 스틴트는 고속 Overtake를 짧은 직선부터, 여유 있는 스틴트는 덜 쓴 직선을, 반만 떼는 코너는 완전히 떼라고', () {
    final lines = deepBatteryLines(null, _analysis, labels);
    // 배터리 양은 배터리 게이지 %(한 통 4MJ = 100%)로 말한다.
    expect(lines.first, '한 랩에 배터리를 64% 쓰고 48% 채웠어. AI는 73% 쓰고 73% 채웠어');
    // 280km/h 넘는 Overtake: T2→T3 직선(190m) 60m, 메인 직선(200m) 150m → 짧은 직선부터.
    expect(
      lines,
      contains('소프트(1~5랩): 3랩 중 3랩은 메인 직선에서 배터리가 바닥났어. 메인 직선에 들어갈 때 배터리가 15%였어. 바닥나지 않은 스틴트에서는 35%였어. '
          'T4에서 AI보다 배터리를 8% 더 썼어. 거기서 Overtake를 켠 거리가 60m야 '
          '→ 280km/h가 넘을 때 켜는 Overtake부터 줄여. T2→T3 직선에서 60m, 메인 직선에서 150m 순서로 줄이면 돼. '
          '짧은 직선일수록 같은 배터리로 버는 시간이 적어. 코너를 빠져나갈 때 켜는 Overtake는 그대로 둬'),
    );
    expect(lines, contains('소프트(6~10랩): 배터리가 바닥난 곳이 없는데 T2→T3 직선에서는 AI보다 배터리를 랩마다 13% 덜 썼어 → 거기서는 Overtake로 더 써'));
    // T4: 완전히 뗀 거리 0m로 50kJ — AI는 80m 완전히 떼고 300kJ(AI가 0.05초 빠르다).
    expect(
      lines,
      contains('T4: 코너에 들어갈 때 스로틀을 완전히 뗀 거리가 0m뿐이라 배터리를 랩마다 1%밖에 못 채워. AI는 80m를 완전히 떼고 8%를 채워. '
          '그러면서도 이 구간에서 시간을 잃지 않아 → 스로틀을 반만 떼고 버티지 말고, 완전히 뗀 다음 브레이크를 짧게 한 번 밟아'),
    );
    expect(lines.where((l) => l.startsWith('T4: 이 구간을 지나면서')), isEmpty);   // 같은 코너를 두 번 짚지 않는다

    // AI가 T4에서 0.15초 더 걸려 250kJ를 더 채우면(1MJ당 0.6초) 아직 권하고, 0.25초 더 걸리면(1MJ당 1.0초) 비싸서 권하지 않는다.
    expect(
      deepBatteryLines(null, _build(aiT4TimeMs: 3600), labels),
      contains(contains('그 대신 이 구간을 0.150초 더 걸려 지나가. 시간을 조금 내주고 배터리를 6% 더 채우는 셈이야')),
    );
    final costly = deepBatteryLines(null, _build(aiT4TimeMs: 3700), labels);
    expect(costly.where((l) => l.contains('완전히 뗀 거리')), isEmpty);
    expect(costly, contains('T4: 이 구간을 지나면서 너는 배터리가 랩마다 9% 줄고, AI는 5% 늘어. 여기서 Overtake를 켠 거리가 50m야 → 여기서는 Overtake를 끄고 지나가'));
  });

  test('전략: 피트 창과 스톱, 남은 랩으로 못 되찾는 스톱, 짧게 탄 컴파운드, 추정 대안', () {
    final lines = deepStrategyLines(_analysis, _stints);
    expect(lines[0], '출발할 때 게임이 알려 준 피트 시기는 5~8랩이었어. 피트에는 5랩에 1번 들어갔어. 모두 그때 게임이 가장 좋다고 본 랩이야');
    expect(
      lines[1],
      '5랩에 새 소프트로 바꿨어. 그때 타이어는 40% 닳아 있었어. 게임은 이 타이어로 3랩 더 갈 수 있다고 봤어(피트 시기 마지막은 8랩). '
      '새 소프트가 랩당 2.000초 빨라도, 피트 스톱 한 번에 잃는 20.0초를 되찾으려면 10랩이 필요한데 남은 랩은 5랩뿐이야 '
      '→ 타이어가 한계라서가 아니라 계획대로 들어온 거야',
    );
    expect(lines[2], '게임이 본 타이어 수명보다 일찍 바꾼 타이어가 있어. 소프트는 9랩까지 탈 수 있는데 5랩만 탔어 → 스틴트를 더 길게 가져가면 피트 스톱을 줄일 수 있어');
    expect(lines.last, '계산해 봐도 지금 전략이 가장 빨랐어. 피트에 들어가는 횟수를 바꿔도 차이가 1.0초도 안 나');

    // 대안이 빠르면: 스톱을 줄여 아낀 시간과 새 타이어로 되찾던 시간, 같은 스톱 수의 더 나은 배분.
    final faster = RaceAnalysis.fromJson({
      'strategy': {
        'totalLaps': 33, 'pitLossMs': 21478, 'stops': const [], 'compounds': const [],
        'options': [
          {'stints': [{'compound': 'Medium', 'laps': 9}, {'compound': 'Soft', 'laps': 7}, {'compound': 'Soft', 'laps': 7}, {'compound': 'Hard', 'laps': 10}], 'deltaMs': 0, 'isActual': true},
          {'stints': [{'compound': 'Medium', 'laps': 11}, {'compound': 'Soft', 'laps': 11}, {'compound': 'Soft', 'laps': 11}], 'deltaMs': -12623, 'isActual': false},
          {'stints': [{'compound': 'Medium', 'laps': 8}, {'compound': 'Soft', 'laps': 8}, {'compound': 'Soft', 'laps': 8}, {'compound': 'Soft', 'laps': 9}], 'deltaMs': -3391, 'isActual': false},
        ],
      },
    });
    expect(deepStrategyLines(faster, const []), [
      '계산해 보면(게임의 타이어 성능 정보와 내 타이어 마모로 추정) 미디엄 11랩, 소프트 11랩, 소프트 11랩으로 나눠서 피트에 2번 들어갔으면 12.6초 빨랐어. '
          '피트에 1번 덜 들어가니 21.5초를 아끼고, 새 타이어로 벌던 시간은 8.9초만 줄어',
      '피트에 3번 들어갈 거라면 미디엄 8랩, 소프트 8랩, 소프트 8랩, 소프트 9랩으로 나눴어야 3.4초 빨랐어',
    ]);
  });

  test('페이스: 기준 읽는 법, 스틴트마다 같은 타이어·같은 랩·스틴트 기준, 가장 느린 스틴트', () {
    final lines = deepPaceLines(_analysis, _stints);
    expect(lines.first, kPaceBasisLine);
    expect(lines[1], '소프트(1~5랩): AI와 비교하면 같은 타이어 기준으로 랩당 0.500초 느렸고, 같은 랩 기준으로 0.200초 느렸고, 스틴트 전체로는 0.200초 느렸어');
    expect(lines[2], '소프트(6~10랩): AI와 비교하면 같은 타이어 기준으로 랩당 0.100초 빨랐고, 같은 랩 기준으로 0.300초 빨랐고, 스틴트 전체로는 0.300초 빨랐어');
    expect(lines.last, '같은 타이어로 비교하면 소프트(1~5랩)가 가장 느렸어(AI보다 랩당 0.500초) → 이 스틴트에서 코너별 타이어 부담부터 봐');
  });

  for (final width in [1100.0, 360.0]) {
    testWidgets('카드: 심층 분석 그림을 넘침 없이 그리고 스틴트·기준을 바꾼다 (폭 $width)', (tester) async {
      tester.view.physicalSize = Size(width, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final review = RaceReview.fromJsonOrNull({
        'strategy': {'gridPosition': 3, 'finishPosition': 2, 'stops': 1, 'pitStops': [
          {'lap': 5, 'positionBefore': 2, 'positionAfter': 3, 'lossMs': 20000, 'fromCompound': 'Soft', 'toCompound': 'Soft'},
        ]},
        'stints': [
          {'compound': 'Soft', 'startLap': 1, 'endLap': 5, 'medianMs': 80000, 'fieldMedianMs': 79800, 'trendMsPerLap': 200, 'fieldTrendMsPerLap': 100},
          {'compound': 'Soft', 'startLap': 6, 'endLap': 10, 'medianMs': 80000, 'fieldMedianMs': 80300, 'trendMsPerLap': 0, 'fieldTrendMsPerLap': 100},
        ],
        'pace': {'myMedianMs': 80000, 'rank': 2, 'rankedCars': 3, 'fieldMedianMs': 80100, 'fastestName': 'NORRIS', 'fastestMedianMs': 79500},
        'battery': {'laps': 10, 'firstStoreJ': 3900000, 'lastStoreJ': 1000000, 'minStoreJ': 200000, 'minStoreLap': 4, 'lowLaps': 3, 'fullLaps': 0, 'perLap': const []},
      })!;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RaceReviewCard(review: review, analysis: _analysis, officialCorners: _corners, setup: _setup),
          ),
        ),
      ));

      expect(tester.takeException(), isNull);
      expect(find.textContaining('가장 빨리 닳는 건 앞왼 타이어야'), findsOneWidget);
      expect(find.text('T1~T2'), findsWidgets);
      expect(find.byKey(const ValueKey('analysis-pace-basis')), findsOneWidget);
      expect(find.text('실제 전략'), findsOneWidget); // 전략 비교

      expect(find.text('1.0%'), findsOneWidget); // 앞 스틴트의 T1~T2 앞왼: 200kJ × 5%/MJ
      await tester.tap(find.byKey(const ValueKey('analysis-stint-6')));
      await tester.pump();
      expect(find.text('1.0%'), findsNothing); // 뒤 스틴트는 170kJ라 0.8~0.9%

      await tester.tap(find.text('같은 랩'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }
}
