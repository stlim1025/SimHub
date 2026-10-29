import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simcenter_app/features/sessions/domain/race_review.dart';
import 'package:simcenter_app/features/sessions/presentation/race_review_card.dart';

void main() {
  final review = RaceReview.fromJsonOrNull({
    'pace': {
      'myMedianMs': 89750,
      'rank': 2,
      'rankedCars': 3,
      'fieldMedianMs': 90000,
      'fastestName': 'NORRIS',
      'fastestMedianMs': 89000,
      'aheadName': 'NORRIS',
      'aheadMedianMs': 89000,
      'behindName': 'LECLERC',
      'behindMedianMs': 91000,
    },
    'strategy': {
      'gridPosition': 3,
      'finishPosition': 2,
      'stops': 1,
      'pitStops': [
        {'lap': 5, 'positionBefore': 2, 'positionAfter': 4, 'lossMs': 45000, 'fromCompound': 'Medium', 'toCompound': 'Hard'},
      ],
      'commonStops': 1,
      'commonStopsCars': 3,
      'winnerStops': 1,
      'winnerCompounds': ['Soft', 'Medium'],
      'fieldPitLossMs': 42500,
    },
    'stints': [
      {'compound': 'Hard', 'startLap': 6, 'endLap': 10, 'medianMs': 89650, 'fieldMedianMs': 91000, 'trendMsPerLap': 100, 'fieldTrendMsPerLap': 0, 'wearPerLapPct': 2.0, 'endLifePct': 91.0},
    ],
    'battery': {
      'laps': 10, 'averageDeployJ': 1100000, 'averageHarvestJ': 700000, 'firstStoreJ': 3900000, 'lastStoreJ': 2400000,
      'minStoreJ': 200000, 'minStoreLap': 8, 'lowLaps': 4, 'fullLaps': 0,
      'perLap': [
        {'lap': 1, 'storeJ': 3900000, 'deployedJ': 900000, 'harvestedJ': 800000},
        {'lap': 8, 'storeJ': 200000, 'deployedJ': 1500000, 'harvestedJ': 600000},
        {'lap': 10, 'storeJ': 2400000},
      ],
    },
  })!;

  test('JSON → 총평 재료, 형식이 틀리면 null', () {
    expect(review.pace!.rank, 2);
    expect(review.strategy.pitStops.single.placesGained, -2);
    expect(review.stints.single.extraTrendMs, 100);
    expect(review.battery!.lowLaps, 4);
    expect(review.battery!.perLap.map((l) => (l.lap, l.storeJ, l.deployedJ)), [(1, 3900000.0, 900000.0), (8, 200000.0, 1500000.0), (10, 2400000.0, null)]);
    expect(RaceReview.fromJsonOrNull(null), isNull);
    expect(RaceReview.fromJsonOrNull({'pace': {'rank': 1}})!.pace, isNull);
  });

  test('항목 평가: 페이스·전략·타이어·배터리와 한 줄 총평', () {
    final sections = raceReviewSections(review);
    expect(sections.map((s) => s.title), [kPaceSectionTitle, kStrategySectionTitle, kTyreSectionTitle, kBatterySectionTitle]);

    final pace = sections[0].section;
    expect(pace.grade, ReviewGrade.fair); // 중앙값보다 0.25초 빠름 < 0.3초
    // 중앙값·순위·가장 빠른 차는 그래프가 보여 주고, 줄은 짚을 것만.
    expect(pace.lines, ['바로 앞 NORRIS은 랩당 0.750초 빨랐어요']); // 섹터 값이 없으면 근거 없는 조언을 붙이지 않는다

    final strategy = sections[1].section;
    expect(strategy.grade, ReviewGrade.poor); // 피트에서 2.5초 더 잃음
    expect(pitStopGrade(review.strategy.pitStops.single, review.strategy.fieldPitLossMs), ReviewGrade.poor);
    // 피트 직후 순위가 떨어진 것만으로는 아쉬움이 아니다 — 손실이 AI와 비슷하면 보통.
    const normalStop = RacePitStopReview(lap: 5, positionBefore: 2, positionAfter: 6, lossMs: 43000, fromCompound: 'Medium', toCompound: 'Hard');
    expect(pitStopGrade(normalStop, 42500), ReviewGrade.fair);
    expect(strategyReview(RaceStrategyReview(gridPosition: 3, finishPosition: 3, stops: 1, pitStops: const [normalStop], fieldPitLossMs: 42500)).lines, isEmpty);
    expect(strategy.lines, [
      '5랩 피트에서 AI보다 2.500초 더 잃었어요', // 인·아웃 랩 값이 없으면 어디서 잃었는지 말하지 않는다
      '완주한 차 대부분(3대)과 같은 1스톱이었어요',
    ]);

    final tyres = sections[2].section;
    expect(tyres.grade, ReviewGrade.poor);
    expect(tyres.lines, ['Hard 6–10랩: AI보다 랩당 0.100초씩 더 빨리 느려졌어요']); // 바퀴 값이 없으면 원인을 짐작하지 않는다

    final battery = sections[3].section;
    expect(battery.grade, ReviewGrade.poor); // 바닥 4랩 + 끝 60% 남김
    // 바닥 랩은 L8(5%), 그 랩 배포 1500kJ — 배포가 있는 두 랩 평균 1200kJ보다 300kJ 많다.
    expect(battery.lines.first, startsWith('L8에서 배터리가 10% 아래였어요. 그 랩들 배포가 평균보다 300kJ 많았어요 →'));
    expect(battery.lines.last, startsWith('레이스가 끝날 때 60%를 남겼어요'));

    expect(raceReviewSummary(sections), '전략·타이어 관리·배터리 관리에서 시간을 잃은 레이스예요.');
  });

  test('내 데이터가 있으면 근거를 들어 짚는다: 섹터·인아웃 랩·앞뒤 마모·마지막 랩·실제 순위 변화', () {
    // 페이스: S2에서 AI보다 0.4초 느리고 S3에서 0.2초 빠르다. 앞 차와는 S2에서 0.3초 차이.
    const pace = RacePaceReview(
      myMedianMs: 80000, rank: 4, rankedCars: 20, fieldMedianMs: 80200, fastestName: 'VER', fastestMedianMs: 79500,
      aheadName: 'NOR', aheadMedianMs: 79700,
      mySectorMs: [25000, 30400, 24600], fieldSectorMs: [25000, 30000, 24800], aheadSectorMs: [24950, 30100, 24650],
    );
    // 그리드 7위 → 1랩 7위 → 7랩 4위, 10랩 피트로 21위 → 12랩 6위 → 20랩 15위(3스톱, 대부분 1스톱).
    const strategy = RaceStrategyReview(
      gridPosition: 7, finishPosition: 15, stops: 3, commonStops: 1, commonStopsCars: 14,
      pitStops: [
        RacePitStopReview(lap: 10, lossMs: 25000, fromCompound: 'Soft', toCompound: 'Hard', inLapLossMs: 6000, outLapLossMs: 19000),
      ],
      fieldPitLossMs: 22000, fieldInLapLossMs: 5500, fieldOutLapLossMs: 16500,
      lapPositions: [(lap: 1, position: 7), (lap: 7, position: 4), (lap: 10, position: 21), (lap: 12, position: 6), (lap: 20, position: 15)],
    );
    final paceLines = paceReview(pace, strategy).lines;
    expect(paceLines[0], 'S2에서 AI 중앙값보다 랩당 0.400초 느려요(S3에서는 0.200초 빨라요) → 랩 분석에서 S2 코너를 기준 랩과 비교해 보세요');
    expect(paceLines[1], startsWith('바로 앞 NOR은 랩당 0.300초 빨랐고, 그중 S2에서 0.300초 차이 났어요'));
    // 출발은 잃지 않았다(7 → 7) — 피트 구간(10~12랩: 4 → 6)과 주행 중(7 → 4 얻고 6 → 15 잃음)만.
    expect(paceLines[2], startsWith('페이스는 4위인데 결과는 15위예요 — 피트 구간에서 2계단, 주행 중 6계단 잃었어요'));
    expect(paceLines[2], isNot(contains('출발')));
    expect(paceLines[2], contains('대부분은 1스톱이었는데 3스톱을 했어요'));

    // 전략: 아웃 랩에서 AI보다 2.5초, 인 랩 0.5초 더 — 아웃 랩을 짚는다.
    expect(strategyReview(strategy).lines.first, contains('인 랩 +0.500초, 아웃 랩 +2.500초(AI 대비) → 아웃 랩에서 더 잃었어요'));

    // 타이어: 뒤가 앞보다 빨리 닳으면 탈출 스로틀, 끝 수명이 낮고 마지막 랩들이 느려졌으면 그 차이로.
    const rearWorn = RaceStintReview(
      compound: 'Soft', startLap: 1, endLap: 9, trendMsPerLap: 200, fieldTrendMsPerLap: 50, wearPerLapPct: 4.0, endLifePct: 22,
      wheelWearPerLapPct: [3.2, 3.4, 4.6, 4.8], endLapsSlowerMs: 600,
    );
    final tyreLines = tyreReview(const [rearWorn, RaceStintReview(compound: 'Hard', startLap: 10, endLap: 30)]).lines;
    expect(tyreLines[0], contains('뒤 타이어(랩당 4.7%)가 앞(3.3%)보다 빨리 닳았어요 → 코너 탈출에서 스로틀을 천천히 밟아 휠스핀을 줄이세요'));
    expect(tyreLines[1], contains('수명 22%까지 탔고 마지막 랩들이 스틴트 중앙값보다 0.600초 느렸어요'));

    // 배터리: 가득 찬 랩을 랩 번호로, 그 랩 배포가 평균보다 적었는지로(회수 기록이 없어도).
    const full = RaceBatteryReview(
      laps: 4, firstStoreJ: 3900000, lastStoreJ: 1000000, minStoreJ: 1000000, minStoreLap: 4, fullLaps: 3,
      perLap: [
        RaceBatteryLap(lap: 1, storeJ: 3900000, deployedJ: 3000000),
        RaceBatteryLap(lap: 2, storeJ: 3900000, deployedJ: 3000000),
        RaceBatteryLap(lap: 3, storeJ: 3900000, deployedJ: 3000000),
        RaceBatteryLap(lap: 4, storeJ: 1000000, deployedJ: 7000000),
      ],
    );
    expect(batteryReview(full).lines.first, startsWith('L1·L2·L3에서 배터리가 가득 찼어요. 그 랩들 배포가 평균보다 1000kJ 적었어요'));
    expect(raceReviewSummary([(title: '페이스', section: (grade: ReviewGrade.good, lines: const <String>[]))]),
        '페이스가 좋았던 레이스예요.');
  });

  for (final width in [1100.0, 360.0]) {
    testWidgets('카드: 항목마다 평가와 그림을 넘침 없이 그린다 (폭 $width)', (tester) async {
      tester.view.physicalSize = Size(width, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: RaceReviewCard(review: review)))));

      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('race-review-grade-$kStrategySectionTitle')), findsOneWidget);
      expect(find.textContaining('2위', findRichText: true), findsOneWidget); // 페이스 순위
      expect(find.textContaining('P3', findRichText: true), findsOneWidget); // 출발
      expect(find.text('L5'), findsWidgets); // 피트 랩
      expect(find.text('91%'), findsOneWidget); // 끝 수명
      expect(find.text('5%'), findsOneWidget); // 최저 잔량
      expect(find.text('랩 끝 잔량'), findsOneWidget); // 랩별 그래프
      expect(find.text('랩별 배포 · 회수'), findsOneWidget);

      // 제목 줄을 누르면 접히고, 다시 누르면 펴진다.
      await tester.tap(find.text('Race Review'));
      await tester.pump();
      expect(find.text('랩 끝 잔량'), findsNothing);
      expect(find.text('Race Review'), findsOneWidget);
      await tester.tap(find.text('Race Review'));
      await tester.pump();
      expect(find.text('랩 끝 잔량'), findsOneWidget);

      // 랩별 잔량 그래프를 누르면(마우스는 올리면) 그 랩의 잔량·배포·회수가 뜬다.
      final caption = tester.getTopLeft(find.text('랩 끝 잔량'));
      await tester.tapAt(caption + const Offset(4, 40));
      await tester.pump();
      expect(find.byKey(const ValueKey('race-review-tooltip')), findsOneWidget);
      expect(find.textContaining('L1 · 잔량 98% (3900kJ)'), findsOneWidget);
      expect(find.textContaining('배포 900kJ · 회수 800kJ'), findsOneWidget);
    });
  }
}
