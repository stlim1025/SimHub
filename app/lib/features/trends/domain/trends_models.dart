/// 내 성과 추세(`GET /me/trends`, Trends 화면). 목록은 모두 시간 순(오래된 것부터)이다.
/// 차이 값은 "나 − 비교 대상"이라 음수면 내가 빠르다.
class Trends {
  const Trends({required this.races, required this.qualifying, required this.weeklyLaps, required this.tracks});

  final List<RaceTrend> races;
  final List<QualifyingTrend> qualifying;
  final List<WeeklyLaps> weeklyLaps;
  final List<TrackProgression> tracks;

  factory Trends.fromJson(Map<String, dynamic> json) => Trends(
        races: [for (final e in json['races'] as List<dynamic>) RaceTrend.fromJson(e as Map<String, dynamic>)],
        qualifying: [for (final e in json['qualifying'] as List<dynamic>) QualifyingTrend.fromJson(e as Map<String, dynamic>)],
        weeklyLaps: [for (final e in json['weeklyLaps'] as List<dynamic>) WeeklyLaps.fromJson(e as Map<String, dynamic>)],
        tracks: [for (final e in json['tracks'] as List<dynamic>) TrackProgression.fromJson(e as Map<String, dynamic>)],
      );
}

/// 레이스 한 판: 순위·AI 난이도, 팀메이트 대비 랩당 페이스, 필드(AI 최고 랩 중앙값) 대비 %, 꾸준함(깨끗한 랩 표준편차).
class RaceTrend {
  const RaceTrend({
    required this.sessionId,
    required this.classifiedAt,
    required this.trackName,
    required this.countryCode,
    required this.sessionKind,
    required this.isSprint,
    required this.gameMode,
    required this.aiDifficulty,
    required this.grid,
    required this.position,
    required this.resultStatus,
    required this.teammatePaceGapPerLapMs,
    required this.fieldPaceGapPercent,
    required this.consistencyMs,
    required this.cleanLaps,
  });

  final String sessionId;
  final DateTime classifiedAt;
  final String trackName;
  final String? countryCode;
  final String sessionKind;
  final bool isSprint;
  final String gameMode;
  final int? aiDifficulty;
  final int? grid;
  final int? position;
  final String? resultStatus;
  final int? teammatePaceGapPerLapMs;
  final double? fieldPaceGapPercent;
  final int? consistencyMs;
  final int? cleanLaps;

  factory RaceTrend.fromJson(Map<String, dynamic> json) => RaceTrend(
        sessionId: json['sessionId'] as String,
        classifiedAt: DateTime.parse(json['classifiedAt'] as String),
        trackName: json['trackName'] as String,
        countryCode: json['countryCode'] as String?,
        sessionKind: json['sessionKind'] as String,
        isSprint: json['isSprint'] as bool? ?? false,
        gameMode: json['gameMode'] as String? ?? '',
        aiDifficulty: json['aiDifficulty'] as int?,
        grid: json['grid'] as int?,
        position: json['position'] as int?,
        resultStatus: json['resultStatus'] as String?,
        teammatePaceGapPerLapMs: json['teammatePaceGapPerLapMs'] as int?,
        fieldPaceGapPercent: (json['fieldPaceGapPercent'] as num?)?.toDouble(),
        consistencyMs: json['consistencyMs'] as int?,
        cleanLaps: json['cleanLaps'] as int?,
      );
}

/// 주말 예선 하나: 마지막으로 달린 단계의 순위와 팀메이트 대비 최고 랩 차이.
class QualifyingTrend {
  const QualifyingTrend({
    required this.weekendId,
    required this.at,
    required this.trackName,
    required this.countryCode,
    required this.aiDifficulty,
    required this.position,
    required this.teammateGapMs,
    required this.teammateGapPercent,
  });

  final String weekendId;
  final DateTime at;
  final String trackName;
  final String? countryCode;
  final int? aiDifficulty;
  final int? position;
  final int? teammateGapMs;
  final double? teammateGapPercent;

  factory QualifyingTrend.fromJson(Map<String, dynamic> json) => QualifyingTrend(
        weekendId: json['weekendId'] as String,
        at: DateTime.parse(json['at'] as String),
        trackName: json['trackName'] as String,
        countryCode: json['countryCode'] as String?,
        aiDifficulty: json['aiDifficulty'] as int?,
        position: json['position'] as int?,
        teammateGapMs: json['teammateGapMs'] as int?,
        teammateGapPercent: (json['teammateGapPercent'] as num?)?.toDouble(),
      );
}

/// 한 주(월요일 시작)에 달린 랩 수.
class WeeklyLaps {
  const WeeklyLaps({required this.weekStart, required this.laps});

  final DateTime weekStart;
  final int laps;

  factory WeeklyLaps.fromJson(Map<String, dynamic> json) =>
      WeeklyLaps(weekStart: DateTime.parse(json['weekStart'] as String), laps: json['laps'] as int);
}

/// 트랙 하나의 최고 랩 변화(세션마다 세션 최고 랩과 그때까지의 최고 랩).
class TrackProgression {
  const TrackProgression({
    required this.trackId,
    required this.trackName,
    required this.countryCode,
    required this.lapCount,
    required this.points,
  });

  final String trackId;
  final String trackName;
  final String? countryCode;
  final int lapCount;
  final List<TrackProgressionPoint> points;

  factory TrackProgression.fromJson(Map<String, dynamic> json) => TrackProgression(
        trackId: json['trackId'] as String,
        trackName: json['trackName'] as String,
        countryCode: json['countryCode'] as String?,
        lapCount: json['lapCount'] as int,
        points: [for (final e in json['points'] as List<dynamic>) TrackProgressionPoint.fromJson(e as Map<String, dynamic>)],
      );
}

class TrackProgressionPoint {
  const TrackProgressionPoint({
    required this.at,
    required this.sessionType,
    required this.sessionBestMs,
    required this.bestSoFarMs,
  });

  final DateTime at;
  final String sessionType;
  final int sessionBestMs;
  final int bestSoFarMs;

  factory TrackProgressionPoint.fromJson(Map<String, dynamic> json) => TrackProgressionPoint(
        at: DateTime.parse(json['at'] as String),
        sessionType: json['sessionType'] as String,
        sessionBestMs: json['sessionBestMs'] as int,
        bestSoFarMs: json['bestSoFarMs'] as int,
      );
}
