import 'lap_compare.dart';
import 'lap_detail_models.dart';

/// 값이 없는 칸의 자리표시.
const String kDetailNoValueText = '-';

/// ERS 배터리 최대 저장량(J, docs/15 §3.2). ERS %는 이 값 기준이다.
const double kErsCapacityJ = 4000000;

/// 타이어 마모 단계 경계(%) — 25 미만 초록, 50 미만 노랑, 75 미만 주황, 그 이상 빨강(docs/15 §2.3).
const double kWearMediumFrom = 25;
const double kWearHighFrom = 50;
const double kWearCriticalFrom = 75;

/// Lap ID를 줄여 보여 줄 글자 수.
const int _shortLapIdLength = 8;

const int _msPerSecond = 1000;
const int _msPerMinute = 60 * _msPerSecond;
const int _secondsPerMinute = 60;
const double _percent = 100;

// -- 탭 (`/laps/:lapId?tab=`) ----------------------------------------------------

const String kLapTabDetails = 'details';
const String kLapTabTelemetry = 'telemetry';
const String kLapTabAnalysis = 'analysis';
const String kLapTabBest = 'best';

/// 화면에 보이는 순서.
const List<String> kLapTabs = [kLapTabDetails, kLapTabTelemetry, kLapTabAnalysis, kLapTabBest];

/// 주소의 `tab` 값을 탭으로 바꾼다. 없거나 모르는 값이면 `details`(docs/15 §2.3).
String normalizeLapTab(String? value) => kLapTabs.contains(value) ? value! : kLapTabDetails;

/// 랩 상세 주소. [tab]을 주면 `?tab=`을, [compare]를 주면 비교 선택 쿼리(docs/15 §10, D-51 — 기본값은 싣지 않음)를 붙인다.
/// 행 클릭은 탭·비교 없이 연다.
String lapDetailLocation(String lapId, {String? tab, LapCompareSelection? compare}) {
  final query = {'tab': ?tab, ...?compare?.toQuery()};
  final path = '/laps/$lapId';
  return query.isEmpty ? path : Uri(path: path, queryParameters: query).toString();
}

/// 랩 셋업 주소(`/laps/:lapId/setup`). Lap Details 카드의 View Setup이 연다.
String lapSetupLocation(String lapId) => '/laps/$lapId/setup';

// -- 공유 링크 (`/share/laps/:lapId?tab=`) ------------------------------------------

/// 공유 링크 화면의 탭(로그인 없이 볼 수 있는 탭만, 화면 순서).
const List<String> kSharedLapTabs = [kLapTabDetails, kLapTabTelemetry];

/// 공유 링크 주소의 `tab` 값을 탭으로 바꾼다. 없거나 모르는 값(`best` 포함)이면 `details`.
String normalizeSharedLapTab(String? value) => kSharedLapTabs.contains(value) ? value! : kLapTabDetails;

/// 로그인 없이 여는 공유 랩 주소(Share 버튼이 복사한다). Telemetry 탭이면 `?tab=telemetry`를 붙이고,
/// 그 밖의 탭(기본·Your Best Laps)은 싣지 않는다. [compareLapId]를 주면 비교 중인 랩을 `compareLapId`로 싣는다 —
/// 비교 종류(내 최고 랩 등)는 시간이 지나면 다른 랩이 되므로, 지금 비교 중인 랩 ID 하나로 고정한다.
String sharedLapLocation(String lapId, {String? tab, String? compareLapId}) {
  final path = '/share/laps/$lapId';
  final query = {
    if (tab == kLapTabTelemetry) 'tab': tab!,
    kCompareLapIdQuery: ?compareLapId,
  };
  return query.isEmpty ? path : Uri(path: path, queryParameters: query).toString();
}

// -- 비교 Delta -------------------------------------------------------------------

/// Delta 색 구분: 빠름(초록) · 느림(빨강) · 같음.
enum DeltaTone { faster, slower, even }

DeltaTone deltaToneOf(int deltaMs) => deltaMs < 0
    ? DeltaTone.faster
    : deltaMs > 0
        ? DeltaTone.slower
        : DeltaTone.even;

/// `-0.123` / `+0.456` / `0.000`. 60초 이상이면 `+1:02.345`(순수 함수).
String formatDeltaMs(int deltaMs) {
  final sign = deltaMs < 0 ? '-' : (deltaMs > 0 ? '+' : '');
  final abs = deltaMs.abs();
  final millis = (abs % _msPerSecond).toString().padLeft(3, '0');
  if (abs < _msPerMinute) {
    return '$sign${abs ~/ _msPerSecond}.$millis';
  }
  final seconds = ((abs ~/ _msPerSecond) % _secondsPerMinute).toString().padLeft(2, '0');
  return '$sign${abs ~/ _msPerMinute}:$seconds.$millis';
}

/// Delta 비율 `+12.3%` = (이 랩 − 비교 랩) / 비교 랩(docs/15 §10, D-51). 비교 랩이 0 이하면 null(순수 함수).
String? formatDeltaPercent(int lapMs, int referenceMs) {
  if (referenceMs <= 0) {
    return null;
  }
  final percent = (lapMs - referenceMs) / referenceMs * _percent;
  final rounded = percent.toStringAsFixed(1);
  if (rounded == '0.0' || rounded == '-0.0') {
    return '0.0%';
  }
  return '${percent > 0 ? '+' : ''}$rounded%';
}

// -- 타이어·손상 --------------------------------------------------------------------

/// 타이어 마모 단계. [unknown]은 값이 없을 때.
enum TyreWearLevel { unknown, low, medium, high, critical }

TyreWearLevel tyreWearLevelOf(double? percent) {
  if (percent == null) {
    return TyreWearLevel.unknown;
  }
  if (percent < kWearMediumFrom) {
    return TyreWearLevel.low;
  }
  if (percent < kWearHighFrom) {
    return TyreWearLevel.medium;
  }
  return percent < kWearCriticalFrom ? TyreWearLevel.high : TyreWearLevel.critical;
}

/// 반올림한 정수 `31%`. null이면 `-`.
String formatPercent(double? value) => value == null ? kDetailNoValueText : '${value.round()}%';

/// 이 랩 동안 늘어난 마모 `+4.0%`(끝 − 시작). 시작·끝 중 하나라도 없으면 null.
String? formatWearDelta(double? start, double? end) {
  if (start == null || end == null) {
    return null;
  }
  final delta = end - start;
  return '${delta < 0 ? '' : '+'}${delta.toStringAsFixed(1)}%';
}

/// 손상 칸: 0·null이면 `-`, 그 밖은 `10%`.
String damageText(double? value) => value == null || value == 0 ? kDetailNoValueText : formatPercent(value);

/// 바퀴 4개 손상·마모: `31% / - / 24% / -`(FL / FR / RL / RR). 모두 0·null이면 `-` 하나.
String wheelValuesText(WheelValues? wheels) {
  final texts = wheels?.ordered.map(damageText).toList();
  if (texts == null || texts.every((t) => t == kDetailNoValueText)) {
    return kDetailNoValueText;
  }
  return texts.join(' / ');
}

// -- 연료·ERS·날씨 -------------------------------------------------------------------

/// 이 랩 연료 사용량(kg) = 시작 − 끝. 하나라도 없으면 null.
double? fuelUsedKg(CarSnapshot car) {
  final start = car.fuelStartKg;
  final end = car.fuelEndKg;
  return start == null || end == null ? null : start - end;
}

/// `1.70 kg`. null이면 `-`.
String formatKg(double? kg) => kg == null ? kDetailNoValueText : '${kg.toStringAsFixed(2)} kg';

/// ERS 저장량(J) → 배터리 %(4 MJ 기준). null이면 null.
double? ersPercentOf(double? joules) => joules == null ? null : joules / kErsCapacityJ * _percent;

/// 이 랩 ERS 사용량(%) = (시작 − 끝) / 4 MJ × 100. 하나라도 없으면 null. 회수가 더 많으면 음수다.
double? ersUsedPercent(CarSnapshot car) {
  final start = car.ersStoreStartJ;
  final end = car.ersStoreEndJ;
  return start == null || end == null ? null : ersPercentOf(start - end);
}

/// 소수 한 자리 `12.7%`(음수는 `-3.2%`). null이면 `-`.
String formatOneDecimalPercent(double? value) =>
    value == null ? kDetailNoValueText : '${value.toStringAsFixed(1)}%';

/// 반올림한 `21°C`. null이면 `-`.
String formatTemperature(double? celsius) => celsius == null ? kDetailNoValueText : '${celsius.round()}°C';

/// 비 예보 `4%`. null이면 `-`.
String formatRainForecast(int? percent) => percent == null ? kDetailNoValueText : '$percent%';

/// 남은 랩 수 `13.1`. null이면 `-`.
String formatLapsRemaining(double? laps) => laps == null ? kDetailNoValueText : laps.toStringAsFixed(1);

// -- 컴파운드 (F1 UDP 번호) ----------------------------------------------------------

/// F1 UDP `m_visualTyreCompound` 번호 → 이름(세션 결과의 `visualCompound`와 같은 이름, Agent `F1EnumMaps`와 같은 표).
const Map<int, String> _visualCompoundNames = {
  16: 'Soft',
  17: 'Medium',
  18: 'Hard',
  7: 'Intermediate',
  8: 'Wet',
};

/// F1 UDP `m_actualTyreCompound` 번호 → 라벨(Agent `F1EnumMaps.ToActualCompoundLabel`과 같은 표).
const Map<int, String> _actualCompoundLabels = {
  16: 'C5',
  17: 'C4',
  18: 'C3',
  19: 'C2',
  20: 'C1',
  21: 'C0',
  22: 'C6',
  7: 'Inter',
  8: 'Wet',
};

/// 보이는 컴파운드 이름. F1 밖(클래식·F2)·모르는 값·null은 null.
String? visualCompoundName(int? code) => _visualCompoundNames[code];

/// 실제 컴파운드 라벨(`C0`~`C6`·`Inter`·`Wet`). 모르는 값·null은 null.
String? actualCompoundLabel(int? code) => _actualCompoundLabels[code];

/// Lap ID 앞 [_shortLapIdLength]자.
String shortLapId(String lapId) =>
    lapId.length <= _shortLapIdLength ? lapId : lapId.substring(0, _shortLapIdLength);
