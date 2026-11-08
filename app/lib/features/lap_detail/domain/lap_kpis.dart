/// 랩 상세 KPI 띠(미션 컨트롤)의 값 계산: 랩 정체 · 비교 랩과의 차이 · 섹터 · 최고 속도 · 타이어(순수 함수).
library;

import '../../../core/util/lap_time.dart';
import '../../auth/domain/user_preferences.dart';
import '../../laps/domain/lap_display.dart';
import '../../laps/domain/lap_models.dart';
import 'lap_compare.dart';
import 'lap_detail_display.dart';
import 'lap_detail_models.dart';
import 'telemetry_math.dart';
import 'track_map.dart';

/// KPI 띠의 섹터 칸 수(F1 25 = S1·S2·S3).
const int kLapKpiSectorCount = 3;

/// 값이 없는 KPI 칸의 자리표시(트레이스를 불러오는 중·없음 포함).
const String kLapKpiNoValueText = '—';

const String _titleSeparator = ' · ';
const String _lapNumberPrefix = 'L';
const String _tyreAgeSuffix = '랩';
const String _comparePrefix = 'vs ';
const String _personalBestLabel = 'PB';
const String _leaderboardLabel = 'Leaderboard';
const String _otherLapLabel = 'Lap';
const String _otherCarLabel = 'Car';
const String _kphUnit = 'km/h';
const String _mphUnit = 'mph';
const int _msPerSecond = 1000;
const int _msPerMinute = 60 * _msPerSecond;
const int _millisDigits = 3;

/// KPI 띠의 비교 칸 상태.
enum LapKpiCompareState {
  /// 비교 안 함 — 비교 칸을 숨긴다.
  hidden,

  /// 비교 대상이 없다(조건에 맞는 랩 없음·볼 수 없는 랩·다른 차 랩타임 모름).
  unavailable,

  /// 비교 대상이 곧 이 랩(내 최고 랩·리더보드 최고 랩).
  itself,

  /// 비교 랩과의 차이가 있다([LapKpis.deltaMs]).
  delta,
}

/// 섹터 칸 하나: 번호(1부터), 이 랩 시간(ms, 모르면 null), 비교 랩과의 차이(ms, 비교 섹터를 모르면 null).
typedef LapKpiSector = ({int number, int? timeMs, int? deltaMs});

/// KPI 띠 값. 최고 속도는 트레이스에서 따로 읽는다([lapTopSpeedKph]).
class LapKpis {
  const LapKpis({
    required this.lapTimeMs,
    required this.compareKind,
    required this.compareState,
    required this.sectors,
    this.referenceMs,
    this.deltaMs,
    this.tyreCompound,
    this.tyreAgeLaps,
    this.tyreWearPercent,
  });

  final int lapTimeMs;

  /// 비교 칸 이름을 정하는 비교 종류(서버가 실제로 고른 종류가 있으면 그것).
  final LapCompareKind compareKind;
  final LapKpiCompareState compareState;

  /// 비교 랩 랩타임(ms). [LapKpiCompareState.delta]·[LapKpiCompareState.itself]일 때만 있다.
  final int? referenceMs;

  /// 이 랩 − 비교 랩(ms). [LapKpiCompareState.delta]일 때만 있다.
  final int? deltaMs;

  /// S1~S3 순서.
  final List<LapKpiSector> sectors;

  /// 랩 끝 보이는 컴파운드 이름(`Soft`·`Medium` …). 모르면 null.
  final String? tyreCompound;

  /// 랩 끝 타이어 사용 랩 수. 모르면 null.
  final int? tyreAgeLaps;

  /// 랩 끝 네 바퀴 평균 마모(%). 모르면 null.
  final double? tyreWearPercent;

  /// 이 랩이 비교 기준의 최고 랩인지(랩타임을 보라색으로).
  bool get isBest => compareState == LapKpiCompareState.itself;
}

/// 랩 상세 + 비교 선택 → KPI 띠 값.
/// 비교 대상은 랩 상세 탭과 같은 규칙이다: "비교 안 함"이면 숨기고, 같은 세션의 다른 차([LapCompareKind.car])는
/// 주소에 실린 랩타임([LapCompareSelection.compareTimeMs])과만 비교한다(그 차 섹터 시간은 몰라 섹터 차이는 없다).
/// 비교 대상이 곧 이 랩이면(직접 고른 랩 ID 제외) 섹터 차이도 없다.
LapKpis lapKpisOf(LapDetail detail, LapCompareSelection compare) {
  final lap = detail.lap;
  final car = detail.car;
  final otherCar = compare.kind == LapCompareKind.car;
  final comparison = compare.kind == LapCompareKind.none || otherCar ? null : detail.comparison;
  final itself = comparison != null && detail.comparesWithItself && comparison.kind != LapCompareKind.lap;
  final referenceMs = otherCar ? compare.compareTimeMs : comparison?.lapTimeMs;
  final state = switch (compare.kind) {
    LapCompareKind.none => LapKpiCompareState.hidden,
    _ when itself => LapKpiCompareState.itself,
    _ when referenceMs == null => LapKpiCompareState.unavailable,
    _ => LapKpiCompareState.delta,
  };
  final sectorReference = state == LapKpiCompareState.delta ? comparison?.sectors : null;
  return LapKpis(
    lapTimeMs: lap.lapTimeMs,
    compareKind: otherCar ? LapCompareKind.car : comparison?.kind ?? compare.kind,
    compareState: state,
    referenceMs: state == LapKpiCompareState.hidden || state == LapKpiCompareState.unavailable ? null : referenceMs,
    deltaMs: state == LapKpiCompareState.delta ? lap.lapTimeMs - referenceMs! : null,
    sectors: [
      for (var n = 1; n <= kLapKpiSectorCount; n++)
        _sectorOf(n, sectorTimeOf(lap.sectors, n), sectorReference == null ? null : sectorTimeOf(sectorReference, n)),
    ],
    tyreCompound: visualCompoundName(car?.visualTyreCompound),
    tyreAgeLaps: car?.tyreAgeLaps,
    tyreWearPercent: averageWear(car?.tyreWearEnd),
  );
}

LapKpiSector _sectorOf(int number, int? timeMs, int? referenceMs) => (
      number: number,
      timeMs: timeMs,
      deltaMs: timeMs == null || referenceMs == null ? null : timeMs - referenceMs,
    );

/// 랩 정체 한 줄: `Zandvoort · Race L23`. 세션 유형을 모르면 빼고, 랩 번호가 없으면 붙이지 않는다.
String lapKpiTitle(Lap lap) {
  final session = sessionTypeLabel(lap.sessionType);
  final number = lap.lapNumber;
  final detail = [
    if (session != kLapNoValueText) session,
    if (number != null) '$_lapNumberPrefix$number',
  ].join(' ');
  return detail.isEmpty ? lap.trackName : '${lap.trackName}$_titleSeparator$detail';
}

/// 비교 칸 이름: `vs PB` · `vs Leaderboard` · `vs Lap` · `vs {드라이버}`(다른 차, 이름을 모르면 `vs Car`).
String lapKpiCompareLabel(LapCompareKind kind, {String? otherCarName}) {
  final target = switch (kind) {
    LapCompareKind.leaderboard => _leaderboardLabel,
    LapCompareKind.lap => _otherLapLabel,
    LapCompareKind.car => (otherCarName ?? '').isEmpty ? _otherCarLabel : otherCarName!,
    LapCompareKind.best || LapCompareKind.none => _personalBestLabel,
  };
  return '$_comparePrefix$target';
}

/// 타이어 칸 아래 줄: `12랩 · 18%`(사용 랩 수 · 평균 마모). 아는 값만 잇고, 둘 다 모르면 null.
String? formatTyreKpiCaption({int? ageLaps, double? wearPercent}) {
  final parts = [
    if (ageLaps != null) '$ageLaps$_tyreAgeSuffix',
    if (wearPercent != null) formatPercent(wearPercent),
  ];
  return parts.isEmpty ? null : parts.join(_titleSeparator);
}

/// 섹터 칸 시간: 1분 미만은 `24.112`, 넘으면 `1:02.345`. 모르면 [kLapKpiNoValueText].
String formatKpiSectorTime(int? ms) {
  if (ms == null || ms < 0) {
    return kLapKpiNoValueText;
  }
  if (ms >= _msPerMinute) {
    return formatLapTime(ms);
  }
  return '${ms ~/ _msPerSecond}.${(ms % _msPerSecond).toString().padLeft(_millisDigits, '0')}';
}

/// 트레이스의 최고 속도(km/h). 트레이스가 없거나 비었으면 null.
double? lapTopSpeedKph(LapTrace? trace) =>
    trace == null || trace.isEmpty ? null : lapTelemetryStatsOf(trace).topSpeedKph;

/// 최고 속도 칸: 값(`318`, Imperial이면 mph로 바꿔 반올림)과 단위(`km/h`·`mph`). 속도를 모르면 값이 [kLapKpiNoValueText].
({String value, String unit}) formatKpiSpeed(double? kph, UnitSystem units) {
  final imperial = units == UnitSystem.imperial;
  return (
    value: kph == null ? kLapKpiNoValueText : (imperial ? kphToMph(kph) : kph).round().toString(),
    unit: imperial ? _mphUnit : _kphUnit,
  );
}
