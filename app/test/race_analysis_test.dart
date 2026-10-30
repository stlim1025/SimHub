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

final RaceAnalysis _analysis = RaceAnalysis.fromJson({
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
        _segment(0, work: [5, 5, 40, 40], more: {'deployKj': 1200, 'harvestKj': 300, 'overtakeM': 300, 'emptyM': 150, 'emptyLaps': 3, 'storeEndKj': 400}),
        _segment(1, work: [200, 100, 150, 100], more: {
          'understeerDeg': 2.5, 'trailBrakeM': 30, 'throttleSteerM': 50, 'lockupM': 12, 'kerbM': 20, 'timeTrendMsPerLap': 40,
          'deployKj': 100, 'harvestKj': 800, 'brakeM': 60, 'storeEndKj': 1100,
        }),
        _segment(2, work: [5, 5, 30, 30], more: {'deployKj': 900, 'harvestKj': 50, 'overtakeM': 200, 'storeEndKj': 250}),
        _segment(3, work: [150, 80, 120, 90], more: {'understeerDeg': 1.0, 'throttleSteerM': 45, 'deployKj': 200, 'harvestKj': 700, 'brakeM': 50, 'storeEndKj': 750}),
        _segment(4, work: [100, 70, 80, 60], more: {'understeerDeg': 3.0, 'deployKj': 400, 'harvestKj': 50, 'overtakeM': 60, 'storeEndKj': 600}),
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
        _segment(4, work: [95, 70, 80, 60], more: {'understeerDeg': 2.6, 'deployKj': 380, 'harvestKj': 50, 'overtakeM': 40, 'storeEndKj': 1400}),
      ],
    },
  ],
  'fieldErs': [
    {'index': 0, 'harvestKj': 800, 'deployKj': 1300, 'cars': 19},
    {'index': 1, 'harvestKj': 900, 'deployKj': 300, 'cars': 19},
    {'index': 2, 'harvestKj': 100, 'deployKj': 900, 'cars': 19},
    {'index': 3, 'harvestKj': 800, 'deployKj': 300, 'cars': 19},
    {'index': 4, 'harvestKj': 300, 'deployKj': 100, 'cars': 19},
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
    expect(_analysis.strategy!.options.last.plan, 'S4→S3→S3');
    expect(labels, ['메인 직선', 'T1–T2', 'T2→T3 직선', 'T3', 'T4']);
    expect(segmentLabels(_analysis, null), ['메인 직선', '코너 1', '직선 1', '코너 2', '코너 3']);
    // 두 구간 사이 빈틈(700~710m)의 코너는 앞뒤 여유 안 첫 구간 하나에만 든다.
    final between = segmentLabels(_analysis, const [(number: 9, letter: '', fraction: 0.705)]);
    expect(between.where((l) => l == 'T9').length, 1);
  });

  test('타이어: 리미터 바퀴, 부담 큰 코너의 원인과 할 것, 그립이 빠진 코너, 같은 컴파운드 비교, 세팅', () {
    final lines = deepTyreLines(_stints, _analysis, labels, _setup);
    expect(lines.first, startsWith('리미터는 앞왼 — 랩당 마모 3.8%p(다음 뒤왼 3.0%p), 마찰 일 475kJ'));
    // T1–T2: 앞왼 (200 + 170) / 2 = 185kJ, 랩의 39%, 마모 ≈ 0.185MJ × 5%/MJ.
    expect(lines[1], startsWith('T1–T2: 앞왼 185kJ(랩의 39%, 마모 ≈0.9%p) — 앞이 뒤보다'));
    expect(lines[1], endsWith('→ 진입 속도를 조금 낮추고 감은 채로 버티지 마 — 앞이 물릴 때 돌려'));
    expect(lines[2], contains('T3: 앞왼 145kJ'));
    expect(lines[2], endsWith('풀 스로틀로 꺾은 거리 40m → 탈출에서 핸들을 먼저 풀고 그다음 풀 스로틀'));   // (45 + 35) / 2 = 문턱 40m
    expect(lines, contains(startsWith('Soft 1–5랩: AI보다 랩당 0.100초씩 더 떨어졌어 — 시간이 늘어난 곳은 T1–T2(+0.040초/랩)')));
    expect(lines, contains(startsWith('Soft 1–5랩은 6–10랩보다 앞왼 일이 랩당 50kJ 많았어(마모 ≈+0.3%p) — 차이는 T1–T2(풀 스로틀 조향 50m vs 30m)')));
    expect(lines, contains('세팅: 앞 캠버 -3.50°는 코너 그립엔 좋지만 앞 타이어를 더 달궈 → 레이스에선 0.1~0.2° 세워 봐'));
    // 부담 큰 코너(T1–T2 2.25° · T3 1.0° · T4 2.8°)의 평균 언더스티어 2.0° → 앞 날개·안티롤바.
    expect(lines, contains('세팅: 부담이 큰 코너에서 앞이 평균 2.0° 더 미끄러져 → 앞 날개 +1~2 또는 앞 안티롤바를 낮춰 앞 그립을 올려 봐(지금 앞 날개 40, 앞 안티롤바 7)'));
    // 트레이스로 분석한 스틴트가 없으면 줄이 없다.
    expect(deepTyreLines(_stints, RaceAnalysis.fromJson(const {}), const [], _setup), isEmpty);
  });

  test('배터리: 바닥난 스틴트는 AI보다 더 쓴 곳을, 여유 있는 스틴트는 덜 쓴 직선을, 배터리를 잃고 나온 코너', () {
    final lines = deepBatteryLines(null, _analysis, labels);
    expect(lines.first, startsWith('랩당 배터리 사용'));
    expect(
      lines,
      contains('Soft 1–5랩: 3랩 중 3랩은 메인 직선에서 배터리가 바닥났어(들어갈 때 잔량 600kJ, 바닥 안 난 스틴트 1400kJ)'
          ' — T4에서 AI보다 300kJ 더 썼어(Overtake 60m) → T4에선 Medium으로 두고 메인 직선까지 남겨'),
    );
    expect(lines, contains('Soft 6–10랩: T2→T3 직선에서 AI보다 랩당 500kJ 덜 썼어(바닥난 곳 없음) → 거기선 Overtake로 더 써'));
    expect(lines, contains('T4: 이 구간에서 배터리가 넌 랩당 −340kJ, AI는 +200kJ → Overtake(50m)를 끄고 Medium으로 지나가'));
  });

  test('전략: 피트 창과 스톱, 남은 랩으로 못 되찾는 스톱, 짧게 탄 컴파운드, 추정 대안', () {
    final lines = deepStrategyLines(_analysis, _stints);
    expect(lines[0], '출발 때 게임 피트 창은 5~8랩 — 1스톱으로 5랩에 들어왔어, 모두 그때 창의 이상 랩이야');
    expect(lines[1], '5랩 Soft→Soft: 마모 40%. 게임은 3랩 더 간다고 봤어(창 끝 8랩). 새 Soft 세트가 랩당 2.000초 빨라 스톱 손실 20.0초를 되찾는 데 10랩인데 남은 건 5랩이야'
        ' → 타이어 한계가 아니라 계획대로 들어온 거야');
    expect(lines[2], '게임 기준 쓸 수 있는 랩보다 짧게 탔어(탄 랩/쓸 수 있는 랩): Soft 5/9랩 — 스틴트를 늘리면 스톱을 줄일 수 있어');
    expect(lines.last, '추정으로도 지금 전략이 가장 빨랐어 — 다른 스톱 수와 1.0초 안이야');

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
      '추정(게임 타이어 델타·내 마모 기준): M11→S11→S11(2스톱)이면 12.6초 빨랐어 — 스톱을 1번 덜 해서 21.5초를 아끼고, 새 타이어로 되찾던 건 8.9초뿐이야',
      '3스톱으로 갈 거면 M8→S8→S8→S9로 나눠야 3.4초 빨랐어',
    ]);
  });

  test('페이스: 기준 읽는 법, 스틴트마다 같은 타이어·같은 랩·스틴트 기준, 가장 느린 스틴트', () {
    final lines = deepPaceLines(_analysis, _stints);
    expect(lines.first, kPaceBasisLine);
    expect(lines[1], 'Soft 1–5랩: 같은 타이어 +0.500초 · 같은 랩 +0.200초 · 스틴트 +0.200초');
    expect(lines[2], 'Soft 6–10랩: 같은 타이어 −0.100초 · 같은 랩 −0.300초 · 스틴트 −0.300초');
    expect(lines.last, '같은 타이어로 보면 Soft 1–5랩이 가장 느렸어(랩당 +0.500초) → 이 스틴트의 코너별 타이어 부담부터 봐');
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
      expect(find.textContaining('리미터는 앞왼'), findsOneWidget);
      expect(find.text('T1–T2'), findsWidgets);
      expect(find.byKey(const ValueKey('analysis-pace-basis')), findsOneWidget);
      expect(find.text('실제'), findsOneWidget); // 전략 비교

      await tester.tap(find.byKey(const ValueKey('analysis-stint-6')));
      await tester.pump();
      expect(find.text('170kJ'), findsOneWidget); // 뒤 스틴트의 T1–T2 앞왼

      await tester.tap(find.text('같은 랩'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }
}
