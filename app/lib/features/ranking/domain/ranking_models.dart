/// 옛 서버가 `displayOrder`를 주지 않을 때의 순서 값(목록은 서버 순서를 그대로 쓴다).
const int _unknownDisplayOrder = 0;

/// 트랙 마스터(04 §3.8). `GET /tracks`는 캘린더 순서(`displayOrder`)로 준다(D-43, docs/15 §4.1).
class Track {
  const Track({
    required this.trackId,
    required this.gameCode,
    required this.name,
    this.countryCode,
    this.displayOrder = _unknownDisplayOrder,
  });

  final String trackId;
  final String gameCode;
  final String name;

  /// ISO 3166-1 alpha-2 대문자. 모르면 null(회색 원 국기).
  final String? countryCode;

  /// F1 25 캘린더 순서(→ 리버스 → 그 밖).
  final int displayOrder;

  factory Track.fromJson(Map<String, dynamic> json) => Track(
        trackId: json['trackId'] as String,
        gameCode: json['gameCode'] as String,
        name: json['name'] as String,
        countryCode: json['countryCode'] as String?,
        displayOrder: json['displayOrder'] as int? ?? _unknownDisplayOrder,
      );
}

/// 랭킹 한 줄(04 §3.7 / 05 §3.4).
class RankingEntry {
  const RankingEntry({
    required this.rank,
    required this.displayName,
    required this.bestLapTimeMs,
    required this.setAt,
  });

  final int rank;
  final String displayName;
  final int bestLapTimeMs;
  final DateTime setAt;

  factory RankingEntry.fromJson(Map<String, dynamic> json) => RankingEntry(
        rank: json['rank'] as int,
        displayName: json['displayName'] as String,
        bestLapTimeMs: json['bestLapTimeMs'] as int,
        setAt: DateTime.parse(json['setAt'] as String),
      );
}

/// 트랙·기간별 TOP N 스냅샷. REST 초기 로드와 RankingHub 브로드캐스트가 동일 형태.
class RankingSnapshot {
  const RankingSnapshot({
    required this.trackId,
    required this.trackName,
    required this.gameCode,
    required this.period,
    required this.periodKey,
    required this.entries,
  });

  final String trackId;
  final String trackName;
  final String gameCode;
  final String period;
  final String periodKey;
  final List<RankingEntry> entries;

  factory RankingSnapshot.fromJson(Map<String, dynamic> json) => RankingSnapshot(
        trackId: json['trackId'] as String,
        trackName: (json['trackName'] as String?) ?? '',
        gameCode: json['gameCode'] as String,
        period: json['period'] as String,
        periodKey: json['periodKey'] as String,
        entries: (json['entries'] as List<dynamic>)
            .map((e) => RankingEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
