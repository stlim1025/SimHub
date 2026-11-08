// 세션 상세 B안(미션 컨트롤) 보드의 순수 계산: KPI 띠 · 내 순위 변화 · 모든 차 스틴트 · 핵심 장면.
// 화면은 이 결과를 그리기만 한다(색은 [KpiTone]을 팔레트 색으로 바꾼다).
import 'dart:math' as math;

import 'race_highlights.dart';
import 'session_detail_display.dart';
import 'session_display.dart';
import 'session_models.dart';

/// 레이스 세션의 `sessionType`(KPI·순위 그래프·스틴트·핵심 장면은 레이스만).
const String kRaceSessionType = 'Race';

/// 핵심 장면 카드에 담는 최대 줄 수(출발·피트·패널티는 항상 넣고 나머지 장면으로 채운다).
const int kKeyMomentsMax = 12;

const int _msPerSecond = 1000;

/// 순위 그래프 세로 눈금 간격: 차가 이 수 이하면 1칸마다, 넘으면 [_positionTickStep]칸마다.
const int _densePositionTicks = 10;
const int _positionTickStep = 5;

/// 마지막 순위와 이 칸 수 이내로 붙은 5 단위 눈금은 빼고 마지막 순위만 둔다.
const int _positionTickMinGap = 2;

/// 순위 그래프 세로축 끝을 맞추는 단위(내가 지난 가장 낮은 순위 + 1을 이 단위로 올린다, 차 수를 넘지 않는다).
const int _positionAxisStep = 5;

/// 순위 그래프 가로 눈금: 최대 개수와 고르는 간격 후보.
const int _maxLapTicks = 8;
const List<int> _lapTickSteps = [1, 2, 5, 10, 15, 20, 25, 50];

/// 핵심 장면에 넣는 패널티 종류(경고·랩 무효·안내는 빼고 실제 벌칙만, 소문자로 비교).
const Set<String> _seriousPenalties = {'drive through', 'stop go', 'grid penalty', 'time penalty', 'disqualified'};

/// 한 글자로 줄여 쓸 수 있는 컴파운드(`Soft` → `S`). 그 밖은 `?`.
const Set<String> _knownCompounds = {'Soft', 'Medium', 'Hard', 'Intermediate', 'Wet'};

/// 컴파운드 한 글자(`Medium` → `M`, 모르면 `?`, 순수 함수).
String compoundLetter(String? compound) =>
    compound != null && _knownCompounds.contains(compound) ? compound[0] : '?';

/// 내 결과 행(`isPlayer`). 없으면 null.
SessionResult? myResultOf(SessionDetail detail) => detail.results.where((r) => r.isPlayer).firstOrNull;

// -- KPI 띠 ------------------------------------------------------------------------

/// KPI 글자 색 종류. 화면이 팔레트 색으로 바꾼다(강조 = 앰버, fastest = 보라).
enum KpiTone { normal, accent, fastest, success, danger, muted }

/// KPI 칸 종류(위젯 키·테스트용).
enum SessionKpiId { finish, gap, bestLap, pit, penalty, points }

/// KPI 띠 한 칸: 이름(작은 대문자) · 값(큰 글자) · 보조 줄.
class SessionKpi {
  const SessionKpi({
    required this.id,
    required this.label,
    required this.value,
    this.sub,
    this.valueTone = KpiTone.normal,
    this.subTone = KpiTone.muted,
  });

  final SessionKpiId id;
  final String label;
  final String value;
  final String? sub;
  final KpiTone valueTone;
  final KpiTone subTone;
}

/// 세션의 KPI 칸들(순수 함수). 레이스는 Finish · Gap to P1 · Best Lap · Pit · Penalty · Points,
/// 그 밖(예선·연습)은 Position · Best Lap · Gap to P1. 값을 모르는 칸은 뺀다.
List<SessionKpi> sessionKpis(SessionDetail detail) {
  final isRace = detail.header.sessionType == kRaceSessionType;
  final me = myResultOf(detail);
  final finish = _finishKpi(detail, me, isRace: isRace);
  final gap = _gapKpi(detail, me, isRace: isRace);
  final best = _bestLapKpi(detail, me);
  if (!isRace) {
    return [?finish, ?best, ?gap];
  }
  return [?finish, ?gap, ?best, ?_pitKpi(detail, me), ?_penaltyKpi(detail, me), ?_pointsKpi(detail, me)];
}

SessionKpi? _finishKpi(SessionDetail detail, SessionResult? me, {required bool isRace}) {
  final header = detail.header;
  final label = isRace ? 'Finish' : 'Position';
  final position = knownPosition(me?.position) ?? header.myPosition;
  final status = me?.resultStatus ?? header.myResultStatus;
  final String value;
  final KpiTone tone;
  if (isRace && status != null && !isRunningOrFinished(status) && resultStatusLabel(status) != kNoValueText) {
    value = resultStatusLabel(status);
    tone = KpiTone.danger;
  } else if (position != null) {
    value = 'P$position';
    tone = KpiTone.accent;
  } else {
    return null;
  }
  if (!isRace) {
    final count = detail.results.isNotEmpty ? detail.results.length : header.carCount;
    return SessionKpi(id: SessionKpiId.finish, label: label, value: value, valueTone: tone, sub: count > 0 ? '$count대 중' : null);
  }
  final grid = knownPosition(me?.gridPosition) ?? header.myGridPosition;
  final change = me?.positionChange ?? (grid != null && position != null ? grid - position : null);
  final start = grid == null ? null : '(P$grid 출발)';
  final changeText = change == null ? null : signedPositionText(change);
  final sub = [?changeText, ?start].join(' ');
  final subTone = switch (change) {
    final int c when c > 0 => KpiTone.success,
    final int c when c < 0 => KpiTone.danger,
    _ => KpiTone.muted,
  };
  return SessionKpi(
    id: SessionKpiId.finish,
    label: label,
    value: value,
    valueTone: tone,
    sub: sub.isEmpty ? null : sub,
    subTone: subTone,
  );
}

/// 순위 변화 글자: `+4` · `−2`(빼기 기호) · `±0`(순수 함수).
String signedPositionText(int change) => change > 0
    ? '+$change'
    : change < 0
        ? '−${-change}'
        : '±0';

SessionKpi? _gapKpi(SessionDetail detail, SessionResult? me, {required bool isRace}) {
  final reference = referenceRow(detail.results, isRace: isRace);
  if (me == null || reference == null) {
    return null;
  }
  final laps = detail.header.totalLaps > 0 ? detail.header.totalLaps : reference.numLaps;
  if (me.carIndex == reference.carIndex) {
    // 우승이면 1위와의 차 대신 총 시간(예선·연습 1위는 칸을 뺀다).
    final total = me.totalRaceTimeMs;
    return !isRace || total == null
        ? null
        : SessionKpi(
            id: SessionKpiId.gap,
            label: 'Race Time',
            value: formatRaceTime(total + me.penaltiesTimeMs),
            sub: '$laps Laps',
          );
  }
  final referenceBest = reference.bestLapTimeMs;
  return SessionKpi(
    id: SessionKpiId.gap,
    label: 'Gap to P1',
    value: gapToLeaderText(me, reference, isRace: isRace),
    sub: isRace ? '$laps Laps' : (referenceBest == null ? null : 'P1 ${formatRaceTime(referenceBest)}'),
  );
}

/// KPI Gap 칸 글자: 레이스는 끝내지 못했으면 상태(DNF), 랩 뒤처지면 `+1 Lap`, 아니면 `+4.218`.
/// 예선·연습은 최고 랩 차 `+0.311`. 모르면 `-`(순수 함수).
String gapToLeaderText(SessionResult me, SessionResult reference, {required bool isRace}) {
  if (isRace) {
    if (!isRunningOrFinished(me.resultStatus)) {
      return resultStatusLabel(me.resultStatus);
    }
    final lapsBehind = reference.numLaps - me.numLaps;
    if (lapsBehind > 0) {
      return lapsBehind == 1 ? '+1 Lap' : '+$lapsBehind Laps';
    }
  }
  final gap = gapToReferenceMs(me, reference, isRace: isRace);
  return gap == null ? kNoValueText : formatGapMs(gap);
}

SessionKpi? _bestLapKpi(SessionDetail detail, SessionResult? me) {
  final best = me?.bestLapTimeMs ?? detail.myBestLap?.lapTimeMs ?? detail.header.myBestLapTimeMs;
  if (best == null) {
    return null;
  }
  final rank = detail.results.any((r) => r.bestLapTimeMs != null) ? bestLapRank(detail.results, best) : null;
  final fastest = rank == 1 || (me?.isFastestLap ?? false);
  return SessionKpi(
    id: SessionKpiId.bestLap,
    label: 'Best Lap',
    value: formatRaceTime(best),
    valueTone: fastest ? KpiTone.fastest : KpiTone.normal,
    sub: rank == null ? null : '전체 $rank위',
  );
}

/// 내 최고 랩 [myBestMs]의 전체 순위(1부터) = 나보다 빠른 다른 차 최고 랩 수 + 1(순수 함수).
int bestLapRank(List<SessionResult> results, int myBestMs) =>
    1 + results.where((r) => !r.isPlayer && r.bestLapTimeMs != null && r.bestLapTimeMs! < myBestMs).length;

SessionKpi? _pitKpi(SessionDetail detail, SessionResult? me) {
  final stops = myPitStops(detail);
  final count = me?.numPitStops ?? (stops.isEmpty ? null : stops.length);
  if (count == null) {
    return null;
  }
  return SessionKpi(id: SessionKpiId.pit, label: 'Pit', value: '$count', sub: pitStopsText(stops));
}

/// KPI Pit 보조 줄: 한 번이면 `L19 M→H`, 여러 번이면 랩만 `L12 · L30`, 없으면 null(순수 함수).
String? pitStopsText(List<PitStopSummary> stops) {
  if (stops.isEmpty) {
    return null;
  }
  if (stops.length == 1) {
    final stop = stops.single;
    final compounds = stop.fromCompound == null && stop.toCompound == null
        ? ''
        : ' ${compoundLetter(stop.fromCompound)}→${compoundLetter(stop.toCompound)}';
    return 'L${stop.lap}$compounds';
  }
  return stops.map((s) => 'L${s.lap}').join(' · ');
}

SessionKpi? _penaltyKpi(SessionDetail detail, SessionResult? me) {
  if (me == null) {
    return null;
  }
  final serious = detail.penalties.where((p) => p.isPlayer && isSeriousPenalty(p)).lastOrNull;
  final String value;
  if (me.penaltiesTimeMs > 0) {
    value = '+${penaltySecondsText(me.penaltiesTimeMs)}s';
  } else if (me.numPenalties > 0) {
    value = '${me.numPenalties}건';
  } else {
    return SessionKpi(id: SessionKpiId.penalty, label: 'Penalty', value: '0', valueTone: KpiTone.muted);
  }
  return SessionKpi(
    id: SessionKpiId.penalty,
    label: 'Penalty',
    value: value,
    valueTone: KpiTone.danger,
    sub: serious?.infringement ?? (me.penaltiesTimeMs > 0 ? '${me.numPenalties}건' : null),
  );
}

/// 패널티 시간(ms) → 초 글자(`5`, `2.5`, 순수 함수).
String penaltySecondsText(int ms) =>
    ms % _msPerSecond == 0 ? '${ms ~/ _msPerSecond}' : (ms / _msPerSecond).toStringAsFixed(1);

/// 실제 벌칙인지(시간 벌칙이거나 드라이브 스루·스톱 앤 고·그리드·실격, 경고·랩 무효는 아니다, 순수 함수).
bool isSeriousPenalty(SessionPenalty penalty) =>
    penalty.timeS != null || _seriousPenalties.contains(penalty.penalty?.toLowerCase());

SessionKpi? _pointsKpi(SessionDetail detail, SessionResult? me) {
  final points = me?.points ?? detail.header.myPoints;
  if (points == null) {
    return null;
  }
  final header = detail.header;
  final round = header.round;
  final season = header.seasonNumber;
  final sub = round == null ? null : (season == null ? 'R$round' : 'Season $season · R$round');
  return SessionKpi(id: SessionKpiId.points, label: 'Points', value: '$points', sub: sub);
}

// -- 피트 스톱 ---------------------------------------------------------------------

/// 내 피트 스톱 하나: 인 랩, 바꾸기 전·후 컴파운드(모르면 null), 손실(ms, 모르면 null).
typedef PitStopSummary = ({int lap, String? fromCompound, String? toCompound, int? lossMs});

String? _nonEmpty(String value) => value.isEmpty ? null : value;

/// 내 피트 스톱(랩 순, 순수 함수). 레이스 리뷰의 스톱이 있으면 그것을, 없으면 내 결과의 스틴트 경계를,
/// 그것도 없으면 Laps의 IN PIT 묶음(묶음 첫 랩, 앞·뒤 랩 컴파운드)을 쓴다.
List<PitStopSummary> myPitStops(SessionDetail detail) {
  final reviewed = detail.raceReview?.strategy.pitStops ?? const [];
  if (reviewed.isNotEmpty) {
    return [
      for (final stop in reviewed)
        (
          lap: stop.lap,
          fromCompound: _nonEmpty(stop.fromCompound),
          toCompound: _nonEmpty(stop.toCompound),
          lossMs: stop.lossMs,
        ),
    ]..sort((a, b) => a.lap.compareTo(b.lap));
  }
  final stints = myResultOf(detail)?.tyreStints ?? const [];
  if (stints.length > 1) {
    return [
      for (var i = 0; i < stints.length - 1; i++)
        (
          lap: stints[i].endLap,
          fromCompound: stints[i].visualCompound,
          toCompound: stints[i + 1].visualCompound,
          lossMs: null,
        ),
    ];
  }
  final laps = [...detail.laps]..sort((a, b) => a.lapNumber.compareTo(b.lapNumber));
  final stops = <PitStopSummary>[];
  for (var i = 0; i < laps.length; i++) {
    if (!laps[i].inPit || (i > 0 && laps[i - 1].inPit)) {
      continue;
    }
    var end = i;
    while (end + 1 < laps.length && laps[end + 1].inPit) {
      end++;
    }
    stops.add((
      lap: laps[i].lapNumber,
      fromCompound: i > 0 ? laps[i - 1].visualCompound : null,
      toCompound: end + 1 < laps.length ? laps[end + 1].visualCompound : laps[end].visualCompound,
      lossMs: null,
    ));
  }
  return stops;
}

// -- 내 순위 변화 그래프 ---------------------------------------------------------------

/// 순위 그래프 점 하나(랩 끝 순위).
typedef LapPositionPoint = ({int lap, int position});

/// 순위 그래프 재료: 출발 그리드(랩 0, 모르면 null) · 랩 끝 순위 · 피트 스톱 · 세로축 끝 순위 · 가로축 끝(마지막 랩).
class PositionTrace {
  const PositionTrace({
    required this.grid,
    required this.points,
    required this.pitStops,
    required this.maxPosition,
    required this.maxLap,
  });

  final int? grid;
  final List<LapPositionPoint> points;
  final List<PitStopSummary> pitStops;

  /// 세로축 아래 끝 순위(위는 P1). 내가 지난 순위만 보이게 줄인 값이라 차 수보다 작을 수 있다.
  final int maxPosition;
  final int maxLap;

  /// 가로축 시작 랩(그리드가 있으면 0, 없으면 첫 랩).
  int get minLap => grid != null ? 0 : points.first.lap;

  /// 마지막 랩 끝 순위.
  int get finalPosition => points.last.position;
}

/// 내 랩 순위로 그리는 순위 그래프 재료(순수 함수). 그릴 점(그리드 포함)이 둘 미만이면 null.
/// 세로축은 P1부터 내가 지난 가장 낮은 순위 + 1을 5 단위로 올린 순위까지(차 수를 넘지 않는다, 예: P8까지 → P10).
PositionTrace? positionTraceOf(SessionDetail detail) {
  final points = <LapPositionPoint>[
    for (final lap in detail.laps)
      if (knownPosition(lap.position) case final position?) (lap: lap.lapNumber, position: position),
  ]..sort((a, b) => a.lap.compareTo(b.lap));
  final grid = knownPosition(myResultOf(detail)?.gridPosition) ?? detail.header.myGridPosition;
  if (points.isEmpty || points.length + (grid == null ? 0 : 1) < 2) {
    return null;
  }
  final maxLap = points.last.lap;
  final lowest = [?grid, for (final point in points) point.position].reduce(math.max);
  final field = [detail.results.length, detail.header.carCount, lowest].reduce(math.max);
  final axis = math.min(field, ((lowest + 1) / _positionAxisStep).ceil() * _positionAxisStep);
  return PositionTrace(
    grid: grid,
    points: points,
    pitStops: [
      for (final stop in myPitStops(detail))
        if (stop.lap >= 1 && stop.lap <= maxLap) stop,
    ],
    maxPosition: math.max(2, math.max(lowest, axis)),
    maxLap: maxLap,
  );
}

/// 순위 그래프 세로 눈금(P1부터): 차가 10대 이하면 모두, 넘으면 P1 · P5 · P10 …, 마지막 순위는 늘 넣는다(순수 함수).
List<int> positionTicks(int maxPosition) {
  if (maxPosition <= _densePositionTicks) {
    return [for (var p = 1; p <= maxPosition; p++) p];
  }
  final ticks = [1, for (var p = _positionTickStep; p < maxPosition; p += _positionTickStep) p];
  // 마지막 눈금과 너무 붙으면 그 눈금 대신 마지막 순위를 둔다.
  if (maxPosition - ticks.last <= _positionTickMinGap && ticks.length > 1) {
    ticks.removeLast();
  }
  return [...ticks, maxPosition];
}

/// 순위 그래프 가로 눈금(랩 번호): 시작 랩(0 = 그리드) · 1·2·5·10… 간격의 배수 · 마지막 랩, 많아야 9개(순수 함수).
/// 시작·마지막 랩과 간격의 절반보다 붙은 배수는 뺀다.
List<int> lapTicks(int minLap, int maxLap) {
  final span = math.max(1, maxLap - minLap);
  final step = _lapTickSteps.firstWhere((s) => span / s <= _maxLapTicks, orElse: () => _lapTickSteps.last);
  return [
    minLap,
    for (var lap = step; lap < maxLap; lap += step)
      if (lap - minLap >= step / 2 && maxLap - lap >= step / 2) lap,
    if (maxLap > minLap) maxLap,
  ];
}

// -- 모든 차 타이어 스틴트 --------------------------------------------------------------

/// 스틴트 막대 한 칸(컴파운드 · 첫 랩 · 마지막 랩).
typedef StintSegment = ({String compound, int startLap, int endLap});

/// 결과 한 줄의 스틴트 막대들(순수 함수). 스틴트 끝 랩을 이어 붙이고, 마지막 스틴트는 그 차가 달린 랩 수까지,
/// 달린 랩 수를 넘는 끝 랩은 잘라 낸다(빈 칸은 뺀다).
List<StintSegment> stintSegmentsOf(SessionResult row) {
  final segments = <StintSegment>[];
  var start = 1;
  for (var i = 0; i < row.tyreStints.length; i++) {
    final stint = row.tyreStints[i];
    final isLast = i == row.tyreStints.length - 1;
    final end = isLast ? row.numLaps : math.min(stint.endLap, row.numLaps);
    if (end >= start) {
      segments.add((compound: stint.visualCompound, startLap: start, endLap: end));
      start = end + 1;
    }
  }
  return segments;
}

// -- 핵심 장면 ----------------------------------------------------------------------

/// 핵심 장면 종류.
enum KeyMomentKind { start, overtake, overtaken, collision, crash, retirement, safetyCar, virtualSafetyCar, redFlag, pit, penalty }

/// 핵심 장면 한 줄(Race Review 카드).
class KeyMoment {
  const KeyMoment({
    required this.lap,
    required this.kind,
    this.otherName,
    this.fromPosition,
    this.toPosition,
    this.fromCompound,
    this.toCompound,
    this.lossMs,
    this.description,
    this.penaltySeconds,
  });

  final int lap;
  final KeyMomentKind kind;

  /// 추월·충돌 상대 이름.
  final String? otherName;

  /// 출발: 그리드 → 1랩 끝 순위.
  final int? fromPosition;
  final int? toPosition;

  /// 피트: 바꾸기 전·후 컴파운드, 손실(ms).
  final String? fromCompound;
  final String? toCompound;
  final int? lossMs;

  /// 패널티: 침해(없으면 벌칙 이름), 시간 벌칙(초).
  final String? description;
  final int? penaltySeconds;

  /// 이 장면으로 바뀐 순위(+ = 올라감). 출발·추월·추월당함만, 그 밖은 null.
  int? get positionDelta => switch (kind) {
        KeyMomentKind.start when fromPosition != null && toPosition != null => fromPosition! - toPosition!,
        KeyMomentKind.overtake => 1,
        KeyMomentKind.overtaken => -1,
        _ => null,
      };
}

/// 핵심 장면 이름(하이라이트 장면 이름과 같은 말).
const Map<KeyMomentKind, String> _momentLabels = {
  KeyMomentKind.start: '출발',
  KeyMomentKind.overtake: '추월',
  KeyMomentKind.overtaken: '추월당함',
  KeyMomentKind.collision: '충돌',
  KeyMomentKind.crash: '벽 충돌',
  KeyMomentKind.retirement: '리타이어',
  KeyMomentKind.safetyCar: '세이프티카',
  KeyMomentKind.virtualSafetyCar: '버추얼 세이프티카',
  KeyMomentKind.redFlag: '적기',
  KeyMomentKind.pit: '피트',
  KeyMomentKind.penalty: '패널티',
};

/// 핵심 장면 글자: `출발 P7 → P5`, `추월 RUSSELL`, `피트 M → H · 22.4초`, `패널티 · Corner cutting` …(순수 함수).
String keyMomentText(KeyMoment moment) {
  final label = _momentLabels[moment.kind]!;
  return switch (moment.kind) {
    KeyMomentKind.start when moment.fromPosition != null && moment.toPosition != null =>
      '$label P${moment.fromPosition} → P${moment.toPosition}',
    KeyMomentKind.overtake || KeyMomentKind.overtaken || KeyMomentKind.collision when moment.otherName != null =>
      '$label ${moment.otherName}',
    KeyMomentKind.pit => [
        if (moment.fromCompound != null || moment.toCompound != null)
          '$label ${compoundLetter(moment.fromCompound)} → ${compoundLetter(moment.toCompound)}'
        else
          label,
        if (moment.lossMs case final loss?) '${(loss / _msPerSecond).toStringAsFixed(1)}초',
      ].join(' · '),
    KeyMomentKind.penalty when moment.description != null => '$label · ${moment.description}',
    _ => label,
  };
}

/// 핵심 장면 오른쪽 칸: 순위 변화 `+2`·`−1`, 시간 벌칙 `+5s`, 그 밖은 null(순수 함수).
String? keyMomentDeltaText(KeyMoment moment) {
  if (moment.kind == KeyMomentKind.penalty) {
    return moment.penaltySeconds == null ? null : '+${moment.penaltySeconds}s';
  }
  final delta = moment.positionDelta;
  return delta == null ? null : signedPositionText(delta);
}

/// 레이스 핵심 장면(랩 순, 순수 함수). 출발(그리드 → 1랩 끝 순위)·피트·실제 벌칙은 늘 넣고,
/// [highlights]의 내 장면(추월·추월당함·충돌·벽 충돌·리타이어·깃발)으로 [max]줄까지 채운다.
List<KeyMoment> keyMomentsOf(SessionDetail detail, {RaceHighlights? highlights, int max = kKeyMomentsMax}) {
  final fixed = <KeyMoment>[];
  final grid = knownPosition(myResultOf(detail)?.gridPosition) ?? detail.header.myGridPosition;
  final firstLap = detail.laps.where((l) => l.lapNumber == 1).firstOrNull;
  final afterStart = knownPosition(firstLap?.position);
  if (grid != null && afterStart != null) {
    fixed.add(KeyMoment(lap: 1, kind: KeyMomentKind.start, fromPosition: grid, toPosition: afterStart));
  }
  for (final stop in myPitStops(detail)) {
    fixed.add(KeyMoment(
      lap: stop.lap,
      kind: KeyMomentKind.pit,
      fromCompound: stop.fromCompound,
      toCompound: stop.toCompound,
      lossMs: stop.lossMs,
    ));
  }
  for (final penalty in detail.penalties) {
    if (penalty.isPlayer && isSeriousPenalty(penalty)) {
      fixed.add(KeyMoment(
        lap: penalty.lap ?? 1,
        kind: KeyMomentKind.penalty,
        description: penalty.infringement ?? penalty.penalty,
        penaltySeconds: penalty.timeS,
      ));
    }
  }
  final scenes = highlights == null ? const <KeyMoment>[] : _highlightMoments(detail, highlights);
  final room = math.max(0, max - fixed.length);
  final indexed = [...fixed, ...scenes.take(room)].indexed.toList()
    ..sort((a, b) {
      final byLap = a.$2.lap.compareTo(b.$2.lap);
      return byLap != 0 ? byLap : a.$1.compareTo(b.$1);
    });
  return [for (final (_, moment) in indexed) moment];
}

/// 하이라이트의 내 장면 → 핵심 장면(출발·결승 장면은 뺀다, 장면 시각 순).
List<KeyMoment> _highlightMoments(SessionDetail detail, RaceHighlights highlights) {
  final me = highlights.cars.where((c) => c.isPlayer).firstOrNull?.carIndex ?? myResultOf(detail)?.carIndex;
  if (me == null) {
    return const [];
  }
  final clips = [...highlights.mine]..sort((a, b) => a.eventMs.compareTo(b.eventMs));
  final moments = <KeyMoment>[];
  for (final clip in clips) {
    final other = clip.otherCar;
    final mine = clip.focusCar == me;
    final moment = switch (clip.kind) {
      HighlightKind.overtake when mine && other != null =>
        KeyMoment(lap: clip.lap, kind: KeyMomentKind.overtake, otherName: highlights.nameOf(other)),
      HighlightKind.overtake when other == me =>
        KeyMoment(lap: clip.lap, kind: KeyMomentKind.overtaken, otherName: highlights.nameOf(clip.focusCar)),
      HighlightKind.collision => KeyMoment(
          lap: clip.lap,
          kind: KeyMomentKind.collision,
          otherName: mine ? (other == null ? null : highlights.nameOf(other)) : highlights.nameOf(clip.focusCar),
        ),
      HighlightKind.crash when mine => KeyMoment(lap: clip.lap, kind: KeyMomentKind.crash),
      HighlightKind.retirement when mine => KeyMoment(lap: clip.lap, kind: KeyMomentKind.retirement),
      HighlightKind.safetyCar => KeyMoment(lap: clip.lap, kind: KeyMomentKind.safetyCar),
      HighlightKind.virtualSafetyCar => KeyMoment(lap: clip.lap, kind: KeyMomentKind.virtualSafetyCar),
      HighlightKind.redFlag => KeyMoment(lap: clip.lap, kind: KeyMomentKind.redFlag),
      _ => null,
    };
    if (moment != null) {
      moments.add(moment);
    }
  }
  return moments;
}
