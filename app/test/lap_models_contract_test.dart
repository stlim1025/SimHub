import 'package:flutter_test/flutter_test.dart';
import 'package:simcenter_app/features/laps/domain/lap_models.dart';
import 'package:simcenter_app/features/ranking/domain/ranking_models.dart';

/// docs/15 §4.2의 LapDto(추가 필드 포함) 예시.
Map<String, dynamic> _lapJson([Map<String, dynamic> override = const {}]) => {
      'lapId': 'l1',
      'trackName': 'Jeddah',
      'gameCode': 'F1_25',
      'sessionType': 'TimeTrial',
      'lapTimeMs': 98448,
      'sectors': [
        {'sectorNumber': 1, 'sectorTimeMs': 31000},
      ],
      'isValid': true,
      'isRankingEligible': true,
      'setAt': '2026-07-26T09:00:00Z',
      'lapNumber': 5,
      'gameMode': 'DriverCareer',
      'team': {'name': 'Ferrari', 'color': '#E8002D'},
      'weather': 'Clear',
      'hasTrace': true,
      ...override,
    };

void main() {
  group('Track (docs/15 §4.1)', () {
    test('Track.fromJson은 countryCode·displayOrder를 읽는다', () {
      final t = Track.fromJson({
        'trackId': 't1',
        'gameCode': 'F1_25',
        'name': 'Jeddah',
        'countryCode': 'SA',
        'displayOrder': 5,
      });

      expect(t.countryCode, 'SA');
      expect(t.displayOrder, 5);
    });

    test('Track.fromJson은 countryCode·displayOrder가 없거나 null이어도 읽는다', () {
      final t = Track.fromJson({'trackId': 't1', 'gameCode': 'F1_25', 'name': 'Old', 'countryCode': null});

      expect(t.countryCode, isNull);
      expect(t.displayOrder, 0);
    });

    test('MyTrack.fromJson은 countryCode·displayOrder를 읽고, 없으면 null·0이다', () {
      final base = {
        'trackId': 't1',
        'trackName': 'Jeddah',
        'gameCode': 'F1_25',
        'lapCount': 3,
        'bestValidLapTimeMs': 98448,
        'lastSetAt': '2026-07-26T09:00:00Z',
      };

      final withCountry = MyTrack.fromJson({...base, 'countryCode': 'SA', 'displayOrder': 5});
      final without = MyTrack.fromJson(base);

      expect(withCountry.countryCode, 'SA');
      expect(withCountry.displayOrder, 5);
      expect(without.countryCode, isNull);
      expect(without.displayOrder, 0);
    });
  });

  group('Lap (docs/15 §4.2)', () {
    test('Lap.fromJson은 추가 필드(lapNumber·gameMode·team·weather·hasTrace)를 읽는다', () {
      final lap = Lap.fromJson(_lapJson());

      expect(lap.lapNumber, 5);
      expect(lap.gameMode, 'DriverCareer');
      expect(lap.team?.name, 'Ferrari');
      expect(lap.team?.color, '#E8002D');
      expect(lap.weather, 'Clear');
      expect(lap.hasTrace, isTrue);
    });

    test('Lap.fromJson은 추가 필드가 null이면 null·false로 읽는다(스냅샷 없는 옛 랩)', () {
      final lap = Lap.fromJson(_lapJson({
        'lapNumber': null,
        'gameMode': null,
        'team': null,
        'weather': null,
        'hasTrace': null,
      }));

      expect(lap.lapNumber, isNull);
      expect(lap.gameMode, isNull);
      expect(lap.team, isNull);
      expect(lap.weather, isNull);
      expect(lap.hasTrace, isFalse);
    });

    test('Lap.fromJson은 추가 필드가 아예 없어도(옛 서버) 읽는다', () {
      final json = _lapJson()
        ..remove('lapNumber')
        ..remove('gameMode')
        ..remove('team')
        ..remove('weather')
        ..remove('hasTrace');

      final lap = Lap.fromJson(json);

      expect(lap.lapId, 'l1');
      expect(lap.team, isNull);
      expect(lap.hasTrace, isFalse);
    });

    test('Lap.fromJson은 이름 없는 팀 객체를 팀 없음으로 본다', () {
      final lap = Lap.fromJson(_lapJson({'team': {'color': '#E8002D'}}));

      expect(lap.team, isNull);
    });
  });
}
