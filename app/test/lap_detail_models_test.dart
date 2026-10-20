import 'package:flutter_test/flutter_test.dart';
import 'package:simcenter_app/features/lap_detail/domain/lap_detail_models.dart';

/// docs/15 §4.2의 LapDetailResponse 예시.
Map<String, dynamic> _detailJson([Map<String, dynamic> override = const {}]) => {
      'lap': {
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
      },
      'trackId': 't1',
      'countryCode': 'SA',
      'sessionId': 's1',
      'car': {
        'visualTyreCompound': 16,
        'actualTyreCompound': 18,
        'tyreAgeLaps': 3,
        'tyreWearStart': {'frontLeft': 27.0, 'frontRight': 14.0, 'rearLeft': 20.0, 'rearRight': 14.0},
        'tyreWearEnd': {'frontLeft': 31.0, 'frontRight': 18.0, 'rearLeft': 24.0, 'rearRight': 18.5},
        'tyreDamage': {'frontLeft': 1, 'frontRight': 2, 'rearLeft': 3, 'rearRight': 4},
        'brakeDamage': {'frontLeft': 0, 'frontRight': 0, 'rearLeft': 0, 'rearRight': 5},
        'frontLeftWingDamage': 0,
        'frontRightWingDamage': 10,
        'rearWingDamage': 0,
        'floorDamage': 0,
        'diffuserDamage': 0,
        'sidepodDamage': 20,
        'gearboxDamage': 10,
        'engineDamage': 30,
        'fuelStartKg': 24.4,
        'fuelEndKg': 22.7,
        'fuelRemainingLaps': 13.1,
        'ersStoreStartJ': 1494000,
        'ersStoreEndJ': 988000,
        'ersDeployedJ': 2100000,
        'ersHarvestedJ': 1600000,
      },
      'conditions': {'weather': 'Clear', 'airTempC': 21, 'trackTempC': 31, 'rainForecastPercent': 4},
      'comparison': {
        'lapId': 'best',
        'lapTimeMs': 97003,
        'sectors': [
          {'sectorNumber': 1, 'sectorTimeMs': 30500},
        ],
        'setAt': '2026-07-20T09:00:00Z',
        'hasTrace': true,
      },
      ...override,
    };

void main() {
  group('LapDetail.fromJson', () {
    test('랩·트랙·세션 연결·비교 대상을 읽는다', () {
      final d = LapDetail.fromJson(_detailJson());

      expect(d.lap.lapId, 'l1');
      expect(d.lap.team?.name, 'Ferrari');
      expect(d.trackId, 't1');
      expect(d.countryCode, 'SA');
      expect(d.sessionId, 's1');
      expect(d.comparison?.lapId, 'best');
      expect(d.comparison?.lapTimeMs, 97003);
      expect(d.comparison?.sectors.single.sectorTimeMs, 30500);
      expect(d.comparison?.setAt, DateTime.utc(2026, 7, 20, 9));
      expect(d.comparison?.hasTrace, isTrue);
      expect(d.comparesWithItself, isFalse);
    });

    test('차량 스냅샷의 타이어·손상·연료·ERS를 읽는다(정수도 실수로)', () {
      final car = LapDetail.fromJson(_detailJson()).car!;

      expect(car.visualTyreCompound, 16);
      expect(car.actualTyreCompound, 18);
      expect(car.tyreAgeLaps, 3);
      expect(car.tyreWearStart?.frontLeft, 27.0);
      expect(car.tyreWearEnd?.rearRight, 18.5);
      expect(car.tyreDamage?.rearRight, 4.0);
      expect(car.brakeDamage?.rearRight, 5.0);
      expect(car.frontRightWingDamage, 10.0);
      expect(car.sidepodDamage, 20.0);
      expect(car.gearboxDamage, 10.0);
      expect(car.engineDamage, 30.0);
      expect(car.fuelStartKg, 24.4);
      expect(car.fuelEndKg, 22.7);
      expect(car.fuelRemainingLaps, 13.1);
      expect(car.ersStoreStartJ, 1494000.0);
      expect(car.ersStoreEndJ, 988000.0);
      expect(car.ersDeployedJ, 2100000.0);
      expect(car.ersHarvestedJ, 1600000.0);
    });

    test('날씨·기온·비 예보를 읽는다', () {
      final c = LapDetail.fromJson(_detailJson()).conditions!;

      expect(c.weather, 'Clear');
      expect(c.airTempC, 21.0);
      expect(c.trackTempC, 31.0);
      expect(c.rainForecastPercent, 4);
    });

    test('스냅샷·조건·비교·세션이 null이면 null로 읽는다(옛 Agent 랩)', () {
      final d = LapDetail.fromJson(_detailJson({
        'car': null,
        'conditions': null,
        'comparison': null,
        'sessionId': null,
        'countryCode': null,
      }));

      expect(d.car, isNull);
      expect(d.conditions, isNull);
      expect(d.comparison, isNull);
      expect(d.sessionId, isNull);
      expect(d.countryCode, isNull);
      expect(d.comparesWithItself, isFalse);
    });

    test('스냅샷 안의 필드도 각각 없거나 null일 수 있다', () {
      final car = LapDetail.fromJson(_detailJson({
        'car': {'tyreAgeLaps': 2, 'tyreWearEnd': {'frontLeft': 10, 'frontRight': null}},
      })).car!;

      expect(car.tyreAgeLaps, 2);
      expect(car.visualTyreCompound, isNull);
      expect(car.tyreWearStart, isNull);
      expect(car.tyreWearEnd?.frontLeft, 10.0);
      expect(car.tyreWearEnd?.frontRight, isNull);
      expect(car.tyreWearEnd?.rearLeft, isNull);
      expect(car.fuelStartKg, isNull);
    });

    test('비교 대상의 필수 값이 빠지거나 형식이 틀리면 비교 없음으로 보고 상세는 읽는다', () {
      for (final broken in [
        {'lapId': 'b', 'sectors': [], 'setAt': '2026-07-26T09:00:00Z'},
        {'lapId': 'b', 'lapTimeMs': 'fast', 'setAt': '2026-07-26T09:00:00Z'},
        {'lapId': 'b', 'lapTimeMs': 98000, 'setAt': 'yesterday'},
      ]) {
        final d = LapDetail.fromJson(_detailJson({'comparison': broken}));

        expect(d.comparison, isNull, reason: '$broken');
        expect(d.car, isNotNull);
      }
    });

    test('비교 대상의 랩타임이 실수로 와도 읽고, 잘못된 섹터는 건너뛴다', () {
      final d = LapDetail.fromJson(_detailJson({
        'comparison': {
          'lapId': 'b',
          'lapTimeMs': 98000.0,
          'setAt': '2026-07-26T09:00:00Z',
          'sectors': [
            {'sectorNumber': 1, 'sectorTimeMs': 30500},
            {'sectorNumber': 2},
          ],
        },
      }));

      expect(d.comparison?.lapTimeMs, 98000);
      expect(d.comparison?.sectors, hasLength(1));
    });

    test('비교 대상이 이 랩이면 comparesWithItself가 참이다', () {
      final d = LapDetail.fromJson(_detailJson({
        'comparison': {'lapId': 'l1', 'lapTimeMs': 98448, 'sectors': [], 'setAt': '2026-07-26T09:00:00Z'},
      }));

      expect(d.comparesWithItself, isTrue);
      expect(d.comparison?.hasTrace, isFalse); // 빠진 hasTrace는 false.
    });
  });

  group('LapTrace.fromJson', () {
    Map<String, dynamic> traceJson([Map<String, dynamic> override = const {}]) => {
          'lapId': 'l1',
          'resolutionM': 5,
          'sampleCount': 3,
          'timeMs': [0, 100, 210],
          'speedKph': [200, 210, 220],
          'throttle': [100, 90, 80],
          'brake': [0, 10, 20],
          'steer': [-10, 0, 10],
          'gear': [6, 7, 8],
          'rpm': [11000, 11500, 12000],
          ...override,
        };

    test('채널 7개와 해상도를 읽는다', () {
      final t = LapTrace.fromJson(traceJson());

      expect(t.lapId, 'l1');
      expect(t.resolutionM, 5);
      expect(t.length, 3);
      expect(t.timeMs, [0, 100, 210]);
      expect(t.speedKph, [200, 210, 220]);
      expect(t.throttle, [100, 90, 80]);
      expect(t.brake, [0, 10, 20]);
      expect(t.steer, [-10, 0, 10]);
      expect(t.gear, [6, 7, 8]);
      expect(t.rpm, [11000, 11500, 12000]);
      expect(t.distanceAt(2), 10.0);
      expect(t.lengthM, 10.0);
    });

    test('채널 길이가 다르면 가장 짧은 길이만 쓴다', () {
      final t = LapTrace.fromJson(traceJson({'rpm': [11000, 11500]}));

      expect(t.length, 2);
      expect(t.timeMs, [0, 100]);
      expect(t.rpm, [11000, 11500]);
    });

    test('extra의 worldPosX·worldPosZ를 월드 위치로 읽는다(없으면 빈 목록)', () {
      final t = LapTrace.fromJson(traceJson({
        'extra': {
          'worldPosX': [1.5, 2, -3.25],
          'worldPosZ': [10, 20.5, 30],
          'gForceLateral': [0.1, 0.2, 0.3],
        },
      }));

      expect(t.worldPosX, [1.5, 2.0, -3.25]);
      expect(t.worldPosZ, [10.0, 20.5, 30.0]);
      expect(t.hasPositions, isTrue);
      expect(LapTrace.fromJson(traceJson()).hasPositions, isFalse);
    });

    test('위치 채널이 하나만 있거나 길이가 다르면 위치가 없는 것으로 본다', () {
      final onlyX = LapTrace.fromJson(traceJson({
        'extra': {'worldPosX': [1, 2, 3]},
      }));
      final short = LapTrace.fromJson(traceJson({
        'extra': {'worldPosX': [1, 2], 'worldPosZ': [1, 2]},
      }));

      expect(onlyX.hasPositions, isFalse);
      expect(onlyX.worldPosX, isEmpty);
      expect(short.hasPositions, isFalse);
    });

    test('빠진 채널이 있으면 길이 0으로 본다', () {
      final t = LapTrace.fromJson(traceJson()..remove('gear'));

      expect(t.length, 0);
      expect(t.isEmpty, isTrue);
    });

    test('숫자가 아닌 표본(null 등)이 있으면 0으로 채우지 않고 빈 트레이스로 본다', () {
      final t = LapTrace.fromJson(traceJson({'speedKph': [200, null, 220]}));

      expect(t.isEmpty, isTrue);
    });

    test('해상도가 0 이하이면 1m로 본다', () {
      final t = LapTrace.fromJson(traceJson({'resolutionM': 0}));

      expect(t.resolutionM, 1);
    });
  });
}
