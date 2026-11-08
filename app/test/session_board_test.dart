import 'package:flutter_test/flutter_test.dart';
import 'package:simcenter_app/features/sessions/domain/race_highlights.dart';
import 'package:simcenter_app/features/sessions/domain/race_review.dart';
import 'package:simcenter_app/features/sessions/domain/session_board.dart';
import 'package:simcenter_app/features/sessions/domain/session_models.dart';

import 'support/fakes.dart';

const _mediumHard = [
  TyreStintView(endLap: 19, visualCompound: 'Medium', actualCompound: 'C3'),
  TyreStintView(endLap: 255, visualCompound: 'Hard', actualCompound: 'C2'),
];

/// 36랩 레이스: 1위 VERSTAPPEN, 나는 P7 출발 P3(+4.218, 5초 패널티 포함), 최고 랩은 전체 1위.
List<SessionResult> _race() => [
      resultOf(1, name: 'VERSTAPPEN', numLaps: 36, bestLapTimeMs: 72506, totalRaceTimeMs: 2646210, points: 25),
      resultOf(2, name: 'NORRIS', numLaps: 36, bestLapTimeMs: 72611, gapMs: 1904, points: 18),
      resultOf(
        3,
        name: 'ME',
        isPlayer: true,
        numLaps: 36,
        gridPosition: 7,
        positionChange: 4,
        bestLapTimeMs: 72384,
        gapMs: 4218,
        penaltiesTimeMs: 5000,
        numPenalties: 1,
        points: 15,
        tyreStints: _mediumHard,
      ),
      resultOf(4, name: 'LECLERC', numLaps: 35, bestLapTimeMs: 72790, resultStatus: 'DidNotFinish'),
    ];

List<SessionLap> _laps(List<int> positions, {int? pitLap}) => [
      for (var i = 0; i < positions.length; i++)
        SessionLap(
          lapNumber: i + 1,
          position: positions[i],
          inPit: i + 1 == pitLap,
          visualCompound: pitLap == null || i + 1 <= pitLap ? 'Medium' : 'Hard',
        ),
    ];

const _myPenalty = SessionPenalty(
  lap: 22,
  carIndex: 2,
  isPlayer: true,
  infringement: 'Corner cutting gained time',
  penalty: 'Time penalty',
  timeS: 5,
);

SessionDetail _raceDetail({
  List<SessionResult>? results,
  List<SessionLap> laps = const [],
  List<SessionPenalty> penalties = const [_myPenalty],
  RaceReview? review,
  int totalLaps = 36,
}) =>
    detailOf(
      'r1',
      results: results ?? _race(),
      laps: laps,
      penalties: penalties,
      raceReview: review,
      totalLaps: totalLaps,
      round: 9,
      seasonNumber: 1,
    );

SessionKpi _kpi(List<SessionKpi> kpis, SessionKpiId id) => kpis.singleWhere((k) => k.id == id);

HighlightClip _clip(HighlightKind kind, int lap, int focus, [int? other]) => HighlightClip(
      kind: kind,
      startMs: lap * 1000,
      endMs: lap * 1000 + 500,
      eventMs: lap * 1000 + 250,
      focusCar: focus,
      otherCar: other,
      lap: lap,
      cars: const [],
    );

RaceHighlights _highlights(List<HighlightClip> mine) => RaceHighlights(
      sessionId: 'r1',
      trackId: 'Zandvoort',
      gameCode: 'F1_25',
      totalLaps: 36,
      cars: const [
        HighlightCar(carIndex: 0, name: 'VERSTAPPEN', teamColor: null, isPlayer: false, position: 1),
        HighlightCar(carIndex: 1, name: 'NORRIS', teamColor: null, isPlayer: false, position: 2),
        HighlightCar(carIndex: 2, name: 'ME', teamColor: null, isPlayer: true, position: 3),
        HighlightCar(carIndex: 3, name: 'RUSSELL', teamColor: null, isPlayer: false, position: 4),
      ],
      flags: const [],
      mine: mine,
      race: const [],
    );

void main() {
  group('sessionKpis', () {
    test('레이스: Finish · Gap to P1 · Best Lap · Pit · Penalty · Points', () {
      final kpis = sessionKpis(_raceDetail());

      expect(kpis.map((k) => k.id), [
        SessionKpiId.finish,
        SessionKpiId.gap,
        SessionKpiId.bestLap,
        SessionKpiId.pit,
        SessionKpiId.penalty,
        SessionKpiId.points,
      ]);
      final finish = _kpi(kpis, SessionKpiId.finish);
      expect((finish.label, finish.value, finish.valueTone), ('Finish', 'P3', KpiTone.accent));
      expect((finish.sub, finish.subTone), ('+4 (P7 출발)', KpiTone.success));
      final gap = _kpi(kpis, SessionKpiId.gap);
      expect((gap.label, gap.value, gap.sub), ('Gap to P1', '+4.218', '36 Laps'));
      final best = _kpi(kpis, SessionKpiId.bestLap);
      expect((best.value, best.valueTone, best.sub), ('1:12.384', KpiTone.fastest, '전체 1위'));
      final pit = _kpi(kpis, SessionKpiId.pit);
      expect((pit.value, pit.sub), ('1', 'L19 M→H'));
      final penalty = _kpi(kpis, SessionKpiId.penalty);
      expect((penalty.value, penalty.valueTone, penalty.sub), ('+5s', KpiTone.danger, 'Corner cutting gained time'));
      final points = _kpi(kpis, SessionKpiId.points);
      expect((points.value, points.sub), ('15', 'Season 1 · R9'));
    });

    test('순위를 잃으면 빨간 −, 그대로면 ±0, 패널티가 없으면 0(흐리게)', () {
      final lost = sessionKpis(_raceDetail(results: [
        resultOf(1, totalRaceTimeMs: 1000),
        resultOf(2, isPlayer: true, gridPosition: 1, positionChange: -1),
      ]));
      expect(_kpi(lost, SessionKpiId.finish).sub, '−1 (P1 출발)');
      expect(_kpi(lost, SessionKpiId.finish).subTone, KpiTone.danger);
      expect(_kpi(lost, SessionKpiId.penalty).value, '0');
      expect(_kpi(lost, SessionKpiId.penalty).valueTone, KpiTone.muted);

      final same = sessionKpis(_raceDetail(results: [resultOf(1, isPlayer: true, gridPosition: 1, positionChange: 0)]));
      expect(_kpi(same, SessionKpiId.finish).sub, '±0 (P1 출발)');
    });

    test('우승이면 Gap 대신 총 시간(패널티 포함)', () {
      final kpis = sessionKpis(_raceDetail(results: [
        resultOf(1, isPlayer: true, numLaps: 36, totalRaceTimeMs: 2646210, penaltiesTimeMs: 5000),
        resultOf(2, gapMs: 1904),
      ]));

      final gap = _kpi(kpis, SessionKpiId.gap);
      expect((gap.label, gap.value, gap.sub), ('Race Time', '44:11.210', '36 Laps'));
    });

    test('끝내지 못했으면 Finish·Gap에 상태(DNF)', () {
      final kpis = sessionKpis(_raceDetail(results: [
        resultOf(1, totalRaceTimeMs: 1000),
        resultOf(2, isPlayer: true, resultStatus: 'DidNotFinish', numLaps: 3),
      ]));

      expect(_kpi(kpis, SessionKpiId.finish).value, 'DNF');
      expect(_kpi(kpis, SessionKpiId.finish).valueTone, KpiTone.danger);
      expect(_kpi(kpis, SessionKpiId.gap).value, 'DNF');
    });

    test('예선: Position · Best Lap · Gap to P1(최고 랩 차)만', () {
      final detail = detailOf(
        'q1',
        sessionType: 'Qualifying',
        sessionKind: 'Qualifying3',
        results: [
          resultOf(1, name: 'POLE', bestLapTimeMs: 71591),
          resultOf(2, bestLapTimeMs: 71700),
          resultOf(3, isPlayer: true, bestLapTimeMs: 71902),
        ],
      );
      final kpis = sessionKpis(detail);

      expect(kpis.map((k) => k.id), [SessionKpiId.finish, SessionKpiId.bestLap, SessionKpiId.gap]);
      final position = _kpi(kpis, SessionKpiId.finish);
      expect((position.label, position.value, position.sub), ('Position', 'P3', '3대 중'));
      final best = _kpi(kpis, SessionKpiId.bestLap);
      expect((best.value, best.valueTone, best.sub), ('1:11.902', KpiTone.normal, '전체 3위'));
      final gap = _kpi(kpis, SessionKpiId.gap);
      expect((gap.value, gap.sub), ('+0.311', 'P1 1:11.591'));
    });

    test('내 결과가 없으면 헤더의 최고 랩만', () {
      final kpis = sessionKpis(detailOf('d1', myBestLapTimeMs: 91234));

      expect(kpis.map((k) => k.id), [SessionKpiId.bestLap]);
      expect(_kpi(kpis, SessionKpiId.bestLap).value, '1:31.234');
      expect(_kpi(kpis, SessionKpiId.bestLap).sub, isNull);
    });
  });

  test('bestLapRank: 나보다 빠른 다른 차 수 + 1', () {
    final results = _race();
    expect(bestLapRank(results, 72384), 1);
    expect(bestLapRank(results, 72700), 3);
    expect(bestLapRank(results, 80000), 4);
  });

  group('myPitStops', () {
    test('레이스 리뷰 스톱이 먼저(손실 포함)', () {
      final review = RaceReview.fromJsonOrNull({
        'strategy': {
          'pitStops': [
            {'lap': 19, 'lossMs': 22400, 'fromCompound': 'Medium', 'toCompound': 'Hard'},
          ],
        },
      });
      expect(myPitStops(_raceDetail(review: review)), [
        (lap: 19, fromCompound: 'Medium', toCompound: 'Hard', lossMs: 22400),
      ]);
    });

    test('리뷰가 없으면 내 결과의 스틴트 경계', () {
      expect(myPitStops(_raceDetail()), [(lap: 19, fromCompound: 'Medium', toCompound: 'Hard', lossMs: null)]);
    });

    test('스틴트도 없으면 Laps의 IN PIT 묶음(앞·뒤 랩 컴파운드)', () {
      final detail = _raceDetail(
        results: [resultOf(1, isPlayer: true)],
        laps: [
          const SessionLap(lapNumber: 1, visualCompound: 'Soft'),
          const SessionLap(lapNumber: 2, visualCompound: 'Soft', inPit: true),
          const SessionLap(lapNumber: 3, visualCompound: 'Hard', inPit: true),
          const SessionLap(lapNumber: 4, visualCompound: 'Hard'),
        ],
      );
      expect(myPitStops(detail), [(lap: 2, fromCompound: 'Soft', toCompound: 'Hard', lossMs: null)]);
    });

    test('pitStopsText: 한 번은 컴파운드까지, 여러 번은 랩만, 없으면 null', () {
      expect(pitStopsText(const [(lap: 19, fromCompound: 'Medium', toCompound: 'Hard', lossMs: null)]), 'L19 M→H');
      expect(pitStopsText(const [(lap: 19, fromCompound: null, toCompound: null, lossMs: null)]), 'L19');
      expect(
        pitStopsText(const [
          (lap: 12, fromCompound: 'Soft', toCompound: 'Medium', lossMs: null),
          (lap: 30, fromCompound: 'Medium', toCompound: 'Hard', lossMs: null),
        ]),
        'L12 · L30',
      );
      expect(pitStopsText(const []), isNull);
    });
  });

  group('positionTraceOf', () {
    test('그리드(랩 0)부터 랩 끝 순위, 세로축은 지난 순위 + 1을 5 단위로(22대 중 P8 → P10), 피트 랩', () {
      final field = [..._race(), for (var p = 5; p <= 22; p++) resultOf(p)];
      final trace = positionTraceOf(_raceDetail(results: field, laps: _laps([5, 5, 4, 8, 6, 3], pitLap: 4)))!;

      expect(trace.grid, 7);
      expect(trace.minLap, 0);
      expect(trace.maxLap, 6);
      expect(trace.points.first, (lap: 1, position: 5));
      expect(trace.finalPosition, 3);
      expect(trace.maxPosition, 10);
      // 리뷰 없음 → 스틴트 경계(L19)는 6랩 밖이라 빠진다.
      expect(trace.pitStops, isEmpty);
    });

    test('세로축은 차 수를 넘지 않고, 그릴 점이 모자라면 null', () {
      final small = positionTraceOf(_raceDetail(laps: _laps([4, 4])))!;
      expect(small.maxPosition, 7); // 결과 4대 · 지난 가장 낮은 순위 P7(그리드) → P10이 아니라 P7까지

      expect(positionTraceOf(_raceDetail(results: [resultOf(1, isPlayer: true, gridPosition: 0)], laps: _laps([1]))),
          isNull);
      expect(positionTraceOf(_raceDetail()), isNull);
    });

    test('positionTicks: 10대 이하는 모두, 넘으면 5 단위 + 마지막(붙으면 마지막만)', () {
      expect(positionTicks(4), [1, 2, 3, 4]);
      expect(positionTicks(22), [1, 5, 10, 15, 22]);
      expect(positionTicks(25), [1, 5, 10, 15, 20, 25]);
    });

    test('lapTicks: 시작(0 = 그리드)·간격 배수·마지막 랩, 끝과 붙은 배수는 뺀다', () {
      expect(lapTicks(0, 36), [0, 5, 10, 15, 20, 25, 30, 36]);
      expect(lapTicks(1, 6), [1, 2, 3, 4, 5, 6]);
      expect(lapTicks(0, 1), [0, 1]);
    });
  });

  test('stintSegmentsOf: 스틴트 끝 랩을 잇고 마지막은 달린 랩까지, 넘는 끝 랩은 자른다', () {
    expect(stintSegmentsOf(resultOf(1, numLaps: 36, tyreStints: _mediumHard)), [
      (compound: 'Medium', startLap: 1, endLap: 19),
      (compound: 'Hard', startLap: 20, endLap: 36),
    ]);
    // 14랩에서 멈춘 차: 첫 스틴트 끝(19)이 달린 랩을 넘어 잘리고, 두 번째 스틴트는 빈 칸이라 빠진다.
    expect(stintSegmentsOf(resultOf(1, numLaps: 14, tyreStints: _mediumHard)), [
      (compound: 'Medium', startLap: 1, endLap: 14),
    ]);
    expect(stintSegmentsOf(resultOf(1, numLaps: 0, tyreStints: _mediumHard)), isEmpty);
  });

  group('keyMomentsOf', () {
    test('출발·피트·실제 벌칙 + 하이라이트 내 장면(추월·추월당함·충돌), 랩 순, 출발·결승 장면과 경고는 뺀다', () {
      final detail = _raceDetail(
        laps: _laps([5, 5, 5], pitLap: 2),
        penalties: [
          _myPenalty,
          const SessionPenalty(lap: 5, isPlayer: true, infringement: 'Corner cutting', penalty: 'Warning'),
          const SessionPenalty(lap: 6, carIndex: 0, infringement: 'Pit lane speeding', penalty: 'Drive through'),
        ],
      );
      final moments = keyMomentsOf(
        detail,
        highlights: _highlights([
          _clip(HighlightKind.start, 1, 2),
          _clip(HighlightKind.overtake, 12, 2, 3),
          _clip(HighlightKind.overtake, 25, 1, 2),
          _clip(HighlightKind.collision, 8, 3, 2),
          _clip(HighlightKind.overtake, 14, 0, 1), // 남의 추월은 내 장면이 아니다
          _clip(HighlightKind.finish, 36, 2),
        ]),
      );

      expect([for (final m in moments) (m.lap, keyMomentText(m), keyMomentDeltaText(m))], [
        (1, '출발 P7 → P5', '+2'),
        (8, '충돌 RUSSELL', null),
        (12, '추월 RUSSELL', '+1'),
        (19, '피트 M → H', null),
        (22, '패널티 · Corner cutting gained time', '+5s'),
        (25, '추월당함 NORRIS', '−1'),
      ]);
    });

    test('하이라이트가 없어도 출발·피트·벌칙은 담고, 줄 수가 넘치면 하이라이트 장면부터 덜 담는다', () {
      final review = RaceReview.fromJsonOrNull({
        'strategy': {
          'pitStops': [
            {'lap': 19, 'lossMs': 22400, 'fromCompound': 'Medium', 'toCompound': 'Hard'},
          ],
        },
      });
      final detail = _raceDetail(laps: _laps([5]), review: review);

      final plain = keyMomentsOf(detail);
      expect([for (final m in plain) keyMomentText(m)], ['출발 P7 → P5', '피트 M → H · 22.4초', '패널티 · Corner cutting gained time']);

      final capped = keyMomentsOf(
        detail,
        max: 4,
        highlights: _highlights([for (var lap = 2; lap < 10; lap++) _clip(HighlightKind.overtake, lap, 2, 3)]),
      );
      expect(capped, hasLength(4));
      expect(capped.where((m) => m.kind == KeyMomentKind.overtake), hasLength(1));
    });

    test('compoundLetter: 아는 컴파운드는 첫 글자, 모르면 ?', () {
      expect(compoundLetter('Medium'), 'M');
      expect(compoundLetter('Intermediate'), 'I');
      expect(compoundLetter('Unknown'), '?');
      expect(compoundLetter(null), '?');
    });
  });
}
