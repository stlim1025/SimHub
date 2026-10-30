import 'dart:math' as math;

import 'session_detail_models.dart';

// 레이스 총평(`raceReview`): 서버가 낸 수치(깨끗한 랩 중앙값·피트 스톱·스틴트 추세·배터리)를 평가 글로 바꾼다. 모두 순수 함수.
// 말투는 레이스 엔지니어가 무전으로 드라이버에게 말하듯 — 짧은 반말, 수치 먼저, 할 것은 지시로(` → ` 뒤).

/// 페이스가 다른 차들 중앙값보다 이만큼(ms) 빠르거나 느리면 좋음·아쉬움.
const int kPaceMarginMs = 300;

/// 피트 스톱 손실이 다른 차들보다 이만큼(ms) 크면 짚는다.
const int kPitLossMarginMs = 1500;

/// 전략 평가: 추정 대안 전략이 이만큼(ms) 빠르면 아쉬움(단 실제 레이스에서 내 스톱 수가 가장 잘 통했으면 실제 결과를 믿는다),
/// 나와 스톱 수가 달라 뒤에서 출발해 앞에 들어온 차가 이 수 이상이면 아쉬움. 줄에 늘어놓을 완주 순위·상대 수.
const int kStrategyPoorMs = 5000;
const int _rivalsAheadPoor = 2;
const int _listedFinishes = 5;
const int _listedRivals = 3;

/// 피트 구간: 인 랩부터 이만큼 뒤 랩까지(서버가 피트 뒤 순위를 보는 랩과 같다).
const int kPitSettleLaps = 2;

/// 피트 뒤·페이스 대비 이만큼 순위를 잃으면 짚는다.
const int _placesLost = 2;

/// 스틴트 랩타임 추세가 같은 컴파운드 다른 차들보다 이만큼(ms/랩) 크거나 작으면 타이어를 빨리 잃었다·잘 지켰다.
const int kTrendMarginMs = 50;

/// 스틴트 끝 잔여 수명(%)이 이 아래면 너무 오래 탔다(마모가 빠른지도 새 타이어가 여기까지 가는 랩 수로 본다), 이 이상이면(마지막 스틴트 제외) 일찍 들어왔다.
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

/// 피트 스톱 하나: 인 랩, 앞 랩 순위 → 아웃 랩 다음 랩 순위, 손실(ms), 바꾸기 전·후 컴파운드, 인 랩·아웃 랩 손실(ms),
/// 비슷한 때 같은 스톱 수로 들어간 다른 차들(없으면 비슷한 때 들어간 차들)의 손실·인 랩·아웃 랩 손실 중앙값과 그 스톱 수.
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
    this.peerLossMs,
    this.peerCount = 0,
    this.peerInLapLossMs,
    this.peerOutLapLossMs,
  });

  final int lap;
  final int? positionBefore;
  final int? positionAfter;
  final int? lossMs;
  final String fromCompound;
  final String toCompound;
  final int? inLapLossMs;
  final int? outLapLossMs;
  final int? peerLossMs;
  final int peerCount;
  final int? peerInLapLossMs;
  final int? peerOutLapLossMs;

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
      peerLossMs: jsonInt(json['peerLossMs']),
      peerCount: jsonInt(json['peerCount']) ?? 0,
      peerInLapLossMs: jsonInt(json['peerInLapLossMs']),
      peerOutLapLossMs: jsonInt(json['peerOutLapLossMs']),
    );
  }
}

/// 내 랩 끝 순위 하나.
typedef RaceLapPosition = ({int lap, int position});

/// 스톱 수 하나로 완주한 차들의 결과 순위(오름차순, 나 포함).
typedef RaceStopGroup = ({int stops, List<int> finishes});

/// 나와 스톱 수가 다르면서 출발·결과 순서가 나와 뒤바뀐 차.
typedef RaceStrategyRival = ({String name, int stops, int grid, int finish});

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
    this.stopGroups = const [],
    this.rivals = const [],
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

  /// 스톱 수별 완주 순위(스톱 수 순서).
  final List<RaceStopGroup> stopGroups;

  /// 나와 스톱 수가 달라 출발·결과 순서가 뒤바뀐 차(결과 순서).
  final List<RaceStrategyRival> rivals;

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
      stopGroups: jsonObjects(json['stopGroups'], (j) {
        final stops = jsonInt(j['stops']);
        final finishes = j['finishes'];
        return stops == null || finishes is! List ? null : (stops: stops, finishes: [for (final f in finishes) ?jsonInt(f)]);
      }),
      rivals: jsonObjects(json['rivals'], (j) {
        final name = jsonString(j['name']);
        final stops = jsonInt(j['stops']);
        final grid = jsonInt(j['gridPosition']);
        final finish = jsonInt(j['finishPosition']);
        return name == null || stops == null || grid == null || finish == null
            ? null
            : (name: name, stops: stops, grid: grid, finish: finish);
      }),
    );
  }
}

/// 내 스틴트 하나: 컴파운드·랩 범위, 깨끗한 랩 중앙값과 랩타임 추세(+면 느려짐)를 같은 컴파운드 다른 차들과, 랩당 마모·끝 잔여 수명,
/// 같은 컴파운드로 AI가 피트 전까지 탄 랩 수(중앙값).
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
    this.fieldStintLaps,
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

  /// 같은 컴파운드로 AI가 피트 전까지 탄 랩 수(중앙값, 마지막 스틴트 제외). 모르면 null.
  final int? fieldStintLaps;

  /// 내 추세 − 다른 차들 추세(ms/랩, +면 타이어를 더 빨리 잃었다). 모르면 null.
  int? get extraTrendMs =>
      trendMsPerLap == null || fieldTrendMsPerLap == null ? null : trendMsPerLap! - fieldTrendMsPerLap!;

  /// 이 마모라면 새 타이어가 수명 30%까지 가는 랩 수(내림). 마모를 모르거나 0 이하면 null.
  int? get lapsToLowLife {
    final wear = wearPerLapPct;
    return wear == null || wear <= 0 ? null : ((_percent - _lowLifePct) / wear).floor();
  }

  /// 마모가 빠른지: 새 타이어가 수명 30%까지 가는 랩 수가 AI가 같은 컴파운드로 탄 랩 수보다 짧다.
  /// 고정 기준(랩당 몇 %)은 레이스 길이마다 맞지 않아 AI 스틴트 길이와 견준다. 둘 중 하나라도 모르면 false.
  bool get wearsFast {
    final laps = lapsToLowLife;
    final field = fieldStintLaps;
    return laps != null && field != null && laps < field;
  }

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
      fieldStintLaps: jsonInt(json['fieldStintLaps']),
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

String _pct(double fraction) => '${(fraction * _percent).round()}%';

/// 배터리 양(kJ)을 배터리 게이지 %로(한 통 4MJ = 100%, `8%`).
String batteryShareOfKj(num kj) => _pct(kj * _joulesPerKj / kErsCapacityJ);

/// 문장에 쓰는 타이어 이름(소프트·미디엄·하드·인터·웻, 모르는 이름은 그대로).
String compoundName(String compound) => switch (compound) {
      'Soft' => '소프트',
      'Medium' => '미디엄',
      'Hard' => '하드',
      'Intermediate' => '인터',
      'Wet' => '웻',
      _ => compound,
    };

/// 문장에 쓰는 스틴트 이름(`미디엄(1~9랩)`).
String stintName(String compound, int startLap, int endLap) => '${compoundName(compound)}($startLap~$endLap랩)';

/// 끝 글자 받침에 맞춘 조사를 붙인다(`미디엄이`·`소프트가`). [rieulAsVowel]이면 ㄹ 받침도 받침 없음으로 본다(`로`/`으로`).
/// 괄호로 끝나면 괄호 앞 말에 맞춘다(`소프트(1~5랩)가`). 한글이 아닌 끝 글자는 받침이 있는 것으로 본다.
String withParticle(String word, String afterConsonant, String afterVowel, {bool rieulAsVowel = false}) {
  const hangulBase = 0xAC00;
  const hangulLast = 0xD7A3;
  const finals = 28;
  const rieul = 8;
  final open = word.endsWith(')') ? word.lastIndexOf('(') : -1;
  final head = open > 0 ? word.substring(0, open) : word;
  if (head.isEmpty) {
    return word;
  }
  final code = head.codeUnitAt(head.length - 1);
  if (code < hangulBase || code > hangulLast) {
    return '$word$afterConsonant';
  }
  final last = (code - hangulBase) % finals;
  return last == 0 || (rieulAsVowel && last == rieul) ? '$word$afterVowel' : '$word$afterConsonant';
}

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

String _sectorName(int index) => '${index + 1}섹터';

/// 페이스 평가: 수치는 그래프가 보여 주고, 줄은 섹터별 AI 비교·결과 앞뒤 차와의 섹터 비교·페이스 순위와 결과 순위가 어긋난 구간(실제 랩별 순위로).
ReviewSection paceReview(RacePaceReview pace, RaceStrategyReview strategy) {
  final lines = <String>[];
  final toField = sectorGaps(pace.mySectorMs, pace.fieldSectorMs);
  if (toField != null) {
    final slow = _slowestSector(toField);
    final fast = _fastestSector(toField);
    if (slow.gap >= kSectorMarginMs) {
      lines.add('${_sectorName(slow.sector)}에서 AI들의 보통 기록보다 랩당 ${_seconds(slow.gap)} 느려'
          '${fast.gap <= -kSectorMarginMs ? '. ${_sectorName(fast.sector)}는 ${_seconds(fast.gap)} 빨라' : ''}'
          ' → 랩 분석에서 ${_sectorName(slow.sector)} 코너들을 기준 랩과 겹쳐서 비교해 봐');
    } else if (fast.gap <= -kSectorMarginMs) {
      lines.add('${_sectorName(fast.sector)}에서 AI들의 보통 기록보다 랩당 ${_seconds(fast.gap)} 빨라. 여기가 네가 가장 강한 섹터야');
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
          ? '바로 앞 차($aheadName)는 랩당 ${_seconds(diff)} 빨랐어. 그중 ${_sectorName(slow.sector)}에서만 ${_seconds(slow.gap)} 차이가 나 '
              '→ ${_sectorName(slow.sector)}만 줄이면 따라잡을 수 있어'
          : '바로 앞 차($aheadName)는 랩당 ${_seconds(diff)} 빨랐어');
    } else {
      final fast = toAhead == null ? null : _fastestSector(toAhead);
      lines.add(fast != null && fast.gap <= -kSectorMarginMs
          ? '바로 앞 차($aheadName)보다 랩당 ${_seconds(diff)} 빨랐는데 못 넘었어. ${_sectorName(fast.sector)}에서 ${_seconds(fast.gap)} 더 빨랐으니 '
              '→ ${_sectorName(fast.sector)}에서 바짝 붙고, 이어지는 직선에서 배터리를 몰아서 써'
          : '바로 앞 차($aheadName)보다 랩당 ${_seconds(diff)} 빨랐는데 못 넘었어');
    }
  }
  final behind = pace.behindMedianMs;
  final behindName = pace.behindName;
  if (behind != null && behindName != null && behind < pace.myMedianMs) {
    lines.add('바로 뒤 차($behindName)가 랩당 ${_seconds(pace.myMedianMs - behind)} 빨랐는데 끝까지 잘 막아냈어');
  }
  final finish = strategy.finishPosition;
  if (finish != null) {
    final changes = positionChanges(strategy);
    if (finish < pace.rank) {
      final gained = [
        if (changes != null && changes.start > 0) '출발에서 ${changes.start}계단',
        if (changes != null && changes.track > 0) '달리면서 ${changes.track}계단',
      ];
      lines.add('페이스는 ${pace.rank}위였는데 $finish위로 들어왔어'
          '${gained.isEmpty ? '' : '. ${gained.join(', ')} 올라갔어'}');
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
    if (changes.pits < 0) '피트에 들어갔다 나오면서 ${-changes.pits}계단',
    if (changes.track < 0) '달리면서 ${-changes.track}계단',
  ];
  var line = lost.isEmpty ? head : '$head. ${lost.join(', ')} 잃었어';
  if (changes.pits < 0 && changes.track > 0) {
    line += '. 달리면서 ${changes.track}계단 되찾았지만 다 메우지는 못했어';
  }
  final common = strategy.commonStops;
  if (changes.pits < 0 && common != null && strategy.stops > common && !stopChoiceWorkedBest(strategy)) {
    line += ' → 다른 차들은 대부분 피트에 $common번 들어갔는데 우리는 ${strategy.stops}번 들어갔어. 피트에 덜 들어가면 그만큼 덜 잃어';
  }
  return line;
}

/// 피트 스톱 하나의 평가: 비슷한 때 들어간 차들(없으면 다른 차들 전체)보다 피트에서 시간을 많이 잃으면 아쉬움, 피트 뒤 순위를 얻으면 좋음.
/// 피트 직후 순위가 떨어지는 것은 피트 손실만큼 당연하므로 평가하지 않는다.
ReviewGrade pitStopGrade(RacePitStopReview stop, int? fieldLossMs) {
  final loss = stop.lossMs;
  final reference = stop.peerLossMs ?? fieldLossMs;
  final places = stop.placesGained;
  if (loss != null && reference != null && loss - reference >= kPitLossMarginMs) {
    return ReviewGrade.poor;
  }
  return places != null && places > 0 ? ReviewGrade.good : ReviewGrade.fair;
}

/// 시간을 더 잃은 스톱: 비슷한 때 들어간 차들(없으면 AI들 전체)과 견주고, 인 랩·아웃 랩을 나눠 더 잃은 쪽을 짚는다.
String _slowStopLine(RacePitStopReview stop, RaceStrategyReview strategy) {
  final peer = stop.peerLossMs != null;
  final extra = stop.lossMs! - (stop.peerLossMs ?? strategy.fieldPitLossMs!);
  final who = peer ? '비슷한 때 피트에 들어간 차들' : 'AI들';
  final head = '${stop.lap}랩 피트 스톱에서 $who보다 ${_seconds(extra)} 더 잃었어';
  final inLoss = stop.inLapLossMs;
  final outLoss = stop.outLapLossMs;
  final fieldIn = peer ? stop.peerInLapLossMs : strategy.fieldInLapLossMs;
  final fieldOut = peer ? stop.peerOutLapLossMs : strategy.fieldOutLapLossMs;
  if (inLoss == null || outLoss == null || fieldIn == null || fieldOut == null) {
    return head;
  }
  final extraIn = inLoss - fieldIn;
  final extraOut = outLoss - fieldOut;
  String versus(int ms) => '${_seconds(ms)} ${ms >= 0 ? '더' : '덜'} 걸렸';
  final split = '그 차들과 비교하면 피트로 들어가는 랩에서 ${versus(extraIn)}고, 피트에서 나오는 랩에서 ${versus(extraOut)}어';
  return extraIn >= extraOut
      ? '$head. $split → 들어가는 랩에서 더 잃었어. 피트 입구 직전에 속도를 줄이는 곳과 피트 레인에 들어가는 부분을 다시 봐'
      : '$head. $split → 나오는 랩에서 더 잃었어. 피트에서 나와 차가운 새 타이어로 도는 첫 랩을 다시 봐';
}

/// 내 스톱 수로 완주한 차들이 다른 스톱 수보다 높은 순위를 냈는지(견줄 다른 스톱 수가 없으면 false).
bool stopChoiceWorkedBest(RaceStrategyReview strategy) {
  final mine = strategy.stopGroups.where((g) => g.stops == strategy.stops && g.finishes.isNotEmpty).firstOrNull;
  final others = [for (final g in strategy.stopGroups) if (g.stops != strategy.stops && g.finishes.isNotEmpty) g.finishes.first];
  return mine != null && others.isNotEmpty && mine.finishes.first < others.reduce(math.min);
}

/// `피트에 2번 들어간`(0번이면 `피트에 들어가지 않은`).
String _stoppedText(int stops) => stops == 0 ? '피트에 들어가지 않은' : '피트에 $stops번 들어간';

/// `피트 2번`(0번이면 `피트에 안 들어가는 전략`).
String _stopsPlan(int stops) => stops == 0 ? '피트에 안 들어가는 전략' : '피트 $stops번';

/// 완주 순위 목록 `1, 3, 5위`(많으면 앞 몇 개와 `등`).
String _finishList(List<int> finishes) {
  final shown = finishes.take(_listedFinishes).join(', ');
  return finishes.length > _listedFinishes ? '$shown위 등' : '$shown위';
}

/// 상대 목록 `NORRIS(1위 출발 → 2위, 피트 2번)`(많으면 앞 몇 대와 `등 n대`).
String _rivalList(List<RaceStrategyRival> rivals) {
  final shown = rivals
      .take(_listedRivals)
      .map((r) => '${r.name}(${r.grid}위 출발 → ${r.finish}위, ${_stopsPlan(r.stops)})')
      .join(', ');
  return rivals.length > _listedRivals ? '$shown 등 ${rivals.length}대' : shown;
}

/// 전략 평가: 결과와 전략 선택으로 매긴다 — 피트 스톱 하나의 실행은 짚을 것으로만 남기고 평가를 혼자 정하지 않는다.
/// - 아쉬움: 나와 스톱 수가 다른 차가 뒤에서 출발해 앞에 [_rivalsAheadPoor]대 이상 들어왔거나(순위를 잃었으면 1대라도),
///   다른 스톱 수가 더 높은 순위를 내고 나는 순위를 잃었거나, 추정 대안이 [kStrategyPoorMs] 이상 빠르고 실제로도 내 스톱 수가 가장 잘 통하지 않았을 때.
/// - 좋음: 그 밖에 순위를 얻었거나 우승했거나, 내 스톱 수가 가장 높은 순위를 냈거나, 다른 전략으로 앞에서 출발한 차를 앞질렀을 때.
///
/// 줄: 스톱 수별 완주 순위와 어느 쪽이 통했는지, 순서가 뒤바뀐 상대, 비슷한 때 들어간 차들보다 시간을 더 잃은 스톱, 순위를 얻은 스톱.
/// [alternativeGainMs]·[alternativeStops]는 심층 분석의 가장 빠른 대안 전략(실제보다 빠른 시간, 스톱 수).
ReviewSection strategyReview(RaceStrategyReview strategy, {int? alternativeGainMs, int? alternativeStops}) {
  final lines = <String>[];
  final grid = strategy.gridPosition;
  final finish = strategy.finishPosition;
  final gained = grid != null && finish != null ? grid - finish : 0;

  final mine = strategy.stopGroups.where((g) => g.stops == strategy.stops && g.finishes.isNotEmpty).firstOrNull;
  final others = [for (final g in strategy.stopGroups) if (g.stops != strategy.stops && g.finishes.isNotEmpty) g];
  final bestOther = others.isEmpty ? null : others.reduce((a, b) => a.finishes.first <= b.finishes.first ? a : b);
  final choiceBest = stopChoiceWorkedBest(strategy);
  final choiceWorse = mine != null && bestOther != null && bestOther.finishes.first < mine.finishes.first;
  if (mine != null && bestOther != null) {
    final rest = others
        .map((g) => '${_stoppedText(g.stops)} ${g.finishes.length}대 중 가장 높은 순위는 ${g.finishes.first}위')
        .join(', ');
    final head = mine.finishes.length == 1
        ? '${_stoppedText(mine.stops)} 건 우리뿐이었고(${mine.finishes.single}위), $rest였어'
        : '${_stoppedText(mine.stops)} ${mine.finishes.length}대(우리 포함)는 ${_finishList(mine.finishes)}였고, $rest였어';
    lines.add(choiceBest
        ? '$head. 이번 레이스는 ${_stopsPlan(mine.stops)}이 가장 잘 통했고, 우리도 그렇게 갔어'
        : choiceWorse
            ? '$head → 이번 레이스는 ${_stopsPlan(bestOther.stops)}이 더 잘 통했어. 비슷한 레이스면 ${_stopsPlan(bestOther.stops)}도 생각해 봐'
            : head);
  }

  final ahead = [for (final r in strategy.rivals) if (finish != null && r.finish < finish) r];
  final behind = [for (final r in strategy.rivals) if (finish != null && r.finish > finish) r];
  if (ahead.isNotEmpty) {
    lines.add('다른 전략으로 너보다 뒤에서 출발해 앞에 들어온 차: ${_rivalList(ahead)} '
        '→ 그 차들이 언제 어떤 타이어로 바꿨는지 보고 다음 전략에 참고해');
  }
  if (behind.isNotEmpty) {
    lines.add('다른 전략으로 너보다 앞에서 출발했는데 뒤로 들어온 차: ${_rivalList(behind)}');
  }

  for (final stop in strategy.pitStops) {
    switch (pitStopGrade(stop, strategy.fieldPitLossMs)) {
      case ReviewGrade.poor:
        lines.add(_slowStopLine(stop, strategy));
      case ReviewGrade.good:
        lines.add('${stop.lap}랩 피트 스톱으로 순위가 ${stop.placesGained}계단 올라갔어');
      case ReviewGrade.fair:
        break;
    }
  }

  final alternativeBetter = alternativeGainMs != null &&
      alternativeGainMs >= kStrategyPoorMs &&
      !choiceBest &&
      alternativeStops != strategy.stops;
  final poor = ahead.length >= _rivalsAheadPoor || (ahead.isNotEmpty && gained < 0) || (choiceWorse && gained < 0) || alternativeBetter;
  final grade = poor
      ? ReviewGrade.poor
      : gained > 0 || finish == 1 || choiceBest || behind.isNotEmpty
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
      ? '앞 타이어가 랩마다 $front%씩 닳아서 뒤 타이어($rear%)보다 빨리 닳았어 → 코너에 들어갈 때 브레이크를 일찍 놓고 핸들을 덜 꺾어'
      : '뒤 타이어가 랩마다 $rear%씩 닳아서 앞 타이어($front%)보다 빨리 닳았어 → 코너를 나갈 때 스로틀을 천천히 열어서 뒷바퀴가 헛돌지 않게 해';
}

/// 타이어 평가: 스틴트 수치는 그림이 보여 주고, 줄은 스틴트마다 랩타임 추세(AI 대비)·앞뒤 마모로 본 원인·끝 수명과 마지막 랩 페이스.
ReviewSection tyreReview(List<RaceStintReview> stints) {
  final lines = <String>[];
  var worse = 0;
  var better = 0;
  for (final (i, stint) in stints.indexed) {
    final last = i == stints.length - 1;
    final label = stintName(stint.compound, stint.startLap, stint.endLap);
    final wear = stint.wearPerLapPct;
    final extra = stint.extraTrendMs;
    final fastWear = stint.wearsFast;
    final lostGrip = extra != null && extra >= kTrendMarginMs;
    if (lostGrip || fastWear) {
      worse++;
      final facts = [
        if (lostGrip) '랩이 지날수록 AI보다 랩당 ${_seconds(extra)}씩 더 느려졌어',
        if (fastWear && wear != null)
          '타이어가 랩마다 ${wear.toStringAsFixed(1)}%씩 닳아. 새 타이어라도 ${stint.lapsToLowLife}랩이면 수명이 30%만 남는데, '
              'AI는 이 타이어로 보통 ${stint.fieldStintLaps}랩을 탔어',
      ];
      final advice = _axleAdvice(stint);
      lines.add('$label: ${facts.join('. ')}${advice == null ? '' : '. $advice'}');
    } else if (extra != null && extra <= -kTrendMarginMs) {
      better++;
      lines.add('$label: 랩이 지날수록 느려지는 정도가 AI보다 랩당 ${_seconds(extra)} 작았어. 타이어 관리를 잘했어');
    }
    if (tyreLifeLine(stint, last: last) case final lifeLine?) {
      lines.add(lifeLine);
    }
  }
  final grade = worse > 0
      ? ReviewGrade.poor
      : better > 0
          ? ReviewGrade.good
          : ReviewGrade.fair;
  return (grade: grade, lines: lines);
}

/// 스틴트 끝 수명 줄: 수명을 너무 낮게까지 탔으면(마지막 랩 페이스와 함께) 또는 넉넉히 남기고 들어왔으면(마지막 스틴트 제외). 짚을 게 없으면 null.
String? tyreLifeLine(RaceStintReview stint, {required bool last}) {
  final label = stintName(stint.compound, stint.startLap, stint.endLap);
  final life = stint.endLifePct;
  final slower = stint.endLapsSlowerMs;
  if (life != null && life < _lowLifePct) {
    return slower != null && slower > 0
        ? '$label: 타이어 수명이 ${life.round()}% 남을 때까지 탔고, 마지막 몇 랩이 이 스틴트의 보통 랩보다 ${_seconds(slower)} 느렸어 '
            '→ 한두 랩 일찍 피트에 들어오면 그만큼 아낄 수 있어'
        : '$label: 타이어 수명이 ${life.round()}% 남을 때까지 탔는데 마지막 랩 페이스는 지켰어';
  }
  if (life != null && !last && life >= _earlyStopLifePct) {
    return '$label: 타이어 수명이 ${life.round()}% 남았을 때 들어왔어 → 이 스틴트를 더 끌면 피트 스톱을 한 번 줄일 수 있어';
  }
  return null;
}

/// 랩 번호 목록 `12랩, 13랩, 20랩`(많으면 앞 몇 개와 전체 랩 수).
String _lapList(List<int> laps) {
  final shown = laps.take(_listedLaps).map((l) => '$l랩').join(', ');
  return laps.length > _listedLaps ? '$shown을 포함한 ${laps.length}개 랩' : shown;
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
        ? '$head. 그 랩들은 평균보다 배터리를 ${batteryShareOfKj(deploy)} 더 썼어 → 효과가 작은 짧은 직선에서는 Overtake를 쓰지 말고 긴 직선에서만 써'
        : harvest != null && harvest < 0
            ? '$head. 그 랩들은 평균보다 배터리를 ${batteryShareOfKj(-harvest)} 덜 채웠어 → 브레이크 구간을 길게 가져가서 더 채워'
            : head);
  }
  if (battery.fullLaps >= _ersFlagLaps) {
    issues++;
    final flow = _flowVersusAverage(fullLaps, perLap);
    final where = fullLaps.isEmpty ? '${battery.fullLaps}랩' : _lapList([for (final l in fullLaps) l.lap]);
    final deploy = flow.deploy;
    lines.add(deploy != null && deploy < 0
        ? '$where에서 배터리가 꽉 찼어. 그 랩들은 평균보다 배터리를 ${batteryShareOfKj(-deploy)} 덜 썼어 '
            '→ 꽉 차면 더 채울 수 없으니 그 랩들은 Overtake로 더 써'
        : '$where에서 배터리가 꽉 찼어');
  }
  if (batteryLeftoverLine(battery) case final leftover?) {
    issues++;
    lines.add(leftover);
  }
  if (issues == 0) {
    lines.add('배터리가 바닥나거나 꽉 찬 랩 없이 잘 썼어. 끝날 때 배터리가 ${_pct(battery.lastStoreJ / kErsCapacityJ)} 남았어');
  }
  final grade = issues == 0
      ? ReviewGrade.good
      : issues == 1
          ? ReviewGrade.fair
          : ReviewGrade.poor;
  return (grade: grade, lines: lines);
}

/// 레이스 끝에 배터리를 많이 남겼으면 그 줄(아니면 null).
String? batteryLeftoverLine(RaceBatteryReview battery) => battery.lastStoreJ >= kErsCapacityJ * _ersLeftoverFraction
    ? '체커기를 받을 때 배터리가 ${_pct(battery.lastStoreJ / kErsCapacityJ)} 남아 있었어 → 마지막 두세 랩은 남김없이 다 써도 돼'
    : null;

/// 배터리가 거의 바닥·가득 찬 랩을 짚기 시작하는 횟수.
const int kErsFlagLaps = _ersFlagLaps;

/// 스틴트 끝 수명(%): 이 아래는 위험, 이 이상은 넉넉함(그림 색).
const double kLowTyreLifePct = _lowLifePct;
const double kHealthyTyreLifePct = _earlyStopLifePct;

/// 항목 이름.
const String kPaceSectionTitle = '페이스';
const String kStrategySectionTitle = '전략';
const String kTyreSectionTitle = '타이어 관리';
const String kBatterySectionTitle = '배터리 관리';

/// 총평의 항목들(데이터가 있는 것만, 페이스 → 전략 → 타이어 → 배터리).
/// [alternativeGainMs]·[alternativeStops]는 심층 분석의 가장 빠른 대안 전략(전략 평가에 쓴다, [strategyReview]).
List<({String title, ReviewSection section})> raceReviewSections(RaceReview review, {int? alternativeGainMs, int? alternativeStops}) {
  final pace = review.pace;
  final battery = review.battery;
  final strategy = review.strategy;
  return [
    if (pace != null) (title: kPaceSectionTitle, section: paceReview(pace, strategy)),
    if (strategy.gridPosition != null || strategy.pitStops.isNotEmpty)
      (
        title: kStrategySectionTitle,
        section: strategyReview(strategy, alternativeGainMs: alternativeGainMs, alternativeStops: alternativeStops),
      ),
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
    return '${withParticle(good.join(', '), '이', '가')} 좋았어. 잘 달렸어.';
  }
  if (good.isEmpty) {
    return '${poor.join(', ')}에서 시간을 잃었어. 하나씩 같이 보자.';
  }
  return '${withParticle(good.join(', '), '이', '가')} 좋았고, ${withParticle(poor.join(', '), '이', '가')} 아쉬웠어. 하나씩 같이 보자.';
}
