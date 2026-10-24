import 'dart:math' as math;

import '../../lap_detail/domain/ghost_replay.dart';
import 'session_detail_models.dart';

/// 하이라이트 장면 종류(서버 `HighlightKind` 이름 그대로).
enum HighlightKind { start, overtake, collision, crash, retirement, safetyCar, virtualSafetyCar, redFlag, finish, unknown }

/// 깃발 구간 종류(서버 `RaceFlagKind` 이름 그대로).
enum RaceFlagKind { safetyCar, virtualSafetyCar, redFlag, unknown }

/// 서버 enum 이름(`SafetyCar`) → Dart enum(`safetyCar`). 모르는 이름은 [fallback].
T _enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
  if (name is! String || name.isEmpty) {
    return fallback;
  }
  final lower = name[0].toLowerCase() + name.substring(1);
  return values.firstWhere((v) => v.name == lower, orElse: () => fallback);
}

/// 차 한 대의 이름표 재료(순위표).
class HighlightCar {
  const HighlightCar({
    required this.carIndex,
    required this.name,
    required this.teamColor,
    required this.isPlayer,
    required this.position,
  });

  final int carIndex;
  final String name;

  /// `#RRGGBB`(서버 팀 색). 모르면 null.
  final String? teamColor;
  final bool isPlayer;
  final int position;

  static HighlightCar? fromJsonOrNull(Map<String, dynamic> json) {
    final car = jsonInt(json['carIndex']);
    if (car == null) {
      return null;
    }
    return HighlightCar(
      carIndex: car,
      name: jsonString(json['name']) ?? '#$car',
      teamColor: jsonString(json['teamColor']),
      isPlayer: jsonBool(json['isPlayer']),
      position: jsonInt(json['position']) ?? 0,
    );
  }
}

/// 깃발 구간(세션 시간 ms).
class HighlightFlag {
  const HighlightFlag({required this.kind, required this.fromMs, required this.toMs});

  final RaceFlagKind kind;
  final int fromMs;
  final int toMs;

  static HighlightFlag? fromJsonOrNull(Map<String, dynamic> json) {
    final from = jsonInt(json['fromMs']);
    final to = jsonInt(json['toMs']);
    if (from == null || to == null) {
      return null;
    }
    return HighlightFlag(kind: _enumByName(RaceFlagKind.values, json['kind'], RaceFlagKind.unknown), fromMs: from, toMs: to);
  }
}

/// 클립 안 차 한 대의 움직임(같은 칸 = 같은 순간, 시간은 세션 ms, 시간 순).
class HighlightCarTrack {
  const HighlightCarTrack({
    required this.carIndex,
    required this.timeMs,
    required this.x,
    required this.z,
    required this.speedKph,
    required this.gear,
    required this.throttle,
    required this.brake,
    required this.lap,
  });

  final int carIndex;
  final List<int> timeMs;
  final List<double> x;
  final List<double> z;
  final List<int> speedKph;
  final List<int> gear;
  final List<int> throttle;
  final List<int> brake;
  final List<int> lap;

  int get length => timeMs.length;

  /// 열 길이가 다르거나 비었으면 null(그 차만 버린다).
  static HighlightCarTrack? fromJsonOrNull(Map<String, dynamic> json) {
    final car = jsonInt(json['carIndex']);
    List<int> ints(String key) => [for (final v in (json[key] as List<dynamic>? ?? const [])) jsonInt(v) ?? 0];
    List<double> doubles(String key) => [for (final v in (json[key] as List<dynamic>? ?? const [])) jsonDouble(v) ?? 0];
    final time = ints('timeMs');
    final x = doubles('x');
    final z = doubles('z');
    final speed = ints('speedKph');
    final gear = ints('gear');
    final throttle = ints('throttle');
    final brake = ints('brake');
    final lap = ints('lap');
    final n = time.length;
    if (car == null || n == 0 || [x, z, speed, gear, throttle, brake, lap].any((c) => c.length != n)) {
      return null;
    }
    return HighlightCarTrack(
      carIndex: car,
      timeMs: time,
      x: x,
      z: z,
      speedKph: speed,
      gear: gear,
      throttle: throttle,
      brake: brake,
      lap: lap,
    );
  }
}

/// 하이라이트 클립 하나: 장면 종류·구간(세션 ms)·장면 순간·중심 차(카메라가 따라감)·상대 차·중심 차의 랩, 그리고 둘레 차들.
class HighlightClip {
  const HighlightClip({
    required this.kind,
    required this.startMs,
    required this.endMs,
    required this.eventMs,
    required this.focusCar,
    required this.otherCar,
    required this.lap,
    required this.cars,
  });

  final HighlightKind kind;
  final int startMs;
  final int endMs;
  final int eventMs;
  final int focusCar;
  final int? otherCar;
  final int lap;
  final List<HighlightCarTrack> cars;

  HighlightCarTrack? get focus => cars.where((c) => c.carIndex == focusCar).firstOrNull;

  /// 중심 차 움직임이 없거나 구간이 비면 null(그 클립만 버린다).
  static HighlightClip? fromJsonOrNull(Map<String, dynamic> json) {
    final start = jsonInt(json['startMs']);
    final end = jsonInt(json['endMs']);
    final focus = jsonInt(json['focusCar']);
    if (start == null || end == null || focus == null || end <= start) {
      return null;
    }
    final clip = HighlightClip(
      kind: _enumByName(HighlightKind.values, json['kind'], HighlightKind.unknown),
      startMs: start,
      endMs: end,
      eventMs: jsonInt(json['eventMs']) ?? start,
      focusCar: focus,
      otherCar: jsonInt(json['otherCar']),
      lap: jsonInt(json['lap']) ?? 1,
      cars: jsonObjects(json['cars'], HighlightCarTrack.fromJsonOrNull),
    );
    return clip.focus == null ? null : clip;
  }
}

/// 레이스 하이라이트(`GET /me/sessions/{id}/highlights`): 트랙, 차 이름표, 깃발 구간, 내 하이라이트·레이스 하이라이트 두 묶음.
class RaceHighlights {
  const RaceHighlights({
    required this.sessionId,
    required this.trackId,
    required this.gameCode,
    required this.totalLaps,
    required this.cars,
    required this.flags,
    required this.mine,
    required this.race,
  });

  final String sessionId;
  final String trackId;
  final String gameCode;
  final int totalLaps;
  final List<HighlightCar> cars;
  final List<HighlightFlag> flags;
  final List<HighlightClip> mine;
  final List<HighlightClip> race;

  factory RaceHighlights.fromJson(Map<String, dynamic> json) => RaceHighlights(
        sessionId: json['sessionId'] as String,
        trackId: json['trackId'] as String,
        gameCode: json['gameCode'] as String,
        totalLaps: jsonInt(json['totalLaps']) ?? 0,
        cars: jsonObjects(json['cars'], HighlightCar.fromJsonOrNull),
        flags: jsonObjects(json['flags'], HighlightFlag.fromJsonOrNull),
        mine: jsonObjects(json['mine'], HighlightClip.fromJsonOrNull),
        race: jsonObjects(json['race'], HighlightClip.fromJsonOrNull),
      );

  HighlightCar? car(int carIndex) => cars.where((c) => c.carIndex == carIndex).firstOrNull;

  /// 차 이름(순위표에 없으면 `#번호`).
  String nameOf(int carIndex) => car(carIndex)?.name ?? '#$carIndex';
}

/// 장면 종류 이름(캡션).
const Map<HighlightKind, String> kHighlightKindLabels = {
  HighlightKind.start: '출발',
  HighlightKind.overtake: '추월',
  HighlightKind.collision: '충돌',
  HighlightKind.crash: '벽 충돌',
  HighlightKind.retirement: '리타이어',
  HighlightKind.safetyCar: '세이프티카',
  HighlightKind.virtualSafetyCar: '버추얼 세이프티카',
  HighlightKind.redFlag: '적기',
  HighlightKind.finish: '결승',
  HighlightKind.unknown: '장면',
};

/// 깃발 배너 글자.
const Map<RaceFlagKind, String> kRaceFlagLabels = {
  RaceFlagKind.safetyCar: '세이프티카',
  RaceFlagKind.virtualSafetyCar: '버추얼 세이프티카',
  RaceFlagKind.redFlag: '적기',
  RaceFlagKind.unknown: '깃발',
};

/// 깃발이 겹칠 때 앞서는 순서(클수록 앞선다): 적기 > 세이프티카 > 버추얼.
const Map<RaceFlagKind, int> _flagPriority = {
  RaceFlagKind.unknown: 0,
  RaceFlagKind.virtualSafetyCar: 1,
  RaceFlagKind.safetyCar: 2,
  RaceFlagKind.redFlag: 3,
};

/// 클립 캡션: `12랩 · 추월 · A → B`, `12랩 · 충돌 · A ↔ B`, 출발은 `출발`, 결승은 `39랩 · 결승 · A`(순수 함수).
String highlightCaption(HighlightClip clip, String Function(int carIndex) nameOf) {
  final kind = kHighlightKindLabels[clip.kind]!;
  final focus = nameOf(clip.focusCar);
  final other = clip.otherCar == null ? null : nameOf(clip.otherCar!);
  final scene = switch (clip.kind) {
    HighlightKind.start => kind,
    HighlightKind.overtake when other != null => '$kind · $focus → $other',
    HighlightKind.collision when other != null => '$kind · $focus ↔ $other',
    HighlightKind.overtake ||
    HighlightKind.collision ||
    HighlightKind.crash ||
    HighlightKind.retirement ||
    HighlightKind.finish =>
      '$kind · $focus',
    _ => kind,
  };
  return clip.kind == HighlightKind.start ? scene : '${clip.lap}랩 · $scene';
}

/// 세션 시간 [timeMs]에 걸린 깃발(겹치면 적기 > 세이프티카 > 버추얼). 없으면 null(순수 함수).
RaceFlagKind? activeRaceFlag(List<HighlightFlag> flags, double timeMs) {
  RaceFlagKind? active;
  for (final flag in flags) {
    if (timeMs >= flag.fromMs &&
        timeMs <= flag.toMs &&
        (active == null || _flagPriority[flag.kind]! > _flagPriority[active]!)) {
      active = flag.kind;
    }
  }
  return active;
}

/// 클립 차 한 대를 세션 시간으로 따라가는 경로(순수 계산, [ReplayCar]). 표본 사이는 선형 보간하고,
/// 첫 표본 전·마지막 표본 뒤에는 그 자리에 멈춰 있다(리타이어한 차는 선 자리에 남는다).
/// 진행 방향은 지나온 경로 거리 앞뒤로 본다(멈춘 차는 마지막으로 움직인 방향).
class TimedCarPath implements ReplayCar {
  TimedCarPath(this.track) : _distances = _cumulative(track);

  final HighlightCarTrack track;

  /// 표본마다 첫 표본부터 달린 경로 거리(m).
  final List<double> _distances;

  static List<double> _cumulative(HighlightCarTrack track) {
    final result = List<double>.filled(track.length, 0);
    for (var i = 1; i < track.length; i++) {
      final dx = track.x[i] - track.x[i - 1];
      final dz = track.z[i] - track.z[i - 1];
      result[i] = result[i - 1] + math.sqrt(dx * dx + dz * dz);
    }
    return result;
  }

  /// [elapsedMs]의 소수 표본 번호(0 ~ length−1).
  double _positionAt(double elapsedMs) {
    final times = track.timeMs;
    final last = track.length - 1;
    if (last == 0 || elapsedMs <= times.first) {
      return 0;
    }
    if (elapsedMs >= times[last]) {
      return last.toDouble();
    }
    var low = 0;
    var high = last;
    while (high - low > 1) {
      final mid = (low + high) ~/ 2;
      if (times[mid] <= elapsedMs) {
        low = mid;
      } else {
        high = mid;
      }
    }
    final span = times[high] - times[low];
    return low + (span <= 0 ? 0.0 : (elapsedMs - times[low]) / span);
  }

  static double _lerp(List<num> values, double position) {
    final lower = position.floor();
    if (lower >= values.length - 1) {
      return values.last.toDouble();
    }
    return values[lower] + (values[lower + 1] - values[lower]) * (position - lower);
  }

  /// 경로 거리 [distanceM]의 위치(앞뒤 표본 보간, 경로 밖은 양 끝).
  ({double x, double z}) _pointAtDistance(double distanceM) {
    final d = distanceM.clamp(0.0, _distances.last);
    var low = 0;
    var high = _distances.length - 1;
    while (high - low > 1) {
      final mid = (low + high) ~/ 2;
      if (_distances[mid] <= d) {
        low = mid;
      } else {
        high = mid;
      }
    }
    final span = _distances[high] - _distances[low];
    final t = span <= 0 ? 0.0 : (d - _distances[low]) / span;
    return (x: track.x[low] + (track.x[high] - track.x[low]) * t, z: track.z[low] + (track.z[high] - track.z[low]) * t);
  }

  double _headingAtDistance(double distanceM, double lookM) {
    final behind = _pointAtDistance(distanceM - lookM);
    final ahead = _pointAtDistance(distanceM + lookM);
    final dx = ahead.x - behind.x;
    final dz = ahead.z - behind.z;
    return dx == 0 && dz == 0 ? 0 : math.atan2(dz, dx);
  }

  @override
  double headingAt(double elapsedMs, {required double lookM}) =>
      _headingAtDistance(_lerp(_distances, _positionAt(elapsedMs)), lookM);

  @override
  ReplayFrame frameAt(double elapsedMs) {
    final position = _positionAt(elapsedMs);
    final distance = _lerp(_distances, position);
    return (
      x: _lerp(track.x, position),
      z: _lerp(track.z, position),
      heading: _headingAtDistance(distance, kReplayHeadingLookM),
      distanceM: distance,
      speedKph: _lerp(track.speedKph, position),
      gear: track.gear[position.floor()],
      rpm: 0,
      throttle: _lerp(track.throttle, position).round(),
      brake: _lerp(track.brake, position).round(),
      finished: false,
      batteryPercent: null,
      ersFlowKw: null,
    );
  }
}
