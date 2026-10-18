import 'package:flutter_test/flutter_test.dart';
import 'package:simcenter_app/features/sessions/domain/session_models.dart';

/// 스펙 §7.2의 SessionSummaryDto 예시.
const _summaryJson = <String, dynamic>{
  'sessionId': 's1',
  'classifiedAt': '2026-10-17T12:10:00Z',
  'trackName': 'Spa',
  'sessionType': 'Race',
  'sessionKind': 'Race',
  'gameMode': 'DriverCareer',
  'seasonId': null,
  'carCount': 22,
  'myPosition': 4,
  'myGridPosition': 6,
  'myResultStatus': 'Finished',
  'myBestLapTimeMs': 105321,
  'myPoints': 12,
};

Map<String, dynamic> _detailJson({
  Map<String, dynamic> session = const {},
  List<Map<String, dynamic>>? results,
}) =>
    {
      'session': {
        ..._summaryJson,
        'totalLaps': 15,
        'aiDifficulty': 85,
        'isNetworkGame': false,
        'round': 7,
        ...session,
      },
      'results': results ?? [_resultJson()],
    };

Map<String, dynamic> _resultJson({Map<String, dynamic> override = const {}}) => {
      'position': 1,
      'carIndex': 0,
      'name': 'NORRIS',
      'teamId': 8,
      'teamName': 'McLaren',
      'teamColor': '#FF8000',
      'raceNumber': 4,
      'isAiControlled': true,
      'isPlayer': false,
      'gridPosition': 1,
      'numLaps': 15,
      'bestLapTimeMs': 104987,
      'isFastestLap': true,
      'totalRaceTimeMs': 1598765,
      'penaltiesTimeMs': 0,
      'numPenalties': 0,
      'numPitStops': 1,
      'points': 25,
      'resultStatus': 'Finished',
      'tyreStints': [
        {'endLap': 7, 'visualCompound': 'Medium', 'actualCompound': 'C3'},
      ],
      ...override,
    };

void main() {
  group('SessionSummary.fromJson', () {
    test('스펙 예시를 읽는다', () {
      final s = SessionSummary.fromJson(_summaryJson);

      expect(s.sessionId, 's1');
      expect(s.classifiedAt, DateTime.utc(2026, 10, 17, 12, 10));
      expect(s.trackName, 'Spa');
      expect(s.sessionType, 'Race');
      expect(s.sessionKind, 'Race');
      expect(s.gameMode, 'DriverCareer');
      expect(s.seasonId, isNull);
      expect(s.carCount, 22);
      expect(s.myPosition, 4);
      expect(s.myGridPosition, 6);
      expect(s.myResultStatus, 'Finished');
      expect(s.myBestLapTimeMs, 105321);
      expect(s.myPoints, 12);
    });

    test('내 결과가 없으면 my*가 모두 null이다', () {
      final s = SessionSummary.fromJson({
        ..._summaryJson,
        'myPosition': null,
        'myGridPosition': null,
        'myResultStatus': null,
        'myBestLapTimeMs': null,
        'myPoints': null,
      });

      expect(s.myPosition, isNull);
      expect(s.myGridPosition, isNull);
      expect(s.myResultStatus, isNull);
      expect(s.myBestLapTimeMs, isNull);
      expect(s.myPoints, isNull);
    });

    test('순위 0은 모름(null), isSprintWeekend를 읽고 없으면 false', () {
      final s = SessionSummary.fromJson({..._summaryJson, 'myPosition': 0, 'myGridPosition': 0, 'isSprintWeekend': true});
      expect(s.myPosition, isNull);
      expect(s.myGridPosition, isNull);
      expect(s.isSprintWeekend, isTrue);
      expect(SessionSummary.fromJson(_summaryJson).isSprintWeekend, isFalse);
      final h = SessionDetail.fromJson(_detailJson(session: {'isSprintWeekend': true})).header;
      expect(h.isSprintWeekend, isTrue);
    });

    test('시즌에 속하면 seasonId를 읽는다', () {
      expect(SessionSummary.fromJson({..._summaryJson, 'seasonId': 'season-1'}).seasonId, 'season-1');
    });
  });

  group('SessionSummaryPage.fromJson', () {
    test('page·pageSize·total·items를 읽는다', () {
      final page = SessionSummaryPage.fromJson({
        'page': 2,
        'pageSize': 15,
        'total': 16,
        'items': [_summaryJson, {..._summaryJson, 'sessionId': 's2'}],
      });

      expect(page.page, 2);
      expect(page.pageSize, 15);
      expect(page.total, 16);
      expect(page.items.map((s) => s.sessionId), ['s1', 's2']);
    });

    test('빈 목록도 읽는다', () {
      final page = SessionSummaryPage.fromJson({'page': 1, 'pageSize': 15, 'total': 0, 'items': <dynamic>[]});

      expect(page.items, isEmpty);
      expect(page.total, 0);
    });
  });

  group('SessionDetail.fromJson', () {
    test('헤더(요약 + 세션 설정)와 결과를 읽는다', () {
      final d = SessionDetail.fromJson(_detailJson());
      final h = d.header;

      expect(h.sessionId, 's1');
      expect(h.trackName, 'Spa');
      expect(h.myPosition, 4);
      expect(h.totalLaps, 15);
      expect(h.aiDifficulty, 85);
      expect(h.isNetworkGame, isFalse);
      expect(h.round, 7);

      final r = d.results.single;
      expect(r.position, 1);
      expect(r.carIndex, 0);
      expect(r.name, 'NORRIS');
      expect(r.teamId, 8);
      expect(r.teamName, 'McLaren');
      expect(r.teamColor, '#FF8000');
      expect(r.raceNumber, 4);
      expect(r.isAiControlled, isTrue);
      expect(r.isPlayer, isFalse);
      expect(r.gridPosition, 1);
      expect(r.numLaps, 15);
      expect(r.bestLapTimeMs, 104987);
      expect(r.isFastestLap, isTrue);
      expect(r.totalRaceTimeMs, 1598765);
      expect(r.penaltiesTimeMs, 0);
      expect(r.numPenalties, 0);
      expect(r.numPitStops, 1);
      expect(r.points, 25);
      expect(r.resultStatus, 'Finished');
      expect(r.tyreStints.single.endLap, 7);
      expect(r.tyreStints.single.visualCompound, 'Medium');
      expect(r.tyreStints.single.actualCompound, 'C3');
    });

    test('시즌이 없으면 seasonId·round가 null이다', () {
      final h = SessionDetail.fromJson(_detailJson(session: {'seasonId': null, 'round': null})).header;

      expect(h.seasonId, isNull);
      expect(h.round, isNull);
    });

    test('베스트 랩·총 시간·팀·번호가 null이어도 읽는다', () {
      final r = SessionDetail.fromJson(_detailJson(results: [
        _resultJson(override: {
          'bestLapTimeMs': null,
          'isFastestLap': false,
          'totalRaceTimeMs': null,
          'teamId': null,
          'raceNumber': null,
          'teamName': 'Unknown Team',
        }),
      ])).results.single;

      expect(r.bestLapTimeMs, isNull);
      expect(r.isFastestLap, isFalse);
      expect(r.totalRaceTimeMs, isNull);
      expect(r.teamId, isNull);
      expect(r.raceNumber, isNull);
      expect(r.teamName, 'Unknown Team');
    });

    test('tyreStints가 빈 목록이면 빈 목록이고 actualCompound는 null일 수 있다', () {
      final empty = SessionDetail.fromJson(_detailJson(results: [
        _resultJson(override: {'tyreStints': <dynamic>[]}),
      ])).results.single;
      final noActual = SessionDetail.fromJson(_detailJson(results: [
        _resultJson(override: {
          'tyreStints': [
            {'endLap': 3, 'visualCompound': 'Soft', 'actualCompound': null},
          ],
        }),
      ])).results.single;

      expect(empty.tyreStints, isEmpty);
      expect(noActual.tyreStints.single.actualCompound, isNull);
    });

    test('결과 순서를 유지한다', () {
      final d = SessionDetail.fromJson(_detailJson(results: [
        _resultJson(override: {'position': 1, 'carIndex': 5}),
        _resultJson(override: {'position': 2, 'carIndex': 2}),
      ]));

      expect(d.results.map((r) => r.carIndex), [5, 2]);
    });
  });
}
