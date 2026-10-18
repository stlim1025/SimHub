import 'dart:math' as math;

import '../../laps/domain/lap_models.dart';

/// 트레이스 해상도의 최솟값(m). 서버 검증은 1~50m(docs/15 §5) — 0 이하가 오면 이 값으로 본다.
const int _minResolutionM = 1;

/// JSON 숫자(정수·실수 모두) → double. 없거나 숫자가 아니면 null.
double? _doubleOrNull(Object? value) => value is num ? value.toDouble() : null;

/// JSON 숫자 → int(실수는 버림). 없거나 숫자가 아니면 null.
int? _intOrNull(Object? value) => value is num ? value.toInt() : null;

Map<String, dynamic>? _mapOrNull(Object? value) => value is Map<String, dynamic> ? value : null;

String? _stringOrNull(Object? value) => value is String ? value : null;

/// 바퀴 4개 값(docs/15 §3.1 `WheelSet`). 바퀴마다 null일 수 있다.
class WheelValues {
  const WheelValues({this.frontLeft, this.frontRight, this.rearLeft, this.rearRight});

  final double? frontLeft;
  final double? frontRight;
  final double? rearLeft;
  final double? rearRight;

  /// FL · FR · RL · RR 순서.
  List<double?> get ordered => [frontLeft, frontRight, rearLeft, rearRight];

  static WheelValues? fromJsonOrNull(Object? json) {
    final map = _mapOrNull(json);
    if (map == null) {
      return null;
    }
    return WheelValues(
      frontLeft: _doubleOrNull(map['frontLeft']),
      frontRight: _doubleOrNull(map['frontRight']),
      rearLeft: _doubleOrNull(map['rearLeft']),
      rearRight: _doubleOrNull(map['rearRight']),
    );
  }
}

/// 랩 끝의 차량 스냅샷(docs/15 §3.2·§4.2 `car`). 모든 필드는 각각 null일 수 있다.
/// 컴파운드는 게임 원래 번호(F1: 보이는 16 Soft·17 Medium·18 Hard·7 Inter·8 Wet)다.
class CarSnapshot {
  const CarSnapshot({
    this.visualTyreCompound,
    this.actualTyreCompound,
    this.tyreAgeLaps,
    this.tyreWearStart,
    this.tyreWearEnd,
    this.tyreDamage,
    this.brakeDamage,
    this.frontLeftWingDamage,
    this.frontRightWingDamage,
    this.rearWingDamage,
    this.floorDamage,
    this.diffuserDamage,
    this.sidepodDamage,
    this.gearboxDamage,
    this.engineDamage,
    this.fuelStartKg,
    this.fuelEndKg,
    this.fuelRemainingLaps,
    this.ersStoreStartJ,
    this.ersStoreEndJ,
    this.ersDeployedJ,
    this.ersHarvestedJ,
  });

  final int? visualTyreCompound;
  final int? actualTyreCompound;
  final int? tyreAgeLaps;

  /// 타이어 마모(%) — 랩 시작 값(없으면 null)과 끝 값.
  final WheelValues? tyreWearStart;
  final WheelValues? tyreWearEnd;

  /// 타이어·브레이크 손상(%).
  final WheelValues? tyreDamage;
  final WheelValues? brakeDamage;

  /// 차체 손상(%).
  final double? frontLeftWingDamage;
  final double? frontRightWingDamage;
  final double? rearWingDamage;
  final double? floorDamage;
  final double? diffuserDamage;
  final double? sidepodDamage;
  final double? gearboxDamage;
  final double? engineDamage;

  /// 연료(kg)와 남은 랩 수.
  final double? fuelStartKg;
  final double? fuelEndKg;
  final double? fuelRemainingLaps;

  /// ERS 저장량(J) 시작·끝과 이 랩의 배포·회수량(J).
  final double? ersStoreStartJ;
  final double? ersStoreEndJ;
  final double? ersDeployedJ;
  final double? ersHarvestedJ;

  static CarSnapshot? fromJsonOrNull(Object? json) {
    final map = _mapOrNull(json);
    if (map == null) {
      return null;
    }
    return CarSnapshot(
      visualTyreCompound: _intOrNull(map['visualTyreCompound']),
      actualTyreCompound: _intOrNull(map['actualTyreCompound']),
      tyreAgeLaps: _intOrNull(map['tyreAgeLaps']),
      tyreWearStart: WheelValues.fromJsonOrNull(map['tyreWearStart']),
      tyreWearEnd: WheelValues.fromJsonOrNull(map['tyreWearEnd']),
      tyreDamage: WheelValues.fromJsonOrNull(map['tyreDamage']),
      brakeDamage: WheelValues.fromJsonOrNull(map['brakeDamage']),
      frontLeftWingDamage: _doubleOrNull(map['frontLeftWingDamage']),
      frontRightWingDamage: _doubleOrNull(map['frontRightWingDamage']),
      rearWingDamage: _doubleOrNull(map['rearWingDamage']),
      floorDamage: _doubleOrNull(map['floorDamage']),
      diffuserDamage: _doubleOrNull(map['diffuserDamage']),
      sidepodDamage: _doubleOrNull(map['sidepodDamage']),
      gearboxDamage: _doubleOrNull(map['gearboxDamage']),
      engineDamage: _doubleOrNull(map['engineDamage']),
      fuelStartKg: _doubleOrNull(map['fuelStartKg']),
      fuelEndKg: _doubleOrNull(map['fuelEndKg']),
      fuelRemainingLaps: _doubleOrNull(map['fuelRemainingLaps']),
      ersStoreStartJ: _doubleOrNull(map['ersStoreStartJ']),
      ersStoreEndJ: _doubleOrNull(map['ersStoreEndJ']),
      ersDeployedJ: _doubleOrNull(map['ersDeployedJ']),
      ersHarvestedJ: _doubleOrNull(map['ersHarvestedJ']),
    );
  }
}

/// 랩 끝의 날씨·기온(docs/15 §4.2 `conditions`).
class LapConditions {
  const LapConditions({this.weather, this.airTempC, this.trackTempC, this.rainForecastPercent});

  final String? weather;
  final double? airTempC;
  final double? trackTempC;
  final int? rainForecastPercent;

  static LapConditions? fromJsonOrNull(Object? json) {
    final map = _mapOrNull(json);
    if (map == null) {
      return null;
    }
    return LapConditions(
      weather: _stringOrNull(map['weather']),
      airTempC: _doubleOrNull(map['airTempC']),
      trackTempC: _doubleOrNull(map['trackTempC']),
      rainForecastPercent: _intOrNull(map['rainForecastPercent']),
    );
  }
}

/// 비교 대상 = 같은 트랙·게임의 내 최고 유효 랩(D-46). 이 랩 자신일 수도 있다.
class ComparisonLap {
  const ComparisonLap({
    required this.lapId,
    required this.lapTimeMs,
    required this.sectors,
    required this.setAt,
    required this.hasTrace,
  });

  final String lapId;
  final int lapTimeMs;
  final List<LapSector> sectors;
  final DateTime setAt;
  final bool hasTrace;

  /// 비교 대상은 덤이라, 필수 값(Id·랩타임·시각)이 빠지거나 형식이 틀리면 null(비교 없음)로 보고 랩 상세는 그대로 보인다.
  static ComparisonLap? fromJsonOrNull(Object? json) {
    final map = _mapOrNull(json);
    final lapId = map?['lapId'];
    final lapTimeMs = _intOrNull(map?['lapTimeMs']);
    final setAt = DateTime.tryParse(_stringOrNull(map?['setAt']) ?? '');
    if (map == null || lapId is! String || lapTimeMs == null || setAt == null) {
      return null;
    }
    final rawSectors = map['sectors'];
    return ComparisonLap(
      lapId: lapId,
      lapTimeMs: lapTimeMs,
      sectors: [
        if (rawSectors is List)
          for (final sector in rawSectors) ?_sectorOrNull(sector),
      ],
      setAt: setAt,
      hasTrace: map['hasTrace'] == true,
    );
  }

  static LapSector? _sectorOrNull(Object? json) {
    final map = _mapOrNull(json);
    final number = _intOrNull(map?['sectorNumber']);
    final time = _intOrNull(map?['sectorTimeMs']);
    return number == null || time == null ? null : LapSector(sectorNumber: number, sectorTimeMs: time);
  }
}

/// `GET /me/laps/{lapId}` 응답(docs/15 §4.2 LapDetailResponse).
class LapDetail {
  const LapDetail({
    required this.lap,
    required this.trackId,
    this.countryCode,
    this.sessionId,
    this.car,
    this.conditions,
    this.comparison,
  });

  final Lap lap;
  final String trackId;
  final String? countryCode;

  /// 같은 SessionKey의 내 세션. 없으면 null.
  final String? sessionId;

  /// 차량 스냅샷. 옛 Agent로 기록한 랩이면 null.
  final CarSnapshot? car;
  final LapConditions? conditions;

  /// 내 최고 유효 랩. 유효 랩이 없으면 null.
  final ComparisonLap? comparison;

  /// 이 랩이 곧 내 최고 유효 랩인지.
  bool get isPersonalBest => comparison?.lapId == lap.lapId;

  factory LapDetail.fromJson(Map<String, dynamic> json) => LapDetail(
        lap: Lap.fromJson(json['lap'] as Map<String, dynamic>),
        trackId: json['trackId'] as String,
        countryCode: json['countryCode'] as String?,
        sessionId: json['sessionId'] as String?,
        car: CarSnapshot.fromJsonOrNull(json['car']),
        conditions: LapConditions.fromJsonOrNull(json['conditions']),
        comparison: ComparisonLap.fromJsonOrNull(json['comparison']),
      );
}

/// 1랩 텔레메트리 트레이스(docs/15 §3.3·§4.2, D-45). 표본 i의 랩 거리 = i × [resolutionM].
/// 채널 길이가 다르면 가장 짧은 길이로 자르고, 빠진 채널이 있으면 빈 트레이스로 본다.
class LapTrace {
  const LapTrace({
    required this.lapId,
    required this.resolutionM,
    required this.timeMs,
    required this.speedKph,
    required this.throttle,
    required this.brake,
    required this.steer,
    required this.gear,
    required this.rpm,
  });

  final String lapId;
  final int resolutionM;

  /// 랩 시작부터 ms.
  final List<int> timeMs;
  final List<int> speedKph;

  /// 0~100.
  final List<int> throttle;

  /// 0~100.
  final List<int> brake;

  /// −100~100.
  final List<int> steer;

  /// −1(R)~8, 0 = N.
  final List<int> gear;
  final List<int> rpm;

  int get length => timeMs.length;

  bool get isEmpty => length == 0;

  /// 표본 [index]의 랩 거리(m).
  double distanceAt(int index) => (index * resolutionM).toDouble();

  /// 마지막 표본의 거리(m). 빈 트레이스면 0.
  double get lengthM => isEmpty ? 0 : distanceAt(length - 1);

  factory LapTrace.fromJson(Map<String, dynamic> json) {
    const channels = ['timeMs', 'speedKph', 'throttle', 'brake', 'steer', 'gear', 'rpm'];
    final raw = [for (final name in channels) json[name]];
    // 빠진 채널이나 숫자가 아닌 표본이 하나라도 있으면 그 채널을 빈 것으로 본다 → 트레이스 전체가 빈 것이 된다
    // (0으로 채우면 속도·Delta에 가짜 급락이 그려진다).
    final lists = [
      for (final value in raw)
        if (value is List && value.every((e) => e is num)) [for (final e in value) (e as num).toInt()] else <int>[],
    ];
    final length = lists.map((l) => l.length).reduce(math.min);
    List<int> channel(int i) => List.unmodifiable(lists[i].take(length));
    return LapTrace(
      lapId: json['lapId'] as String,
      resolutionM: math.max(_minResolutionM, _intOrNull(json['resolutionM']) ?? _minResolutionM),
      timeMs: channel(0),
      speedKph: channel(1),
      throttle: channel(2),
      brake: channel(3),
      steer: channel(4),
      gear: channel(5),
      rpm: channel(6),
    );
  }
}
