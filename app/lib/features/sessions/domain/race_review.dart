import 'session_detail_models.dart';

// 레이스 총평(`raceReview`): 서버가 낸 수치(깨끗한 랩 중앙값·피트 스톱·스틴트 추세·배터리)를 평가 글로 바꾼다. 모두 순수 함수.
// 말투는 레이스 엔지니어가 무전으로 드라이버에게 말하듯 — 짧은 반말, 수치 먼저, 할 것은 지시로(` → ` 뒤).

/// 페이스가 다른 차들 중앙값보다 이만큼(ms) 빠르거나 느리면 좋음·아쉬움.
const int kPaceMarginMs = 300;

/// 피트 스톱 손실이 다른 차들보다 이만큼(ms) 크면 짚는다.
const int kPitLossMarginMs = 1500;

/// 피트 구간: 인 랩부터 이만큼 뒤 랩까지(서버가 피트 뒤 순위를 보는 랩과 같다).
const int kPitSettleLaps = 2;

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

/// 섹터 수, 바퀴 수(앞왼·앞오·뒤왼·뒤오 순).
const int kSectorCount = 3;
const int kWheelCount = 4;

/// 섹터가 AI·앞 차보다 이만큼(ms) 느리거나 빠르면 짚는다.
const int kSectorMarginMs = 100;

/// 앞·뒤 타이어 랩당 마모 차이가 이만큼(%p) 이상이면 어느 쪽이 먼저 닳는지 짚는다.
const double _axleWearGapPct = 0.3;

/// 배터리 랩 끝 잔량이 용량의 이 비율 아래면 거의 바닥, 이 비율 이상이면 가득(서버와 같다).
const double kErsLowFraction = 0.1;
const double kErsFullFraction = 0.95;

/// 짚는 랩 목록에 이름을 적는 최대 수.
const int _listedLaps = 4;
const double _joulesPerKj = 1000;

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
    this.mySectorMs,
    this.fieldSectorMs,
    this.aheadSectorMs,
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

  /// 섹터 1·2·3 깨끗한 랩 중앙값(ms): 내 값, 다른 차들 값의 중앙값, 결과 바로 앞 차 값. 모르면 null.
  final List<int>? mySectorMs;
  final List<int>? fieldSectorMs;
  final List<int>? aheadSectorMs;

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
      mySectorMs: _sectors(json['mySectorMs']),
      fieldSectorMs: _sectors(json['fieldSectorMs']),
      aheadSectorMs: _sectors(json['aheadSectorMs']),
    );
  }
}

/// 섹터 세 개(ms) 목록. 형식이 틀리면 null.
List<int>? _sectors(Object? json) {
  if (json is! List || json.length != kSectorCount) {
    return null;
  }
  final values = [for (final v in json) ?jsonInt(v)];
  return values.length == kSectorCount ? values : null;
}

/// 피트 스톱 하나: 인 랩, 앞 랩 순위 → 아웃 랩 다음 랩 순위, 손실(ms), 바꾸기 전·후 컴파운드, 인 랩·아웃 랩 손실(ms).
class RacePitStopReview {
  const RacePitStopReview({
    required this.lap,
    this.positionBefore,
    this.positionAfter,
    this.lossMs,
    required this.fromCompound,
    required this.toCompound,
    this.inLapLossMs,
    this.outLapLossMs,
  });

  final int lap;
  final int? positionBefore;
  final int? positionAfter;
  final int? lossMs;
  final String fromCompound;
  final String toCompound;
  final int? inLapLossMs;
  final int? outLapLossMs;

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
      inLapLossMs: jsonInt(json['inLapLossMs']),
      outLapLossMs: jsonInt(json['outLapLossMs']),
    );
  }
}

/// 내 랩 끝 순위 하나.
typedef RaceLapPosition = ({int lap, int position});

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
    this.lapPositions = const [],
    this.fieldInLapLossMs,
    this.fieldOutLapLossMs,
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

  /// 내 랩 끝 순위(랩 순서, 기록된 랩만).
  final List<RaceLapPosition> lapPositions;

  /// 다른 차들 인 랩·아웃 랩 손실 중앙값(ms).
  final int? fieldInLapLossMs;
  final int? fieldOutLapLossMs;

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
      lapPositions: jsonObjects(json['lapPositions'], (j) {
        final lap = jsonInt(j['lap']);
        final position = jsonInt(j['position']);
        return lap == null || position == null ? null : (lap: lap, position: position);
      }),
      fieldInLapLossMs: jsonInt(json['fieldInLapLossMs']),
      fieldOutLapLossMs: jsonInt(json['fieldOutLapLossMs']),
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
    this.wheelWearPerLapPct,
    this.endLapsSlowerMs,
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

  /// 바퀴별 랩당 마모(%p, 앞왼·앞오·뒤왼·뒤오), 마지막 깨끗한 랩들이 스틴트 중앙값보다 느린 정도(ms). 모르면 null.
  final List<double>? wheelWearPerLapPct;
  final int? endLapsSlowerMs;

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
      wheelWearPerLapPct: _wheels(json['wheelWearPerLapPct']),
      endLapsSlowerMs: jsonInt(json['endLapsSlowerMs']),
    );
  }
}

/// 바퀴 네 개 값 목록. 형식이 틀리면 null.
List<double>? _wheels(Object? json) {
  if (json is! List || json.length != kWheelCount) {
    return null;
  }
  final values = [for (final v in json) ?jsonDouble(v)];
  return values.length == kWheelCount ? values : null;
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

String _signedSeconds(int ms) => '${ms >= 0 ? '+' : '−'}${(ms.abs() / _msPerSecond).toStringAsFixed(3)}초';

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

/// 섹터별 차이(내 값 − [other], ms, +면 내가 느림). 하나라도 모르면 null.
List<int>? sectorGaps(List<int>? mine, List<int>? other) =>
    mine == null || other == null ? null : [for (var i = 0; i < kSectorCount; i++) mine[i] - other[i]];

/// 차이가 가장 큰(느린) 섹터 번호(0부터)와 값.
({int sector, int gap}) _slowestSector(List<int> gaps) {
  var worst = 0;
  for (var i = 1; i < gaps.length; i++) {
    if (gaps[i] > gaps[worst]) {
      worst = i;
    }
  }
  return (sector: worst, gap: gaps[worst]);
}

/// 차이가 가장 작은(빠른) 섹터 번호(0부터)와 값.
({int sector, int gap}) _fastestSector(List<int> gaps) {
  var best = 0;
  for (var i = 1; i < gaps.length; i++) {
    if (gaps[i] < gaps[best]) {
      best = i;
    }
  }
  return (sector: best, gap: gaps[best]);
}

String _sectorName(int index) => 'S${index + 1}';

/// 페이스 평가: 수치는 그래프가 보여 주고, 줄은 섹터별 AI 비교·결과 앞뒤 차와의 섹터 비교·페이스 순위와 결과 순위가 어긋난 구간(실제 랩별 순위로).
ReviewSection paceReview(RacePaceReview pace, RaceStrategyReview strategy) {
  final lines = <String>[];
  final toField = sectorGaps(pace.mySectorMs, pace.fieldSectorMs);
  if (toField != null) {
    final slow = _slowestSector(toField);
    final fast = _fastestSector(toField);
    if (slow.gap >= kSectorMarginMs) {
      lines.add('${_sectorName(slow.sector)}에서 AI 중앙값보다 랩당 ${_seconds(slow.gap)} 느려'
          '${fast.gap <= -kSectorMarginMs ? '(${_sectorName(fast.sector)}은 ${_seconds(fast.gap)} 빨라)' : ''}'
          ' → 랩 분석 열어서 ${_sectorName(slow.sector)} 코너를 기준 랩이랑 맞춰 봐');
    } else if (fast.gap <= -kSectorMarginMs) {
      lines.add('${_sectorName(fast.sector)}에서 AI 중앙값보다 랩당 ${_seconds(fast.gap)} 빨라 — 거기가 우리 제일 강한 섹터야');
    }
  }
  final ahead = pace.aheadMedianMs;
  final aheadName = pace.aheadName;
  if (ahead != null && aheadName != null) {
    final diff = pace.myMedianMs - ahead;
    final toAhead = sectorGaps(pace.mySectorMs, pace.aheadSectorMs);
    if (diff > 0) {
      final slow = toAhead == null ? null : _slowestSector(toAhead);
      lines.add(slow != null && slow.gap >= kSectorMarginMs
          ? '앞차 $aheadName, 랩당 ${_seconds(diff)} 빨랐어. 그중 ${_sectorName(slow.sector)}에서 ${_seconds(slow.gap)} '
              '→ ${_sectorName(slow.sector)}만 줄이면 잡을 수 있어'
          : '앞차 $aheadName, 랩당 ${_seconds(diff)} 빨랐어');
    } else {
      final fast = toAhead == null ? null : _fastestSector(toAhead);
      lines.add(fast != null && fast.gap <= -kSectorMarginMs
          ? '앞차 $aheadName보다 랩당 ${_seconds(diff)} 빨랐는데 못 넘었어. ${_sectorName(fast.sector)}에서 ${_seconds(fast.gap)}로 제일 빨랐고 '
              '→ ${_sectorName(fast.sector)}에서 붙고, 이어지는 직선에서 배터리 몰아 써'
          : '앞차 $aheadName보다 랩당 ${_seconds(diff)} 빨랐는데 못 넘었어');
    }
  }
  final behind = pace.behindMedianMs;
  final behindName = pace.behindName;
  if (behind != null && behindName != null && behind < pace.myMedianMs) {
    lines.add('뒤차 $behindName, 랩당 ${_seconds(pace.myMedianMs - behind)} 빨랐는데 잘 막아냈어');
  }
  final finish = strategy.finishPosition;
  if (finish != null) {
    final changes = positionChanges(strategy);
    if (finish < pace.rank) {
      final gained = [
        if (changes != null && changes.start > 0) '출발에서 ${changes.start}계단',
        if (changes != null && changes.track > 0) '주행 중 ${changes.track}계단',
      ];
      lines.add('페이스는 ${pace.rank}위였는데 $finish위로 들어왔어'
          '${gained.isEmpty ? '' : ' — ${gained.join(', ')} 올라섰어'}');
    } else if (finish - pace.rank >= _placesLost) {
      lines.add(_lostPlacesLine(pace.rank, finish, changes, strategy));
    }
  }
  return (grade: paceGrade(pace), lines: lines);
}

/// 그리드 → 결과 순위 변화를 출발(그리드 → 1랩)·피트 구간(인 랩 ~ 그 뒤 [kPitSettleLaps]랩)·주행 중(나머지 랩)으로 나눈다(+ = 얻음).
/// 그리드나 랩별 순위를 모르면 null.
({int start, int pits, int track})? positionChanges(RaceStrategyReview strategy) {
  final grid = strategy.gridPosition;
  final laps = strategy.lapPositions;
  if (grid == null || laps.isEmpty) {
    return null;
  }
  bool inPitWindow(int lap) => strategy.pitStops.any((s) => lap >= s.lap && lap <= s.lap + kPitSettleLaps);
  final start = laps.first.lap == 1 ? grid - laps.first.position : 0;
  var pits = 0;
  var track = 0;
  for (var i = 1; i < laps.length; i++) {
    final delta = laps[i - 1].position - laps[i].position;
    if (inPitWindow(laps[i].lap)) {
      pits += delta;
    } else {
      track += delta;
    }
  }
  return (start: start, pits: pits, track: track);
}

/// 결과가 페이스 순위보다 낮을 때: 실제로 순위를 잃은 구간만 짚고, 다른 차들보다 스톱이 많으면 줄이라고 한다.
String _lostPlacesLine(int paceRank, int finish, ({int start, int pits, int track})? changes, RaceStrategyReview strategy) {
  final head = '페이스는 $paceRank위인데 결과는 $finish위야';
  if (changes == null) {
    return head;
  }
  final lost = [
    if (changes.start < 0) '출발에서 ${-changes.start}계단',
    if (changes.pits < 0) '피트 구간에서 ${-changes.pits}계단',
    if (changes.track < 0) '주행 중 ${-changes.track}계단',
  ];
  var line = lost.isEmpty ? head : '$head — ${lost.join(', ')} 잃었어';
  if (changes.pits < 0 && changes.track > 0) {
    line += '. 주행 중 ${changes.track}계단 되찾았는데 다 못 메웠어';
  }
  final common = strategy.commonStops;
  if (changes.pits < 0 && common != null && strategy.stops > common) {
    line += ' → 다들 $common스톱이었는데 우린 ${strategy.stops}스톱이야. 스톱 줄이면 피트에서 덜 잃어';
  }
  return line;
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

/// 시간을 더 잃은 스톱: 인 랩·아웃 랩을 AI와 나눠 비교해, 더 잃은 쪽을 짚는다.
String _slowStopLine(RacePitStopReview stop, RaceStrategyReview strategy) {
  final extra = stop.lossMs! - strategy.fieldPitLossMs!;
  final head = '${stop.lap}랩 피트, AI보다 ${_seconds(extra)} 더 잃었어';
  final inLoss = stop.inLapLossMs;
  final outLoss = stop.outLapLossMs;
  final fieldIn = strategy.fieldInLapLossMs;
  final fieldOut = strategy.fieldOutLapLossMs;
  if (inLoss == null || outLoss == null || fieldIn == null || fieldOut == null) {
    return head;
  }
  final extraIn = inLoss - fieldIn;
  final extraOut = outLoss - fieldOut;
  final split = '인 랩 ${_signedSeconds(extraIn)}, 아웃 랩 ${_signedSeconds(extraOut)}(AI 대비)';
  return extraIn >= extraOut
      ? '$head — $split → 인 랩에서 더 잃었어. 피트 진입 직전 감속이랑 피트 레인 진입 다시 보자'
      : '$head — $split → 아웃 랩에서 더 잃었어. 피트 나와서 찬 타이어로 도는 첫 랩 다시 보자';
}

/// 전략 평가: 그리드 → 결과·스톱 흐름·우승 차 전략은 그림이 보여 주고, 줄은 시간을 더 잃은 스톱(인·아웃 랩 비교)·순위를 얻은 스톱·스톱 수 비교.
ReviewSection strategyReview(RaceStrategyReview strategy) {
  final lines = <String>[];
  final grid = strategy.gridPosition;
  final finish = strategy.finishPosition;
  final gainedOverall = grid != null && finish != null ? grid - finish : 0;
  var poor = 0;
  var good = 0;
  for (final stop in strategy.pitStops) {
    switch (pitStopGrade(stop, strategy.fieldPitLossMs)) {
      case ReviewGrade.poor:
        poor++;
        lines.add(_slowStopLine(stop, strategy));
      case ReviewGrade.good:
        good++;
        lines.add('${stop.lap}랩 피트로 ${stop.placesGained}계단 올라섰어');
      case ReviewGrade.fair:
        break;
    }
  }
  final common = strategy.commonStops;
  if (common != null && strategy.commonStopsCars > 0) {
    lines.add(common == strategy.stops
        ? '완주 차 대부분(${strategy.commonStopsCars}대)이 $common스톱, 우리도 $common스톱이었어'
        : '완주 차 대부분(${strategy.commonStopsCars}대)이 $common스톱, 우린 ${strategy.stops}스톱이었어');
  }
  final grade = poor > 0
      ? ReviewGrade.poor
      : good > 0 || gainedOverall > 0
          ? ReviewGrade.good
          : ReviewGrade.fair;
  return (grade: grade, lines: lines);
}

/// 앞·뒤 타이어 랩당 마모(%p). 바퀴 값을 모르면 null.
({double front, double rear})? axleWear(RaceStintReview stint) {
  final wheels = stint.wheelWearPerLapPct;
  return wheels == null ? null : (front: (wheels[0] + wheels[1]) / 2, rear: (wheels[2] + wheels[3]) / 2);
}

/// 타이어를 빨리 잃었을 때: 앞·뒤 중 먼저 닳은 쪽으로 원인과 할 것을 고른다(바퀴 값이 없거나 비슷하면 null).
String? _axleAdvice(RaceStintReview stint) {
  final axle = axleWear(stint);
  if (axle == null || (axle.front - axle.rear).abs() < _axleWearGapPct) {
    return null;
  }
  final front = axle.front.toStringAsFixed(1);
  final rear = axle.rear.toStringAsFixed(1);
  return axle.front > axle.rear
      ? '앞 타이어(랩당 $front%)가 뒤($rear%)보다 빨리 닳았어 → 진입에서 브레이크 일찍 풀고 스티어링 덜 써'
      : '뒤 타이어(랩당 $rear%)가 앞($front%)보다 빨리 닳았어 → 탈출에서 스로틀 천천히 열어서 휠스핀 줄이자';
}

/// 타이어 평가: 스틴트 수치는 그림이 보여 주고, 줄은 스틴트마다 랩타임 추세(AI 대비)·앞뒤 마모로 본 원인·끝 수명과 마지막 랩 페이스.
ReviewSection tyreReview(List<RaceStintReview> stints) {
  final lines = <String>[];
  var worse = 0;
  var better = 0;
  for (final (i, stint) in stints.indexed) {
    final last = i == stints.length - 1;
    final label = '${stint.compound} ${stint.startLap}–${stint.endLap}랩';
    final wear = stint.wearPerLapPct;
    final life = stint.endLifePct;
    final extra = stint.extraTrendMs;
    final fastWear = wear != null && wear >= _fastWearPct;
    final lostGrip = extra != null && extra >= kTrendMarginMs;
    if (lostGrip || fastWear) {
      worse++;
      final facts = [
        if (lostGrip) 'AI보다 랩당 ${_seconds(extra)}씩 더 빨리 떨어졌어',
        if (fastWear) '마모 랩당 ${wear.toStringAsFixed(1)}%야',
      ];
      final advice = _axleAdvice(stint);
      lines.add('$label: ${facts.join(', ')}${advice == null ? '' : '. $advice'}');
    } else if (extra != null && extra <= -kTrendMarginMs) {
      better++;
      lines.add('$label: AI보다 랩당 ${_seconds(extra)}씩 덜 떨어졌어 — 타이어 관리 좋았어');
    }
    final slower = stint.endLapsSlowerMs;
    if (life != null && life < _lowLifePct) {
      lines.add(slower != null && slower > 0
          ? '$label: 수명 ${life.round()}%까지 탔고 마지막 랩들이 스틴트 중앙값보다 ${_seconds(slower)} 느렸어 → 한두 랩 일찍 박스하면 그만큼 아낄 수 있어'
          : '$label: 수명 ${life.round()}%까지 탔는데 마지막 랩 페이스는 지켰어');
    } else if (life != null && !last && life >= _earlyStopLifePct) {
      lines.add('$label: 수명 ${life.round()}% 남기고 들어왔어 → 스틴트 더 끌면 스톱 하나 줄일 수 있어');
    }
  }
  final grade = worse > 0
      ? ReviewGrade.poor
      : better > 0
          ? ReviewGrade.good
          : ReviewGrade.fair;
  return (grade: grade, lines: lines);
}

/// 랩 번호 목록 `L12·L13·L20`(많으면 앞 몇 개와 나머지 수).
String _lapList(List<int> laps) {
  final shown = laps.take(_listedLaps).map((l) => 'L$l').join('·');
  return laps.length > _listedLaps ? '$shown 외 ${laps.length - _listedLaps}랩' : shown;
}

/// 짚은 랩들의 배포·회수를 레이스 평균과 비교한 차이(kJ, +면 평균보다 많다). 각각 모르면 null.
({int? deploy, int? harvest}) _flowVersusAverage(List<RaceBatteryLap> flagged, List<RaceBatteryLap> all) {
  double? mean(Iterable<double?> values) {
    final known = values.whereType<double>().toList();
    return known.isEmpty ? null : known.reduce((a, b) => a + b) / known.length;
  }

  int? versus(double? Function(RaceBatteryLap lap) of) {
    final flaggedMean = mean(flagged.map(of));
    final allMean = mean(all.map(of));
    return flaggedMean == null || allMean == null ? null : ((flaggedMean - allMean) / _joulesPerKj).round();
  }

  return (deploy: versus((l) => l.deployedJ), harvest: versus((l) => l.harvestedJ));
}

/// 배터리 평가: 잔량·배포·회수는 그림이 보여 주고, 줄은 거의 바닥·가득 찬 랩(랩 번호와 그 랩 배포·회수를 평균과 비교)·끝에 남긴 배터리.
ReviewSection batteryReview(RaceBatteryReview battery) {
  final lines = <String>[];
  final perLap = battery.perLap;
  final lowLaps = [for (final l in perLap) if (l.storeJ < kErsCapacityJ * kErsLowFraction) l];
  final fullLaps = [for (final l in perLap) if (l.storeJ >= kErsCapacityJ * kErsFullFraction) l];
  final lowPct = _pct(kErsLowFraction);
  var issues = 0;
  if (battery.lowLaps >= _ersFlagLaps) {
    issues++;
    final flow = _flowVersusAverage(lowLaps, perLap);
    final where = lowLaps.isEmpty ? '${battery.lowLaps}랩' : _lapList([for (final l in lowLaps) l.lap]);
    final deploy = flow.deploy;
    final harvest = flow.harvest;
    final head = '$where에서 배터리가 $lowPct 아래까지 떨어졌어';
    lines.add(deploy != null && deploy > 0
        ? '$head. 그 랩들 배포가 평균보다 ${deploy}kJ 많았어 → 그 랩들은 효과 작은 짧은 직선은 Normal로 두고 긴 직선에서만 써'
        : harvest != null && harvest < 0
            ? '$head. 그 랩들 회수가 평균보다 ${-harvest}kJ 적었어 → 브레이킹 구간 길게 가져가서 회수 늘리자'
            : head);
  }
  if (battery.fullLaps >= _ersFlagLaps) {
    issues++;
    final flow = _flowVersusAverage(fullLaps, perLap);
    final where = fullLaps.isEmpty ? '${battery.fullLaps}랩' : _lapList([for (final l in fullLaps) l.lap]);
    final deploy = flow.deploy;
    lines.add(deploy != null && deploy < 0
        ? '$where에서 배터리가 꽉 찼어. 그 랩들 배포가 평균보다 ${-deploy}kJ 적었어 → 꽉 차면 더 못 모아. 그 랩들은 Overtake 모드로 더 써'
        : '$where에서 배터리가 꽉 찼어');
  }
  if (battery.lastStoreJ >= kErsCapacityJ * _ersLeftoverFraction) {
    issues++;
    lines.add('체커 받을 때 ${_pct(battery.lastStoreJ / kErsCapacityJ)} 남겼어 → 마지막 두세 랩은 다 털어 써도 돼');
  }
  if (issues == 0) {
    lines.add('바닥나거나 꽉 찬 랩 없이 잘 썼어. 끝 잔량 ${_pct(battery.lastStoreJ / kErsCapacityJ)}');
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
    return '전체적으로 무난한 레이스였어. 수고했어.';
  }
  if (poor.isEmpty) {
    return '${good.join('·')}${_subjectParticle(good.last)} 좋았어. 잘 달렸어.';
  }
  if (good.isEmpty) {
    return '${poor.join('·')}에서 시간을 잃었어. 하나씩 짚어 보자.';
  }
  return '${good.join('·')}${_subjectParticle(good.last)} 좋았고, ${poor.join('·')}${_subjectParticle(poor.last)} 아쉬웠어. 하나씩 짚어 보자.';
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
