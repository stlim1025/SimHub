import 'package:flutter_test/flutter_test.dart';
import 'package:simcenter_app/features/lap_detail/domain/lap_compare.dart';
import 'package:simcenter_app/features/lap_detail/domain/lap_detail_display.dart';
import 'package:simcenter_app/features/lap_detail/domain/lap_detail_models.dart';
import 'package:simcenter_app/features/lap_detail/presentation/lap_info_card.dart';

/// 비교 대상 선택·필터·어시스트(docs/15 §10, D-51)의 순수 로직.
void main() {
  group('LapCompareSelection 주소 쿼리', () {
    test('쿼리가 없으면 기본(내 최고 랩, 필터 없음)이고, 기본은 쿼리에 싣지 않는다', () {
      final selection = LapCompareSelection.fromQuery(const {});

      expect(selection, LapCompareSelection.defaults);
      expect(selection.toQuery(), isEmpty);
    });

    test('compare·compareLapId·필터를 읽고 같은 쿼리로 되돌린다(대소문자 무시)', () {
      final selection = LapCompareSelection.fromQuery(const {
        'compare': 'Leaderboard',
        'sameTeam': 'true',
        'sameAssists': 'true',
        'sameSessionType': 'false',
        'tab': 'telemetry',
      });

      expect(selection.kind, LapCompareKind.leaderboard);
      expect(selection.filters, {LapCompareFilter.sameTeam, LapCompareFilter.sameAssists});
      expect(selection.toQuery(), {'compare': 'leaderboard', 'sameTeam': 'true', 'sameAssists': 'true'});
    });

    test('compare=lap인데 ID가 없거나 이상하면 기본(best)으로 본다', () {
      expect(LapCompareSelection.fromQuery(const {'compare': 'lap'}).kind, LapCompareKind.best);
      expect(LapCompareSelection.fromQuery(const {'compare': 'lap', 'compareLapId': 'a b'}).kind, LapCompareKind.best);
      // GUID가 아니면 서버가 400을 내 화면이 깨지므로 기본으로 본다(리뷰 반영).
      expect(LapCompareSelection.fromQuery(const {'compare': 'lap', 'compareLapId': 'abcdefgh'}).kind, LapCompareKind.best);

      final ok = LapCompareSelection.fromQuery(const {'compare': 'lap', 'compareLapId': '0192f0aa-1111-7000-8000-000000000001'});
      expect(ok.kind, LapCompareKind.lap);
      expect(ok.toQuery(), {'compare': 'lap', 'compareLapId': '0192f0aa-1111-7000-8000-000000000001'});
    });

    test('모르는 compare 값은 기본, 랩 ID 비교·비교 안 함에는 필터를 싣지 않는다', () {
      expect(LapCompareSelection.fromQuery(const {'compare': 'fastest'}).kind, LapCompareKind.best);

      final none = LapCompareSelection.fromQuery(const {'compare': 'none', 'sameTeam': 'true'});
      expect(none.toQuery(), {'compare': 'none'});
      expect(none.usesFilters, isFalse);
    });

    test('toggle은 필터를 켜고 끄며, 같은 선택은 같은 값(provider 키)이다', () {
      const base = LapCompareSelection();
      final on = base.toggle(LapCompareFilter.sameTeam);

      expect(on.filters, {LapCompareFilter.sameTeam});
      expect(on.toggle(LapCompareFilter.sameTeam), base);
      expect(base.filters, isEmpty); // 원본은 그대로
      expect(
        const LapCompareSelection(filters: {LapCompareFilter.sameTeam, LapCompareFilter.sameAssists}).hashCode,
        const LapCompareSelection(filters: {LapCompareFilter.sameAssists, LapCompareFilter.sameTeam}).hashCode,
      );
      expect(const LapDetailKey('l1'), const LapDetailKey('l1', LapCompareSelection.defaults));
    });

    test('withKind는 필터를 지키고, 랩 ID는 lap일 때만 남긴다', () {
      final selection = const LapCompareSelection(filters: {LapCompareFilter.sameTeam})
          .withKind(LapCompareKind.lap, lapId: '0192f0aa-2222-7000-8000-000000000002');

      expect(selection.compareLapId, '0192f0aa-2222-7000-8000-000000000002');
      expect(selection.filters, {LapCompareFilter.sameTeam});
      expect(selection.withKind(LapCompareKind.leaderboard).compareLapId, isNull);
    });
  });

  group('주소', () {
    test('lapDetailLocation은 탭과 비교 쿼리를 함께 싣는다(기본은 빼고)', () {
      expect(lapDetailLocation('l1', compare: LapCompareSelection.defaults), '/laps/l1');
      expect(
        lapDetailLocation('l1', tab: kLapTabTelemetry, compare: const LapCompareSelection(kind: LapCompareKind.none)),
        '/laps/l1?tab=telemetry&compare=none',
      );
    });

    test('붙여 넣은 랩 ID는 다듬고, 랩 상세 주소면 그 안의 ID를 꺼낸다', () {
      expect(normalizeLapIdInput('  0192f0aa-1111-7000-8000-000000000001 '), '0192f0aa-1111-7000-8000-000000000001');
      expect(normalizeLapIdInput('https://simcenter.test/#/laps/0192f0aa-1111-7000-8000-000000000001?tab=telemetry'), '0192f0aa-1111-7000-8000-000000000001');
      expect(normalizeLapIdInput('https://simcenter.test/laps/abcdef123456'), isNull); // GUID가 아님
      expect(normalizeLapIdInput('short'), isNull);
      expect(normalizeLapIdInput('has space inside'), isNull);
      expect(normalizeLapIdInput(''), isNull);
    });

    test('shareUrlFor: 해시 주소면 해시에, 경로 주소면 경로에, http가 아니면 앱 안 위치만', () {
      const location = '/laps/l1?tab=telemetry&compare=leaderboard';

      expect(shareUrlFor(Uri.parse('https://sim.test/#/laps/l1'), location), 'https://sim.test/#$location');
      expect(shareUrlFor(Uri.parse('http://localhost:5000/laps/l1?tab=best'), location), 'http://localhost:5000$location');
      expect(shareUrlFor(Uri.parse('http://localhost:5000/'), '/laps/l1'), 'http://localhost:5000/laps/l1');
      expect(shareUrlFor(Uri.parse('file:///app/'), location), location);
    });
  });

  group('표시', () {
    test('formatDeltaPercent = (이 랩 − 비교 랩) / 비교 랩, 소수 한 자리', () {
      expect(formatDeltaPercent(110000, 100000), '+10.0%');
      expect(formatDeltaPercent(98448, 98000), '+0.5%');
      expect(formatDeltaPercent(90000, 100000), '-10.0%');
      expect(formatDeltaPercent(100010, 100000), '0.0%');
      expect(formatDeltaPercent(99990, 100000), '0.0%');
      expect(formatDeltaPercent(1000, 0), isNull);
    });

    test('Game Mode 줄 = 모드 · 세션, 모드를 모르면 세션만', () {
      expect(gameModeAndSessionText('DriverCareer', 'Race'), 'Driver Career · Race');
      expect(gameModeAndSessionText(null, 'TimeTrial'), 'Time Trial');
      expect(gameModeAndSessionText(null, 'Weird'), '-');
    });
  });

  group('모델', () {
    test('비교 대상의 종류·주인·팀·적용 필터와 까닭·어시스트를 읽는다', () {
      final detail = LapDetail.fromJson({
        'lap': {
          'lapId': 'l1',
          'trackName': 'Jeddah',
          'gameCode': 'F1_25',
          'sessionType': 'TimeTrial',
          'lapTimeMs': 98448,
          'sectors': [],
          'isValid': true,
          'isRankingEligible': true,
          'setAt': '2026-07-26T09:00:00Z',
        },
        'trackId': 't1',
        'assists': {'tractionControl': 'Medium', 'antiLockBrakes': 'On', 'gearbox': null},
        'comparison': {
          'kind': 'leaderboard',
          'lapId': 'r1',
          'lapTimeMs': 90000,
          'sectors': [],
          'setAt': '2026-07-20T09:00:00Z',
          'hasTrace': true,
          'isMine': false,
          'displayName': '익명 드라이버',
          'team': {'name': 'McLaren', 'color': '#FF8000'},
          'sessionType': 'TimeTrial',
          'appliedFilters': ['sameAssists', 'unknownFilter'],
        },
        'comparisonUnavailable': null,
      });

      final c = detail.comparison!;
      expect(c.kind, LapCompareKind.leaderboard);
      expect(c.isMine, isFalse);
      expect(c.displayName, '익명 드라이버');
      expect(c.team?.name, 'McLaren');
      expect(c.appliedFilters, {LapCompareFilter.sameAssists});
      expect(detail.assists?.tractionControl, 'Medium');
      expect(detail.assists?.antiLockBrakes, 'On');
      expect(detail.assists?.gearbox, isNull);
      expect(detail.comparisonUnavailable, isNull);
    });

    test('옛 응답(kind·isMine 없음)은 내 최고 랩으로, 어시스트가 모두 null이면 null, 까닭을 읽는다', () {
      final detail = LapDetail.fromJson({
        'lap': {
          'lapId': 'l1',
          'trackName': 'Jeddah',
          'gameCode': 'F1_25',
          'sessionType': 'TimeTrial',
          'lapTimeMs': 98448,
          'sectors': [],
          'isValid': true,
          'isRankingEligible': true,
          'setAt': '2026-07-26T09:00:00Z',
        },
        'trackId': 't1',
        'assists': {'tractionControl': null},
        'comparison': null,
        'comparisonUnavailable': 'notFound',
      });

      expect(detail.assists, isNull);
      expect(detail.comparisonUnavailable, ComparisonUnavailable.notFound);
      expect(
        ComparisonLap.fromJsonOrNull({'lapId': 'b', 'lapTimeMs': 1, 'setAt': '2026-07-20T09:00:00Z'})?.isMine,
        isTrue,
      );
    });
  });
}
