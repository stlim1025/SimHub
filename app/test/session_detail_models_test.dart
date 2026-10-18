import 'package:flutter_test/flutter_test.dart';
import 'package:simcenter_app/features/sessions/domain/session_models.dart';

/// docs/15 §11.4 계약 모양의 세션 상세(새 필드 모두 포함).
Map<String, dynamic> _p8Json() => {
      'session': {
        'sessionId': 's1',
        'classifiedAt': '2026-07-26T08:35:00Z',
        'trackName': 'Jeddah',
        'sessionType': 'Qualifying',
        'sessionKind': 'Qualifying3',
        'gameMode': 'DriverCareer',
        'seasonId': 'season-1',
        'carCount': 22,
        'myPosition': 8,
        'myGridPosition': 0,
        'myResultStatus': 'Finished',
        'myBestLapTimeMs': 90088,
        'myPoints': 0,
        'totalLaps': 0,
        'aiDifficulty': 105,
        'isNetworkGame': false,
        'round': 3,
        'countryCode': 'SA',
        'weather': 'Clear',
        'seasonNumber': 1,
        'myTeam': {'name': 'Ferrari', 'color': '#E8002D'},
      },
      'results': [
        {
          'position': 1,
          'carIndex': 0,
          'name': 'NORRIS',
          'teamId': 228,
          'teamName': 'McLaren',
          'teamColor': '#FF8000',
          'raceNumber': 4,
          'isAiControlled': true,
          'isPlayer': false,
          'gridPosition': 0,
          'numLaps': 3,
          'bestLapTimeMs': 89670,
          'isFastestLap': true,
          'totalRaceTimeMs': null,
          'penaltiesTimeMs': 0,
          'numPenalties': 0,
          'numPitStops': 0,
          'points': 0,
          'resultStatus': 'Finished',
          'tyreStints': [],
          'gapMs': 0,
          'positionChange': -1,
        },
      ],
      'qualifyingPositions': [
        {'sessionKind': 'Qualifying1', 'position': 6, 'sessionId': 'q1'},
        {'sessionKind': 'Qualifying2', 'position': 10},
        {'sessionKind': 'Qualifying3', 'position': 8},
      ],
      'myBestLap': {'lapId': 'lap-9', 'lapTimeMs': 90088},
      'setup': {'frontWing': 10, 'rearWing': 8},
      'laps': [
        {
          'lapNumber': 1,
          'position': 11,
          'positionChange': 1,
          'visualCompound': 'Medium',
          'inPit': true,
          'lapTimeMs': 95000,
          'gapToBestMs': 4912,
          'sectors': [30000, 32000, 33000],
          'isValid': false,
          'isBestLap': false,
          'bestSectors': [false, true, false],
          'lapId': null,
        },
      ],
      'engineWear': {
        'ice': 12,
        'turboCharger': 8,
        'mguH': 15,
        'mguK': 6,
        'energyStore': 4,
        'controlElectronics': 3,
        'gearbox': 22,
        'engineDamage': 0,
      },
      'tyreStints': [
        {
          'visualCompound': 'Soft',
          'startLap': 1,
          'endLap': 3,
          'laps': [
            {'lapInStint': 1, 'lapTimeMs': 95000, 'tyreLifeRemaining': 97.5},
          ],
        },
      ],
      'penalties': [
        {
          'lap': 2,
          'carIndex': 5,
          'driverName': 'ME',
          'isPlayer': true,
          'teamColor': '#E8002D',
          'infringement': 'Small Collision',
          'penalty': 'Warning',
          'timeS': null,
        },
      ],
    };

void main() {
  group('SessionDetail.fromJson P8 필드(docs/15 §11.4)', () {
    test('계약의 새 필드를 모두 읽는다', () {
      final detail = SessionDetail.fromJson(_p8Json());
      final header = detail.header;

      expect(header.countryCode, 'SA');
      expect(header.weather, 'Clear');
      expect(header.seasonNumber, 1);
      expect(header.myTeam?.name, 'Ferrari');
      expect(header.myTeam?.color, '#E8002D');
      expect(detail.results.single.gapMs, 0);
      expect(detail.results.single.positionChange, -1);
      expect([for (final q in detail.qualifyingPositions) '${q.label} P${q.position}'], ['Q1 P6', 'Q2 P10', 'Q3 P8']);
      expect(detail.qualifyingPositions.first.sessionId, 'q1');
      expect(detail.myBestLap?.lapId, 'lap-9');
      expect(detail.myBestLap?.lapTimeMs, 90088);
      expect(detail.setup, {'frontWing': 10, 'rearWing': 8});

      final lap = detail.laps.single;
      expect(lap.lapNumber, 1);
      expect(lap.position, 11);
      expect(lap.positionChange, 1);
      expect(lap.visualCompound, 'Medium');
      expect(lap.inPit, isTrue);
      expect(lap.sectorsMs, [30000, 32000, 33000]);
      expect(lap.isValid, isFalse);
      expect(lap.bestSectors, [false, true, false]);
      expect(lap.lapId, isNull);

      expect(detail.engineWear?.gearbox, 22);
      expect(detail.engineWear?.engineDamage, 0);
      expect(detail.tyreStints.single.laps.single.tyreLifeRemaining, 97.5);
      final penalty = detail.penalties.single;
      expect(penalty.isPlayer, isTrue);
      expect(penalty.infringement, 'Small Collision');
      expect(penalty.timeS, isNull);
    });

    test('옛 서버(새 필드 없음)도 읽고 빈 값이 된다', () {
      final json = _p8Json();
      final session = Map<String, dynamic>.of(json['session'] as Map<String, dynamic>)
        ..removeWhere((key, _) => ['countryCode', 'weather', 'seasonNumber', 'myTeam'].contains(key));
      final result = Map<String, dynamic>.of((json['results'] as List).first as Map<String, dynamic>)
        ..remove('gapMs')
        ..remove('positionChange');
      final detail = SessionDetail.fromJson({'session': session, 'results': [result]});

      expect(detail.header.countryCode, isNull);
      expect(detail.header.myTeam, isNull);
      expect(detail.results.single.gapMs, isNull);
      expect(detail.qualifyingPositions, isEmpty);
      expect(detail.myBestLap, isNull);
      expect(detail.setup, isNull);
      expect(detail.laps, isEmpty);
      expect(detail.engineWear, isNull);
      expect(detail.tyreStints, isEmpty);
      expect(detail.penalties, isEmpty);
    });

    test('형식이 틀린 항목은 버리고 나머지를 읽는다', () {
      final json = {
        ..._p8Json(),
        'qualifyingPositions': [6, 'x', 10],
        'myBestLap': {'lapTimeMs': 0},
        'setup': 'nope',
        'laps': [
          'bad',
          {'position': 3},
          {'lapNumber': 2.0, 'sectors': [1000], 'bestSectors': 'no'},
        ],
        'engineWear': {'ice': 'high'},
        'tyreStints': {'not': 'a list'},
        'penalties': [42],
      };
      final detail = SessionDetail.fromJson(json);

      expect([for (final q in detail.qualifyingPositions) '${q.label} P${q.position}'], ['Q1 P6', 'Q3 P10']);
      expect(detail.myBestLap, isNull);
      expect(detail.setup, isNull);
      expect(detail.laps.single.lapNumber, 2);
      expect(detail.laps.single.sectorsMs, [1000, null, null]);
      expect(detail.laps.single.bestSectors, [false, false, false]);
      expect(detail.laps.single.isValid, isTrue);
      expect(detail.engineWear, isNull);
      expect(detail.tyreStints, isEmpty);
      expect(detail.penalties, isEmpty);
    });
  });

  group('SessionSummary.fromJson P8 필드', () {
    test('countryCode·myTeam·seasonNumber를 읽고 없으면 null', () {
      final base = Map<String, dynamic>.of(_p8Json()['session'] as Map<String, dynamic>);
      final summary = SessionSummary.fromJson(base);
      expect(summary.countryCode, 'SA');
      expect(summary.myTeam?.name, 'Ferrari');
      expect(summary.seasonNumber, 1);

      final old = SessionSummary.fromJson(base
        ..remove('countryCode')
        ..remove('myTeam')
        ..remove('seasonNumber'));
      expect(old.countryCode, isNull);
      expect(old.myTeam, isNull);
      expect(old.seasonNumber, isNull);
    });
  });
}
