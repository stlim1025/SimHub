import 'package:flutter_test/flutter_test.dart';
import 'package:simcenter_app/features/lap_detail/domain/lap_detail_display.dart';
import 'package:simcenter_app/features/lap_detail/domain/lap_detail_models.dart';
import 'package:simcenter_app/features/laps/domain/lap_display.dart';

void main() {
  group('lapModeLabel (게임 모드 → MODE 열)', () {
    const cases = {
      'DriverCareer': 'Driver Career',
      'MyTeamCareer': 'My Team',
      'OnlineCareer': 'Online Career',
      'ChallengeCareer': 'Challenge Career',
      'GrandPrix': 'Grand Prix',
      'TimeTrial': 'Time Trial',
      'Online': 'Online',
      'Story': 'Braking Point',
    };
    for (final entry in cases.entries) {
      test('${entry.key} → ${entry.value}', () {
        expect(lapModeLabel(gameMode: entry.key, sessionType: 'Race'), entry.value);
      });
    }

    test('Other·null·모르는 값이면 세션 유형 라벨로 대신한다', () {
      expect(lapModeLabel(gameMode: 'Other', sessionType: 'TimeTrial'), 'Time Trial');
      expect(lapModeLabel(gameMode: null, sessionType: 'Qualifying'), 'Qualifying');
      expect(lapModeLabel(gameMode: 'NewMode2027', sessionType: 'Race'), 'Race');
    });
  });

  test('sessionTypeLabel: TimeTrial은 띄어 쓰고 모르는 값은 -', () {
    expect(sessionTypeLabel('TimeTrial'), 'Time Trial');
    expect(sessionTypeLabel('Practice'), 'Practice');
    expect(sessionTypeLabel('Qualifying'), 'Qualifying');
    expect(sessionTypeLabel('Race'), 'Race');
    expect(sessionTypeLabel('Unknown'), '-');
  });

  test('weatherLabel: 게임 날씨 6가지 이름, 모르는 값은 그대로, null은 null', () {
    expect(weatherLabel('Clear'), 'Clear');
    expect(weatherLabel('LightCloud'), 'Light Cloud');
    expect(weatherLabel('Overcast'), 'Overcast');
    expect(weatherLabel('LightRain'), 'Light Rain');
    expect(weatherLabel('HeavyRain'), 'Heavy Rain');
    expect(weatherLabel('Storm'), 'Storm');
    expect(weatherLabel('Snow'), 'Snow');
    expect(weatherLabel(null), isNull);
  });

  test('trackLapsLocation·lapDetailLocation 주소', () {
    expect(trackLapsLocation('t1'), '/laps/tracks/t1');
    expect(lapDetailLocation('l1'), '/laps/l1');
    expect(lapDetailLocation('l1', tab: kLapTabTelemetry), '/laps/l1?tab=telemetry');
    expect(lapDetailLocation('l1', tab: kLapTabBest), '/laps/l1?tab=best');
    expect(lapDetailLocation('l1', tab: kLapTabDetails), '/laps/l1?tab=details');
  });

  test('normalizeLapTab: 모르는 값·null은 details', () {
    expect(normalizeLapTab('telemetry'), kLapTabTelemetry);
    expect(normalizeLapTab('best'), kLapTabBest);
    expect(normalizeLapTab('details'), kLapTabDetails);
    expect(normalizeLapTab('nope'), kLapTabDetails);
    expect(normalizeLapTab(null), kLapTabDetails);
  });

  group('formatDeltaMs · deltaToneOf', () {
    test('빠르면 -, 느리면 +, 같으면 부호 없이 0.000', () {
      expect(formatDeltaMs(-123), '-0.123');
      expect(formatDeltaMs(456), '+0.456');
      expect(formatDeltaMs(0), '0.000');
      expect(formatDeltaMs(1445), '+1.445');
    });

    test('60초 이상은 분을 붙인다', () {
      expect(formatDeltaMs(62345), '+1:02.345');
      expect(formatDeltaMs(-60000), '-1:00.000');
    });

    test('부호 → 색 구분', () {
      expect(deltaToneOf(-1), DeltaTone.faster);
      expect(deltaToneOf(1), DeltaTone.slower);
      expect(deltaToneOf(0), DeltaTone.even);
    });
  });

  group('타이어 마모 단계 (25/50/75%)', () {
    test('경계값', () {
      expect(tyreWearLevelOf(null), TyreWearLevel.unknown);
      expect(tyreWearLevelOf(0), TyreWearLevel.low);
      expect(tyreWearLevelOf(24.9), TyreWearLevel.low);
      expect(tyreWearLevelOf(25), TyreWearLevel.medium);
      expect(tyreWearLevelOf(49.9), TyreWearLevel.medium);
      expect(tyreWearLevelOf(50), TyreWearLevel.high);
      expect(tyreWearLevelOf(74.9), TyreWearLevel.high);
      expect(tyreWearLevelOf(75), TyreWearLevel.critical);
      expect(tyreWearLevelOf(100), TyreWearLevel.critical);
    });
  });

  group('퍼센트·마모 증가·손상 글자', () {
    test('formatPercent는 반올림한 정수 %, null은 -', () {
      expect(formatPercent(31.4), '31%');
      expect(formatPercent(31.5), '32%');
      expect(formatPercent(null), '-');
    });

    test('formatWearDelta는 끝 − 시작을 소수 한 자리로, 시작이 없으면 null', () {
      expect(formatWearDelta(27, 31), '+4.0%');
      expect(formatWearDelta(20, 20), '+0.0%');
      expect(formatWearDelta(null, 31), isNull);
      expect(formatWearDelta(27, null), isNull);
    });

    test('damageText는 0·null이면 -', () {
      expect(damageText(0), '-');
      expect(damageText(null), '-');
      expect(damageText(10), '10%');
    });

    test('wheelValuesText는 FL / FR / RL / RR 순서, 0은 -', () {
      const wheels = WheelValues(frontLeft: 31, frontRight: 0, rearLeft: 24, rearRight: null);

      expect(wheelValuesText(wheels), '31% / - / 24% / -');
      expect(wheelValuesText(null), '-');
      expect(wheelValuesText(const WheelValues(frontLeft: 0, frontRight: 0, rearLeft: 0, rearRight: 0)), '-');
    });
  });

  group('연료·ERS (ERS 최대 4 MJ)', () {
    const car = CarSnapshot(
      fuelStartKg: 24.4,
      fuelEndKg: 22.7,
      ersStoreStartJ: 1494000,
      ersStoreEndJ: 988000,
    );

    test('이 랩 연료 사용량 = 시작 − 끝', () {
      expect(fuelUsedKg(car), closeTo(1.7, 1e-9));
      expect(fuelUsedKg(const CarSnapshot(fuelEndKg: 22.7)), isNull);
      expect(formatKg(1.7), '1.70 kg');
      expect(formatKg(null), '-');
    });

    test('ERS % = J / 4,000,000 × 100, 이 랩 사용 = (시작 − 끝)', () {
      expect(ersPercentOf(988000), closeTo(24.7, 1e-9));
      expect(ersUsedPercent(car), closeTo(12.65, 1e-9));
      expect(ersUsedPercent(const CarSnapshot(ersStoreEndJ: 1)), isNull);
      expect(formatOneDecimalPercent(12.65), '12.7%');
      expect(formatOneDecimalPercent(-3.24), '-3.2%');
      expect(formatOneDecimalPercent(null), '-');
    });
  });

  test('formatTemperature·formatRainForecast', () {
    expect(formatTemperature(21), '21°C');
    expect(formatTemperature(21.6), '22°C');
    expect(formatTemperature(null), '-');
    expect(formatRainForecast(4), '4%');
    expect(formatRainForecast(null), '-');
  });

  group('컴파운드 번호(F1 UDP)', () {
    test('보이는 컴파운드: 16 Soft · 17 Medium · 18 Hard · 7 Intermediate · 8 Wet', () {
      expect(visualCompoundName(16), 'Soft');
      expect(visualCompoundName(17), 'Medium');
      expect(visualCompoundName(18), 'Hard');
      expect(visualCompoundName(7), 'Intermediate');
      expect(visualCompoundName(8), 'Wet');
      expect(visualCompoundName(99), isNull);
      expect(visualCompoundName(null), isNull);
    });

    test('실제 컴파운드: 16 C5 … 21 C0, 22 C6, 7 Inter, 8 Wet', () {
      expect(actualCompoundLabel(16), 'C5');
      expect(actualCompoundLabel(18), 'C3');
      expect(actualCompoundLabel(21), 'C0');
      expect(actualCompoundLabel(22), 'C6');
      expect(actualCompoundLabel(7), 'Inter');
      expect(actualCompoundLabel(8), 'Wet');
      expect(actualCompoundLabel(1), isNull);
    });
  });

  test('shortLapId는 앞 8자', () {
    expect(shortLapId('0192f0aa-1111-7000-8000-000000000001'), '0192f0aa');
    expect(shortLapId('abc'), 'abc');
  });
}
