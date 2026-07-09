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

/// 개별 랩(무효 랩 포함, D-15/D-16).
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
