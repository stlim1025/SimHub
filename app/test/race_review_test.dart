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
    expect(pace.lines, ['바로 앞 NORRIS은 랩당 0.750초 빨랐어요 → 순위를 올리려면 그만큼 페이스가 더 필요해요']);

    final strategy = sections[1].section;
    expect(strategy.grade, ReviewGrade.poor); // 피트에서 2.5초 더 잃음
    expect(pitStopGrade(review.strategy.pitStops.single, review.strategy.fieldPitLossMs), ReviewGrade.poor);
    // 피트 직후 순위가 떨어진 것만으로는 아쉬움이 아니다 — 손실이 AI와 비슷하면 보통.
    const normalStop = RacePitStopReview(lap: 5, positionBefore: 2, positionAfter: 6, lossMs: 43000, fromCompound: 'Medium', toCompound: 'Hard');
    expect(pitStopGrade(normalStop, 42500), ReviewGrade.fair);
    expect(strategyReview(RaceStrategyReview(gridPosition: 3, finishPosition: 3, stops: 1, pitStops: const [normalStop], fieldPitLossMs: 42500)).lines, isEmpty);
    expect(strategy.lines, [
      '5랩 피트에서 AI보다 2.500초 더 잃었어요 → 피트 진입 브레이킹과 아웃 랩 첫 코너를 점검하세요',
      '완주한 차 대부분(3대)과 같은 1스톱이었어요',
    ]);

    final tyres = sections[2].section;
    expect(tyres.grade, ReviewGrade.poor);
    expect(tyres.lines.single, startsWith('Hard 6–10랩: AI보다 랩당 0.100초씩 더 빨리 떨어졌어요'));

    final battery = sections[3].section;
    expect(battery.grade, ReviewGrade.poor); // 바닥 4랩 + 끝 60% 남김
    expect(battery.lines.first, startsWith('배터리가 거의 바닥인 랩이 4번이에요'));
    expect(battery.lines.last, startsWith('레이스가 끝날 때 60%를 남겼어요'));

    expect(raceReviewSummary(sections), '전략·타이어 관리·배터리 관리에서 시간을 잃은 레이스예요.');
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
    });
  }
}
