import 'dart:math' as math;

import 'session_display.dart';
import 'session_models.dart';

/// 세션 상세 카드가 2열이 되는 콘텐츠 폭(docs/15 §11.3 "900px 미만 1열").
const double kSessionDetailTwoColumnWidth = 900;

const int _msPerSecond = 1000;
const int _secondsPerMinute = 60;
const int _msPerMinute = _msPerSecond * _secondsPerMinute;
const int _minutesPerHour = 60;
const int _msPerHour = _msPerMinute * _minutesPerHour;

/// 타이어 수명 그래프의 위 끝(%)과 아래 끝을 맞추는 눈금 단위.
const double kTyreLifeMax = 100;
const double _tyreLifeStep = 10;

/// 랩타임 그래프의 위·아래 여백과 눈금 단위(ms).
const double _lapTimePaddingMs = 250;
const double _lapTimeStepMs = 500;

// -- 이름 ------------------------------------------------------------------------

const Map<String, String> _sessionKindNames = {
  'Practice1': 'Practice 1',
  'Practice2': 'Practice 2',
  'Practice3': 'Practice 3',
  'ShortPractice': 'Short Practice',
  'Qualifying1': 'Qualifying 1',
  'Qualifying2': 'Qualifying 2',
  'Qualifying3': 'Qualifying 3',
  'ShortQualifying': 'Short Qualifying',
  'OneShotQualifying': 'One-Shot Qualifying',
  'SprintShootout1': 'Sprint Shootout 1',
  'SprintShootout2': 'Sprint Shootout 2',
  'SprintShootout3': 'Sprint Shootout 3',
  'ShortSprintShootout': 'Short Sprint Shootout',
  'OneShotSprintShootout': 'One-Shot Sprint Shootout',
  kSprintKind: 'Sprint',
  'Race': 'Race',
  'Race2': 'Race 2',
  'Race3': 'Race 3',
  'TimeTrial': 'Time Trial',
};

/// 세션 종류 전체 이름(`Qualifying3` → `Qualifying 3`, docs/15 §11.2). 스프린트 주말이면 `Race` → `Sprint`,
/// `Race2` → `Race`([displaySessionKind]). 모르면 `-`.
String sessionKindName(String kind, {bool sprintWeekend = false}) =>
    _sessionKindNames[displaySessionKind(kind, sprintWeekend: sprintWeekend)] ?? kNoValueText;

/// 모드 줄(`Driver Career Season 1`, 시즌이 아니면 `Grand Prix` 등, D-54).
String gameModeLine(String gameMode, int? seasonNumber) {
  final mode = gameModeLabel(gameMode);
  return seasonNumber == null ? mode : '$mode Season $seasonNumber';
}

// -- 시간 차 ---------------------------------------------------------------------

String _two(int value) => value.toString().padLeft(2, '0');

String _three(int value) => value.toString().padLeft(3, '0');

/// Final Classification GAP 칸: 항상 분을 붙인 `+0:02.309`(1시간 이상 `+1:02:03.456`). 음수는 0(순수 함수).
String formatClassificationGap(int ms) {
  final gap = math.max(0, ms);
  final hours = gap ~/ _msPerHour;
  final minutes = (gap ~/ _msPerMinute) % _minutesPerHour;
  final tail = '${_two((gap ~/ _msPerSecond) % _secondsPerMinute)}.${_three(gap % _msPerSecond)}';
  return hours > 0 ? '+$hours:${_two(minutes)}:$tail' : '+${gap ~/ _msPerMinute}:$tail';
}

/// Final Classification GAP 칸 글자(docs/15 §11.3). 레이스에서 끝내지 못한 차는 상태(DNF), 랩 뒤처지면 `+1 Lap`,
/// 기준 행(1위)은 자기 시간, 나머지는 서버 `gapMs`(없으면 앱이 같은 기준으로 계산)를 `+0:02.309`로.
String classificationGapText(SessionResult row, SessionResult? reference, {required bool isRace}) {
  if (isRace && !isRunningOrFinished(row.resultStatus)) {
    return resultStatusLabel(row.resultStatus);
  }
  if (reference == null) {
    return kNoValueText;
  }
  if (isRace) {
    final lapsBehind = reference.numLaps - row.numLaps;
    if (lapsBehind > 0) {
      return lapsBehind == 1 ? '+1 Lap' : '+$lapsBehind Laps';
    }
  }
  if (row.carIndex == reference.carIndex) {
    return timeOrGap(row, reference, isRace: isRace);
  }
  final gap = row.gapMs ?? _computedGapMs(row, reference, isRace: isRace);
  if (gap == null) {
    return isRunningOrFinished(row.resultStatus) ? kNoValueText : resultStatusLabel(row.resultStatus);
  }
  return formatClassificationGap(gap);
}

int? _computedGapMs(SessionResult row, SessionResult reference, {required bool isRace}) {
  if (isRace) {
    final rowTotal = row.totalRaceTimeMs;
    final referenceTotal = reference.totalRaceTimeMs;
    return rowTotal == null || referenceTotal == null
        ? null
        : (rowTotal + row.penaltiesTimeMs) - (referenceTotal + reference.penaltiesTimeMs);
  }
  final rowBest = row.bestLapTimeMs;
  final referenceBest = reference.bestLapTimeMs;
  return rowBest == null || referenceBest == null ? null : rowBest - referenceBest;
}

/// Laps 카드 섹터 칸: 1분 미만 `30.123`, 이상 `1:02.345`, 없으면 `-`(순수 함수).
String formatSectorTime(int? ms) {
  if (ms == null) {
    return kNoValueText;
  }
  final value = math.max(0, ms);
  final tail = _three(value % _msPerSecond);
  return value < _msPerMinute
      ? '${value ~/ _msPerSecond}.$tail'
      : '${value ~/ _msPerMinute}:${_two((value ~/ _msPerSecond) % _secondsPerMinute)}.$tail';
}

/// Laps 카드 GAP 칸(내 최고 랩 대비 `+0.418`). 최고 랩(0)·값 없음은 `-`.
/// 최고 랩보다 빠른 무효 랩은 음수로 와서 `-0.123`(서버 확정, docs/15 §11.4).
String lapGapText(SessionLap lap) {
  final gap = lap.gapToBestMs;
  if (gap == null || gap == 0 || lap.isBestLap) {
    return kNoValueText;
  }
  return gap < 0 ? '-${formatGapMs(-gap).substring(1)}' : formatGapMs(gap);
}

// -- 순위 변동 ---------------------------------------------------------------------

/// 순위 변동 방향(↑ 초록 · ↓ 빨강 · 그대로).
enum PositionTrend { up, down, same }

/// 순위 변동(양수 = 올라감) → 방향 + 크기 글자(`1`, `9`). 그대로면 `-`, 값이 없으면 null(순수 함수).
({PositionTrend trend, String text})? positionChangeOf(int? change) {
  if (change == null) {
    return null;
  }
  if (change == 0) {
    return (trend: PositionTrend.same, text: kNoValueText);
  }
  return (trend: change > 0 ? PositionTrend.up : PositionTrend.down, text: '${change.abs()}');
}

// -- 스틴트 그래프 -------------------------------------------------------------------

/// 그래프 점 하나(x = 스틴트 안 랩, y = 값).
typedef StintPoint = ({int x, double y});

/// 그래프 선 하나 = 스틴트 하나(컴파운드 색). [startLap] = 스틴트 첫 랩(세션 랩 번호, 모르면 null).
typedef StintLine = ({String label, String compound, int? startLap, List<StintPoint> points});

/// `Stint 1 · Medium` (`L1–L12`가 있으면 덧붙인다).
String _stintLabel(int index, SessionTyreStint stint) {
  final start = stint.startLap;
  final end = stint.endLap;
  final range = start != null && end != null && end >= start ? ' (L$start–L$end)' : '';
  return 'Stint ${index + 1} · ${stint.visualCompound}$range';
}

List<StintLine> _linesOf(List<SessionTyreStint> stints, double? Function(StintLap lap) valueOf) {
  final lines = <StintLine>[];
  for (var i = 0; i < stints.length; i++) {
    final points = [
      for (final lap in stints[i].laps)
        if (valueOf(lap) case final y?) (x: lap.lapInStint, y: y),
    ]..sort((a, b) => a.x.compareTo(b.x));
    if (points.isNotEmpty) {
      lines.add((
        label: _stintLabel(i, stints[i]),
        compound: stints[i].visualCompound,
        startLap: stints[i].startLap,
        points: points,
      ));
    }
  }
  return lines;
}

/// Tyre Life Remaining 선들(y = 100 − 평균 마모, docs/15 §11.3). 값이 없는 스틴트는 뺀다(순수 함수).
List<StintLine> tyreLifeLines(List<SessionTyreStint> stints) => _linesOf(stints, (lap) => lap.tyreLifeRemaining);

/// Tyre Stints Lap Times 선들(y = 랩타임 ms). 값이 없는 스틴트는 뺀다(순수 함수).
List<StintLine> lapTimeLines(List<SessionTyreStint> stints) =>
    _linesOf(stints, (lap) => lap.lapTimeMs?.toDouble());

/// 가로축 끝(가장 긴 스틴트의 랩 수, 최소 1).
int stintChartMaxX(List<StintLine> lines) =>
    lines.expand((line) => line.points).fold(1, (maxX, point) => math.max(maxX, point.x));

Iterable<double> _values(List<StintLine> lines) => lines.expand((line) => line.points).map((p) => p.y);

/// 타이어 수명 세로축: 위 100, 아래 = 최솟값 아래 10 단위(0 미만 안 됨, F1Laps 30–100 모양).
({double min, double max}) tyreLifeRange(List<StintLine> lines) {
  final values = _values(lines);
  if (values.isEmpty) {
    return (min: 0, max: kTyreLifeMax);
  }
  final low = values.reduce(math.min);
  final min = math.max(0.0, ((low - 1) / _tyreLifeStep).floor() * _tyreLifeStep);
  return (min: math.min(min, kTyreLifeMax - _tyreLifeStep), max: kTyreLifeMax);
}

/// 랩타임 세로축: 최솟값·최댓값에 여백을 두고 0.5초 단위로 맞춘다.
({double min, double max}) lapTimeRange(List<StintLine> lines) {
  final values = _values(lines);
  if (values.isEmpty) {
    return (min: 0, max: _lapTimeStepMs);
  }
  final low = ((values.reduce(math.min) - _lapTimePaddingMs) / _lapTimeStepMs).floor() * _lapTimeStepMs;
  final high = ((values.reduce(math.max) + _lapTimePaddingMs) / _lapTimeStepMs).ceil() * _lapTimeStepMs;
  return (min: math.max(0.0, low), max: high);
}

// -- 엔진 마모 ---------------------------------------------------------------------

/// Engine Wear 목록(F1Laps 순서). 값이 없으면 null.
List<({String label, double? value})> engineWearItems(EngineWear wear) => [
      (label: 'ICE', value: wear.ice),
      (label: 'Turbo Charger', value: wear.turboCharger),
      (label: 'MGU-H', value: wear.mguH),
      (label: 'MGU-K', value: wear.mguK),
      (label: 'Energy Store', value: wear.energyStore),
      (label: 'Control Electronics', value: wear.controlElectronics),
      (label: 'Gearbox', value: wear.gearbox),
      (label: 'Engine Damage', value: wear.engineDamage),
    ];

// -- 패널티 -----------------------------------------------------------------------

/// PENALTY 칸: `Time Penalty (5s)`, 시간이 없으면 이름만. 이름이 없으면 `-`.
String penaltyText(SessionPenalty penalty) {
  final name = penalty.penalty ?? kNoValueText;
  final seconds = penalty.timeS;
  return seconds == null ? name : '$name (${seconds}s)';
}
