/// 시즌 AI 난이도 가이드(`GET /me/seasons/{id}/ai-difficulty`, 시즌 상세 AI 탭).
/// 같은 차를 탄 AI 팀메이트와의 차이로 지금 난이도가 맞는지 본다(차 성능 차이가 빠진다).
/// 차이 값은 모두 "나 − 팀메이트"라 음수면 내가 빠르다.
class SeasonAiDifficulty {
  const SeasonAiDifficulty({
    required this.currentAiDifficulty,
    required this.qualifying,
    required this.race,
    required this.car,
    required this.weekends,
    required this.timeTrial,
  });

  /// 가장 최근 레이스(없으면 예선)의 AI 난이도. 모르면 null.
  final int? currentAiDifficulty;
  final AiVerdict qualifying;
  final AiVerdict race;
  final AiCarLevel car;
  final List<AiWeekend> weekends;
  final List<AiTimeTrialRow> timeTrial;

  factory SeasonAiDifficulty.fromJson(Map<String, dynamic> json) => SeasonAiDifficulty(
        currentAiDifficulty: json['currentAiDifficulty'] as int?,
        qualifying: AiVerdict.fromJson(json['qualifying'] as Map<String, dynamic>),
        race: AiVerdict.fromJson(json['race'] as Map<String, dynamic>),
        car: AiCarLevel.fromJson(json['car'] as Map<String, dynamic>),
        weekends: [for (final e in json['weekends'] as List<dynamic>) AiWeekend.fromJson(e as Map<String, dynamic>)],
        timeTrial: [for (final e in json['timeTrial'] as List<dynamic>) AiTimeTrialRow.fromJson(e as Map<String, dynamic>)],
      );
}

/// 판정 종류(서버 문자열).
enum AiVerdictKind {
  raise,
  keep,
  lower,
  notEnoughData;

  static AiVerdictKind parse(String? value) => switch (value) {
        'Raise' => raise,
        'Keep' => keep,
        'Lower' => lower,
        _ => notEnoughData,
      };
}

/// 예선 또는 레이스 판정. [steps]는 바꿀 폭 추정(`1-2`·`3+`), 적정·데이터 부족이면 null.
/// [medianGapPercent]·[medianGapMs]는 팀메이트 대비 중앙값(레이스는 랩당), [samples]는 판정에 쓴 세션 수.
class AiVerdict {
  const AiVerdict({
    required this.kind,
    required this.steps,
    required this.medianGapPercent,
    required this.medianGapMs,
    required this.samples,
    required this.aheadOfTeammate,
  });

  final AiVerdictKind kind;
  final String? steps;
  final double? medianGapPercent;
  final int? medianGapMs;
  final int samples;
  final int aheadOfTeammate;

  factory AiVerdict.fromJson(Map<String, dynamic> json) => AiVerdict(
        kind: AiVerdictKind.parse(json['verdict'] as String?),
        steps: json['steps'] as String?,
        medianGapPercent: (json['medianGapPercent'] as num?)?.toDouble(),
        medianGapMs: json['medianGapMs'] as int?,
        samples: json['samples'] as int? ?? 0,
        aheadOfTeammate: json['aheadOfTeammate'] as int? ?? 0,
      );
}

/// 차 성능 위치(시즌 평균 순위). 팀메이트 값이 이 차의 수준이다.
class AiCarLevel {
  const AiCarLevel({
    required this.teammateQualiPosition,
    required this.teammateRacePosition,
    required this.myQualiPosition,
    required this.myRacePosition,
  });

  final double? teammateQualiPosition;
  final double? teammateRacePosition;
  final double? myQualiPosition;
  final double? myRacePosition;

  factory AiCarLevel.fromJson(Map<String, dynamic> json) => AiCarLevel(
        teammateQualiPosition: (json['teammateQualiPosition'] as num?)?.toDouble(),
        teammateRacePosition: (json['teammateRacePosition'] as num?)?.toDouble(),
        myQualiPosition: (json['myQualiPosition'] as num?)?.toDouble(),
        myRacePosition: (json['myRacePosition'] as num?)?.toDouble(),
      );
}

/// 주말 한 줄: 예선(마지막 단계 순위, 둘 다 기록한 마지막 단계의 최고 랩 차이)과 레이스들.
class AiWeekend {
  const AiWeekend({
    required this.weekendId,
    required this.round,
    required this.trackName,
    required this.countryCode,
    required this.aiDifficulty,
    required this.weather,
    required this.teammateName,
    required this.myQualiPosition,
    required this.teammateQualiPosition,
    required this.qualiGapMs,
    required this.qualiGapPercent,
    required this.races,
  });

  final String weekendId;
  final int round;
  final String trackName;
  final String? countryCode;
  final int? aiDifficulty;

  /// 예선에서 내 랩들의 가장 나쁜 날씨(`Clear`…`Storm`). 모르면 null.
  final String? weather;
  final String? teammateName;
  final int? myQualiPosition;
  final int? teammateQualiPosition;
  final int? qualiGapMs;
  final double? qualiGapPercent;
  final List<AiRace> races;

  /// 본 레이스(스프린트가 아닌 마지막 레이스). 없으면 null.
  AiRace? get mainRace => races.where((r) => !r.isSprint).lastOrNull;

  /// 스프린트. 없으면 null.
  AiRace? get sprint => races.where((r) => r.isSprint).firstOrNull;

  factory AiWeekend.fromJson(Map<String, dynamic> json) => AiWeekend(
        weekendId: json['weekendId'] as String,
        round: json['round'] as int,
        trackName: json['trackName'] as String,
        countryCode: json['countryCode'] as String?,
        aiDifficulty: json['aiDifficulty'] as int?,
        weather: json['weather'] as String?,
        teammateName: json['teammateName'] as String?,
        myQualiPosition: json['myQualiPosition'] as int?,
        teammateQualiPosition: json['teammateQualiPosition'] as int?,
        qualiGapMs: json['qualiGapMs'] as int?,
        qualiGapPercent: (json['qualiGapPercent'] as num?)?.toDouble(),
        races: [for (final e in json['races'] as List<dynamic>) AiRace.fromJson(e as Map<String, dynamic>)],
      );
}

/// 레이스 한 판. [paceGapPerLapMs]는 둘 다 완주하고 랩 수가 같을 때만 있다.
class AiRace {
  const AiRace({
    required this.sessionId,
    required this.sessionKind,
    required this.isSprint,
    required this.myGrid,
    required this.myPosition,
    required this.teammatePosition,
    required this.paceGapPerLapMs,
    required this.paceGapPercent,
    required this.myResultStatus,
  });

  final String sessionId;
  final String sessionKind;
  final bool isSprint;
  final int? myGrid;
  final int? myPosition;
  final int? teammatePosition;
  final int? paceGapPerLapMs;
  final double? paceGapPercent;
  final String? myResultStatus;

  factory AiRace.fromJson(Map<String, dynamic> json) => AiRace(
        sessionId: json['sessionId'] as String,
        sessionKind: json['sessionKind'] as String,
        isSprint: json['isSprint'] as bool? ?? false,
        myGrid: json['myGrid'] as int?,
        myPosition: json['myPosition'] as int?,
        teammatePosition: json['teammatePosition'] as int?,
        paceGapPerLapMs: json['paceGapPerLapMs'] as int?,
        paceGapPercent: (json['paceGapPercent'] as num?)?.toDouble(),
        myResultStatus: json['myResultStatus'] as String?,
      );
}

/// 타임트라이얼 비교 한 줄: 내 TT 최고 랩 vs 그 주말 마른 노면 예선의 가장 빠른 AI 랩. [gapPercent] 음수 = TT가 빠름.
class AiTimeTrialRow {
  const AiTimeTrialRow({
    required this.weekendId,
    required this.trackName,
    required this.countryCode,
    required this.timeTrialBestMs,
    required this.aiFastestQualiMs,
    required this.aiDifficulty,
    required this.gapPercent,
  });

  final String weekendId;
  final String trackName;
  final String? countryCode;
  final int timeTrialBestMs;
  final int aiFastestQualiMs;
  final int aiDifficulty;
  final double gapPercent;

  factory AiTimeTrialRow.fromJson(Map<String, dynamic> json) => AiTimeTrialRow(
        weekendId: json['weekendId'] as String,
        trackName: json['trackName'] as String,
        countryCode: json['countryCode'] as String?,
        timeTrialBestMs: json['timeTrialBestMs'] as int,
        aiFastestQualiMs: json['aiFastestQualiMs'] as int,
        aiDifficulty: json['aiDifficulty'] as int,
        gapPercent: (json['gapPercent'] as num).toDouble(),
      );
}
