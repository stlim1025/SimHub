import 'session_detail_models.dart';

// 레이스 총평(`raceReview`): 서버가 낸 수치(깨끗한 랩 중앙값·피트 스톱·스틴트 추세·배터리)를 평가 글로 바꾼다. 모두 순수 함수.

/// 페이스가 다른 차들 중앙값보다 이만큼(ms) 빠르거나 느리면 좋음·아쉬움.
const int kPaceMarginMs = 300;

/// 피트 스톱 손실이 다른 차들보다 이만큼(ms) 크면 짚는다.
const int kPitLossMarginMs = 1500;

/// 피트 뒤·페이스 대비 이만큼 순위를 잃으면 짚는다.
const int _placesLost = 2;

/// 스틴트 랩타임 추세가 같은 컴파운드 다른 차들보다 이만큼(ms/랩) 크거나 작으면 타이어를 빨리 잃었다·잘 지켰다.
const int kTrendMarginMs = 50;

/// 랩당 마모(%p)가 이 이상이면 빠르다, 스틴트 끝 잔여 수명(%)이 이 아래면 너무 오래 탔다, 이 이상이면(마지막 스틴트 제외) 일찍 들어왔다.
const double _fastWearPct = 3;
const double _lowLifePct = 30;
const double _earlyStopLifePct = 60;

/// 배터리: 용량(J), 거의 바닥·가득 찬 랩이 이 이상이면 짚는다, 레이스 끝 잔량이 이 비율 이상이면 남겼다.
const double kErsCapacityJ = 4000000;
const int _ersFlagLaps = 3;
const double _ersLeftoverFraction = 0.5;

const double _msPerSecond = 1000;
const double _percent = 100;

/// 페이스: 깨끗한 랩(1랩·피트 인아웃·세이프티카 랩 제외) 중앙값.
class RacePaceReview {
  const RacePaceReview({
    required this.myMedianMs,
    required this.rank,
    required this.rankedCars,
    required this.fieldMedianMs,
    required this.fastestName,
    required this.fastestMedianMs,
    this.aheadName,
    this.aheadMedianMs,
    this.behindName,
    this.behindMedianMs,
  });

  final int myMedianMs;
  final int rank;
  final int rankedCars;
  final int fieldMedianMs;
  final String fastestName;
  final int fastestMedianMs;
  final String? aheadName;
  final int? aheadMedianMs;
  final String? behindName;
  final int? behindMedianMs;

  static RacePaceReview? fromJsonOrNull(Object? json) {
    if (json is! Map<String, dynamic>) {
      return null;
    }
    final my = jsonInt(json['myMedianMs']);
    final rank = jsonInt(json['rank']);
    final ranked = jsonInt(json['rankedCars']);
    final field = jsonInt(json['fieldMedianMs']);
    final fastest = jsonInt(json['fastestMedianMs']);
    if (my == null || rank == null || ranked == null || field == null || fastest == null) {
      return null;
    }
    return RacePaceReview(
      myMedianMs: my,
      rank: rank,
      rankedCars: ranked,
      fieldMedianMs: field,
      fastestName: jsonString(json['fastestName']) ?? '',
      fastestMedianMs: fastest,
      aheadName: jsonString(json['aheadName']),
      aheadMedianMs: jsonInt(json['aheadMedianMs']),
      behindName: jsonString(json['behindName']),
      behindMedianMs: jsonInt(json['behindMedianMs']),
    );
  }
}

/// 피트 스톱 하나: 인 랩, 앞 랩 순위 → 아웃 랩 다음 랩 순위, 손실(ms), 바꾸기 전·후 컴파운드.
class RacePitStopReview {
  const RacePitStopReview({
    required this.lap,
    this.positionBefore,
    this.positionAfter,
    this.lossMs,
    required this.fromCompound,
    required this.toCompound,
  });

  final int lap;
  final int? positionBefore;
  final int? positionAfter;
  final int? lossMs;
  final String fromCompound;
  final String toCompound;

  /// 피트 전후로 얻은 순위(+ = 올라감). 모르면 null.
  int? get placesGained =>
      positionBefore == null || positionAfter == null ? null : positionBefore! - positionAfter!;

  static RacePitStopReview? fromJsonOrNull(Map<String, dynamic> json) {
    final lap = jsonInt(json['lap']);
    if (lap == null) {
      return null;
    }
    return RacePitStopReview(
      lap: lap,
      positionBefore: jsonInt(json['positionBefore']),
      positionAfter: jsonInt(json['positionAfter']),
      lossMs: jsonInt(json['lossMs']),
      fromCompound: jsonString(json['fromCompound']) ?? '',
      toCompound: jsonString(json['toCompound']) ?? '',
    );
  }
}

/// 전략: 그리드·결과, 스톱, 완주 차들이 가장 많이 한 스톱 수, 우승 차 전략, 다른 차들 스톱 손실 중앙값.
class RaceStrategyReview {
  const RaceStrategyReview({
    this.gridPosition,
    this.finishPosition,
    this.stops = 0,
    this.pitStops = const [],
    this.commonStops,
    this.commonStopsCars = 0,
    this.winnerStops,
    this.winnerCompounds = const [],
    this.fieldPitLossMs,
  });

  final int? gridPosition;
  final int? finishPosition;
  final int stops;
  final List<RacePitStopReview> pitStops;
  final int? commonStops;
  final int commonStopsCars;
  final int? winnerStops;
  final List<String> winnerCompounds;
  final int? fieldPitLossMs;

  static RaceStrategyReview fromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      return const RaceStrategyReview();
    }
    final compounds = json['winnerCompounds'];
    return RaceStrategyReview(
      gridPosition: jsonInt(json['gridPosition']),
      finishPosition: jsonInt(json['finishPosition']),
      stops: jsonInt(json['stops']) ?? 0,
      pitStops: jsonObjects(json['pitStops'], RacePitStopReview.fromJsonOrNull),
      commonStops: jsonInt(json['commonStops']),
      commonStopsCars: jsonInt(json['commonStopsCars']) ?? 0,
      winnerStops: jsonInt(json['winnerStops']),
      winnerCompounds: [
        if (compounds is List)
          for (final c in compounds) ?jsonString(c),
      ],
      fieldPitLossMs: jsonInt(json['fieldPitLossMs']),
    );
  }
}

/// 내 스틴트 하나: 컴파운드·랩 범위, 깨끗한 랩 중앙값과 랩타임 추세(+면 느려짐)를 같은 컴파운드 다른 차들과, 랩당 마모·끝 잔여 수명.
class RaceStintReview {
  const RaceStintReview({
    required this.compound,
    required this.startLap,
    required this.endLap,
    this.medianMs,
    this.fieldMedianMs,
    this.trendMsPerLap,
    this.fieldTrendMsPerLap,
    this.wearPerLapPct,
    this.endLifePct,
  });

  final String compound;
  final int startLap;
  final int endLap;
  final int? medianMs;
  final int? fieldMedianMs;
  final int? trendMsPerLap;
  final int? fieldTrendMsPerLap;
  final double? wearPerLapPct;
  final double? endLifePct;

  /// 내 추세 − 다른 차들 추세(ms/랩, +면 타이어를 더 빨리 잃었다). 모르면 null.
  int? get extraTrendMs =>
      trendMsPerLap == null || fieldTrendMsPerLap == null ? null : trendMsPerLap! - fieldTrendMsPerLap!;

  static RaceStintReview? fromJsonOrNull(Map<String, dynamic> json) {
    final start = jsonInt(json['startLap']);
    final end = jsonInt(json['endLap']);
    final compound = jsonString(json['compound']);
    if (start == null || end == null || compound == null) {
      return null;
    }
    return RaceStintReview(
      compound: compound,
      startLap: start,
      endLap: end,
      medianMs: jsonInt(json['medianMs']),
      fieldMedianMs: jsonInt(json['fieldMedianMs']),
      trendMsPerLap: jsonInt(json['trendMsPerLap']),
      fieldTrendMsPerLap: jsonInt(json['fieldTrendMsPerLap']),
      wearPerLapPct: jsonDouble(json['wearPerLapPct']),
      endLifePct: jsonDouble(json['endLifePct']),
    );
  }
}

/// 배터리 한 랩: 랩 번호, 랩 끝 잔량(J), 그 랩의 배포·회수(J, 모르면 null).
class RaceBatteryLap {
  const RaceBatteryLap({required this.lap, required this.storeJ, this.deployedJ, this.harvestedJ});

  final int lap;
  final double storeJ;
  final double? deployedJ;
  final double? harvestedJ;

  static RaceBatteryLap? fromJsonOrNull(Map<String, dynamic> json) {
    final lap = jsonInt(json['lap']);
    final store = jsonDouble(json['storeJ']);
    if (lap == null || store == null) {
      return null;
    }
    return RaceBatteryLap(
      lap: lap,
      storeJ: store,
      deployedJ: jsonDouble(json['deployedJ']),
      harvestedJ: jsonDouble(json['harvestedJ']),
    );
  }
}

/// 배터리: 기록된 랩 수, 랩당 평균 배포·회수(J), 랩 끝 잔량 처음·끝·최저(J)와 그 랩, 거의 바닥·가득 찬 랩 수, 랩별 기록.
class RaceBatteryReview {
  const RaceBatteryReview({
    required this.laps,
    this.averageDeployJ,
    this.averageHarvestJ,
    required this.firstStoreJ,
    required this.lastStoreJ,
    required this.minStoreJ,
    required this.minStoreLap,
    this.lowLaps = 0,
    this.fullLaps = 0,
    this.perLap = const [],
  });

  final int laps;
  final double? averageDeployJ;
  final double? averageHarvestJ;
  final double firstStoreJ;
  final double lastStoreJ;
  final double minStoreJ;
  final int minStoreLap;
  final int lowLaps;
  final int fullLaps;
  final List<RaceBatteryLap> perLap;

  static RaceBatteryReview? fromJsonOrNull(Object? json) {
    if (json is! Map<String, dynamic>) {
      return null;
    }
    final laps = jsonInt(json['laps']);
    final first = jsonDouble(json['firstStoreJ']);
    final last = jsonDouble(json['lastStoreJ']);
    final min = jsonDouble(json['minStoreJ']);
    final minLap = jsonInt(json['minStoreLap']);
    if (laps == null || first == null || last == null || min == null || minLap == null) {
      return null;
    }
    return RaceBatteryReview(
      laps: laps,
      averageDeployJ: jsonDouble(json['averageDeployJ']),
      averageHarvestJ: jsonDouble(json['averageHarvestJ']),
      firstStoreJ: first,
      lastStoreJ: last,
      minStoreJ: min,
      minStoreLap: minLap,
      lowLaps: jsonInt(json['lowLaps']) ?? 0,
      fullLaps: jsonInt(json['fullLaps']) ?? 0,
      perLap: jsonObjects(json['perLap'], RaceBatteryLap.fromJsonOrNull),
    );
  }
}

/// 레이스 총평 재료(`GET /me/sessions/{id}`의 `raceReview`, 레이스만).
class RaceReview {
  const RaceReview({this.pace, this.strategy = const RaceStrategyReview(), this.stints = const [], this.battery});

  final RacePaceReview? pace;
  final RaceStrategyReview strategy;
  final List<RaceStintReview> stints;
  final RaceBatteryReview? battery;

  static RaceReview? fromJsonOrNull(Object? json) {
    if (json is! Map<String, dynamic>) {
      return null;
    }
    return RaceReview(
      pace: RacePaceReview.fromJsonOrNull(json['pace']),
      strategy: RaceStrategyReview.fromJson(json['strategy']),
      stints: jsonObjects(json['stints'], RaceStintReview.fromJsonOrNull),
      battery: RaceBatteryReview.fromJsonOrNull(json['battery']),
    );
  }
}

/// 항목 평가: 좋음·보통·아쉬움.
enum ReviewGrade { good, fair, poor }

/// 총평 한 항목: 평가와 줄들(관찰 → 할 것).
typedef ReviewSection = ({ReviewGrade grade, List<String> lines});

String _seconds(int ms) => '${(ms.abs() / _msPerSecond).toStringAsFixed(3)}초';

String _pct(double fraction) => '${(fraction * _percent).round()}%';

/// 페이스 등급: 다른 차들 중앙값과의 차이로.
ReviewGrade paceGrade(RacePaceReview pace) {
  final gap = pace.myMedianMs - pace.fieldMedianMs;
  return gap <= -kPaceMarginMs
      ? ReviewGrade.good
      : gap >= kPaceMarginMs
          ? ReviewGrade.poor
          : ReviewGrade.fair;
}

/// 페이스 평가: 수치(중앙값·순위·가장 빠른 차)는 그래프가 보여 주고, 줄은 결과 앞뒤 차와의 비교·페이스 순위와 결과 순위가 어긋난 것만.
ReviewSection paceReview(RacePaceReview pace, RaceStrategyReview strategy) {
  final lines = <String>[];
  final ahead = pace.aheadMedianMs;
  final aheadName = pace.aheadName;
  if (ahead != null && aheadName != null) {
    final diff = pace.myMedianMs - ahead;
    lines.add(diff > 0
        ? '바로 앞 $aheadName은 랩당 ${_seconds(diff)} 빨랐어요 → 순위를 올리려면 그만큼 페이스가 더 필요해요'
        : '바로 앞 $aheadName보다 랩당 ${_seconds(diff)} 빨랐는데 넘지 못했어요 → DRS 구간 앞 탈출과 배터리를 추월 한 곳에 몰아 쓰세요');
  }
  final behind = pace.behindMedianMs;
  final behindName = pace.behindName;
  if (behind != null && behindName != null && behind < pace.myMedianMs) {
    lines.add('뒤의 $behindName이 랩당 ${_seconds(pace.myMedianMs - behind)} 빨랐지만 순위를 지켜냈어요');
  }
  final finish = strategy.finishPosition;
  if (finish != null) {
    if (finish < pace.rank) {
      lines.add('페이스 순위(${pace.rank}위)보다 높은 $finish위로 끝냈어요 — 출발·전략·배틀에서 얻었어요');
    } else if (finish - pace.rank >= _placesLost) {
      lines.add('페이스는 ${pace.rank}위인데 결과는 $finish위예요 — 출발·피트·배틀에서 순위를 잃었어요');
    }
  }
  return (grade: paceGrade(pace), lines: lines);
}

/// 피트 스톱 하나의 평가: 다른 차들보다 피트에서 시간을 많이 잃으면 아쉬움, 피트 뒤 순위를 얻으면 좋음.
/// 피트 직후 순위가 떨어지는 것은 피트 손실만큼 당연하므로 평가하지 않는다.
ReviewGrade pitStopGrade(RacePitStopReview stop, int? fieldLossMs) {
  final loss = stop.lossMs;
  final places = stop.placesGained;
  if (loss != null && fieldLossMs != null && loss - fieldLossMs >= kPitLossMarginMs) {
    return ReviewGrade.poor;
  }
  return places != null && places > 0 ? ReviewGrade.good : ReviewGrade.fair;
}

/// 전략 평가: 그리드 → 결과·스톱 흐름·우승 차 전략은 그림이 보여 주고, 줄은 짚을 스톱과 스톱 수 비교만.
ReviewSection strategyReview(RaceStrategyReview strategy) {
  final lines = <String>[];
  final grid = strategy.gridPosition;
  final finish = strategy.finishPosition;
  final gainedOverall = grid != null && finish != null ? grid - finish : 0;
  var poor = 0;
  var good = 0;
  final fieldLoss = strategy.fieldPitLossMs;
  for (final stop in strategy.pitStops) {
    final loss = stop.lossMs;
    final places = stop.placesGained;
    switch (pitStopGrade(stop, fieldLoss)) {
      case ReviewGrade.poor:
        poor++;
        lines.add('${stop.lap}랩 피트에서 AI보다 ${_seconds(loss! - fieldLoss!)} 더 잃었어요 → 피트 진입 브레이킹과 아웃 랩 첫 코너를 점검하세요');
      case ReviewGrade.good:
        good++;
        lines.add('${stop.lap}랩 피트로 $places계단 올라섰어요');
      case ReviewGrade.fair:
        break;
    }
  }
  final common = strategy.commonStops;
  if (common != null && strategy.commonStopsCars > 0) {
    lines.add(common == strategy.stops
        ? '완주한 차 대부분(${strategy.commonStopsCars}대)과 같은 $common스톱이었어요'
        : '완주한 차 대부분(${strategy.commonStopsCars}대)은 $common스톱, 나는 ${strategy.stops}스톱이었어요');
  }
  final grade = poor > 0
      ? ReviewGrade.poor
      : good > 0 || gainedOverall > 0
          ? ReviewGrade.good
          : ReviewGrade.fair;
  return (grade: grade, lines: lines);
}

/// 타이어 평가: 스틴트 수치는 그림이 보여 주고, 줄은 스틴트마다 짚을 것(추세·마모·끝 수명)을 하나씩.
ReviewSection tyreReview(List<RaceStintReview> stints) {
  final lines = <String>[];
  var worse = 0;
  var better = 0;
  for (final (i, stint) in stints.indexed) {
    final last = i == stints.length - 1;
    final wear = stint.wearPerLapPct;
    final life = stint.endLifePct;
    final extra = stint.extraTrendMs;
    final advice = <String>[];
    if (extra != null && extra >= kTrendMarginMs) {
      worse++;
      advice.add('AI보다 랩당 ${_seconds(extra)}씩 더 빨리 떨어졌어요. 연석·탈출 휠스핀·늦은 브레이킹으로 타이어를 혹사했어요');
    } else if (extra != null && extra <= -kTrendMarginMs) {
      better++;
      advice.add('AI보다 타이어를 잘 지켰어요');
    }
    if (wear != null && wear >= _fastWearPct) {
      worse++;
      advice.add('마모가 빨라요 → 코너 진입 속도를 조금 낮추고 핸들을 덜 꺾으세요');
    }
    if (life != null && life < _lowLifePct) {
      advice.add('그립 절벽 직전까지 탔어요 → 한두 랩 일찍 들어가는 게 안전해요');
    } else if (life != null && !last && life >= _earlyStopLifePct) {
      advice.add('수명이 ${life.round()}% 남았는데 들어왔어요 → 스틴트를 늘리면 스톱을 줄일 수 있어요');
    }
    for (final a in advice) {
      lines.add('${stint.compound} ${stint.startLap}–${stint.endLap}랩: $a');
    }
  }
  final grade = worse > 0
      ? ReviewGrade.poor
      : better > 0
          ? ReviewGrade.good
          : ReviewGrade.fair;
  return (grade: grade, lines: lines);
}

/// 배터리 평가: 잔량·배포·회수는 그림이 보여 주고, 줄은 거의 바닥·가득 찬 랩, 끝에 남긴 배터리.
ReviewSection batteryReview(RaceBatteryReview battery) {
  final lines = <String>[];
  if (battery.lowLaps >= _ersFlagLaps) {
    lines.add('배터리가 거의 바닥인 랩이 ${battery.lowLaps}번이에요. 방어·추월할 때 쓸 배터리가 없었어요 '
        '→ 효과가 작은 짧은 직선에서는 아끼고, 긴 직선 하나에 몰아 쓰세요');
  }
  if (battery.fullLaps >= _ersFlagLaps) {
    lines.add('배터리가 가득 찬 랩이 ${battery.fullLaps}번이에요. 가득 차면 더 회수하지 못해 에너지를 버린 셈이에요 '
        '→ 그때는 오버테이크 모드로 더 쓰세요');
  }
  if (battery.lastStoreJ >= kErsCapacityJ * _ersLeftoverFraction) {
    lines.add('레이스가 끝날 때 ${_pct(battery.lastStoreJ / kErsCapacityJ)}를 남겼어요. 마지막 두세 랩은 다 써도 돼요');
  }
  final issues = lines.length;
  if (issues == 0) {
    lines.add('바닥나거나 가득 차 버린 랩 없이 고르게 썼어요');
  }
  final grade = issues == 0
      ? ReviewGrade.good
      : issues == 1
          ? ReviewGrade.fair
          : ReviewGrade.poor;
  return (grade: grade, lines: lines);
}

/// 배터리가 거의 바닥·가득 찬 랩을 짚기 시작하는 횟수.
const int kErsFlagLaps = _ersFlagLaps;

/// 스틴트 끝 수명(%): 이 아래는 위험, 이 이상은 넉넉함(그림 색).
const double kLowTyreLifePct = _lowLifePct;
const double kHealthyTyreLifePct = _earlyStopLifePct;

/// 랩당 마모(%p)가 이 이상이면 빠르다(그림 색).
const double kFastWearPct = _fastWearPct;

/// 항목 이름.
const String kPaceSectionTitle = '페이스';
const String kStrategySectionTitle = '전략';
const String kTyreSectionTitle = '타이어 관리';
const String kBatterySectionTitle = '배터리 관리';

/// 총평의 항목들(데이터가 있는 것만, 페이스 → 전략 → 타이어 → 배터리).
List<({String title, ReviewSection section})> raceReviewSections(RaceReview review) {
  final pace = review.pace;
  final battery = review.battery;
  final strategy = review.strategy;
  return [
    if (pace != null) (title: kPaceSectionTitle, section: paceReview(pace, strategy)),
    if (strategy.gridPosition != null || strategy.pitStops.isNotEmpty)
      (title: kStrategySectionTitle, section: strategyReview(strategy)),
    if (review.stints.isNotEmpty) (title: kTyreSectionTitle, section: tyreReview(review.stints)),
    if (battery != null) (title: kBatterySectionTitle, section: batteryReview(battery)),
  ];
}

/// 맨 위 한 줄 총평: 좋았던 항목·아쉬운 항목. 항목이 없으면 null.
String? raceReviewSummary(List<({String title, ReviewSection section})> sections) {
  if (sections.isEmpty) {
    return null;
  }
  final good = [for (final s in sections) if (s.section.grade == ReviewGrade.good) s.title];
  final poor = [for (final s in sections) if (s.section.grade == ReviewGrade.poor) s.title];
  if (poor.isEmpty && good.isEmpty) {
    return '전체적으로 무난한 레이스였어요.';
  }
  if (poor.isEmpty) {
    return '${good.join('·')}${_subjectParticle(good.last)} 좋았던 레이스예요.';
  }
  if (good.isEmpty) {
    return '${poor.join('·')}에서 시간을 잃은 레이스예요.';
  }
  return '${good.join('·')}${_subjectParticle(good.last)} 좋았고, ${poor.join('·')}${_subjectParticle(poor.last)} 아쉬웠어요.';
}

/// 받침이 있으면 `이`, 없으면 `가`(한글 끝 글자 기준, 순수 함수).
String _subjectParticle(String word) {
  const hangulBase = 0xAC00;
  const hangulLast = 0xD7A3;
  const finals = 28;
  final code = word.codeUnitAt(word.length - 1);
  if (code < hangulBase || code > hangulLast) {
    return '이';
  }
  return (code - hangulBase) % finals == 0 ? '가' : '이';
}
