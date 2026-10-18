// 세션 상세 P8 추가 필드(docs/15 §11.4, D-53). 서버와 같이 개발 중이라 새 필드는 모두 선택이고,
// 형식이 틀린 항목은 버린다(화면 전체가 깨지지 않게 — 카드가 "데이터 없음"을 보여 준다).

/// JSON 숫자 → int. 정수가 아닌 수는 반올림, 숫자가 아니면 null.
int? jsonInt(Object? value) => switch (value) {
      final int v => v,
      final num v when v.isFinite => v.round(),
      _ => null,
    };

/// JSON 숫자 → double. 숫자가 아니거나 유한하지 않으면 null.
double? jsonDouble(Object? value) => value is num && value.isFinite ? value.toDouble() : null;

/// JSON 문자열. 빈 문자열·문자열이 아니면 null.
String? jsonString(Object? value) => value is String && value.isNotEmpty ? value : null;

bool jsonBool(Object? value) => value == true;

/// 객체 목록만 골라 [parse]한다. 목록이 아니면 빈 목록, [parse]가 null을 주는 항목은 버린다.
List<T> jsonObjects<T>(Object? value, T? Function(Map<String, dynamic> json) parse) {
  if (value is! List) {
    return const [];
  }
  return [
    for (final item in value)
      if (item is Map<String, dynamic>) ?parse(item),
  ];
}

/// 길이 [length]인 값 목록(모자라면 null로 채운다).
List<T?> _fixedList<T>(Object? value, T? Function(Object? item) parse, int length) {
  final items = value is List ? value : const <Object?>[];
  return [for (var i = 0; i < length; i++) i < items.length ? parse(items[i]) : null];
}

/// 섹터 수(F1 25 = 3, docs/15 §11.3).
const int kSessionSectorCount = 3;

/// 같은 주말 예선의 내 순위 한 칸(Q1 P6). 서버가 숫자만 주면 [label]은 순서대로 `Q1`·`Q2`….
class QualifyingPosition {
  const QualifyingPosition({required this.label, required this.position, this.sessionId});

  final String label;
  final int? position;
  final String? sessionId;

  /// 객체(`{sessionKind|label, position, sessionId?}`) 또는 숫자 목록을 읽는다(형식 미확정 — 둘 다 받는다).
  static List<QualifyingPosition> listFromJson(Object? value) {
    if (value is! List) {
      return const [];
    }
    final result = <QualifyingPosition>[];
    for (var i = 0; i < value.length; i++) {
      final item = value[i];
      final fallbackLabel = 'Q${i + 1}';
      if (item is Map<String, dynamic>) {
        result.add(QualifyingPosition(
          label: jsonString(item['label']) ?? qualifyingKindShort(jsonString(item['sessionKind'])) ?? fallbackLabel,
          position: jsonInt(item['position']),
          sessionId: jsonString(item['sessionId']),
        ));
      } else if (jsonInt(item) case final position?) {
        result.add(QualifyingPosition(label: fallbackLabel, position: position));
      }
    }
    return result;
  }
}

/// `Qualifying2` → `Q2`, `SprintShootout1` → `SQ1`, `OneShotQualifying` → `OSQ`. 모르면 null.
String? qualifyingKindShort(String? kind) => switch (kind) {
      'Qualifying1' => 'Q1',
      'Qualifying2' => 'Q2',
      'Qualifying3' => 'Q3',
      'ShortQualifying' => 'Q',
      'OneShotQualifying' => 'OSQ',
      'SprintShootout1' => 'SQ1',
      'SprintShootout2' => 'SQ2',
      'SprintShootout3' => 'SQ3',
      'ShortSprintShootout' => 'SQ',
      'OneShotSprintShootout' => 'OSSQ',
      _ => null,
    };

/// 세션 내 최고 랩(`myBestLap`). 랩 상세로 가는 링크.
class SessionBestLap {
  const SessionBestLap({required this.lapId, required this.lapTimeMs});

  final String? lapId;
  final int lapTimeMs;

  static SessionBestLap? fromJsonOrNull(Object? json) {
    if (json is! Map<String, dynamic>) {
      return null;
    }
    final time = jsonInt(json['lapTimeMs']);
    return time == null || time <= 0 ? null : SessionBestLap(lapId: jsonString(json['lapId']), lapTimeMs: time);
  }
}

/// Laps 카드 한 줄(내 차, docs/15 §11.3).
class SessionLap {
  const SessionLap({
    required this.lapNumber,
    this.position,
    this.positionChange,
    this.visualCompound,
    this.inPit = false,
    this.lapTimeMs,
    this.gapToBestMs,
    this.sectorsMs = const [null, null, null],
    this.isValid = true,
    this.isBestLap = false,
    this.bestSectors = const [false, false, false],
    this.lapId,
  });

  final int lapNumber;
  final int? position;

  /// 이전 랩 대비 순위 변동(양수 = 올라감).
  final int? positionChange;
  final String? visualCompound;
  final bool inPit;
  final int? lapTimeMs;

  /// 내 최고 랩 대비(0 = 최고 랩).
  final int? gapToBestMs;

  /// S1·S2·S3(ms). 길이는 항상 [kSessionSectorCount].
  final List<int?> sectorsMs;
  final bool isValid;

  /// 세션 최고 랩(보라).
  final bool isBestLap;

  /// 섹터마다 세션 최고 섹터인지(보라). 길이는 항상 [kSessionSectorCount].
  final List<bool> bestSectors;

  /// 이 랩이 저장돼 있으면 랩 상세 Id.
  final String? lapId;

  static SessionLap? fromJsonOrNull(Map<String, dynamic> json) {
    final number = jsonInt(json['lapNumber']);
    if (number == null) {
      return null;
    }
    final valid = json['isValid'];
    return SessionLap(
      lapNumber: number,
      position: jsonInt(json['position']),
      positionChange: jsonInt(json['positionChange']),
      visualCompound: jsonString(json['visualCompound']),
      inPit: jsonBool(json['inPit']),
      lapTimeMs: _positiveOrNull(jsonInt(json['lapTimeMs'])),
      gapToBestMs: jsonInt(json['gapToBestMs']),
      sectorsMs: _fixedList(json['sectors'], (v) => _positiveOrNull(jsonInt(v)), kSessionSectorCount),
      isValid: valid is bool ? valid : true,
      isBestLap: jsonBool(json['isBestLap']),
      bestSectors: [
        for (final flag in _fixedList(json['bestSectors'], (v) => v is bool ? v : null, kSessionSectorCount))
          flag ?? false,
      ],
      lapId: jsonString(json['lapId']),
    );
  }
}

int? _positiveOrNull(int? value) => value == null || value <= 0 ? null : value;

/// 엔진 부품 마모(%, 세션 마지막 내 랩).
class EngineWear {
  const EngineWear({
    this.ice,
    this.turboCharger,
    this.mguH,
    this.mguK,
    this.energyStore,
    this.controlElectronics,
    this.gearbox,
    this.engineDamage,
  });

  final double? ice;
  final double? turboCharger;
  final double? mguH;
  final double? mguK;
  final double? energyStore;
  final double? controlElectronics;
  final double? gearbox;
  final double? engineDamage;

  bool get isEmpty => [ice, turboCharger, mguH, mguK, energyStore, controlElectronics, gearbox, engineDamage]
      .every((v) => v == null);

  /// 객체가 아니거나 값이 하나도 없으면 null.
  static EngineWear? fromJsonOrNull(Object? json) {
    if (json is! Map<String, dynamic>) {
      return null;
    }
    final wear = EngineWear(
      ice: jsonDouble(json['ice']),
      turboCharger: jsonDouble(json['turboCharger']),
      mguH: jsonDouble(json['mguH']),
      mguK: jsonDouble(json['mguK']),
      energyStore: jsonDouble(json['energyStore']),
      controlElectronics: jsonDouble(json['controlElectronics']),
      gearbox: jsonDouble(json['gearbox']),
      engineDamage: jsonDouble(json['engineDamage']),
    );
    return wear.isEmpty ? null : wear;
  }
}

/// 스틴트 안 랩 하나(그래프 점).
class StintLap {
  const StintLap({required this.lapInStint, this.lapTimeMs, this.tyreLifeRemaining});

  /// 1부터.
  final int lapInStint;
  final int? lapTimeMs;

  /// 100 − 평균 마모(%).
  final double? tyreLifeRemaining;

  static StintLap? fromJsonOrNull(Map<String, dynamic> json) {
    final lap = jsonInt(json['lapInStint']);
    return lap == null
        ? null
        : StintLap(
            lapInStint: lap,
            lapTimeMs: _positiveOrNull(jsonInt(json['lapTimeMs'])),
            tyreLifeRemaining: jsonDouble(json['tyreLifeRemaining']),
          );
  }
}

/// 내 타이어 스틴트(그래프 선 하나).
class SessionTyreStint {
  const SessionTyreStint({required this.visualCompound, this.startLap, this.endLap, this.laps = const []});

  final String visualCompound;
  final int? startLap;
  final int? endLap;
  final List<StintLap> laps;

  static SessionTyreStint? fromJsonOrNull(Map<String, dynamic> json) => SessionTyreStint(
        visualCompound: jsonString(json['visualCompound']) ?? 'Unknown',
        startLap: jsonInt(json['startLap']),
        endLap: jsonInt(json['endLap']),
        laps: jsonObjects(json['laps'], StintLap.fromJsonOrNull),
      );
}

/// 패널티 한 건(Penalties 카드).
class SessionPenalty {
  const SessionPenalty({
    this.lap,
    this.carIndex,
    this.driverName,
    this.isPlayer = false,
    this.teamColor,
    this.infringement,
    this.penalty,
    this.timeS,
  });

  final int? lap;
  final int? carIndex;
  final String? driverName;
  final bool isPlayer;
  final String? teamColor;
  final String? infringement;
  final String? penalty;

  /// 시간 벌칙(초). 없으면 null.
  final int? timeS;

  static SessionPenalty? fromJsonOrNull(Map<String, dynamic> json) => SessionPenalty(
        lap: jsonInt(json['lap']),
        carIndex: jsonInt(json['carIndex']),
        driverName: jsonString(json['driverName']),
        isPlayer: jsonBool(json['isPlayer']),
        teamColor: jsonString(json['teamColor']),
        infringement: jsonString(json['infringement']),
        penalty: jsonString(json['penalty']),
        timeS: _positiveOrNull(jsonInt(json['timeS'])),
      );
}

/// 셋업(`setup`, 마지막 랩 `details.setup`) — 키 → 값 그대로. 객체가 아니거나 비면 null.
Map<String, Object?>? setupFromJson(Object? json) {
  if (json is! Map<String, dynamic> || json.isEmpty) {
    return null;
  }
  return Map<String, Object?>.unmodifiable(json);
}
