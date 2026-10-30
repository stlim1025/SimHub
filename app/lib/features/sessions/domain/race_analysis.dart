import 'dart:math' as math;

import '../../lap_detail/domain/lap_corners.dart' show OfficialCorner;
import 'race_review.dart';
import 'session_detail_models.dart';

// 레이스 심층 분석(`GET /me/sessions/{id}/race-analysis`): 서버가 내 랩 트레이스로 낸 구간별 타이어 부담·입력·배터리, 타이어로 본 전략,
// 랩마다 페이스 기준을 읽어 레이스 엔지니어 말투의 평가 줄로 바꾼다. 모두 순수 함수.

/// 바퀴 이름(서버 바퀴 배열 순서: 앞왼·앞오·뒤왼·뒤오), 앞바퀴 수.
const List<String> kWheelNames = ['앞왼', '앞오', '뒤왼', '뒤오'];
const int _frontWheels = 2;

/// 공식 코너가 구간에 드는지 볼 때 구간 앞뒤 여유(m).
const double _cornerMarginM = 40;

/// 타이어: 부담이 큰 코너를 짚는 수, 리미터 바퀴 표면 온도가 다른 바퀴 최고보다 이만큼(°C) 높으면 짚는다,
/// 같은 컴파운드 스틴트끼리 리미터 바퀴 일이 이만큼(kJ/랩) 차이 나면 비교한다, 구간 시간이 랩마다 이만큼(ms) 늘면 그립이 빠진 곳으로 본다.
const int kTopLoadCorners = 3;
const double _tempGapC = 15;
const double _compareWorkKj = 20;
const int _gripLossMs = 20;
const int _gripLossCorners = 2;

/// 코너 입력 문턱: 언더스티어(°), 풀 스로틀로 조향·브레이크 밟은 채 조향·앞 락업·뒤 휠스핀·연석 거리(m).
const double kUndersteerDeg = 2.0;
const double kThrottleSteerM = 40;
const double kTrailBrakeM = 25;
const double kLockupM = 10;
const double kWheelspinM = 10;
const double kKerbM = 80;

/// 스틴트 비교에서 말할 만한 차이: 언더스티어(°)·조향(%p)·거리(m)·락업/휠스핀(m).
const double _understeerDiffDeg = 0.3;
const double _steerDiffPct = 1;
const double _distanceDiffM = 10;
const double _kerbDiffM = 15;
const double _slipDiffM = 5;

/// 세팅 제안: 부담 큰 코너의 평균 언더스티어(°), 랩당 앞 락업(m), 앞 타이어를 달구는 캠버(° 이하).
const double _setupUndersteerDeg = 2.0;
const double _setupLockupM = 20;
const double _hotCamberDeg = -3.2;

/// 배터리: AI와 이만큼(kJ/랩) 차이 나면 짚는다, 랩당 이 거리(m) 이상 바닥이고 그런 랩이 이 수 이상이면(한 랩 사고는 빼고) 짚는다.
const double _ersGapKj = 150;
const double _emptyM = 20;
const int _emptyLapsMin = 2;

/// 배터리 줄일 곳: Overtake로 280km/h 이상 달린 거리가 이 이상(m)인 직선. 덜 떼는 코너: AI가 스로틀을 이만큼(m) 더 오래 완전히 떼며
/// [_ersGapKj] 이상 더 채우는 코너(최대 [_partialLiftCorners]곳) — 단 AI가 그 구간에서 더 걸린 시간이 더 채운 1MJ당 이 초 이하일 때만
/// (카탈루냐 실측: 코너 탈출에서 Overtake로 쓴 1MJ는 1.2~2.9초를 번다).
const double _fastOvertakeM = 20;
const double _liftGapM = 20;
const int _partialLiftCorners = 2;
const double _maxLiftCostSPerMj = 0.6;

/// 전략: 남은 수명이 이 랩 이하이거나 마모가 이 % 이상이면 타이어 때문에 들어온 것, 게임이 본 쓸 수 있는 랩보다 이만큼 덜 탔으면 짚는다,
/// 대안이 이만큼(ms) 이상 빨라야 말한다.
const int _forcedLifeLaps = 2;
const double _forcedWearPct = 70;
const int _spareLaps = 3;
const int kStrategyGainMs = 1000;

const double _kjPerMj = 1000;
const double _msPerSecond = 1000;
const double _percent = 100;

const String kCornerKind = 'Corner';

/// 페이스 기준을 어떻게 읽는지(페이스 줄 맨 앞).
const String kPaceBasisLine = '기준: 같은 타이어(같은 컴파운드·나이, ±5랩 안 AI)가 실력 비교에 가장 공정해 — 같은 랩은 그 순간 레이스 상황, 스틴트는 전략 묶음 결과야';

List<double>? _wheelList(Object? json) {
  if (json is! List || json.length != kWheelNames.length) {
    return null;
  }
  final values = [for (final v in json) ?jsonDouble(v)];
  return values.length == kWheelNames.length ? values : null;
}

/// 랩 구간 하나: 번호, 코너인지, 랩 거리 시작·끝(m — 결승선을 넘는 직선은 시작 > 끝), 기준 랩 최저 속도 지점(m)·속도.
class RaceSegment {
  const RaceSegment({
    required this.index,
    required this.isCorner,
    required this.startM,
    required this.endM,
    required this.apexM,
    required this.minSpeedKph,
  });

  final int index;
  final bool isCorner;
  final int startM;
  final int endM;
  final int apexM;
  final int minSpeedKph;

  /// 결승선을 넘는지.
  bool get wraps => startM > endM;

  /// 랩 거리 [distanceM]가 구간 안(앞뒤 [margin]m 여유)인지.
  bool covers(double distanceM, {double margin = 0}) => wraps
      ? distanceM >= startM - margin || distanceM <= endM + margin
      : distanceM >= startM - margin && distanceM <= endM + margin;

  static RaceSegment? fromJsonOrNull(Map<String, dynamic> json) {
    final index = jsonInt(json['index']);
    final start = jsonInt(json['startM']);
    final end = jsonInt(json['endM']);
    if (index == null || start == null || end == null) {
      return null;
    }
    return RaceSegment(
      index: index,
      isCorner: jsonString(json['kind']) == kCornerKind,
      startM: start,
      endM: end,
      apexM: jsonInt(json['apexM']) ?? start,
      minSpeedKph: jsonInt(json['minSpeedKph']) ?? 0,
    );
  }
}

/// 스틴트 안 한 구간의 랩 평균(서버 `RaceSegmentDriving`): 시간·랩당 늘어난 시간(ms), 바퀴별 마찰 일(kJ), 조향(%)·언더스티어(°),
/// 락업·휠스핀·브레이크 밟은 채 조향·풀 스로틀 조향·브레이크 밟은·연석 거리(m), 바퀴별 최고 표면 온도, 최저·끝 속도,
/// 배터리 채움·씀(kJ)·Overtake·배포 없음 거리(m)·끝 잔량(kJ)·바닥 거리(m).
class RaceSegmentDriving {
  const RaceSegmentDriving({
    required this.index,
    required this.timeMs,
    required this.steerPct,
    required this.trailBrakeM,
    required this.throttleSteerM,
    required this.minSpeedKph,
    required this.endSpeedKph,
    this.brakeM = 0,
    this.timeTrendMsPerLap,
    this.wheelWorkKj,
    this.understeerDeg,
    this.lockupM,
    this.wheelspinM,
    this.kerbM,
    this.peakSurfaceTempC,
    this.harvestKj,
    this.deployKj,
    this.overtakeM,
    this.noDeployM,
    this.storeEndKj,
    this.emptyM,
    this.emptyLaps,
    this.liftM = 0,
    this.fastOvertakeM,
  });

  final int index;
  final int timeMs;
  final int? timeTrendMsPerLap;
  final List<double>? wheelWorkKj;
  final double steerPct;
  final double? understeerDeg;
  final double? lockupM;
  final double? wheelspinM;
  final double trailBrakeM;
  final double throttleSteerM;
  final double brakeM;
  final double? kerbM;
  final List<double>? peakSurfaceTempC;
  final int minSpeedKph;
  final int endSpeedKph;
  final double? harvestKj;
  final double? deployKj;
  final double? overtakeM;
  final double? noDeployM;
  final double? storeEndKj;
  final double? emptyM;

  /// 이 구간에서 배터리가 바닥났던 랩 수(모르면 null).
  final int? emptyLaps;

  /// 스로틀을 완전히 뗀(5% 미만) 거리(m), Overtake로 280km/h 이상 달린 거리(m, 모르면 null).
  final double liftM;
  final double? fastOvertakeM;

  static RaceSegmentDriving? fromJsonOrNull(Map<String, dynamic> json) {
    final index = jsonInt(json['index']);
    if (index == null) {
      return null;
    }
    return RaceSegmentDriving(
      index: index,
      timeMs: jsonInt(json['timeMs']) ?? 0,
      timeTrendMsPerLap: jsonInt(json['timeTrendMsPerLap']),
      wheelWorkKj: _wheelList(json['wheelWorkKj']),
      steerPct: jsonDouble(json['steerPct']) ?? 0,
      understeerDeg: jsonDouble(json['understeerDeg']),
      lockupM: jsonDouble(json['lockupM']),
      wheelspinM: jsonDouble(json['wheelspinM']),
      trailBrakeM: jsonDouble(json['trailBrakeM']) ?? 0,
      throttleSteerM: jsonDouble(json['throttleSteerM']) ?? 0,
      brakeM: jsonDouble(json['brakeM']) ?? 0,
      kerbM: jsonDouble(json['kerbM']),
      peakSurfaceTempC: _wheelList(json['peakSurfaceTempC']),
      minSpeedKph: jsonInt(json['minSpeedKph']) ?? 0,
      endSpeedKph: jsonInt(json['endSpeedKph']) ?? 0,
      harvestKj: jsonDouble(json['harvestKj']),
      deployKj: jsonDouble(json['deployKj']),
      overtakeM: jsonDouble(json['overtakeM']),
      noDeployM: jsonDouble(json['noDeployM']),
      storeEndKj: jsonDouble(json['storeEndKj']),
      emptyM: jsonDouble(json['emptyM']),
      emptyLaps: jsonInt(json['emptyLaps']),
      liftM: jsonDouble(json['liftM']) ?? 0,
      fastOvertakeM: jsonDouble(json['fastOvertakeM']),
    );
  }
}

/// 내 스틴트 하나의 주행 분석: 컴파운드·랩 범위·분석한 랩, 바퀴별 랩당 마찰 일(kJ)·최고 표면·속 온도(°C)·마모(%p), 구간별 평균.
class RaceStintDriving {
  const RaceStintDriving({
    required this.compound,
    required this.startLap,
    required this.endLap,
    required this.laps,
    required this.segments,
    this.wheelWorkKj,
    this.peakSurfaceTempC,
    this.innerTempC,
    this.wheelWearPerLapPct,
  });

  final String compound;
  final int startLap;
  final int endLap;
  final List<int> laps;
  final List<double>? wheelWorkKj;
  final List<double>? peakSurfaceTempC;
  final List<double>? innerTempC;
  final List<double>? wheelWearPerLapPct;
  final List<RaceSegmentDriving> segments;

  String get label => '$compound $startLap–$endLap랩';

  /// 구간 번호의 평균(없으면 null).
  RaceSegmentDriving? segment(int index) {
    for (final s in segments) {
      if (s.index == index) {
        return s;
      }
    }
    return null;
  }

  static RaceStintDriving? fromJsonOrNull(Map<String, dynamic> json) {
    final compound = jsonString(json['compound']);
    final start = jsonInt(json['startLap']);
    final end = jsonInt(json['endLap']);
    if (compound == null || start == null || end == null) {
      return null;
    }
    final laps = json['laps'];
    return RaceStintDriving(
      compound: compound,
      startLap: start,
      endLap: end,
      laps: laps is List ? [for (final l in laps) ?jsonInt(l)] : const [],
      wheelWorkKj: _wheelList(json['wheelWorkKj']),
      peakSurfaceTempC: _wheelList(json['peakSurfaceTempC']),
      innerTempC: _wheelList(json['innerTempC']),
      wheelWearPerLapPct: _wheelList(json['wheelWearPerLapPct']),
      segments: jsonObjects(json['segments'], RaceSegmentDriving.fromJsonOrNull),
    );
  }
}

/// 다른 차들이 구간에서 랩마다 배터리를 채운·쓴 양의 중앙값(kJ)과 본 차 수, 스로틀을 완전히 뗀 거리(m)·구간 통과 시간(ms)의 중앙값(모르면 null).
class FieldSegmentErs {
  const FieldSegmentErs({
    required this.index,
    required this.harvestKj,
    required this.deployKj,
    required this.cars,
    this.liftM,
    this.timeMs,
  });

  final int index;
  final double harvestKj;
  final double deployKj;
  final int cars;
  final double? liftM;
  final int? timeMs;

  static FieldSegmentErs? fromJsonOrNull(Map<String, dynamic> json) {
    final index = jsonInt(json['index']);
    final harvest = jsonDouble(json['harvestKj']);
    final deploy = jsonDouble(json['deployKj']);
    return index == null || harvest == null || deploy == null
        ? null
        : FieldSegmentErs(
            index: index,
            harvestKj: harvest,
            deployKj: deploy,
            cars: jsonInt(json['cars']) ?? 0,
            liftM: jsonDouble(json['liftM']),
            timeMs: jsonInt(json['timeMs']),
          );
  }
}

/// 스톱 하나의 타이어 사정: 인 랩, 그때 게임 피트 창, 끼운 세트 마모(%)·게임이 본 남은 수명(랩), 바꾼 컴파운드, 새 세트로 랩당 빨라지는 정도(ms).
class RaceStopContext {
  const RaceStopContext({
    required this.lap,
    required this.fromCompound,
    required this.toCompound,
    this.idealLap,
    this.latestLap,
    this.wearPct,
    this.lifeLapsLeft,
    this.newSetGainMs,
  });

  final int lap;
  final int? idealLap;
  final int? latestLap;
  final double? wearPct;
  final int? lifeLapsLeft;
  final String fromCompound;
  final String toCompound;
  final int? newSetGainMs;

  static RaceStopContext? fromJsonOrNull(Map<String, dynamic> json) {
    final lap = jsonInt(json['lap']);
    final from = jsonString(json['fromCompound']);
    final to = jsonString(json['toCompound']);
    if (lap == null || from == null || to == null) {
      return null;
    }
    return RaceStopContext(
      lap: lap,
      fromCompound: from,
      toCompound: to,
      idealLap: jsonInt(json['idealLap']),
      latestLap: jsonInt(json['latestLap']),
      wearPct: jsonDouble(json['wearPct']),
      lifeLapsLeft: jsonInt(json['lifeLapsLeft']),
      newSetGainMs: jsonInt(json['newSetGainMs']),
    );
  }
}

/// 컴파운드 모델: 출발 세트 대비 새 세트 랩타임 차(ms), 랩당 느려지는 정도(ms), 게임이 본 쓸 수 있는 랩, 세트 수.
class RaceCompoundModel {
  const RaceCompoundModel({required this.compound, required this.sets, this.offsetMs, this.degMsPerLap, this.usableLaps});

  final String compound;
  final int? offsetMs;
  final int? degMsPerLap;
  final int? usableLaps;
  final int sets;

  static RaceCompoundModel? fromJsonOrNull(Map<String, dynamic> json) {
    final compound = jsonString(json['compound']);
    return compound == null
        ? null
        : RaceCompoundModel(
            compound: compound,
            offsetMs: jsonInt(json['offsetMs']),
            degMsPerLap: jsonInt(json['degMsPerLap']),
            usableLaps: jsonInt(json['usableLaps']),
            sets: jsonInt(json['sets']) ?? 0,
          );
  }
}

/// 전략 안의 스틴트 하나.
typedef RaceStrategyStint = ({String compound, int laps});

/// 전략 하나: 스틴트들, 실제 전략 대비 추정 시간(ms, −면 빠르다), 실제 전략인지.
class RaceStrategyOption {
  const RaceStrategyOption({required this.stints, required this.deltaMs, required this.isActual});

  final List<RaceStrategyStint> stints;
  final int deltaMs;
  final bool isActual;

  int get stops => math.max(0, stints.length - 1);

  /// `M11→S11→S11`.
  String get plan => stints.map((s) => '${s.compound.isEmpty ? '?' : s.compound[0]}${s.laps}').join('→');

  static RaceStrategyOption? fromJsonOrNull(Map<String, dynamic> json) {
    final stints = jsonObjects<RaceStrategyStint>(json['stints'], (j) {
      final compound = jsonString(j['compound']);
      final laps = jsonInt(j['laps']);
      return compound == null || laps == null ? null : (compound: compound, laps: laps);
    });
    return stints.isEmpty
        ? null
        : RaceStrategyOption(stints: stints, deltaMs: jsonInt(json['deltaMs']) ?? 0, isActual: json['isActual'] == true);
  }
}

/// 타이어로 본 전략: 레이스 랩 수, 출발 때 게임 피트 창, 내 스톱 손실(ms), 스톱마다 사정, 컴파운드 모델, 실제·대안 전략.
class RaceStrategyAnalysis {
  const RaceStrategyAnalysis({
    required this.totalLaps,
    required this.stops,
    required this.compounds,
    required this.options,
    this.idealLap,
    this.latestLap,
    this.pitLossMs,
  });

  final int totalLaps;
  final int? idealLap;
  final int? latestLap;
  final int? pitLossMs;
  final List<RaceStopContext> stops;
  final List<RaceCompoundModel> compounds;
  final List<RaceStrategyOption> options;

  static RaceStrategyAnalysis? fromJsonOrNull(Object? json) {
    if (json is! Map<String, dynamic>) {
      return null;
    }
    return RaceStrategyAnalysis(
      totalLaps: jsonInt(json['totalLaps']) ?? 0,
      idealLap: jsonInt(json['idealLap']),
      latestLap: jsonInt(json['latestLap']),
      pitLossMs: jsonInt(json['pitLossMs']),
      stops: jsonObjects(json['stops'], RaceStopContext.fromJsonOrNull),
      compounds: jsonObjects(json['compounds'], RaceCompoundModel.fromJsonOrNull),
      options: jsonObjects(json['options'], RaceStrategyOption.fromJsonOrNull),
    );
  }
}

/// 내 랩 하나의 페이스 기준: 랩타임, 같은 랩 AI 중앙값, 같은 타이어 AI 중앙값, 컴파운드·타이어 나이, 깨끗한 랩인지.
class RaceLapPace {
  const RaceLapPace({
    required this.lap,
    required this.lapTimeMs,
    required this.isClean,
    this.fieldSameLapMs,
    this.fieldSameTyreMs,
    this.compound,
    this.tyreAge,
  });

  final int lap;
  final int lapTimeMs;
  final int? fieldSameLapMs;
  final int? fieldSameTyreMs;
  final String? compound;
  final int? tyreAge;
  final bool isClean;

  static RaceLapPace? fromJsonOrNull(Map<String, dynamic> json) {
    final lap = jsonInt(json['lap']);
    final time = jsonInt(json['lapTimeMs']);
    if (lap == null || time == null) {
      return null;
    }
    return RaceLapPace(
      lap: lap,
      lapTimeMs: time,
      isClean: json['isClean'] == true,
      fieldSameLapMs: jsonInt(json['fieldSameLapMs']),
      fieldSameTyreMs: jsonInt(json['fieldSameTyreMs']),
      compound: jsonString(json['compound']),
      tyreAge: jsonInt(json['tyreAge']),
    );
  }
}

/// 레이스 심층 분석 응답.
class RaceAnalysis {
  const RaceAnalysis({
    required this.trackLengthM,
    required this.segments,
    required this.stints,
    required this.fieldErs,
    required this.lapPace,
    this.referenceLap,
    this.wearPctPerMj,
    this.strategy,
  });

  final int trackLengthM;
  final int? referenceLap;
  final List<RaceSegment> segments;
  final List<RaceStintDriving> stints;
  final double? wearPctPerMj;
  final List<FieldSegmentErs> fieldErs;
  final RaceStrategyAnalysis? strategy;
  final List<RaceLapPace> lapPace;

  static RaceAnalysis fromJson(Map<String, dynamic> json) => RaceAnalysis(
        trackLengthM: jsonInt(json['trackLengthM']) ?? 0,
        referenceLap: jsonInt(json['referenceLap']),
        segments: jsonObjects(json['segments'], RaceSegment.fromJsonOrNull),
        stints: jsonObjects(json['stints'], RaceStintDriving.fromJsonOrNull),
        wearPctPerMj: jsonDouble(json['wearPctPerMj']),
        fieldErs: jsonObjects(json['fieldErs'], FieldSegmentErs.fromJsonOrNull),
        strategy: RaceStrategyAnalysis.fromJsonOrNull(json['strategy']),
        lapPace: jsonObjects(json['lapPace'], RaceLapPace.fromJsonOrNull),
      );

  /// 바퀴 일이 있는(트레이스로 분석한) 스틴트.
  List<RaceStintDriving> get drivenStints => [for (final s in stints) if (s.wheelWorkKj != null) s];

  /// 구간 번호의 AI 배터리(없으면 null).
  FieldSegmentErs? fieldErsAt(int index) {
    for (final f in fieldErs) {
      if (f.index == index) {
        return f;
      }
    }
    return null;
  }
}

/// 구간 이름(구간 번호 순서). 코너는 그 안의 공식 코너(`T1–T3`·`T10`), 직선은 결승선을 넘으면 `메인 직선`, 아니면 앞뒤 코너 사이
/// (`T9→T10 직선`). 공식 코너는 한 구간에만 든다 — 그 지점을 덮는 코너 구간, 없으면 앞뒤 [_cornerMarginM]m 안의 가장 가까운 코너 구간.
/// 공식 코너를 모르거나 구간에 없으면 순서 번호(`코너 3`·`직선 2`).
List<String> segmentLabels(RaceAnalysis analysis, List<OfficialCorner>? corners) {
  final segments = analysis.segments;
  final cornerSegments = [for (final s in segments) if (s.isCorner) s];
  final length = analysis.trackLengthM.toDouble();
  final assigned = <int, List<OfficialCorner>>{};
  if (corners != null && length > 0) {
    for (final c in corners) {
      final distance = c.fraction * length;
      final home = cornerSegments.where((s) => s.covers(distance)).firstOrNull ??
          cornerSegments.where((s) => s.covers(distance, margin: _cornerMarginM)).firstOrNull;
      if (home != null) {
        assigned.putIfAbsent(home.index, () => []).add(c);
      }
    }
  }
  final official = {
    for (final MapEntry(:key, :value) in assigned.entries)
      key: (first: 'T${value.first.number}${value.first.letter}', last: 'T${value.last.number}${value.last.letter}'),
  };

  var cornerNumber = 0;
  var straightNumber = 0;
  final cornerIndexes = [for (final s in cornerSegments) s.index];
  return [
    for (final s in segments)
      if (s.isCorner)
        switch (official[s.index]) {
          (first: final first, last: final last) => first == last ? first : '$first–$last',
          null => '코너 ${++cornerNumber}',
        }
      else if (s.wraps)
        '메인 직선'
      else
        _straightLabel(s.index, cornerIndexes, official) ?? '직선 ${++straightNumber}',
  ];
}

/// 앞 코너의 마지막 공식 코너 → 뒤 코너의 첫 공식 코너 사이 직선(`T9→T10 직선`). 둘 중 하나라도 모르면 null.
String? _straightLabel(int index, List<int> cornerIndexes, Map<int, ({String first, String last})> official) {
  if (cornerIndexes.isEmpty) {
    return null;
  }
  final before = cornerIndexes.lastWhere((c) => c < index, orElse: () => cornerIndexes.last);
  final after = cornerIndexes.firstWhere((c) => c > index, orElse: () => cornerIndexes.first);
  final a = official[before]?.last;
  final b = official[after]?.first;
  return a == null || b == null ? null : '$a→$b 직선';
}

String _kj(double kj) => '${kj.round()}kJ';
String _f1(double value) => value.toStringAsFixed(1);
String _sec(int ms) => '${(ms.abs() / _msPerSecond).toStringAsFixed(3)}초';
String _sec1(int ms) => '${(ms.abs() / _msPerSecond).toStringAsFixed(1)}초';
String _signed(int ms) => '${ms >= 0 ? '+' : '−'}${_sec(ms)}';
String _pct(double fraction) => '${(fraction * _percent).round()}%';

int? _medianOf(List<int> values) {
  if (values.isEmpty) {
    return null;
  }
  final sorted = [...values]..sort();
  final middle = sorted.length ~/ 2;
  return sorted.length.isOdd ? sorted[middle] : ((sorted[middle - 1] + sorted[middle]) / 2).round();
}

/// 가장 큰 값의 번호([except]는 건너뛴다).
int _maxIndex(List<double> values, {int? except}) {
  var best = -1;
  for (var i = 0; i < values.length; i++) {
    if (i != except && (best < 0 || values[i] > values[best])) {
      best = i;
    }
  }
  return math.max(best, 0);
}

/// 스틴트들의 값을 분석한 랩 수로 가중 평균(값이 없는 스틴트는 뺀다, 하나도 없으면 null).
double? _weighted(List<RaceStintDriving> stints, double? Function(RaceStintDriving s) of) {
  var sum = 0.0;
  var weight = 0;
  for (final s in stints) {
    final value = of(s);
    if (value != null && s.laps.isNotEmpty) {
      sum += value * s.laps.length;
      weight += s.laps.length;
    }
  }
  return weight == 0 ? null : sum / weight;
}

/// 바퀴 네 개 값의 가중 평균.
List<double>? _weightedWheels(List<RaceStintDriving> stints, List<double>? Function(RaceStintDriving s) of) {
  final known = [for (final s in stints) if (of(s) != null) s];
  if (known.isEmpty) {
    return null;
  }
  return [for (var w = 0; w < kWheelNames.length; w++) _weighted(known, (s) => of(s)![w])!];
}

/// 구간 하나의 레이스 평균(스틴트 가중).
double? segmentAverage(List<RaceStintDriving> stints, int index, double? Function(RaceSegmentDriving d) of) =>
    _weighted(stints, (s) {
      final segment = s.segment(index);
      return segment == null ? null : of(segment);
    });

/// 리미터 바퀴 번호: 랩당 마모가 가장 큰 바퀴(마모를 모르면 마찰 일). 분석한 스틴트가 없으면 null.
int? tyreLimiterWheel(RaceAnalysis analysis) {
  final driven = analysis.drivenStints;
  final values = _weightedWheels(driven, (s) => s.wheelWearPerLapPct) ?? _weightedWheels(driven, (s) => s.wheelWorkKj);
  return values == null ? null : _maxIndex(values);
}

/// 코너 입력 하나: 관찰과 할 것.
typedef CornerCause = ({String fact, String advice});

/// 코너에서 타이어에 부담을 준 입력(문턱을 넘은 것만). 앞바퀴가 리미터면 언더스티어·브레이크·조향부터, 뒷바퀴면 휠스핀부터.
List<CornerCause> cornerCauses(RaceSegmentDriving d, {required bool front}) {
  final understeer = d.understeerDeg;
  final lockup = d.lockupM;
  final wheelspin = d.wheelspinM;
  final kerb = d.kerbM;
  final understeerCause = understeer != null && understeer >= kUndersteerDeg
      ? (fact: '앞이 뒤보다 ${_f1(understeer)}° 더 미끄러져(조향 ${d.steerPct.round()}%)', advice: '진입 속도를 조금 낮추고 감은 채로 버티지 마 — 앞이 물릴 때 돌려')
      : null;
  final trailCause = d.trailBrakeM >= kTrailBrakeM
      ? (fact: '브레이크 밟은 채 꺾은 거리 ${d.trailBrakeM.round()}m', advice: '브레이크를 조금 일찍 끝내고 꺾어')
      : null;
  final throttleCause = d.throttleSteerM >= kThrottleSteerM
      ? (fact: '풀 스로틀로 꺾은 거리 ${d.throttleSteerM.round()}m', advice: '탈출에서 핸들을 먼저 풀고 그다음 풀 스로틀')
      : null;
  final lockupCause = lockup != null && lockup >= kLockupM
      ? (fact: '앞 락업 ${lockup.round()}m', advice: '첫 브레이크 압력을 조금 줄여서 락업 없이 세워')
      : null;
  final spinCause = wheelspin != null && wheelspin >= kWheelspinM
      ? (fact: '탈출 휠스핀 ${wheelspin.round()}m', advice: '탈출 스로틀을 두 번에 나눠 열어')
      : null;
  final kerbCause = kerb != null && kerb >= kKerbM ? (fact: '연석 ${kerb.round()}m', advice: '연석은 덜 타') : null;
  final ordered = front
      ? [understeerCause, trailCause, throttleCause, lockupCause, kerbCause, spinCause]
      : [spinCause, throttleCause, trailCause, kerbCause, understeerCause, lockupCause];
  return [for (final c in ordered) ?c];
}

/// 레이스 평균으로 묶은 구간 측정(스틴트 가중) — 코너 입력 판정용. 그 구간을 가진 스틴트가 없으면 null.
RaceSegmentDriving? averagedSegment(List<RaceStintDriving> stints, int index) {
  final present = [for (final s in stints) if (s.segment(index) != null) s];
  if (present.isEmpty) {
    return null;
  }
  double? avg(double? Function(RaceSegmentDriving d) of) => segmentAverage(present, index, of);
  return RaceSegmentDriving(
    index: index,
    timeMs: (avg((d) => d.timeMs.toDouble()) ?? 0).round(),
    steerPct: avg((d) => d.steerPct) ?? 0,
    trailBrakeM: avg((d) => d.trailBrakeM) ?? 0,
    throttleSteerM: avg((d) => d.throttleSteerM) ?? 0,
    brakeM: avg((d) => d.brakeM) ?? 0,
    minSpeedKph: (avg((d) => d.minSpeedKph.toDouble()) ?? 0).round(),
    endSpeedKph: (avg((d) => d.endSpeedKph.toDouble()) ?? 0).round(),
    wheelWorkKj: _weightedWheels(present, (s) => s.segment(index)!.wheelWorkKj),
    understeerDeg: avg((d) => d.understeerDeg),
    lockupM: avg((d) => d.lockupM),
    wheelspinM: avg((d) => d.wheelspinM),
    kerbM: avg((d) => d.kerbM),
    peakSurfaceTempC: _weightedWheels(present, (s) => s.segment(index)!.peakSurfaceTempC),
    harvestKj: avg((d) => d.harvestKj),
    deployKj: avg((d) => d.deployKj),
    overtakeM: avg((d) => d.overtakeM),
    noDeployM: avg((d) => d.noDeployM),
    storeEndKj: avg((d) => d.storeEndKj),
    emptyM: avg((d) => d.emptyM),
    liftM: avg((d) => d.liftM) ?? 0,
    fastOvertakeM: avg((d) => d.fastOvertakeM),
  );
}

/// 리미터 바퀴 일이 큰 순서의 코너(레이스 평균).
List<RaceSegment> loadRankedCorners(RaceAnalysis analysis, int limiter) {
  final driven = analysis.drivenStints;
  final loads = <({RaceSegment segment, double load})>[
    for (final s in analysis.segments)
      if (s.isCorner)
        if (segmentAverage(driven, s.index, (d) => d.wheelWorkKj?[limiter]) case final load?) (segment: s, load: load),
  ]..sort((a, b) => b.load.compareTo(a.load));
  return [for (final l in loads) l.segment];
}

/// 타이어 심층 줄: 리미터 바퀴, 그 바퀴에 부담이 큰 코너(마모 환산·입력 원인 → 할 것), 표면 온도, 스틴트마다 AI 대비 추세와 시간이 늘어난 코너·끝 수명,
/// 같은 컴파운드 스틴트끼리 무엇이 달랐는지, 세팅 제안. 트레이스로 분석한 스틴트가 없으면 빈 목록.
List<String> deepTyreLines(
  List<RaceStintReview> reviewStints,
  RaceAnalysis analysis,
  List<String> labels,
  Map<String, Object?>? setup,
) {
  final driven = analysis.drivenStints;
  final limiter = tyreLimiterWheel(analysis);
  if (driven.isEmpty || limiter == null || labels.length != analysis.segments.length) {
    return const [];
  }
  final work = _weightedWheels(driven, (s) => s.wheelWorkKj)!;
  final wear = _weightedWheels(driven, (s) => s.wheelWearPerLapPct);
  final name = kWheelNames[limiter];
  final front = limiter < _frontWheels;
  final perMj = analysis.wearPctPerMj;
  final lines = <String>[];

  final next = _maxIndex(wear ?? work, except: limiter);
  lines.add(wear != null
      ? '리미터는 $name — 랩당 마모 ${_f1(wear[limiter])}%p(다음 ${kWheelNames[next]} ${_f1(wear[next])}%p), 마찰 일 ${_kj(work[limiter])}'
      : '리미터는 $name — 랩당 마찰 일 ${_kj(work[limiter])}(다음 ${kWheelNames[next]} ${_kj(work[next])})');

  final top = loadRankedCorners(analysis, limiter).take(kTopLoadCorners).toList();
  for (final corner in top) {
    final averaged = averagedSegment(driven, corner.index);
    final load = averaged?.wheelWorkKj?[limiter];
    if (averaged == null || load == null) {
      continue;
    }
    final wearShare = perMj == null ? '' : ', 마모 ≈${_f1(load / _kjPerMj * perMj)}%p';
    final head = '${labels[corner.index]}: $name ${_kj(load)}(랩의 ${_pct(load / work[limiter])}$wearShare)';
    final causes = cornerCauses(averaged, front: front);
    lines.add(causes.isEmpty ? head : '$head — ${causes.map((c) => c.fact).join(', ')} → ${causes.first.advice}');
  }

  final peak = _weightedWheels(driven, (s) => s.peakSurfaceTempC);
  if (peak != null) {
    final others = [for (var w = 0; w < peak.length; w++) if (w != limiter) peak[w]].reduce(math.max);
    if (peak[limiter] - others >= _tempGapC) {
      lines.add('$name 표면 온도가 랩마다 ${peak[limiter].round()}°C까지 올라 — 다른 바퀴는 최고 ${others.round()}°C');
    }
  }

  for (final (k, stint) in reviewStints.indexed) {
    final label = '${stint.compound} ${stint.startLap}–${stint.endLap}랩';
    final extra = stint.extraTrendMs;
    RaceStintDriving? drivenStint;
    for (final s in driven) {
      if (s.startLap == stint.startLap) {
        drivenStint = s;
      }
    }
    if (extra != null && extra >= kTrendMarginMs) {
      final lost = drivenStint == null
          ? <RaceSegmentDriving>[]
          : ([for (final d in drivenStint.segments) if ((d.timeTrendMsPerLap ?? 0) >= _gripLossMs) d]
              ..sort((a, b) => b.timeTrendMsPerLap!.compareTo(a.timeTrendMsPerLap!)));
      final where = lost.take(_gripLossCorners).map((d) => '${labels[d.index]}(+${_sec(d.timeTrendMsPerLap!)}/랩)').join('·');
      lines.add('$label: AI보다 랩당 ${_sec(extra)}씩 더 떨어졌어${where.isEmpty ? '' : ' — 시간이 늘어난 곳은 $where'}');
    } else if (extra != null && extra <= -kTrendMarginMs) {
      lines.add('$label: AI보다 랩당 ${_sec(extra)}씩 덜 떨어졌어 — 타이어 관리 좋았어');
    }
    if (tyreLifeLine(stint, last: k == reviewStints.length - 1) case final life?) {
      lines.add(life);
    }
  }

  lines.addAll(_sameCompoundLines(analysis, labels, limiter, perMj));
  lines.addAll(_setupLines(setup, analysis, top.map((c) => c.index).toList(), limiter, labels));
  return lines;
}

/// 같은 컴파운드 스틴트끼리: 리미터 바퀴 일이 가장 적은 스틴트보다 많았던 스틴트마다 차이가 큰 코너와 달랐던 입력.
List<String> _sameCompoundLines(RaceAnalysis analysis, List<String> labels, int limiter, double? perMj) {
  final groups = <String, List<RaceStintDriving>>{};
  for (final s in analysis.drivenStints) {
    groups.putIfAbsent(s.compound, () => []).add(s);
  }
  final name = kWheelNames[limiter];
  final lines = <String>[];
  for (final group in groups.values.where((g) => g.length >= 2)) {
    final best = group.reduce((a, b) => a.wheelWorkKj![limiter] <= b.wheelWorkKj![limiter] ? a : b);
    for (final stint in group.where((s) => !identical(s, best))) {
      final diff = stint.wheelWorkKj![limiter] - best.wheelWorkKj![limiter];
      if (diff < _compareWorkKj) {
        continue;
      }
      final corners = <({int index, double delta})>[
        for (final s in analysis.segments)
          if (s.isCorner)
            (index: s.index, delta: (stint.segment(s.index)?.wheelWorkKj?[limiter] ?? 0) - (best.segment(s.index)?.wheelWorkKj?[limiter] ?? 0)),
      ]..sort((a, b) => b.delta.compareTo(a.delta));
      final reasons = [
        for (final c in corners.take(_gripLossCorners))
          if (c.delta > 0)
            if (_difference(stint.segment(c.index), best.segment(c.index)) case final what?) '${labels[c.index]}($what)',
      ];
      final wearText = perMj == null ? '' : '(마모 ≈+${_f1(diff / _kjPerMj * perMj)}%p)';
      final bestRange = '${best.startLap}–${best.endLap}랩';
      lines.add('${stint.label}은 $bestRange보다 $name 일이 랩당 ${_kj(diff)} 많았어$wearText'
          '${reasons.isEmpty ? '' : ' — 차이는 ${reasons.join('·')}'} → $bestRange처럼 타면 돼');
    }
  }
  return lines;
}

/// 두 스틴트의 같은 구간에서 [worse]가 가장 크게 다른 입력(`언더스티어 2.9° vs 2.4°`). 말할 만한 차이가 없으면 null.
String? _difference(RaceSegmentDriving? worse, RaceSegmentDriving? better) {
  if (worse == null || better == null) {
    return null;
  }
  final candidates = <({double score, String text})>[];
  void add(double? a, double? b, double threshold, String Function(double a, double b) text) {
    if (a != null && b != null && a - b >= threshold) {
      candidates.add((score: (a - b) / threshold, text: text(a, b)));
    }
  }

  add(worse.understeerDeg, better.understeerDeg, _understeerDiffDeg, (a, b) => '언더스티어 ${_f1(a)}° vs ${_f1(b)}°');
  add(worse.steerPct, better.steerPct, _steerDiffPct, (a, b) => '조향 ${a.round()}% vs ${b.round()}%');
  add(worse.throttleSteerM, better.throttleSteerM, _distanceDiffM, (a, b) => '풀 스로틀 조향 ${a.round()}m vs ${b.round()}m');
  add(worse.trailBrakeM, better.trailBrakeM, _distanceDiffM, (a, b) => '브레이크 밟은 채 조향 ${a.round()}m vs ${b.round()}m');
  add(worse.kerbM, better.kerbM, _kerbDiffM, (a, b) => '연석 ${a.round()}m vs ${b.round()}m');
  add(worse.lockupM, better.lockupM, _slipDiffM, (a, b) => '락업 ${a.round()}m vs ${b.round()}m');
  add(worse.wheelspinM, better.wheelspinM, _slipDiffM, (a, b) => '휠스핀 ${a.round()}m vs ${b.round()}m');
  if (candidates.isEmpty) {
    return null;
  }
  candidates.sort((a, b) => b.score.compareTo(a.score));
  return candidates.first.text;
}

/// 세팅 제안(측정한 증상이 있을 때만): 앞이 계속 밀리면 앞 날개·안티롤바, 앞 락업이 많으면 브레이크 바이어스, 앞 타이어가 리미터인데 캠버를 많이 눕혔으면 캠버.
List<String> _setupLines(Map<String, Object?>? setup, RaceAnalysis analysis, List<int> topCorners, int limiter, List<String> labels) {
  if (setup == null) {
    return const [];
  }
  final driven = analysis.drivenStints;
  final front = limiter < _frontWheels;
  final lines = <String>[];

  final understeer = [for (final i in topCorners) ?segmentAverage(driven, i, (d) => d.understeerDeg)];
  final frontWing = jsonDouble(setup['frontWing']);
  final frontBar = jsonDouble(setup['frontAntiRollBar']);
  if (front && understeer.isNotEmpty && frontWing != null) {
    final mean = understeer.reduce((a, b) => a + b) / understeer.length;
    if (mean >= _setupUndersteerDeg) {
      lines.add('세팅: 부담이 큰 코너에서 앞이 평균 ${_f1(mean)}° 더 미끄러져 → 앞 날개 +1~2 또는 앞 안티롤바를 낮춰 앞 그립을 올려 봐'
          '(지금 앞 날개 ${frontWing.round()}${frontBar == null ? '' : ', 앞 안티롤바 ${frontBar.round()}'})');
    }
  }

  final lockups = <({int index, double m})>[
    for (final s in analysis.segments)
      if (s.isCorner)
        if (segmentAverage(driven, s.index, (d) => d.lockupM) case final m? when m > 0) (index: s.index, m: m),
  ]..sort((a, b) => b.m.compareTo(a.m));
  final lockupTotal = lockups.fold(0.0, (sum, l) => sum + l.m);
  final bias = jsonDouble(setup['brakeBias']);
  if (lockupTotal >= _setupLockupM && bias != null) {
    final where = lockups.take(_gripLossCorners).map((l) => labels[l.index]).join('·');
    lines.add('세팅: 앞 락업이 랩당 ${lockupTotal.round()}m($where) → 브레이크 바이어스를 1~2% 뒤로(지금 ${bias.round()}%)');
  }

  final camber = jsonDouble(setup['frontCamber']);
  if (front && camber != null && camber <= _hotCamberDeg) {
    lines.add('세팅: 앞 캠버 ${camber.toStringAsFixed(2)}°는 코너 그립엔 좋지만 앞 타이어를 더 달궈 → 레이스에선 0.1~0.2° 세워 봐');
  }
  return lines;
}

/// 배터리가 순으로 남거나 줄어든 양(kJ, 채움 − 씀).
double _net(double harvest, double deploy) => harvest - deploy;

/// 배터리 심층 줄: 랩당 사용·채움을 AI와, 스틴트마다 바닥난 구간과 줄일 곳(280km/h 넘는 Overtake를 짧은 직선부터 — 코너 탈출은 지킨다)
/// 또는 여유가 있는데 AI보다 덜 쓴 직선(→ 더 써), 완전히 떼는 거리가 짧아 AI보다 덜 채우는 코너(→ 완전히 떼고 브레이크를 짧게), AI보다 배터리를 가장 많이 잃고 나온
/// 코너(Overtake·브레이킹 여부에 맞춘 할 것), 체커 때 남긴 양. 구간 배터리 값이 없으면 빈 목록.
List<String> deepBatteryLines(RaceBatteryReview? battery, RaceAnalysis analysis, List<String> labels) {
  final driven = [for (final s in analysis.stints) if (s.segments.any((d) => d.deployKj != null)) s];
  if (driven.isEmpty || labels.length != analysis.segments.length) {
    return const [];
  }
  double? avg(int index, double? Function(RaceSegmentDriving d) of) => segmentAverage(driven, index, of);
  double total(double? Function(RaceSegmentDriving d) of) =>
      analysis.segments.fold(0.0, (sum, s) => sum + (avg(s.index, of) ?? 0));

  final lines = <String>[];
  final hasField = analysis.fieldErs.isNotEmpty;
  if (hasField) {
    final aiDeploy = analysis.fieldErs.fold(0.0, (sum, f) => sum + f.deployKj);
    final aiHarvest = analysis.fieldErs.fold(0.0, (sum, f) => sum + f.harvestKj);
    lines.add('랩당 배터리 사용 ${_kj(total((d) => d.deployKj))} · 채움 ${_kj(total((d) => d.harvestKj))} — AI는 사용 ${_kj(aiDeploy)} · 채움 ${_kj(aiHarvest)}');
  }

  for (final stint in driven) {
    final overs = <({RaceSegmentDriving d, double more})>[
      for (final d in stint.segments)
        if ((d.deployKj, analysis.fieldErsAt(d.index)) case (final mine?, final ai?)) (d: d, more: mine - ai.deployKj),
    ]..sort((a, b) => b.more.compareTo(a.more));
    final empties = [for (final d in stint.segments) if (_ranFlat(d)) d]..sort((a, b) => b.emptyM!.compareTo(a.emptyM!));
    if (empties.isNotEmpty) {
      final empty = empties.first;
      final where = labels[empty.index];
      final over = overs.where((o) => o.d.index != empty.index && o.more >= _ersGapKj).firstOrNull;
      final overtake = over?.d.overtakeM ?? 0;
      final entry = _entryStore(stint, empty.index, analysis.segments.length);
      final others = [
        for (final o in driven)
          if (!identical(o, stint) && !o.segments.any(_ranFlat)) ?_entryStore(o, empty.index, analysis.segments.length),
      ];
      final emptyLaps = empty.emptyLaps;
      final head = emptyLaps == null
          ? '${stint.label}: $where에서 랩당 ${empty.emptyM!.round()}m는 배터리가 바닥이었어'
          : '${stint.label}: ${stint.laps.length}랩 중 $emptyLaps랩은 $where에서 배터리가 바닥났어';
      final entryText = entry == null
          ? ''
          : '(들어갈 때 잔량 ${_kj(entry)}${others.isEmpty ? '' : ', 바닥 안 난 스틴트 ${_kjRange(others)}'})';
      // 줄일 곳: 280km/h 넘는 Overtake(같은 배터리로 버는 시간이 가장 적다)를 짧은 직선부터. 코너 탈출 Overtake는 지킨다.
      final fast = [
        for (final d in stint.segments)
          if (_segmentOf(analysis, d.index) case final s? when !s.isCorner && (d.fastOvertakeM ?? 0) >= _fastOvertakeM)
            (d: d, length: _lengthOf(s, analysis.trackLengthM)),
      ]..sort((a, b) => a.length.compareTo(b.length));
      final advice = fast.isNotEmpty
          ? '280km/h 넘는 Overtake부터 줄여 — ${fast.map((f) => '${labels[f.d.index]}(${f.d.fastOvertakeM!.round()}m)').join(' → ')} 순서로'
              '(짧은 직선일수록 같은 배터리로 버는 시간이 적어), 코너 탈출 Overtake는 그대로 둬'
          : over == null
              ? '앞 구간에서 Overtake를 줄여 잔량을 채운 채로 들어가'
              : '${labels[over.d.index]}에선 Medium으로 두고 $where까지 남겨';
      lines.add('$head$entryText'
          '${over == null ? '' : ' — ${labels[over.d.index]}에서 AI보다 ${_kj(over.more)} 더 썼어${overtake > 0 ? '(Overtake ${overtake.round()}m)' : ''}'}'
          ' → $advice');
      continue;
    }
    // 바닥나지 않았으면: AI보다 덜 쓴 직선이 있을 때 그 직선에서 더 쓰라고 한다(배터리가 남으면 직선 끝까지 써도 된다).
    final under = overs.reversed
        .where((o) => _segmentOf(analysis, o.d.index)?.isCorner == false && -o.more >= _ersGapKj)
        .firstOrNull;
    if (under != null) {
      lines.add('${stint.label}: ${labels[under.d.index]}에서 AI보다 랩당 ${_kj(-under.more)} 덜 썼어(바닥난 곳 없음) → 거기선 Overtake로 더 써');
    }
  }

  final halfLifted = <int>{};
  if (hasField) {
    // 덜 떼는 코너: 진입에서 스로틀을 완전히 떼는 거리가 짧아 회수가 적은데, AI는 더 오래 완전히 떼고(브레이크를 짧게 찍고) 훨씬 많이 채운다.
    final partial = <({int index, double gap, String line})>[];
    for (final s in analysis.segments.where((s) => s.isCorner)) {
      final ai = analysis.fieldErsAt(s.index);
      final mine = averagedSegment(driven, s.index);
      final aiLift = ai?.liftM;
      final harvest = mine?.harvestKj;
      if (ai == null || mine == null || aiLift == null || harvest == null) {
        continue;
      }
      final gap = ai.harvestKj - harvest;
      if (gap < _ersGapKj || aiLift - mine.liftM < _liftGapM) {
        continue;
      }
      final aiTime = ai.timeMs;
      final slower = aiTime == null ? 0 : aiTime - mine.timeMs;
      // 더 채우는 대가로 내주는 시간이 비싸면(1MJ당 [_maxLiftCostSPerMj]초 초과) 권하지 않는다 — 코너 탈출에서 1MJ로 버는 시간보다 손해일 수 있다.
      if (slower > 0 && slower / _msPerSecond / (gap / _kjPerMj) > _maxLiftCostSPerMj) {
        continue;
      }
      final time = aiTime == null
          ? ''
          : '(이 구간 AI ${_sec(aiTime)} · 너 ${_sec(mine.timeMs)}'
              '${slower > 0 ? ' — ${_sec(slower)} 내주고 ${_kj(gap)} 더 채우는 셈' : ' — 시간도 안 잃어'})';
      partial.add((
        index: s.index,
        gap: gap,
        line: '${labels[s.index]}: 진입에서 완전히 뗀 거리가 ${mine.liftM.round()}m라 랩당 ${_kj(harvest)}만 채워'
            ' — AI는 ${aiLift.round()}m 완전히 떼고 ${_kj(ai.harvestKj)} 채워$time → 반만 떼고 버티지 말고 완전히 떼고 브레이크를 짧게 찍어',
      ));
    }
    partial.sort((a, b) => b.gap.compareTo(a.gap));
    for (final p in partial.take(_partialLiftCorners)) {
      lines.add(p.line);
      halfLifted.add(p.index);
    }

    ({int index, double myNet, double aiNet, double overtake, double brake})? worst;
    for (final s in analysis.segments.where((s) => s.isCorner && !halfLifted.contains(s.index))) {
      final harvest = avg(s.index, (d) => d.harvestKj);
      final deploy = avg(s.index, (d) => d.deployKj);
      final ai = analysis.fieldErsAt(s.index);
      if (harvest == null || deploy == null || ai == null) {
        continue;
      }
      final myNet = _net(harvest, deploy);
      final aiNet = _net(ai.harvestKj, ai.deployKj);
      if (aiNet - myNet >= _ersGapKj && (worst == null || aiNet - myNet > worst.aiNet - worst.myNet)) {
        worst = (
          index: s.index,
          myNet: myNet,
          aiNet: aiNet,
          overtake: avg(s.index, (d) => d.overtakeM) ?? 0,
          brake: avg(s.index, (d) => d.brakeM) ?? 0,
        );
      }
    }
    if (worst != null) {
      final advice = worst.overtake > 0
          ? 'Overtake(${worst.overtake.round()}m)를 끄고 Medium으로 지나가'
          : worst.brake >= _emptyM
              ? '브레이킹 구간을 길게 가져가서 더 채워'
              : '이 코너는 Medium으로 두고 아껴';
      lines.add('${labels[worst.index]}: 이 구간에서 배터리가 넌 랩당 ${_signedKj(worst.myNet)}, AI는 ${_signedKj(worst.aiNet)} → $advice');
    }
  }

  if (battery != null) {
    if (batteryLeftoverLine(battery) case final leftover?) {
      lines.add(leftover);
    }
  }
  return lines;
}

String _signedKj(double kj) => '${kj >= 0 ? '+' : '−'}${_kj(kj.abs())}';

/// 구간 번호의 구간(없으면 null).
RaceSegment? _segmentOf(RaceAnalysis analysis, int index) {
  for (final s in analysis.segments) {
    if (s.index == index) {
      return s;
    }
  }
  return null;
}

/// 구간 길이(m, 결승선을 넘는 직선은 두 덩어리 합).
int _lengthOf(RaceSegment segment, int trackLengthM) =>
    segment.wraps ? trackLengthM - segment.startM + segment.endM : segment.endM - segment.startM;

String _kjRange(List<double> values) {
  final low = values.reduce(math.min).round();
  final high = values.reduce(math.max).round();
  return low == high ? '${low}kJ' : '$low~${high}kJ';
}

/// 스틴트에서 그 구간 배터리가 되풀이해 바닥났는지(랩 수를 모르면 평균 거리로만).
bool _ranFlat(RaceSegmentDriving d) => (d.emptyM ?? 0) >= _emptyM && (d.emptyLaps ?? _emptyLapsMin) >= _emptyLapsMin;

/// 구간에 들어설 때 잔량(kJ) = 랩 순서로 바로 앞 구간 끝 잔량(첫 구간은 마지막 구간). 모르면 null.
double? _entryStore(RaceStintDriving stint, int index, int segmentCount) =>
    stint.segment(index == 0 ? segmentCount - 1 : index - 1)?.storeEndKj;

/// 전략 심층 줄: 출발 때 게임 피트 창과 실제 스톱, 스톱마다 타이어 사정(마모·남은 수명·새 세트 이득·되찾는 랩)과 타이어 때문인지,
/// 게임 기준 쓸 수 있는 랩보다 짧게 탄 컴파운드, 추정 대안 전략. 분석이 없으면 빈 목록.
List<String> deepStrategyLines(RaceAnalysis analysis, List<RaceStintReview> reviewStints) {
  final strategy = analysis.strategy;
  if (strategy == null) {
    return const [];
  }
  final lines = <String>[];
  final loss = strategy.pitLossMs;
  final ideal = strategy.idealLap;
  final latest = strategy.latestLap;
  if (ideal != null && strategy.stops.isNotEmpty) {
    final onIdeal = strategy.stops.every((s) => s.idealLap == s.lap);
    lines.add('출발 때 게임 피트 창은 $ideal${latest == null ? '' : '~$latest'}랩 — ${strategy.stops.length}스톱으로 '
        '${strategy.stops.map((s) => s.lap).join('·')}랩에 들어왔어${onIdeal ? ', 모두 그때 창의 이상 랩이야' : ''}');
  }

  for (final stop in strategy.stops) {
    final wear = stop.wearPct;
    final life = stop.lifeLapsLeft;
    final gain = stop.newSetGainMs;
    final payback = gain != null && gain > 0 && loss != null ? (loss / gain).ceil() : null;
    final remaining = strategy.totalLaps - stop.lap;
    final paybackText = payback == null
        ? ''
        : payback <= remaining
            ? ' 스톱 손실 ${_sec1(loss!)}를 $payback랩이면 되찾아'
            : ' 스톱 손실 ${_sec1(loss!)}를 되찾는 데 $payback랩인데 남은 건 $remaining랩이야';
    final facts = [
      if (wear != null) '마모 ${wear.round()}%',
      if (life != null) '게임은 $life랩 더 간다고 봤어${stop.latestLap == null ? '' : '(창 끝 ${stop.latestLap}랩)'}',
      if (gain != null && gain > 0) '새 ${stop.toCompound} 세트가 랩당 ${_sec(gain)} 빨라$paybackText',
    ];
    final forced = (life != null && life <= _forcedLifeLaps) || (wear != null && wear >= _forcedWearPct);
    lines.add('${stop.lap}랩 ${stop.fromCompound}→${stop.toCompound}: ${facts.join('. ')}'
        ' → ${forced ? '타이어가 한계라 들어올 수밖에 없었어' : '타이어 한계가 아니라 계획대로 들어온 거야'}');
  }

  // 마지막 스틴트는 체커까지라 뺀다.
  final early = reviewStints.isEmpty ? <RaceStintReview>[] : reviewStints.sublist(0, reviewStints.length - 1);
  final spare = [
    for (final compound in strategy.compounds)
      if (compound.usableLaps case final usable?)
        if ([for (final s in early) if (s.compound == compound.compound) s.endLap - s.startLap + 1] case final used when used.isNotEmpty)
          if (usable - used.reduce(math.max) >= _spareLaps) '${compound.compound} ${used.reduce(math.max)}/$usable랩',
  ];
  if (spare.isNotEmpty) {
    lines.add('게임 기준 쓸 수 있는 랩보다 짧게 탔어(탄 랩/쓸 수 있는 랩): ${spare.join(' · ')} — 스틴트를 늘리면 스톱을 줄일 수 있어');
  }

  RaceStrategyOption? actual;
  for (final o in strategy.options) {
    if (o.isActual) {
      actual = o;
    }
  }
  final alternatives = [for (final o in strategy.options) if (!o.isActual) o]..sort((a, b) => a.deltaMs.compareTo(b.deltaMs));
  if (actual != null && alternatives.isNotEmpty) {
    final best = alternatives.first;
    if (best.deltaMs <= -kStrategyGainMs) {
      var line = '추정(게임 타이어 델타·내 마모 기준): ${best.plan}(${best.stops}스톱)이면 ${_sec1(best.deltaMs)} 빨랐어';
      final fewer = actual.stops - best.stops;
      if (fewer > 0 && loss != null && loss * fewer + best.deltaMs > 0) {
        line += ' — 스톱을 $fewer번 덜 해서 ${_sec1(loss * fewer)}를 아끼고, 새 타이어로 되찾던 건 ${_sec1(loss * fewer + best.deltaMs)}뿐이야';
      }
      lines.add(line);
      for (final same in alternatives) {
        if (same.stops == actual.stops && !identical(same, best) && same.deltaMs <= -kStrategyGainMs) {
          lines.add('${actual.stops}스톱으로 갈 거면 ${same.plan}로 나눠야 ${_sec1(same.deltaMs)} 빨랐어');
        }
      }
    } else {
      lines.add('추정으로도 지금 전략이 가장 빨랐어 — 다른 스톱 수와 ${_sec1(kStrategyGainMs)} 안이야');
    }
  }
  return lines;
}

/// 페이스 심층 줄: 기준 읽는 법, 스틴트마다 같은 타이어·같은 랩·스틴트 중앙값 기준 AI 대비(랩당), 같은 타이어로 가장 느렸던 스틴트.
/// 기준 값이 하나도 없으면 빈 목록.
List<String> deepPaceLines(RaceAnalysis analysis, List<RaceStintReview> reviewStints) {
  final lines = <String>[];
  ({String label, int gap})? worst;
  for (final stint in reviewStints) {
    final laps = [for (final p in analysis.lapPace) if (p.isClean && p.lap >= stint.startLap && p.lap <= stint.endLap) p];
    final sameTyre = _medianOf([for (final p in laps) if (p.fieldSameTyreMs != null) p.lapTimeMs - p.fieldSameTyreMs!]);
    final sameLap = _medianOf([for (final p in laps) if (p.fieldSameLapMs != null) p.lapTimeMs - p.fieldSameLapMs!]);
    final median = stint.medianMs;
    final fieldMedian = stint.fieldMedianMs;
    final stintGap = median != null && fieldMedian != null ? median - fieldMedian : null;
    final parts = [
      if (sameTyre != null) '같은 타이어 ${_signed(sameTyre)}',
      if (sameLap != null) '같은 랩 ${_signed(sameLap)}',
      if (stintGap != null) '스틴트 ${_signed(stintGap)}',
    ];
    if (parts.isEmpty) {
      continue;
    }
    final label = '${stint.compound} ${stint.startLap}–${stint.endLap}랩';
    lines.add('$label: ${parts.join(' · ')}');
    if (sameTyre != null && (worst == null || sameTyre > worst.gap)) {
      worst = (label: label, gap: sameTyre);
    }
  }
  if (lines.isEmpty) {
    return const [];
  }
  if (worst != null && worst.gap >= kPaceMarginMs) {
    lines.add('같은 타이어로 보면 ${worst.label}이 가장 느렸어(랩당 ${_signed(worst.gap)}) → 이 스틴트의 코너별 타이어 부담부터 봐');
  }
  return [kPaceBasisLine, ...lines];
}

/// 총평 항목에 심층 분석을 얹는다(평가는 그대로): 페이스·전략은 심층 줄을 앞에 더하고, 타이어·배터리는 심층 줄로 바꾼다(심층 줄이 없으면 그대로).
List<({String title, ReviewSection section})> raceReviewSectionsWithAnalysis(
  RaceReview review,
  RaceAnalysis analysis,
  List<OfficialCorner>? corners,
  Map<String, Object?>? setup,
) {
  final labels = segmentLabels(analysis, corners);
  List<String> deeper(String title, List<String> lines) {
    final deep = switch (title) {
      kPaceSectionTitle => deepPaceLines(analysis, review.stints),
      kStrategySectionTitle => deepStrategyLines(analysis, review.stints),
      kTyreSectionTitle => deepTyreLines(review.stints, analysis, labels, setup),
      kBatterySectionTitle => deepBatteryLines(review.battery, analysis, labels),
      _ => const <String>[],
    };
    if (deep.isEmpty) {
      return lines;
    }
    return title == kPaceSectionTitle || title == kStrategySectionTitle ? [...deep, ...lines] : deep;
  }

  return [
    for (final s in raceReviewSections(review)) (title: s.title, section: (grade: s.section.grade, lines: deeper(s.title, s.section.lines))),
  ];
}
