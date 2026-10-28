import 'package:flutter_test/flutter_test.dart';
import 'package:simcenter_app/features/sessions/domain/race_review.dart';

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
    },
  })!;

  test('JSON → 총평 재료, 형식이 틀리면 null', () {
    expect(review.pace!.rank, 2);
    expect(review.strategy.pitStops.single.placesGained, -2);
    expect(review.stints.single.extraTrendMs, 100);
    expect(review.battery!.lowLaps, 4);
    expect(RaceReview.fromJsonOrNull(null), isNull);
    expect(RaceReview.fromJsonOrNull({'pace': {'rank': 1}})!.pace, isNull);
  });

  test('항목 평가: 페이스·전략·타이어·배터리와 한 줄 총평', () {
    final sections = raceReviewSections(review);
    expect(sections.map((s) => s.title), [kPaceSectionTitle, kStrategySectionTitle, kTyreSectionTitle, kBatterySectionTitle]);

    final pace = sections[0].section;
    expect(pace.grade, ReviewGrade.fair); // 중앙값보다 0.25초 빠름 < 0.3초
    expect(pace.lines.first, '깨끗한 랩 중앙값 1:29.750 — 페이스 2위/3대, AI 전체 중앙값보다 0.250초 빨라요');
    expect(pace.lines, contains('바로 앞 NORRIS은 랩당 0.750초 빨랐어요 → 순위를 올리려면 그만큼 페이스가 더 필요해요'));
    expect(pace.lines.any((l) => l.contains('LECLERC')), isFalse); // 뒤 차가 더 느리면 짚지 않는다

    final strategy = sections[1].section;
    expect(strategy.grade, ReviewGrade.poor); // 피트에서 2.5초 더 잃음
    expect(strategy.lines.first, '3위 출발 → 2위 완주(1계단 상승)');
    expect(strategy.lines[1], startsWith('5랩 피트 Medium → Hard: P2 → P4, 손실 45.000초(AI 42.500초) → 피트에서 2.500초 더 잃었어요'));
    expect(strategy.lines.last, '우승 차 전략: Soft → Medium (1스톱)');

    final tyres = sections[2].section;
    expect(tyres.grade, ReviewGrade.poor);
    expect(tyres.lines.single, contains('추세 +0.100초/랩(AI +0.000초/랩)'));
    expect(tyres.lines.single, contains('AI보다 랩당 0.100초씩 더 빨리 떨어졌어요'));

    final battery = sections[3].section;
    expect(battery.grade, ReviewGrade.poor); // 바닥 4랩 + 끝 60% 남김
    expect(battery.lines.first, '랩당 배포 1100kJ · 회수 700kJ · 끝 잔량 60% · 최저 5%(8랩)');

    expect(raceReviewSummary(sections), '전략·타이어 관리·배터리 관리에서 시간을 잃은 레이스예요.');
    expect(raceReviewSummary([(title: '페이스', section: (grade: ReviewGrade.good, lines: const <String>[]))]),
        '페이스가 좋았던 레이스예요.');
  });
}
