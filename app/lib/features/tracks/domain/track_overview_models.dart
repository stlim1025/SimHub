import '../../../core/util/lap_time.dart';

/// 트랙 개요의 트랙 정보(`track`).
class TrackInfo {
  const TrackInfo({
    required this.trackId,
    required this.name,
    required this.gameCode,
    this.countryCode,
    this.circuitName,
    this.grandPrixName,
    this.lengthKm,
    this.f1LapRecord,
  });

  final String trackId;
  final String name;
  final String gameCode;
  final String? countryCode;
  final String? circuitName;
  final String? grandPrixName;
  final double? lengthKm;

  /// 실제 F1 랩 레코드 표시 글자(예: `1:24.125`). 서버가 밀리초 숫자로 주면 `m:ss.mmm`으로 바꿔 둔다.
  final String? f1LapRecord;

  factory TrackInfo.fromJson(Map<String, dynamic> json) => TrackInfo(
        trackId: json['trackId'] as String,
        name: json['name'] as String,
        gameCode: json['gameCode'] as String,
        countryCode: json['countryCode'] as String?,
        circuitName: json['circuitName'] as String?,
        grandPrixName: json['grandPrixName'] as String?,
        lengthKm: (json['lengthKm'] as num?)?.toDouble(),
        f1LapRecord: switch (json['f1LapRecord']) {
          final int ms => formatLapTime(ms),
          final String text when text.isNotEmpty => text,
          _ => null,
        },
      );
}

/// 그 트랙의 내 기록 요약(`myStats`).
class TrackMyStats {
  const TrackMyStats({
    required this.lapCount,
    required this.sessionCount,
    this.bestLapMs,
    this.bestTimeTrialLapMs,
    this.averageLapMs,
    this.averageAiDifficulty,
  });

  final int lapCount;
  final int sessionCount;
  final int? bestLapMs;
  final int? bestTimeTrialLapMs;
  final int? averageLapMs;
  final double? averageAiDifficulty;

  static const TrackMyStats empty = TrackMyStats(lapCount: 0, sessionCount: 0);

  factory TrackMyStats.fromJson(Map<String, dynamic> json) => TrackMyStats(
        lapCount: (json['lapCount'] as int?) ?? 0,
        sessionCount: (json['sessionCount'] as int?) ?? 0,
        bestLapMs: json['bestLapMs'] as int?,
        bestTimeTrialLapMs: json['bestTimeTrialLapMs'] as int?,
        averageLapMs: (json['averageLapMs'] as num?)?.round(),
        averageAiDifficulty: (json['averageAiDifficulty'] as num?)?.toDouble(),
      );
}

/// Time Trial 상위 기록 한 줄(`topTimeTrial`).
class TrackTopLap {
  const TrackTopLap({
    required this.rank,
    required this.displayName,
    required this.lapTimeMs,
    required this.lapId,
    this.teamName,
  });

  final int rank;
  final String displayName;
  final String? teamName;
  final int lapTimeMs;
  final String lapId;

  factory TrackTopLap.fromJson(Map<String, dynamic> json) => TrackTopLap(
        rank: json['rank'] as int,
        displayName: json['displayName'] as String,
        teamName: json['teamName'] as String?,
        lapTimeMs: json['lapTimeMs'] as int,
        lapId: json['lapId'] as String,
      );
}

/// 내 빠른 랩 한 줄(`myBestLaps`).
class TrackBestLap {
  const TrackBestLap({
    required this.lapId,
    required this.lapTimeMs,
    required this.sessionType,
    required this.isValid,
    required this.setAt,
    this.teamName,
  });

  final String lapId;
  final int lapTimeMs;
  final String sessionType;
  final String? teamName;
  final bool isValid;
  final DateTime setAt;

  factory TrackBestLap.fromJson(Map<String, dynamic> json) => TrackBestLap(
        lapId: json['lapId'] as String,
        lapTimeMs: json['lapTimeMs'] as int,
        sessionType: json['sessionType'] as String,
        teamName: json['teamName'] as String?,
        isValid: (json['isValid'] as bool?) ?? true,
        setAt: DateTime.parse(json['setAt'] as String),
      );
}

/// 트랙 개요(`GET /tracks/{trackId}/overview`). [mapLapId]가 있으면 그 랩의 트레이스로 트랙 지도를 그린다.
class TrackOverview {
  const TrackOverview({
    required this.track,
    required this.myStats,
    required this.topTimeTrial,
    required this.myBestLaps,
    this.mapLapId,
  });

  final TrackInfo track;
  final TrackMyStats myStats;
  final List<TrackTopLap> topTimeTrial;
  final List<TrackBestLap> myBestLaps;
  final String? mapLapId;

  factory TrackOverview.fromJson(Map<String, dynamic> json) => TrackOverview(
        track: TrackInfo.fromJson(json['track'] as Map<String, dynamic>),
        myStats: switch (json['myStats']) {
          final Map<String, dynamic> stats => TrackMyStats.fromJson(stats),
          _ => TrackMyStats.empty,
        },
        topTimeTrial: [
          for (final item in (json['topTimeTrial'] as List<dynamic>? ?? const []))
            TrackTopLap.fromJson(item as Map<String, dynamic>),
        ],
        myBestLaps: [
          for (final item in (json['myBestLaps'] as List<dynamic>? ?? const []))
            TrackBestLap.fromJson(item as Map<String, dynamic>),
        ],
        mapLapId: json['mapLapId'] as String?,
      );
}
