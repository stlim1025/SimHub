/// 내 랩 목록 정렬(서버 `sort` 값, docs/11 §8). 기본은 최신순.
const String kLapSortRecent = 'recent';
const String kLapSortFastest = 'fastest';

/// 옛 서버가 `displayOrder`를 주지 않을 때의 순서 값(서버 순서를 그대로 쓰므로 표시에는 영향이 없다).
const int kUnknownDisplayOrder = 0;

/// 가변 섹터(D-7).
class LapSector {
  const LapSector({required this.sectorNumber, required this.sectorTimeMs});

  final int sectorNumber;
  final int sectorTimeMs;

  factory LapSector.fromJson(Map<String, dynamic> json) => LapSector(
        sectorNumber: json['sectorNumber'] as int,
        sectorTimeMs: json['sectorTimeMs'] as int,
      );
}

/// 랩 스냅샷의 팀(docs/15 §4.2 `team`). 백엔드 TeamCatalog(D-33)가 푼 이름·색.
class LapTeam {
  const LapTeam({required this.name, this.color});

  final String name;

  /// `#RRGGBB`. 화면에서는 `parseHexColor`로 바꾼다.
  final String? color;

  /// 객체가 아니거나 이름이 없으면 팀 없음(null).
  static LapTeam? fromJsonOrNull(Object? json) {
    if (json is! Map<String, dynamic>) {
      return null;
    }
    final name = json['name'];
    if (name is! String || name.isEmpty) {
      return null;
    }
    return LapTeam(name: name, color: json['color'] as String?);
  }
}

/// 개별 랩(무효 랩 포함, D-15/D-16). docs/15 §4.2의 추가 필드는 옛 서버·옛 랩을 위해 모두 없어도 읽는다.
class Lap {
  const Lap({
    required this.lapId,
    required this.trackName,
    required this.gameCode,
    required this.sessionType,
    required this.lapTimeMs,
    required this.sectors,
    required this.isValid,
    required this.isRankingEligible,
    required this.setAt,
    this.lapNumber,
    this.gameMode,
    this.team,
    this.weather,
    this.hasTrace = false,
    this.trackId,
  });

  final String lapId;
  final String trackName;
  final String gameCode;
  final String sessionType;
  final int lapTimeMs;
  final List<LapSector> sectors;
  final bool isValid;
  final bool isRankingEligible;
  final DateTime setAt;

  /// 세션 안의 랩 번호. 모르면 null.
  final int? lapNumber;

  /// 게임 모드(`DriverCareer` 등, 서버 문자열 그대로). 모르면(옛 랩) null.
  final String? gameMode;

  /// 스냅샷의 팀. 스냅샷이 없으면 null.
  final LapTeam? team;

  /// 날씨(`Clear`·`LightCloud`·`Overcast`·`LightRain`·`HeavyRain`·`Storm`). 모르면 null.
  final String? weather;

  /// 텔레메트리 트레이스가 저장됐는지(`GET /me/laps/{id}/trace`).
  final bool hasTrace;

  /// 트랙 Id. `GET /me/laps` 항목에는 없고, 실시간 `LapRecorded`(D-50, docs/15 §9)에만 실린다.
  final String? trackId;

  /// 실시간 페이로드처럼 모양을 믿을 수 없는 JSON을 읽는다. 필수 필드가 없거나 형식이 다르면 null.
  static Lap? tryParse(Map<String, dynamic> json) {
    try {
      return Lap.fromJson(json);
    } on TypeError {
      return null;
    } on FormatException {
      return null;
    }
  }

  factory Lap.fromJson(Map<String, dynamic> json) => Lap(
        lapId: json['lapId'] as String,
        trackName: json['trackName'] as String,
        gameCode: json['gameCode'] as String,
        sessionType: json['sessionType'] as String,
        lapTimeMs: json['lapTimeMs'] as int,
        sectors: (json['sectors'] as List<dynamic>)
            .map((e) => LapSector.fromJson(e as Map<String, dynamic>))
            .toList(),
        isValid: json['isValid'] as bool,
        isRankingEligible: json['isRankingEligible'] as bool,
        setAt: DateTime.parse(json['setAt'] as String),
        lapNumber: json['lapNumber'] as int?,
        gameMode: json['gameMode'] as String?,
        team: LapTeam.fromJsonOrNull(json['team']),
        weather: json['weather'] as String?,
        hasTrace: json['hasTrace'] as bool? ?? false,
        trackId: json['trackId'] as String?,
      );
}

/// 개인 최고(랭킹 적격 기준).
class PersonalBest {
  const PersonalBest({required this.trackId, required this.lapTimeMs, required this.setAt});

  final String trackId;
  final int lapTimeMs;
  final DateTime setAt;

  factory PersonalBest.fromJson(Map<String, dynamic> json) => PersonalBest(
        trackId: json['trackId'] as String,
        lapTimeMs: json['lapTimeMs'] as int,
        setAt: DateTime.parse(json['setAt'] as String),
      );
}

/// 내 랩이 1개 이상 있는 트랙 한 건(`GET /me/tracks`, docs/11 §8). 서버가 마지막 주행 순으로 준다.
/// [bestValidLapTimeMs]는 유효 랩 중 최소 랩타임이며, 유효 랩이 없으면 null.
class MyTrack {
  const MyTrack({
    required this.trackId,
    required this.trackName,
    required this.gameCode,
    required this.lapCount,
    required this.bestValidLapTimeMs,
    required this.lastSetAt,
    this.countryCode,
    this.displayOrder = kUnknownDisplayOrder,
  });

  final String trackId;
  final String trackName;
  final String gameCode;
  final int lapCount;
  final int? bestValidLapTimeMs;
  final DateTime lastSetAt;

  /// ISO 3166-1 alpha-2 대문자(D-43). 모르면 null(회색 원 국기).
  final String? countryCode;

  /// 캘린더 순서(D-43).
  final int displayOrder;

  factory MyTrack.fromJson(Map<String, dynamic> json) => MyTrack(
        trackId: json['trackId'] as String,
        trackName: json['trackName'] as String,
        gameCode: json['gameCode'] as String,
        lapCount: json['lapCount'] as int,
        bestValidLapTimeMs: json['bestValidLapTimeMs'] as int?,
        lastSetAt: DateTime.parse(json['lastSetAt'] as String),
        countryCode: json['countryCode'] as String?,
        displayOrder: json['displayOrder'] as int? ?? kUnknownDisplayOrder,
      );
}

/// 내 랩 기록 응답(04 §3.9).
class MyLaps {
  const MyLaps({
    required this.personalBest,
    required this.page,
    required this.pageSize,
    required this.total,
    required this.laps,
  });

  final PersonalBest? personalBest;
  final int page;
  final int pageSize;
  final int total;
  final List<Lap> laps;

  factory MyLaps.fromJson(Map<String, dynamic> json) {
    final pb = json['personalBest'] as Map<String, dynamic>?;
    final lapsNode = json['laps'] as Map<String, dynamic>;
    return MyLaps(
      personalBest: pb == null ? null : PersonalBest.fromJson(pb),
      page: lapsNode['page'] as int,
      pageSize: lapsNode['pageSize'] as int,
      total: lapsNode['total'] as int,
      laps: (lapsNode['items'] as List<dynamic>)
          .map((e) => Lap.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
