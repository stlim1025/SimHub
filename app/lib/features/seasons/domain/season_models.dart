/// 시즌 목록 한 줄(`GET /me/seasons`, docs/12 §7.2).
/// 내가 결과에 없으면 `my*`가, 결과가 하나도 없으면 `leader*`가 null이다.
/// `gameMode`는 서버가 준 문자열 그대로 두고 표시는 `gameModeLabel`이 맡는다.
class SeasonSummary {
  const SeasonSummary({
    required this.seasonId,
    required this.gameCode,
    required this.gameMode,
    required this.firstSessionAt,
    required this.lastSessionAt,
    required this.roundCount,
    required this.myPosition,
    required this.myPoints,
    required this.leaderName,
    required this.leaderPoints,
  });

  final String seasonId;
  final String gameCode;
  final String gameMode;
  final DateTime firstSessionAt;
  final DateTime lastSessionAt;
  final int roundCount;
  final int? myPosition;
  final int? myPoints;
  final String? leaderName;
  final int? leaderPoints;

  factory SeasonSummary.fromJson(Map<String, dynamic> json) => SeasonSummary(
        seasonId: json['seasonId'] as String,
        gameCode: json['gameCode'] as String,
        gameMode: json['gameMode'] as String,
        firstSessionAt: DateTime.parse(json['firstSessionAt'] as String),
        lastSessionAt: DateTime.parse(json['lastSessionAt'] as String),
        roundCount: json['roundCount'] as int,
        myPosition: json['myPosition'] as int?,
        myPoints: json['myPoints'] as int?,
        leaderName: json['leaderName'] as String?,
        leaderPoints: json['leaderPoints'] as int?,
      );
}

/// 시즌 목록 한 페이지(`PagedResult<SeasonSummaryDto>`).
class SeasonSummaryPage {
  const SeasonSummaryPage({
    required this.page,
    required this.pageSize,
    required this.total,
    required this.items,
  });

  final int page;
  final int pageSize;
  final int total;
  final List<SeasonSummary> items;

  factory SeasonSummaryPage.fromJson(Map<String, dynamic> json) => SeasonSummaryPage(
        page: json['page'] as int,
        pageSize: json['pageSize'] as int,
        total: json['total'] as int,
        items: (json['items'] as List<dynamic>)
            .map((e) => SeasonSummary.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// 라운드(주말)에 속한 세션 하나. Season 탭의 세션 칩이 된다.
class SeasonRoundSession {
  const SeasonRoundSession({
    required this.sessionId,
    required this.sessionType,
    required this.sessionKind,
    required this.myPosition,
    required this.myResultStatus,
  });

  final String sessionId;
  final String sessionType;

  /// 세부 종류(`Race`, `Qualifying1` …). 칩 글자는 `sessionKindLabel`.
  final String sessionKind;

  /// 내 결과가 없으면 둘 다 null.
  final int? myPosition;
  final String? myResultStatus;

  factory SeasonRoundSession.fromJson(Map<String, dynamic> json) => SeasonRoundSession(
        sessionId: json['sessionId'] as String,
        sessionType: json['sessionType'] as String,
        sessionKind: json['sessionKind'] as String,
        myPosition: json['myPosition'] as int?,
        myResultStatus: json['myResultStatus'] as String?,
      );
}

/// 시즌의 한 라운드(= 기록된 주말 하나). 세션은 분류 시각 오름차순으로 온다.
class SeasonRound {
  const SeasonRound({
    required this.round,
    required this.weekendId,
    required this.trackName,
    required this.firstSessionAt,
    required this.winnerName,
    required this.myPoints,
    required this.sessions,
  });

  final int round;
  final String weekendId;
  final String trackName;
  final DateTime firstSessionAt;

  /// 본 레이스 1위. 본 레이스가 없으면 null.
  final String? winnerName;

  /// 그 주말 내 점수 합. 내 결과가 없으면 null.
  final int? myPoints;
  final List<SeasonRoundSession> sessions;

  factory SeasonRound.fromJson(Map<String, dynamic> json) => SeasonRound(
        round: json['round'] as int,
        weekendId: json['weekendId'] as String,
        trackName: json['trackName'] as String,
        firstSessionAt: DateTime.parse(json['firstSessionAt'] as String),
        winnerName: json['winnerName'] as String?,
        myPoints: json['myPoints'] as int?,
        sessions: (json['sessions'] as List<dynamic>)
            .map((e) => SeasonRoundSession.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// 결과표(Results 탭)의 한 칸: 드라이버 × 라운드.
/// 그 라운드에 본 레이스 기록이 없으면 [position]·[resultStatus]가 null이고 [points]만 남을 수 있다.
class StandingCell {
  const StandingCell({
    required this.round,
    required this.position,
    required this.resultStatus,
    required this.points,
  });

  final int round;
  final int? position;
  final String? resultStatus;
  final int points;

  factory StandingCell.fromJson(Map<String, dynamic> json) => StandingCell(
        round: json['round'] as int,
        position: json['position'] as int?,
        resultStatus: json['resultStatus'] as String?,
        points: json['points'] as int,
      );
}

/// Drivers 순위 한 줄. [cells]는 이 드라이버가 결과를 가진 라운드의 칸만 담는다.
class DriverStanding {
  const DriverStanding({
    required this.position,
    required this.driverKey,
    required this.name,
    required this.teamName,
    required this.teamColor,
    required this.isPlayer,
    required this.isAiControlled,
    required this.points,
    required this.wins,
    required this.podiums,
    required this.cells,
  });

  final int position;
  final String driverKey;
  final String name;
  final String teamName;

  /// `#RRGGBB`. 화면에서는 `TeamColorBar`/`parseHexColor`로 바꾼다.
  final String teamColor;
  final bool isPlayer;
  final bool isAiControlled;
  final int points;
  final int wins;
  final int podiums;
  final List<StandingCell> cells;

  factory DriverStanding.fromJson(Map<String, dynamic> json) => DriverStanding(
        position: json['position'] as int,
        driverKey: json['driverKey'] as String,
        name: json['name'] as String,
        teamName: json['teamName'] as String,
        teamColor: json['teamColor'] as String,
        isPlayer: json['isPlayer'] as bool,
        isAiControlled: json['isAiControlled'] as bool,
        points: json['points'] as int,
        wins: json['wins'] as int,
        podiums: json['podiums'] as int,
        cells: (json['cells'] as List<dynamic>)
            .map((e) => StandingCell.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// Constructors 순위 한 줄.
class ConstructorStanding {
  const ConstructorStanding({
    required this.position,
    required this.teamId,
    required this.teamName,
    required this.teamColor,
    required this.points,
    required this.wins,
  });

  final int position;
  final int teamId;
  final String teamName;
  final String teamColor;
  final int points;
  final int wins;

  factory ConstructorStanding.fromJson(Map<String, dynamic> json) => ConstructorStanding(
        position: json['position'] as int,
        teamId: json['teamId'] as int,
        teamName: json['teamName'] as String,
        teamColor: json['teamColor'] as String,
        points: json['points'] as int,
        wins: json['wins'] as int,
      );
}

/// 시즌 순위 스냅샷: 드라이버(칸 포함)와 컨스트럭터.
class SeasonStandings {
  const SeasonStandings({required this.drivers, required this.constructors});

  final List<DriverStanding> drivers;
  final List<ConstructorStanding> constructors;

  factory SeasonStandings.fromJson(Map<String, dynamic> json) => SeasonStandings(
        drivers: (json['drivers'] as List<dynamic>)
            .map((e) => DriverStanding.fromJson(e as Map<String, dynamic>))
            .toList(),
        constructors: (json['constructors'] as List<dynamic>)
            .map((e) => ConstructorStanding.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// 시즌 상세 응답(`GET /me/seasons/{id}`): 헤더 + 라운드 + Standings. 세 탭이 같은 스냅샷을 쓴다.
class SeasonDetail {
  const SeasonDetail({required this.season, required this.rounds, required this.standings});

  final SeasonSummary season;
  final List<SeasonRound> rounds;
  final SeasonStandings standings;

  factory SeasonDetail.fromJson(Map<String, dynamic> json) => SeasonDetail(
        season: SeasonSummary.fromJson(json['season'] as Map<String, dynamic>),
        rounds: (json['rounds'] as List<dynamic>)
            .map((e) => SeasonRound.fromJson(e as Map<String, dynamic>))
            .toList(),
        standings: SeasonStandings.fromJson(json['standings'] as Map<String, dynamic>),
      );
}
