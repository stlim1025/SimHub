import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simcenter_app/features/sessions/domain/race_analysis.dart';
import 'package:simcenter_app/features/sessions/domain/race_review.dart';
import 'package:simcenter_app/features/sessions/presentation/race_review_card.dart';

/// 전략 그림의 출발 순위 설명 글자.
const String _gridLabelText = '출발';

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
      {'compound': 'Hard', 'startLap': 6, 'endLap': 10, 'medianMs': 89650, 'fieldMedianMs': 91000, 'trendMsPerLap': 100, 'fieldTrendMsPerLap': 0, 'wearPerLapPct': 2.0, 'endLifePct': 91.0, 'fieldStintLaps': 5},
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
    expect(review.stints.single.fieldStintLaps, 5);
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
    expect(pace.lines, ['바로 앞 차(NORRIS)는 랩당 0.750초 빨랐어']); // 섹터 값이 없으면 근거 없는 조언을 붙이지 않는다

    final strategy = sections[1].section;
    // 피트에서 2.5초 더 잃었어도 전략 평가는 결과로 매긴다 — 3위 출발 → 2위.
    expect(strategy.grade, ReviewGrade.good);
    expect(pitStopGrade(review.strategy.pitStops.single, review.strategy.fieldPitLossMs), ReviewGrade.poor);
    // 피트 직후 순위가 떨어진 것만으로는 아쉬움이 아니다 — 손실이 AI와 비슷하면 보통.
    const normalStop = RacePitStopReview(lap: 5, positionBefore: 2, positionAfter: 6, lossMs: 43000, fromCompound: 'Medium', toCompound: 'Hard');
    expect(pitStopGrade(normalStop, 42500), ReviewGrade.fair);
    expect(strategyReview(RaceStrategyReview(gridPosition: 3, finishPosition: 3, stops: 1, pitStops: const [normalStop], fieldPitLossMs: 42500)).lines, isEmpty);
    // 인·아웃 랩 값이 없으면 어디서 잃었는지 말하지 않는다. 스톱 수별 결과가 없으면 스톱 수 줄도 없다.
    expect(strategy.lines, ['5랩 피트 스톱에서 AI들보다 2.500초 더 잃었어']);

    final tyres = sections[2].section;
    expect(tyres.grade, ReviewGrade.poor);
    expect(tyres.lines, ['하드(6~10랩): 랩이 지날수록 AI보다 랩당 0.100초씩 더 느려졌어']); // 바퀴 값이 없으면 원인을 짐작하지 않는다

    final battery = sections[3].section;
    expect(battery.grade, ReviewGrade.poor); // 바닥 4랩 + 끝 60% 남김
    // 바닥 랩은 8랩(5%), 그 랩 배포 1500kJ — 배포가 있는 두 랩 평균 1200kJ보다 300kJ(배터리 7.5%) 많다.
    expect(battery.lines.first, startsWith('8랩에서 배터리가 10% 아래까지 떨어졌어. 그 랩들은 평균보다 배터리를 8% 더 썼어 →'));
    expect(battery.lines.last, startsWith('체커기를 받을 때 배터리가 60% 남아 있었어'));

    expect(raceReviewSummary(sections), '전략이 좋았고, 타이어 관리, 배터리 관리가 아쉬웠어. 하나씩 같이 보자.');
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
    expect(paceLines[0],
        '2섹터에서 AI들의 보통 기록보다 랩당 0.400초 느려. 3섹터는 0.200초 빨라 → 랩 분석에서 2섹터 코너들을 기준 랩과 겹쳐서 비교해 봐');
    expect(paceLines[1], startsWith('바로 앞 차(NOR)는 랩당 0.300초 빨랐어. 그중 2섹터에서만 0.300초'));
    // 출발은 잃지 않았다(7 → 7) — 피트 구간(10~12랩: 4 → 6)과 주행 중(7 → 4 얻고 6 → 15 잃음)만.
    expect(paceLines[2], startsWith('페이스는 4위인데 결과는 15위야. 피트에 들어갔다 나오면서 2계단, 달리면서 6계단 잃었어'));
    expect(paceLines[2], isNot(contains('출발')));
    expect(paceLines[2], contains('다른 차들은 대부분 피트에 1번 들어갔는데 우리는 3번 들어갔어'));

    // 전략: 아웃 랩에서 AI보다 2.5초, 인 랩 0.5초 더 — 아웃 랩을 짚는다.
    expect(strategyReview(strategy).lines.first,
        contains('그 차들과 비교하면 피트로 들어가는 랩에서 0.500초 더 걸렸고, 피트에서 나오는 랩에서 2.500초 더 걸렸어 → 나오는 랩에서 더 잃었어'));

    // 타이어: 뒤가 앞보다 빨리 닳으면 탈출 스로틀, 끝 수명이 낮고 마지막 랩들이 느려졌으면 그 차이로.
    const rearWorn = RaceStintReview(
      compound: 'Soft', startLap: 1, endLap: 9, trendMsPerLap: 200, fieldTrendMsPerLap: 50, wearPerLapPct: 4.0, endLifePct: 22,
      wheelWearPerLapPct: [3.2, 3.4, 4.6, 4.8], endLapsSlowerMs: 600,
    );
    final tyreLines = tyreReview(const [rearWorn, RaceStintReview(compound: 'Hard', startLap: 10, endLap: 30)]).lines;
    expect(tyreLines[0],
        contains('뒤 타이어가 랩마다 4.7%씩 닳아서 앞 타이어(3.3%)보다 빨리 닳았어 → 코너를 나갈 때 스로틀을 천천히 열어서 뒷바퀴가 헛돌지 않게 해'));
    expect(tyreLines[1], contains('타이어 수명이 22% 남을 때까지 탔고, 마지막 몇 랩이 이 스틴트의 보통 랩보다 0.600초 느렸어'));

    // 마모: 고정 %가 아니라 새 타이어가 수명 30%까지 가는 랩 수를 AI가 같은 컴파운드로 탄 랩 수와 견준다.
    const quickWear = RaceStintReview(compound: 'Medium', startLap: 1, endLap: 8, wearPerLapPct: 7.0, fieldStintLaps: 11);
    expect(quickWear.lapsToLowLife, 10);
    expect(tyreReview(const [quickWear]).lines.single,
        '미디엄(1~8랩): 타이어가 랩마다 7.0%씩 닳아. 새 타이어라도 10랩이면 수명이 30%만 남는데, AI는 이 타이어로 보통 11랩을 탔어');
    const enoughWear = RaceStintReview(compound: 'Medium', startLap: 1, endLap: 12, wearPerLapPct: 5.2, fieldStintLaps: 11);
    expect(enoughWear.wearsFast, isFalse); // 13랩 ≥ 11랩 — 짧은 레이스에서 랩당 5%대는 보통이다
    expect(tyreReview(const [enoughWear]).lines, isEmpty);
    expect(const RaceStintReview(compound: 'Soft', startLap: 1, endLap: 5, wearPerLapPct: 6.0).wearsFast, isFalse); // AI 랩 수를 모르면 짚지 않는다

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
    expect(batteryReview(full).lines.first, startsWith('1랩, 2랩, 3랩에서 배터리가 꽉 찼어. 그 랩들은 평균보다 배터리를 25% 덜 썼어'));
    expect(raceReviewSummary([(title: '페이스', section: (grade: ReviewGrade.good, lines: const <String>[]))]),
        '페이스가 좋았어. 잘 달렸어.');
  });

  test('전략 평가는 결과와 전략 선택으로: 피트 스톱 하나가 느려도 내 스톱 수가 가장 잘 통했으면 좋음', () {
    // 오스트리아: 2위 출발 원스톱으로 우승, 투스톱 중 가장 높은 건 2위(1위 출발 NORRIS). 20랩 스톱은 AI 전체보다 2.1초 느리지만
    // 비슷한 때 같은 원스톱으로 들어간 차보다는 0.7초 덜 잃었다.
    const austria = RaceStrategyReview(
      gridPosition: 2, finishPosition: 1, stops: 1, fieldPitLossMs: 17300,
      pitStops: [
        RacePitStopReview(lap: 20, positionBefore: 1, positionAfter: 2, lossMs: 19400, fromCompound: 'Hard', toCompound: 'Medium', peerLossMs: 20100, peerCount: 1),
      ],
      stopGroups: [(stops: 1, finishes: [1, 3, 5, 6]), (stops: 2, finishes: [2, 4, 7, 8, 9, 10, 11])],
      rivals: [(name: 'NORRIS', stops: 2, grid: 1, finish: 2)],
    );
    final section = strategyReview(austria, alternativeGainMs: 6000, alternativeStops: 2);
    expect(section.grade, ReviewGrade.good); // 추정 대안이 빨라도 실제로 원스톱이 가장 잘 통했다
    expect(section.lines, [
      '피트에 1번 들어간 4대(우리 포함)는 1, 3, 5, 6위였고, 피트에 2번 들어간 7대 중 가장 높은 순위는 2위였어. '
          '이번 레이스는 피트 1번이 가장 잘 통했고, 우리도 그렇게 갔어',
      '다른 전략으로 너보다 앞에서 출발했는데 뒤로 들어온 차: NORRIS(1위 출발 → 2위, 피트 2번)',
    ]);

    // 다른 스톱 수가 더 잘 통하고, 그 전략으로 뒤에서 출발한 차 둘이 앞에 들어왔으면 아쉬움.
    const beaten = RaceStrategyReview(
      gridPosition: 3, finishPosition: 5, stops: 2,
      stopGroups: [(stops: 1, finishes: [1, 2, 4]), (stops: 2, finishes: [3, 5])],
      rivals: [(name: 'PIASTRI', stops: 1, grid: 6, finish: 2), (name: 'HADJAR', stops: 1, grid: 8, finish: 4)],
    );
    final poor = strategyReview(beaten);
    expect(poor.grade, ReviewGrade.poor);
    expect(
      poor.lines.first,
      '피트에 2번 들어간 2대(우리 포함)는 3, 5위였고, 피트에 1번 들어간 3대 중 가장 높은 순위는 1위였어 '
      '→ 이번 레이스는 피트 1번이 더 잘 통했어. 비슷한 레이스면 피트 1번도 생각해 봐',
    );
    // 혼자 다른 스톱 수면 '우리뿐', 상대가 많으면 앞 몇 대와 전체 수.
    const lonely = RaceStrategyReview(
      gridPosition: 7, finishPosition: 15, stops: 3,
      stopGroups: [(stops: 2, finishes: [1, 3]), (stops: 3, finishes: [15])],
      rivals: [
        (name: 'A', stops: 2, grid: 8, finish: 9), (name: 'B', stops: 2, grid: 9, finish: 10),
        (name: 'C', stops: 2, grid: 10, finish: 11), (name: 'D', stops: 2, grid: 11, finish: 12),
      ],
    );
    final lonelyLines = strategyReview(lonely).lines;
    expect(lonelyLines.first, startsWith('피트에 3번 들어간 건 우리뿐이었고(15위), 피트에 2번 들어간 2대 중 가장 높은 순위는 1위였어'));
    expect(lonelyLines[1], contains('C(10위 출발 → 11위, 피트 2번) 등 4대'));
    expect(poor.lines[1], startsWith('다른 전략으로 너보다 뒤에서 출발해 앞에 들어온 차: PIASTRI(6위 출발 → 2위, 피트 1번), HADJAR(8위 출발 → 4위, 피트 1번)'));

    // 실제 결과로 가릴 수 없고(다른 스톱 수 없음) 추정 대안이 5초 이상 빠르면 아쉬움, 같은 스톱 수 대안이면 평가에 쓰지 않는다.
    const alone = RaceStrategyReview(gridPosition: 4, finishPosition: 4, stops: 3);
    expect(strategyReview(alone, alternativeGainMs: 12600, alternativeStops: 2).grade, ReviewGrade.poor);
    expect(strategyReview(alone, alternativeGainMs: 12600, alternativeStops: 3).grade, ReviewGrade.fair);

    // 비슷한 때 들어간 차들보다 느린 스톱만 짚는다(AI 전체보다 느려도 그 차들보다 빠르면 말하지 않는다).
    expect(pitStopGrade(austria.pitStops.single, austria.fieldPitLossMs), ReviewGrade.fair);
  });

  test('순위 그래프 축 눈금: 범위에 맞는 간격, 양 끝은 늘 넣고 끝에 붙은 눈금은 뺀다', () {
    expect(axisTicks(4, 21), [4, 10, 15, 21]);
    expect(axisTicks(1, 33), [1, 5, 10, 15, 20, 25, 30, 33]);
    expect(axisTicks(1, 5), [1, 2, 3, 4, 5]);
  });

  for (final width in [1100.0, 360.0]) {
    testWidgets('카드: 항목 탭마다 평가, 고른 항목의 그림을 넘침 없이 그린다 (폭 $width)', (tester) async {
      tester.view.physicalSize = Size(width, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: RaceReviewCard(review: review, analysis: RaceAnalysis.fromJson(const {}))))));
      Future<void> open(String title) async {
        await tester.tap(find.byKey(ValueKey('race-review-tab-$title')));
        await tester.pump();
        expect(tester.takeException(), isNull);
      }

      // 처음엔 첫 항목(페이스)만 그린다. 평가는 탭마다 늘 보인다.
      expect(tester.takeException(), isNull);
      for (final title in [kPaceSectionTitle, kStrategySectionTitle, kTyreSectionTitle, kBatterySectionTitle]) {
        expect(find.byKey(ValueKey('race-review-grade-$title')), findsOneWidget);
      }
      expect(find.textContaining('2위 /', findRichText: true), findsOneWidget); // 페이스 순위
      expect(find.text(_gridLabelText), findsNothing);

      await open(kStrategySectionTitle);
      expect(find.textContaining('2위 /', findRichText: true), findsNothing);
      expect(find.text(_gridLabelText), findsOneWidget);
      expect(find.textContaining('3위', findRichText: true), findsWidgets); // 출발 순위
      expect(find.text('5랩'), findsWidgets); // 피트 랩

      await open(kTyreSectionTitle);
      expect(find.text('91%'), findsOneWidget); // 끝 수명

      await open(kBatterySectionTitle);
      expect(find.text('5%'), findsOneWidget); // 최저 잔량
      expect(find.text('랩이 끝날 때 배터리'), findsOneWidget); // 랩별 그래프
      expect(find.text('랩마다 쓴 양과 채운 양'), findsOneWidget);

      // 제목 줄을 누르면 접히고, 다시 누르면 펴진다.
      await tester.tap(find.text('Race Review'));
      await tester.pump();
      expect(find.text('랩이 끝날 때 배터리'), findsNothing);
      expect(find.text('Race Review'), findsOneWidget);
      await tester.tap(find.text('Race Review'));
      await tester.pump();
      expect(find.text('랩이 끝날 때 배터리'), findsOneWidget);

      // 랩별 잔량 그래프를 누르면(마우스는 올리면) 그 랩의 잔량·쓴 양·채운 양이 뜬다(배터리 게이지 %).
      final caption = tester.getTopLeft(find.text('랩이 끝날 때 배터리'));
      await tester.tapAt(caption + const Offset(4, 40));
      await tester.pump();
      expect(find.byKey(const ValueKey('race-review-tooltip')), findsOneWidget);
      expect(find.textContaining('1랩 끝 배터리 98%'), findsOneWidget);
      expect(find.textContaining('쓴 양 23%, 채운 양 20%'), findsOneWidget);
    });
  }
}
