import 'package:flutter_test/flutter_test.dart';
import 'package:simcenter_app/features/auth/domain/user_preferences.dart';
import 'package:simcenter_app/features/lap_detail/domain/lap_compare.dart';
import 'package:simcenter_app/features/lap_detail/domain/lap_detail_display.dart';
import 'package:simcenter_app/features/lap_detail/domain/lap_detail_models.dart';
import 'package:simcenter_app/features/lap_detail/domain/lap_kpis.dart';
import 'package:simcenter_app/features/laps/domain/lap_models.dart';

import 'support/fakes.dart';
import 'support/lap_detail_harness.dart';

const _otherCar = LapCompareSelection.car(sessionId: 's1', carIndex: 3, name: 'VERSTAPPEN', lapTimeMs: 98100);

void main() {
  group('lapKpisOf', () {
    test('내 최고 랩과 비교하면 랩·섹터 차이와 비교 랩타임, 랩 끝 타이어(컴파운드·사용 랩·평균 마모)', () {
      // 이 랩 98.448(31.000 · 33.448 · 34.000) vs 최고 98.000(30.500 · 33.300 · 34.200).
      final kpis = lapKpisOf(sampleDetail(), LapCompareSelection.defaults);

      expect(kpis.lapTimeMs, 98448);
      expect(kpis.compareKind, LapCompareKind.best);
      expect(kpis.compareState, LapKpiCompareState.delta);
      expect(kpis.referenceMs, 98000);
      expect(kpis.deltaMs, 448);
      expect(kpis.isBest, isFalse);
      expect(kpis.sectors, [
        (number: 1, timeMs: 31000, deltaMs: 500),
        (number: 2, timeMs: 33448, deltaMs: 148),
        (number: 3, timeMs: 34000, deltaMs: -200),
      ]);
      expect(kpis.tyreCompound, 'Soft');
      expect(kpis.tyreAgeLaps, 3);
      expect(kpis.tyreWearPercent, (31 + 18 + 24 + 80) / 4);
    });

    test('비교 대상이 곧 이 랩이면(내 최고) 최고 랩으로 보고 섹터 차이는 없다', () {
      final kpis = lapKpisOf(sampleDetail(comparison: sampleComparison(id: 'l1')), LapCompareSelection.defaults);

      expect(kpis.compareState, LapKpiCompareState.itself);
      expect(kpis.isBest, isTrue);
      expect(kpis.referenceMs, 98000);
      expect(kpis.deltaMs, isNull);
      expect(kpis.sectors.map((s) => s.deltaMs), everyElement(isNull));
    });

    test('랩 ID를 직접 골라 이 랩 자신과 비교하면 최고 랩이 아니라 0 차이', () {
      final self = comparisonOf('l1', 98448, sectors: sampleLap().sectors, kind: LapCompareKind.lap);
      final compare = LapCompareSelection.defaults.withKind(LapCompareKind.lap, lapId: 'l1');

      final kpis = lapKpisOf(sampleDetail(comparison: self), compare);

      expect(kpis.compareState, LapKpiCompareState.delta);
      expect(kpis.compareKind, LapCompareKind.lap);
      expect(kpis.deltaMs, 0);
      expect(kpis.sectors.map((s) => s.deltaMs), [0, 0, 0]);
    });

    test('비교 안 함이면 비교 칸을 숨기고(응답에 비교 랩이 남아 있어도) 섹터 차이도 없다', () {
      final kpis = lapKpisOf(sampleDetail(), const LapCompareSelection(kind: LapCompareKind.none));

      expect(kpis.compareState, LapKpiCompareState.hidden);
      expect(kpis.referenceMs, isNull);
      expect(kpis.deltaMs, isNull);
      expect(kpis.sectors.map((s) => s.deltaMs), everyElement(isNull));
      expect(kpis.sectors.map((s) => s.timeMs), [31000, 33448, 34000]);
    });

    test('비교 대상이 없으면 unavailable', () {
      final kpis = lapKpisOf(sampleDetail(withComparison: false), LapCompareSelection.defaults);

      expect(kpis.compareState, LapKpiCompareState.unavailable);
      expect(kpis.referenceMs, isNull);
      expect(kpis.deltaMs, isNull);
    });

    test('리더보드 최고 랩과 비교하면 응답의 비교 종류로 칸 이름을 정한다', () {
      final leader = comparisonOf('top', 97000, kind: LapCompareKind.leaderboard, isMine: false);

      final kpis = lapKpisOf(
        sampleDetail(comparison: leader),
        LapCompareSelection.defaults.withKind(LapCompareKind.leaderboard),
      );

      expect(kpis.compareKind, LapCompareKind.leaderboard);
      expect(kpis.deltaMs, 1448);
      // 비교 랩 섹터를 모르면 섹터 차이는 없다.
      expect(kpis.sectors.map((s) => s.deltaMs), everyElement(isNull));
    });

    test('같은 세션의 다른 차와 비교하면 주소의 랩타임과만 비교하고 섹터 차이는 없다', () {
      final kpis = lapKpisOf(sampleDetail(), _otherCar);

      expect(kpis.compareKind, LapCompareKind.car);
      expect(kpis.compareState, LapKpiCompareState.delta);
      expect(kpis.referenceMs, 98100);
      expect(kpis.deltaMs, 348);
      expect(kpis.sectors.map((s) => s.deltaMs), everyElement(isNull));
    });

    test('다른 차 랩타임을 모르면 unavailable', () {
      const noTime = LapCompareSelection.car(sessionId: 's1', carIndex: 3, name: 'VERSTAPPEN');

      expect(lapKpisOf(sampleDetail(), noTime).compareState, LapKpiCompareState.unavailable);
    });

    test('차량 스냅샷이 없거나 값이 빠지면 타이어 값은 null', () {
      final none = lapKpisOf(sampleDetail(car: null), LapCompareSelection.defaults);
      expect(none.tyreCompound, isNull);
      expect(none.tyreAgeLaps, isNull);
      expect(none.tyreWearPercent, isNull);

      const partial = CarSnapshot(visualTyreCompound: 99, tyreWearEnd: WheelValues(frontLeft: 10));
      final unknown = lapKpisOf(sampleDetail(car: partial), LapCompareSelection.defaults);
      expect(unknown.tyreCompound, isNull); // F1 밖·모르는 컴파운드 번호
      expect(unknown.tyreWearPercent, isNull); // 네 바퀴 중 하나라도 모르면
    });

    test('섹터 시간이 빠진 랩은 그 섹터 시간·차이가 null', () {
      final lap = lapOf('l1', 'Jeddah', 98448, sectors: const [LapSector(sectorNumber: 1, sectorTimeMs: 31000)]);

      final kpis = lapKpisOf(sampleDetail(lap: lap), LapCompareSelection.defaults);

      expect(kpis.sectors, [
        (number: 1, timeMs: 31000, deltaMs: 500),
        (number: 2, timeMs: null, deltaMs: null),
        (number: 3, timeMs: null, deltaMs: null),
      ]);
    });
  });

  group('글자', () {
    test('lapKpiTitle: 트랙 · 세션 유형 + 랩 번호, 모르는 값은 뺀다', () {
      expect(lapKpiTitle(lapOf('l1', 'Zandvoort', 72384, sessionType: 'Race', lapNumber: 23)), 'Zandvoort · Race L23');
      expect(lapKpiTitle(lapOf('l1', 'Zandvoort', 72384)), 'Zandvoort · Time Trial');
      expect(lapKpiTitle(lapOf('l1', 'Zandvoort', 72384, sessionType: 'Unknown', lapNumber: 4)), 'Zandvoort · L4');
      expect(lapKpiTitle(lapOf('l1', 'Zandvoort', 72384, sessionType: 'Unknown')), 'Zandvoort');
    });

    test('lapKpiCompareLabel: 비교 종류별 이름, 다른 차는 드라이버 이름(모르면 Car)', () {
      expect(lapKpiCompareLabel(LapCompareKind.best), 'vs PB');
      expect(lapKpiCompareLabel(LapCompareKind.leaderboard), 'vs Leaderboard');
      expect(lapKpiCompareLabel(LapCompareKind.lap), 'vs Lap');
      expect(lapKpiCompareLabel(LapCompareKind.car, otherCarName: 'NORRIS'), 'vs NORRIS');
      expect(lapKpiCompareLabel(LapCompareKind.car, otherCarName: ''), 'vs Car');
      expect(lapKpiCompareLabel(LapCompareKind.car), 'vs Car');
    });

    test('formatTyreKpiCaption: 사용 랩 · 평균 마모(반올림), 아는 값만', () {
      expect(formatTyreKpiCaption(ageLaps: 12, wearPercent: 17.6), '12랩 · 18%');
      expect(formatTyreKpiCaption(ageLaps: 12), '12랩');
      expect(formatTyreKpiCaption(wearPercent: 4.2), '4%');
      expect(formatTyreKpiCaption(), isNull);
    });

    test('formatKpiSectorTime: 1분 미만은 초부터, 넘으면 분:초, 모르면 —', () {
      expect(formatKpiSectorTime(24112), '24.112');
      expect(formatKpiSectorTime(62345), '1:02.345');
      expect(formatKpiSectorTime(null), kLapKpiNoValueText);
    });

    test('formatKpiSpeed: 반올림한 값과 단위(Imperial이면 mph), 속도를 모르면 —', () {
      expect(formatKpiSpeed(317.6, UnitSystem.metric), (value: '318', unit: 'km/h'));
      expect(formatKpiSpeed(318, UnitSystem.imperial), (value: '198', unit: 'mph'));
      expect(formatKpiSpeed(null, UnitSystem.metric), (value: kLapKpiNoValueText, unit: 'km/h'));
    });

    test('lapTopSpeedKph: 트레이스 최고 속도, 트레이스가 없거나 비었으면 null', () {
      expect(lapTopSpeedKph(traceOf('l1')), 204);
      expect(lapTopSpeedKph(traceOf('l1', count: 0)), isNull);
      expect(lapTopSpeedKph(null), isNull);
    });

    test('sectorTimeOf: 섹터 번호의 시간, 없으면 null', () {
      expect(sectorTimeOf(sampleLap().sectors, 2), 33448);
      expect(sectorTimeOf(const [], 1), isNull);
    });
  });
}
