import '../../laps/domain/lap_models.dart';
import 'session_detail_models.dart';
import 'session_display.dart' show knownPosition;

export 'session_detail_models.dart';

/// 세션 목록 한 줄(`GET /me/sessions`, docs/12 §7.2).
/// 내 차 결과가 없으면 `my*`가 모두 null이고, 시즌에 속하지 않으면 [seasonId]가 null이다.
/// 열거형(`sessionType`·`sessionKind`·`gameMode`·`myResultStatus`)은 서버가 준 문자열 그대로 둔다.
class SessionSummary {
  const SessionSummary({
    required this.sessionId,
    required this.classifiedAt,
    required this.trackName,
    required this.sessionType,
    required this.sessionKind,
    required this.gameMode,
    required this.seasonId,
    required this.carCount,
    required this.myPosition,
    required this.myGridPosition,
    required this.myResultStatus,
    required this.myBestLapTimeMs,
    required this.myPoints,
    this.countryCode,
    this.myTeam,
    this.seasonNumber,
    this.isSprintWeekend = false,
  });

  final String sessionId;
  final DateTime classifiedAt;
  final String trackName;

  /// `Practice`·`Qualifying`·`Race` 중 하나(Time Trial은 목록에 오지 않는다).
  final String sessionType;

  /// 세부 종류(`Race`, `Qualifying3`, `SprintShootout1` …). 표시는 `sessionKindLabel`.
  final String sessionKind;
  final String gameMode;
  final String? seasonId;
  final int carCount;
  final int? myPosition;
  final int? myGridPosition;
  final String? myResultStatus;

  /// 0(기록 없음)은 서버가 null로 내보낸다.
  final int? myBestLapTimeMs;
  final int? myPoints;

  /// 트랙 나라(ISO alpha-2, docs/15 §11.4). 옛 서버면 null.
  final String? countryCode;

  /// 내가 고른 팀(이름·색, D-52). 내 결과가 없거나 옛 서버면 null.
  final LapTeam? myTeam;

  /// 시즌 번호(1부터). 시즌이 아니면 null.
  final int? seasonNumber;

  /// 같은 주말에 Race2가 있다(스프린트 주말) — `Race` = 스프린트. 표시는 `sessionKindName(kind, sprintWeekend:)`.
  final bool isSprintWeekend;

  factory SessionSummary.fromJson(Map<String, dynamic> json) => SessionSummary(
        sessionId: json['sessionId'] as String,
        classifiedAt: DateTime.parse(json['classifiedAt'] as String),
        trackName: json['trackName'] as String,
        sessionType: json['sessionType'] as String,
        sessionKind: json['sessionKind'] as String,
        gameMode: json['gameMode'] as String,
        seasonId: json['seasonId'] as String?,
        carCount: json['carCount'] as int,
        // 순위 0 = 모름(옛 서버 대비) → null.
        myPosition: knownPosition(json['myPosition'] as int?),
        myGridPosition: knownPosition(json['myGridPosition'] as int?),
        myResultStatus: json['myResultStatus'] as String?,
        myBestLapTimeMs: json['myBestLapTimeMs'] as int?,
        myPoints: json['myPoints'] as int?,
        countryCode: jsonString(json['countryCode']),
        myTeam: LapTeam.fromJsonOrNull(json['myTeam']),
        seasonNumber: jsonInt(json['seasonNumber']),
        isSprintWeekend: json['isSprintWeekend'] == true,
      );
}

/// 세션 목록 한 페이지(`PagedResult<SessionSummaryDto>`).
class SessionSummaryPage {
  const SessionSummaryPage({
    required this.page,
    required this.pageSize,
    required this.total,
    required this.items,
  });

  final int page;
  final int pageSize;
  final int total;
  final List<SessionSummary> items;

  factory SessionSummaryPage.fromJson(Map<String, dynamic> json) => SessionSummaryPage(
        page: json['page'] as int,
        pageSize: json['pageSize'] as int,
        total: json['total'] as int,
        items: (json['items'] as List<dynamic>)
            .map((e) => SessionSummary.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// 세션 상세 헤더 = 목록 한 줄의 모든 필드 + 세션 설정(`SessionDetailDto.session`).
class SessionDetailHeader extends SessionSummary {
  const SessionDetailHeader({
    required super.sessionId,
    required super.classifiedAt,
    required super.trackName,
    required super.sessionType,
    required super.sessionKind,
    required super.gameMode,
    required super.seasonId,
    required super.carCount,
    required super.myPosition,
    required super.myGridPosition,
    required super.myResultStatus,
    required super.myBestLapTimeMs,
    required super.myPoints,
    super.countryCode,
    super.myTeam,
    super.seasonNumber,
    super.isSprintWeekend,
    required this.totalLaps,
    required this.aiDifficulty,
    required this.isNetworkGame,
    required this.round,
    this.weather,
    this.hasFieldSamples = false,
  });

  final int totalLaps;
  final int aiDifficulty;
  final bool isNetworkGame;

  /// 시즌 안의 라운드 번호. 시즌에 속하지 않으면 null.
  final int? round;

  /// 세션 날씨(`Clear`·`LightRain` …, docs/15 §11.4). 모르면 null.
  final String? weather;

  /// 이 세션의 모든 차 표본이 있는지(다른 차 베스트 랩을 복원해 내 랩과 비교할 수 있다).
  final bool hasFieldSamples;

  factory SessionDetailHeader.fromJson(Map<String, dynamic> json) {
    final summary = SessionSummary.fromJson(json);
    return SessionDetailHeader(
      sessionId: summary.sessionId,
      classifiedAt: summary.classifiedAt,
      trackName: summary.trackName,
      sessionType: summary.sessionType,
      sessionKind: summary.sessionKind,
      gameMode: summary.gameMode,
      seasonId: summary.seasonId,
      carCount: summary.carCount,
      myPosition: summary.myPosition,
      myGridPosition: summary.myGridPosition,
      myResultStatus: summary.myResultStatus,
      myBestLapTimeMs: summary.myBestLapTimeMs,
      myPoints: summary.myPoints,
      countryCode: summary.countryCode,
      myTeam: summary.myTeam,
      seasonNumber: summary.seasonNumber,
      isSprintWeekend: summary.isSprintWeekend,
      totalLaps: json['totalLaps'] as int,
      aiDifficulty: json['aiDifficulty'] as int,
      isNetworkGame: json['isNetworkGame'] as bool,
      round: json['round'] as int?,
      weather: jsonString(json['weather']),
      hasFieldSamples: json['hasFieldSamples'] == true,
    );
  }
}

/// 타이어 스틴트 하나(스틴트 번호 순서대로 담겨 온다).
class TyreStintView {
  const TyreStintView({
    required this.endLap,
    required this.visualCompound,
    required this.actualCompound,
  });

  final int endLap;

  /// 화면에 보이는 컴파운드(`Soft`·`Medium`·`Hard`·`Intermediate`·`Wet`·`Unknown`).
  final String visualCompound;

  /// 실제 컴파운드 라벨(`C0`~`C6`·`Inter`·`Wet`). 모르면 null.
  final String? actualCompound;

  factory TyreStintView.fromJson(Map<String, dynamic> json) => TyreStintView(
        endLap: json['endLap'] as int,
        visualCompound: json['visualCompound'] as String,
        actualCompound: json['actualCompound'] as String?,
      );
}

/// 세션 결과 한 줄(차 1대). 시간 필드의 0은 서버가 null로 내보낸다.
class SessionResult {
  const SessionResult({
    required this.position,
    required this.carIndex,
    required this.name,
    required this.teamId,
    required this.teamName,
    required this.teamColor,
    required this.raceNumber,
    required this.isAiControlled,
    required this.isPlayer,
    required this.gridPosition,
    required this.numLaps,
    required this.bestLapTimeMs,
    required this.isFastestLap,
    required this.totalRaceTimeMs,
    required this.penaltiesTimeMs,
    required this.numPenalties,
    required this.numPitStops,
    required this.points,
    required this.resultStatus,
    required this.tyreStints,
    this.gapMs,
    this.positionChange,
  });

  final int position;
  final int carIndex;
  final String name;
  final int? teamId;
  final String teamName;

  /// `#RRGGBB`. 화면에서는 `parseHexColor`로 바꾼다.
  final String teamColor;
  final int? raceNumber;
  final bool isAiControlled;
  final bool isPlayer;
  final int gridPosition;
  final int numLaps;
  final int? bestLapTimeMs;
  final bool isFastestLap;
  final int? totalRaceTimeMs;
  final int penaltiesTimeMs;
  final int numPenalties;
  final int numPitStops;
  final int points;
  final String resultStatus;
  final List<TyreStintView> tyreStints;

  /// 1위 대비 차(ms, 레이스 = 총 시간, 예선·연습 = 최고 랩, docs/15 §11.4). 옛 서버면 null.
  final int? gapMs;

  /// 그리드 − 순위(양수 = 올라감). 옛 서버면 null.
  final int? positionChange;

  factory SessionResult.fromJson(Map<String, dynamic> json) => SessionResult(
        position: json['position'] as int,
        carIndex: json['carIndex'] as int,
        name: json['name'] as String,
        teamId: json['teamId'] as int?,
        teamName: json['teamName'] as String,
        teamColor: json['teamColor'] as String,
        raceNumber: json['raceNumber'] as int?,
        isAiControlled: json['isAiControlled'] as bool,
        isPlayer: json['isPlayer'] as bool,
        gridPosition: json['gridPosition'] as int,
        numLaps: json['numLaps'] as int,
        bestLapTimeMs: json['bestLapTimeMs'] as int?,
        isFastestLap: json['isFastestLap'] as bool,
        totalRaceTimeMs: json['totalRaceTimeMs'] as int?,
        penaltiesTimeMs: json['penaltiesTimeMs'] as int,
        numPenalties: json['numPenalties'] as int,
        numPitStops: json['numPitStops'] as int,
        points: json['points'] as int,
        resultStatus: json['resultStatus'] as String,
        tyreStints: (json['tyreStints'] as List<dynamic>)
            .map((e) => TyreStintView.fromJson(e as Map<String, dynamic>))
            .toList(),
        gapMs: jsonInt(json['gapMs']),
        positionChange: jsonInt(json['positionChange']),
      );
}

/// 세션 상세 응답(`GET /me/sessions/{id}`): 헤더 + 결과(순위 오름차순) + P8 카드 데이터(docs/15 §11.4, 모두 선택).
class SessionDetail {
  const SessionDetail({
    required this.header,
    required this.results,
    this.qualifyingPositions = const [],
    this.myBestLap,
    this.setup,
    this.laps = const [],
    this.engineWear,
    this.tyreStints = const [],
    this.penalties = const [],
  });

  final SessionDetailHeader header;
  final List<SessionResult> results;

  /// 같은 주말 예선의 내 순위(예선 세션일 때).
  final List<QualifyingPosition> qualifyingPositions;
  final SessionBestLap? myBestLap;

  /// 마지막 랩의 셋업 키 → 값. 없으면 null.
  final Map<String, Object?>? setup;
  final List<SessionLap> laps;
  final EngineWear? engineWear;
  final List<SessionTyreStint> tyreStints;
  final List<SessionPenalty> penalties;

  factory SessionDetail.fromJson(Map<String, dynamic> json) => SessionDetail(
        header: SessionDetailHeader.fromJson(json['session'] as Map<String, dynamic>),
        results: (json['results'] as List<dynamic>)
            .map((e) => SessionResult.fromJson(e as Map<String, dynamic>))
            .toList(),
        qualifyingPositions: QualifyingPosition.listFromJson(json['qualifyingPositions']),
        myBestLap: SessionBestLap.fromJsonOrNull(json['myBestLap']),
        setup: setupFromJson(json['setup']),
        laps: jsonObjects(json['laps'], SessionLap.fromJsonOrNull),
        engineWear: EngineWear.fromJsonOrNull(json['engineWear']),
        tyreStints: jsonObjects(json['tyreStints'], SessionTyreStint.fromJsonOrNull),
        penalties: jsonObjects(json['penalties'], SessionPenalty.fromJsonOrNull),
      );
}
