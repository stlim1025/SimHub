import 'package:flutter_test/flutter_test.dart';
import 'package:simcenter_app/features/seasons/domain/season_display.dart';
import 'package:simcenter_app/features/seasons/domain/season_models.dart';

import 'support/fakes.dart';

/// 스펙 §7.2의 SeasonSummaryDto 예시.
const _summaryJson = <String, dynamic>{
  'seasonId': 'se1',
  'gameCode': 'F1_25',
  'gameMode': 'DriverCareer',
  'firstSessionAt': '2026-10-17T09:00:00Z',
  'lastSessionAt': '2026-10-24T11:30:00Z',
  'roundCount': 6,
  'myPosition': 3,
  'myPoints': 87,
  'leaderName': 'VERSTAPPEN',
  'leaderPoints': 120,
};

/// 스펙 §7.2의 SeasonDetailDto 예시(라운드 2개, 드라이버 2명, 팀 1개).
Map<String, dynamic> _detailJson() => {
      'season': _summaryJson,
      'rounds': [
        {
          'round': 1,
          'weekendId': 'w1',
          'trackName': 'Bahrain',
          'firstSessionAt': '2026-10-17T09:00:00Z',
          'winnerName': 'NORRIS',
          'myPoints': 12,
          'sessions': [
            {
              'sessionId': 'q1',
              'sessionType': 'Qualifying',
              'sessionKind': 'Qualifying1',
              'myPosition': 2,
              'myResultStatus': 'Finished',
            },
            {
              'sessionId': 'r1',
              'sessionType': 'Race',
              'sessionKind': 'Race',
              'myPosition': 4,
              'myResultStatus': 'Finished',
            },
          ],
        },
        {
          'round': 2,
          'weekendId': 'w2',
          'trackName': 'Jeddah',
          'firstSessionAt': '2026-10-18T09:00:00Z',
          'winnerName': null,
          'myPoints': null,
          'sessions': [
            {
              'sessionId': 'q2',
              'sessionType': 'Qualifying',
              'sessionKind': 'Qualifying1',
              'myPosition': null,
              'myResultStatus': null,
            },
          ],
        },
      ],
      'standings': {
        'drivers': [
          {
            'position': 1,
            'driverKey': 'driver:9',
            'name': 'VERSTAPPEN',
            'teamName': 'Red Bull Racing',
            'teamColor': '#3671C6',
            'isPlayer': false,
            'isAiControlled': true,
            'points': 120,
            'wins': 3,
            'podiums': 5,
            'cells': [
              {'round': 1, 'position': 1, 'resultStatus': 'Finished', 'points': 25},
              {'round': 2, 'position': null, 'resultStatus': null, 'points': 8},
            ],
          },
          {
            'position': 2,
            'driverKey': 'player',
            'name': 'ME',
            'teamName': 'McLaren',
            'teamColor': '#FF8000',
            'isPlayer': true,
            'isAiControlled': false,
            'points': 87,
            'wins': 0,
            'podiums': 2,
            'cells': <dynamic>[],
          },
        ],
        'constructors': [
          {
            'position': 1,
            'teamId': 2,
            'teamName': 'Red Bull Racing',
            'teamColor': '#3671C6',
            'points': 190,
            'wins': 3,
          },
        ],
      },
    };

void main() {
  group('SeasonSummary.fromJson', () {
    test('스펙 예시의 모든 필드를 읽는다', () {
      final s = SeasonSummary.fromJson(_summaryJson);

      expect(s.seasonId, 'se1');
      expect(s.gameCode, 'F1_25');
      expect(s.gameMode, 'DriverCareer');
      expect(s.firstSessionAt, DateTime.utc(2026, 10, 17, 9));
      expect(s.lastSessionAt, DateTime.utc(2026, 10, 24, 11, 30));
      expect(s.roundCount, 6);
      expect(s.myPosition, 3);
      expect(s.myPoints, 87);
      expect(s.leaderName, 'VERSTAPPEN');
      expect(s.leaderPoints, 120);
    });

    test('내 결과가 없으면 my*가, 결과가 하나도 없으면 leader*가 null이다', () {
      final s = SeasonSummary.fromJson({
        ..._summaryJson,
        'myPosition': null,
        'myPoints': null,
        'leaderName': null,
        'leaderPoints': null,
      });

      expect(s.myPosition, isNull);
      expect(s.myPoints, isNull);
      expect(s.leaderName, isNull);
      expect(s.leaderPoints, isNull);
    });
  });

  group('SeasonSummaryPage.fromJson', () {
    test('page·pageSize·total·items를 읽는다', () {
      final page = SeasonSummaryPage.fromJson({
        'page': 2,
        'pageSize': 20,
        'total': 25,
        'items': [_summaryJson, {..._summaryJson, 'seasonId': 'se2'}],
      });

      expect(page.page, 2);
      expect(page.pageSize, 20);
      expect(page.total, 25);
      expect(page.items.map((s) => s.seasonId), ['se1', 'se2']);
    });

    test('빈 목록도 읽는다', () {
      final page = SeasonSummaryPage.fromJson({'page': 1, 'pageSize': 20, 'total': 0, 'items': <dynamic>[]});

      expect(page.items, isEmpty);
      expect(page.total, 0);
    });
  });

  group('SeasonDetail.fromJson', () {
    test('헤더·라운드·세션 칩을 읽는다', () {
      final d = SeasonDetail.fromJson(_detailJson());

      expect(d.season.seasonId, 'se1');
      expect(d.rounds, hasLength(2));
      final r1 = d.rounds[0];
      expect(r1.round, 1);
      expect(r1.weekendId, 'w1');
      expect(r1.trackName, 'Bahrain');
      expect(r1.firstSessionAt, DateTime.utc(2026, 10, 17, 9));
      expect(r1.winnerName, 'NORRIS');
      expect(r1.myPoints, 12);
      expect(r1.sessions.map((s) => s.sessionId), ['q1', 'r1']);
      expect(r1.sessions[0].sessionType, 'Qualifying');
      expect(r1.sessions[0].sessionKind, 'Qualifying1');
      expect(r1.sessions[1].myPosition, 4);
      expect(r1.sessions[1].myResultStatus, 'Finished');
    });

    test('본 레이스가 없거나 내 결과가 없으면 winnerName·myPoints·세션의 my*가 null이다', () {
      final r2 = SeasonDetail.fromJson(_detailJson()).rounds[1];

      expect(r2.winnerName, isNull);
      expect(r2.myPoints, isNull);
      expect(r2.sessions.single.myPosition, isNull);
      expect(r2.sessions.single.myResultStatus, isNull);
    });

    test('Standings 드라이버(칸 포함)와 Constructors를 읽는다', () {
      final standings = SeasonDetail.fromJson(_detailJson()).standings;

      expect(standings.drivers, hasLength(2));
      final max = standings.drivers[0];
      expect(max.position, 1);
      expect(max.driverKey, 'driver:9');
      expect(max.name, 'VERSTAPPEN');
      expect(max.teamName, 'Red Bull Racing');
      expect(max.teamColor, '#3671C6');
      expect(max.isPlayer, isFalse);
      expect(max.isAiControlled, isTrue);
      expect(max.points, 120);
      expect(max.wins, 3);
      expect(max.podiums, 5);
      expect(max.cells, hasLength(2));
      expect(max.cells[0].round, 1);
      expect(max.cells[0].position, 1);
      expect(max.cells[0].resultStatus, 'Finished');
      expect(max.cells[0].points, 25);

      final me = standings.drivers[1];
      expect(me.isPlayer, isTrue);
      expect(me.cells, isEmpty);

      final team = standings.constructors.single;
      expect(team.position, 1);
      expect(team.teamId, 2);
      expect(team.teamName, 'Red Bull Racing');
      expect(team.teamColor, '#3671C6');
      expect(team.points, 190);
      expect(team.wins, 3);
    });

    test('본 레이스 기록이 없는 칸은 position·resultStatus가 null이고 점수는 남는다', () {
      final cell = SeasonDetail.fromJson(_detailJson()).standings.drivers[0].cells[1];

      expect(cell.round, 2);
      expect(cell.position, isNull);
      expect(cell.resultStatus, isNull);
      expect(cell.points, 8);
    });
  });

  group('seasonTitle', () {
    test('seasonTitle_UsesModeLabelAndStartDate', () {
      final season = seasonOf('se1', gameMode: 'DriverCareer', firstSessionAt: DateTime(2026, 10, 17, 12));

      expect(seasonTitle(season), 'Driver Career · 2026.10.17');
    });

    test('모드 라벨은 session_display의 gameModeLabel을 따른다', () {
      final season = seasonOf('se1', gameMode: 'GrandPrix', firstSessionAt: DateTime(2026, 1, 5, 12));

      expect(seasonTitle(season), 'Grand Prix · 2026.01.05');
    });
  });

  group('SeasonCalendarRound.fromJson', () {
    test('스프린트·세션 목록을 읽고 순위 0은 null', () {
      final r = SeasonCalendarRound.fromJson({
        'round': 5,
        'trackId': 't5',
        'trackName': 'Shanghai',
        'racePosition': 2,
        'qualiPosition': 0,
        'sprintPosition': 4,
        'isSprintWeekend': true,
        'sessions': [
          {'sessionId': 's1', 'sessionKind': 'SprintShootout1', 'myPosition': 9},
          {'sessionId': 's2', 'sessionKind': 'Qualifying2', 'myPosition': 0},
        ],
      });
      expect((r.racePosition, r.qualiPosition, r.sprintPosition, r.isSprintWeekend), (2, null, 4, true));
      expect(r.sessions.map((s) => (s.sessionId, s.sessionKind, s.myPosition)), [
        ('s1', 'SprintShootout1', 9),
        ('s2', 'Qualifying2', null),
      ]);
    });

    test('옛 서버(필드 없음)면 스프린트 아님·빈 세션 목록', () {
      final r = SeasonCalendarRound.fromJson({'round': 1, 'trackId': 't1', 'trackName': 'Melbourne'});
      expect((r.sprintPosition, r.isSprintWeekend), (null, false));
      expect(r.sessions, isEmpty);
    });
  });
}
