/// 트랙 마스터(04 §3.8).
class Track {
  const Track({required this.trackId, required this.gameCode, required this.name});

  final String trackId;
  final String gameCode;
  final String name;

  factory Track.fromJson(Map<String, dynamic> json) => Track(
        trackId: json['trackId'] as String,
        gameCode: json['gameCode'] as String,
        name: json['name'] as String,
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
