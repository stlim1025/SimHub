/// 시즌 가져오기 미리보기(`POST /me/seasons/import/preview`, docs/15 §12 D-55).
/// `drivers`·`constructors`는 가져온 뒤 시즌 화면에 나올 Standings와 같다.
class SeasonImportPreview {
  const SeasonImportPreview({
    required this.title,
    required this.gameMode,
    required this.teamName,
    required this.playerName,
    required this.documents,
    required this.rounds,
    required this.drivers,
    required this.constructors,
    required this.linkCandidate,
    required this.alreadyImported,
  });

  final String title;
  final String gameMode;
  final String? teamName;
  final String playerName;
  final List<SeasonImportDocument> documents;
  final List<SeasonImportRound> rounds;
  final List<SeasonImportDriver> drivers;
  final List<SeasonImportConstructor> constructors;
  final SeasonLinkCandidate? linkCandidate;

  /// true면 가져오기가 409다(이미 가져온 시즌).
  final bool alreadyImported;

  factory SeasonImportPreview.fromJson(Map<String, dynamic> json) => SeasonImportPreview(
        title: json['title'] as String,
        gameMode: json['gameMode'] as String,
        teamName: json['teamName'] as String?,
        playerName: json['playerName'] as String,
        documents: _list(json['documents'], SeasonImportDocument.fromJson),
        rounds: _list(json['rounds'], SeasonImportRound.fromJson),
        drivers: _list(json['drivers'], SeasonImportDriver.fromJson),
        constructors: _list(json['constructors'], SeasonImportConstructor.fromJson),
        linkCandidate: json['linkCandidate'] == null
            ? null
            : SeasonLinkCandidate.fromJson(json['linkCandidate'] as Map<String, dynamic>),
        alreadyImported: json['alreadyImported'] as bool? ?? false,
      );
}

/// 찾은 문서 하나. [kind] = `F1LapsSeason`·`InGameStandings`·`F1LapsSession`.
class SeasonImportDocument {
  const SeasonImportDocument({
    required this.kind,
    required this.title,
    required this.rounds,
    required this.sessions,
    required this.drivers,
  });

  final String kind;
  final String title;
  final int rounds;
  final int sessions;
  final int drivers;

  factory SeasonImportDocument.fromJson(Map<String, dynamic> json) => SeasonImportDocument(
        kind: json['kind'] as String,
        title: json['title'] as String,
        rounds: json['rounds'] as int,
        sessions: json['sessions'] as int,
        drivers: json['drivers'] as int,
      );
}

/// 만들 라운드 한 줄(캘린더 순서).
class SeasonImportRound {
  const SeasonImportRound({required this.round, required this.trackName, required this.sessions, required this.myPoints});

  final int round;
  final String trackName;
  final List<SeasonImportSession> sessions;
  final int? myPoints;

  factory SeasonImportRound.fromJson(Map<String, dynamic> json) => SeasonImportRound(
        round: json['round'] as int,
        trackName: json['trackName'] as String,
        sessions: _list(json['sessions'], SeasonImportSession.fromJson),
        myPoints: json['myPoints'] as int?,
      );
}

/// 라운드 안의 세션. [source] = `Imported`(가져온 세션)·`Recorded`(옮길 기록 세션).
class SeasonImportSession {
  const SeasonImportSession({
    required this.sessionType,
    required this.sessionKind,
    required this.source,
    required this.myPosition,
    required this.carCount,
    required this.lapCount,
  });

  final String sessionType;
  final String sessionKind;
  final String source;
  final int? myPosition;
  final int carCount;
  final int lapCount;

  bool get isRecorded => source == 'Recorded';

  factory SeasonImportSession.fromJson(Map<String, dynamic> json) => SeasonImportSession(
        sessionType: json['sessionType'] as String,
        sessionKind: json['sessionKind'] as String,
        source: json['source'] as String,
        myPosition: json['myPosition'] as int?,
        carCount: json['carCount'] as int? ?? 0,
        lapCount: json['lapCount'] as int? ?? 0,
      );
}

class SeasonImportDriver {
  const SeasonImportDriver({
    required this.position,
    required this.name,
    required this.teamName,
    required this.teamColor,
    required this.points,
    required this.isPlayer,
  });

  final int position;
  final String name;
  final String teamName;
  final String teamColor;
  final int points;
  final bool isPlayer;

  factory SeasonImportDriver.fromJson(Map<String, dynamic> json) => SeasonImportDriver(
        position: json['position'] as int,
        name: json['name'] as String,
        teamName: json['teamName'] as String,
        teamColor: json['teamColor'] as String,
        points: json['points'] as int,
        isPlayer: json['isPlayer'] as bool? ?? false,
      );
}

class SeasonImportConstructor {
  const SeasonImportConstructor({required this.position, required this.teamName, required this.teamColor, required this.points});

  final int position;
  final String teamName;
  final String teamColor;
  final int points;

  factory SeasonImportConstructor.fromJson(Map<String, dynamic> json) => SeasonImportConstructor(
        position: json['position'] as int,
        teamName: json['teamName'] as String,
        teamColor: json['teamColor'] as String,
        points: json['points'] as int,
      );
}

/// 연결할 게임 시즌(링크 ID)과 이 시즌으로 옮길 내 기록 세션들.
class SeasonLinkCandidate {
  const SeasonLinkCandidate({required this.seasonLinkId, required this.sessions});

  final int seasonLinkId;
  final List<SeasonLinkCandidateSession> sessions;

  factory SeasonLinkCandidate.fromJson(Map<String, dynamic> json) => SeasonLinkCandidate(
        seasonLinkId: json['seasonLinkId'] as int,
        sessions: _list(json['sessions'], SeasonLinkCandidateSession.fromJson),
      );
}

class SeasonLinkCandidateSession {
  const SeasonLinkCandidateSession({required this.sessionId, required this.kind, required this.trackName});

  final String sessionId;
  final String kind;
  final String trackName;

  factory SeasonLinkCandidateSession.fromJson(Map<String, dynamic> json) => SeasonLinkCandidateSession(
        sessionId: json['sessionId'] as String,
        kind: json['kind'] as String,
        trackName: json['trackName'] as String,
      );
}

List<T> _list<T>(Object? value, T Function(Map<String, dynamic>) fromJson) =>
    (value as List<dynamic>? ?? const []).map((e) => fromJson(e as Map<String, dynamic>)).toList();
