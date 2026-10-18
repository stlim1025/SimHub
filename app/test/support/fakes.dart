import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simcenter_app/core/config/app_config.dart';
import 'package:simcenter_app/core/network/api_exception.dart';
import 'package:simcenter_app/core/realtime/ranking_hub_client.dart';
import 'package:simcenter_app/features/auth/application/auth_controller.dart';
import 'package:simcenter_app/features/auth/domain/auth_models.dart';
import 'package:simcenter_app/features/devices/data/devices_repository.dart';
import 'package:simcenter_app/features/devices/domain/device_models.dart';
import 'package:simcenter_app/features/lap_detail/data/lap_detail_repository.dart';
import 'package:simcenter_app/features/lap_detail/domain/lap_compare.dart';
import 'package:simcenter_app/features/lap_detail/domain/lap_detail_models.dart';
import 'package:simcenter_app/features/laps/data/laps_repository.dart';
import 'package:simcenter_app/features/laps/domain/lap_models.dart';
import 'package:simcenter_app/features/profile/data/profile_repository.dart';
import 'package:simcenter_app/features/profile/domain/profile_draft.dart';
import 'package:simcenter_app/features/ranking/data/ranking_repository.dart';
import 'package:simcenter_app/features/ranking/domain/ranking_models.dart';
import 'package:simcenter_app/features/seasons/data/seasons_repository.dart';
import 'package:simcenter_app/features/seasons/domain/season_display.dart';
import 'package:simcenter_app/features/seasons/domain/season_models.dart';
import 'package:simcenter_app/features/sessions/data/sessions_repository.dart';
import 'package:simcenter_app/features/sessions/domain/session_display.dart';
import 'package:simcenter_app/features/sessions/domain/session_models.dart';

/// 테스트용 사용자.
const testUser = AppUser(userId: 'u1', displayName: '홍길동');

/// 실제 토큰 저장소/HTTP 없이 고정 사용자로 시작하는 인증 컨트롤러.
class FakeAuthController extends AuthController {
  FakeAuthController(this._user);

  final AppUser? _user;

  @override
  Future<AppUser?> build() async => _user;

  @override
  Future<void> logout() async {
    state = const AsyncData(null);
  }
}

/// 실제 SignalR 연결 없이 `rankingUpdated`·`lapRecorded`(D-50)·재연결·끊김을 테스트가 직접 흘려보내는 허브.
class FakeRankingHub implements RankingHubClient {
  final updates = StreamController<Map<String, dynamic>>.broadcast();
  final laps = StreamController<Map<String, dynamic>>.broadcast();
  final reconnects = StreamController<void>.broadcast();
  final closes = StreamController<void>.broadcast();
  final subscribed = <String>[];
  final unsubscribed = <String>[];
  int stopCalls = 0;
  int connectCalls = 0;

  /// null이 아니면 [connect]가 이 오류로 실패한다. 테스트 도중에 바꿀 수 있다.
  Object? connectError;

  @override
  Stream<Map<String, dynamic>> get rankingUpdated => updates.stream;

  @override
  Stream<Map<String, dynamic>> get lapRecorded => laps.stream;

  @override
  Stream<Map<String, dynamic>> get personalBest => const Stream.empty();

  @override
  Stream<void> get reconnected => reconnects.stream;

  @override
  Stream<void> get closed => closes.stream;

  @override
  Future<void> connect() async {
    connectCalls++;
    final error = connectError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<void> subscribeTrack(String trackId) async => subscribed.add(trackId);

  @override
  Future<void> unsubscribeTrack(String trackId) async => unsubscribed.add(trackId);

  @override
  Future<void> stop() async => stopCalls++;

  @override
  void dispose() {
    updates.close();
    laps.close();
    reconnects.close();
    closes.close();
  }
}

/// 서버가 `LapRecorded`로 보내는 페이로드(D-50, shared/samples/lap_recorded_broadcast.json 모양: LapDto + trackId).
Map<String, dynamic> lapRecordedPayload(
  String lapId, {
  String trackId = 't1',
  String trackName = 'Jeddah',
  int lapTimeMs = 98448,
  bool isValid = true,
}) =>
    {
      'lapId': lapId,
      'trackName': trackName,
      'gameCode': 'F1_25',
      'sessionType': 'TimeTrial',
      'lapTimeMs': lapTimeMs,
      'sectors': [
        {'sectorNumber': 1, 'sectorTimeMs': 32816},
      ],
      'isValid': isValid,
      'isRankingEligible': isValid,
      'setAt': '2026-10-18T11:00:00Z',
      'lapNumber': 6,
      'gameMode': 'TimeTrial',
      'team': {'name': 'Ferrari', 'color': '#E8002D'},
      'weather': 'LightCloud',
      'hasTrace': true,
      'trackId': trackId,
    };

/// 요청을 기록하고 미리 정한 스냅샷을 돌려주는 랭킹 저장소.
class FakeRankingRepository implements RankingRepository {
  FakeRankingRepository({this.tracks = const [], this.entriesFor});

  final List<Track> tracks;

  /// (trackId, period, 호출 순번) → 반환할 항목. null이면 빈 랭킹.
  final List<RankingEntry> Function(String trackId, String period, int callNumber)? entriesFor;

  final requests = <({String trackId, String period})>[];

  @override
  Future<List<Track>> getTracks() async => tracks;

  @override
  Future<RankingSnapshot> getRanking(
    String trackId, {
    String period = 'monthly',
    String gameCode = AppConfig.defaultGameCode,
  }) async {
    requests.add((trackId: trackId, period: period));
    final entries = entriesFor?.call(trackId, period, requests.length) ?? const <RankingEntry>[];
    return snapshotOf(trackId, period, entries);
  }
}

RankingSnapshot snapshotOf(String trackId, String period, List<RankingEntry> entries) =>
    RankingSnapshot(
      trackId: trackId,
      trackName: 'track-$trackId',
      gameCode: 'F1_25',
      period: period,
      periodKey: '2026-10',
      entries: entries,
    );

RankingEntry entryOf(int rank, String name, int ms) =>
    RankingEntry(rank: rank, displayName: name, bestLapTimeMs: ms, setAt: DateTime.utc(2026, 10, 1));

/// 허브가 흘려보내는 `RankingUpdated` 페이로드(= RankingSnapshot JSON).
Map<String, dynamic> hubPayload(String trackId, List<RankingEntry> entries, {String period = 'monthly'}) => {
      'trackId': trackId,
      'trackName': 'track-$trackId',
      'gameCode': 'F1_25',
      'period': period,
      'periodKey': '2026-10',
      'entries': [
        for (final e in entries)
          {
            'rank': e.rank,
            'displayName': e.displayName,
            'bestLapTimeMs': e.bestLapTimeMs,
            'setAt': e.setAt.toIso8601String(),
          },
      ],
    };

/// 랩 조회 요청 한 건(가짜 저장소가 기록한다).
typedef LapsRequest = ({String? trackId, String sort, bool validOnly, int page, int pageSize});

/// 요청을 기록하고 미리 정한 랩·트랙을 돌려주는 랩 저장소.
/// `validOnly`면 유효 랩만 거르고, `sort=fastest`면 랩타임 오름차순으로 정렬해 요청한 page/pageSize만큼 잘라 돌려준다(서버 계약 흉내).
class FakeLapsRepository implements LapsRepository {
  FakeLapsRepository({this.laps = const [], this.tracks = const []});

  /// 테스트 도중 새 랩·트랙으로 바꿀 수 있다(실시간 새 랩 흉내, D-50).
  List<Lap> laps;
  List<MyTrack> tracks;
  final requests = <LapsRequest>[];
  int tracksCalls = 0;

  List<int> get pageSizes => [for (final r in requests) r.pageSize];

  @override
  Future<MyLaps> getMyLaps({
    String? trackId,
    String? sessionType,
    String sort = kLapSortRecent,
    bool validOnly = false,
    int page = 1,
    int pageSize = 20,
  }) async {
    requests.add((trackId: trackId, sort: sort, validOnly: validOnly, page: page, pageSize: pageSize));
    final matching = [
      for (final lap in laps)
        if (!validOnly || lap.isValid) lap,
    ];
    if (sort == kLapSortFastest) {
      matching.sort((a, b) => a.lapTimeMs.compareTo(b.lapTimeMs));
    }
    final start = (page - 1) * pageSize;
    final items = matching.skip(start).take(pageSize).toList();
    return MyLaps(personalBest: null, page: page, pageSize: pageSize, total: matching.length, laps: items);
  }

  @override
  Future<List<MyTrack>> getMyTracks() async {
    tracksCalls++;
    return tracks;
  }
}

Lap lapOf(
  String id,
  String trackName,
  int ms, {
  bool isValid = true,
  String sessionType = 'TimeTrial',
  List<LapSector> sectors = const [],
  int? lapNumber,
  String? gameMode,
  LapTeam? team,
  String? weather,
  bool hasTrace = false,
  DateTime? setAt,
}) =>
    Lap(
      lapId: id,
      trackName: trackName,
      gameCode: 'F1_25',
      sessionType: sessionType,
      lapTimeMs: ms,
      sectors: sectors,
      isValid: isValid,
      isRankingEligible: isValid,
      setAt: setAt ?? DateTime.utc(2026, 10, 12, 9),
      lapNumber: lapNumber,
      gameMode: gameMode,
      team: team,
      weather: weather,
      hasTrace: hasTrace,
    );

MyTrack trackOf(String id, String name, {int lapCount = 3, int? bestMs = 83452, String? countryCode}) => MyTrack(
      trackId: id,
      trackName: name,
      gameCode: 'F1_25',
      lapCount: lapCount,
      bestValidLapTimeMs: bestMs,
      lastSetAt: DateTime.utc(2026, 10, 12, 9),
      countryCode: countryCode,
    );

/// 랩 상세·트레이스를 메모리에서 돌려주는 저장소. [details]에 없는 랩은 404 [ApiException],
/// [traces]에 없는 랩의 트레이스는 null(서버 404와 같다).
class FakeLapDetailRepository implements LapDetailRepository {
  /// [compared]가 있으면 비교 선택마다 상세를 바꿔 돌려준다(없거나 null이면 [details]).
  FakeLapDetailRepository({this.details = const {}, this.traces = const {}, this.compared});

  final Map<String, LapDetail> details;
  final Map<String, LapTrace> traces;
  final LapDetail? Function(String lapId, LapCompareSelection compare)? compared;
  final detailRequests = <String>[];
  final compareRequests = <LapCompareSelection>[];
  final traceRequests = <String>[];
  final comparisonTraceRequests = <String>[];

  @override
  Future<LapDetail> getLapDetail(String lapId, {LapCompareSelection compare = LapCompareSelection.defaults}) async {
    detailRequests.add(lapId);
    compareRequests.add(compare);
    final detail = compared?.call(lapId, compare) ?? details[lapId];
    if (detail == null) {
      throw ApiException('대상을 찾을 수 없어요.', statusCode: 404);
    }
    return detail;
  }

  @override
  Future<LapTrace?> getLapTrace(String lapId) async {
    traceRequests.add(lapId);
    return traces[lapId];
  }

  @override
  Future<LapTrace?> getComparisonTrace(String lapId) async {
    comparisonTraceRequests.add(lapId);
    return traces[lapId];
  }
}

/// 랩 상세. [comparison]을 생략하면 비교 대상 없음([unavailable] = 까닭).
LapDetail lapDetailOf(
  Lap lap, {
  String trackId = 't1',
  String? countryCode = 'SA',
  String? sessionId,
  CarSnapshot? car,
  LapConditions? conditions,
  LapAssists? assists,
  ComparisonLap? comparison,
  ComparisonUnavailable? unavailable,
}) =>
    LapDetail(
      lap: lap,
      trackId: trackId,
      countryCode: countryCode,
      sessionId: sessionId,
      car: car,
      conditions: conditions,
      assists: assists,
      comparison: comparison,
      comparisonUnavailable: unavailable,
    );

ComparisonLap comparisonOf(
  String lapId,
  int ms, {
  List<LapSector> sectors = const [],
  bool hasTrace = false,
  LapCompareKind kind = LapCompareKind.best,
  bool isMine = true,
  String? displayName,
  LapTeam? team,
}) =>
    ComparisonLap(
      lapId: lapId,
      lapTimeMs: ms,
      sectors: sectors,
      setAt: DateTime.utc(2026, 10, 1, 9),
      hasTrace: hasTrace,
      kind: kind,
      isMine: isMine,
      displayName: displayName,
      team: team,
    );

/// 거리 [resolutionM]m 간격 표본 [count]개짜리 트레이스. 시간·속도는 [timeAt]·[speedAt](표본 번호 → 값)으로 바꿀 수 있다.
/// 기본값: 시간 i×100ms, 속도 200+i, 스로틀 50+i, 브레이크 i, 스티어 −i, 기어 6, RPM 11000+i.
LapTrace traceOf(
  String lapId, {
  int count = 5,
  int resolutionM = 5,
  int Function(int i)? timeAt,
  int Function(int i)? speedAt,
}) =>
    LapTrace(
      lapId: lapId,
      resolutionM: resolutionM,
      timeMs: [for (var i = 0; i < count; i++) timeAt?.call(i) ?? i * 100],
      speedKph: [for (var i = 0; i < count; i++) speedAt?.call(i) ?? 200 + i],
      throttle: [for (var i = 0; i < count; i++) 50 + i],
      brake: [for (var i = 0; i < count; i++) i],
      steer: [for (var i = 0; i < count; i++) -i],
      gear: [for (var i = 0; i < count; i++) 6],
      rpm: [for (var i = 0; i < count; i++) 11000 + i],
    );

/// 장치 목록·연결 코드 발급·연결 해제를 메모리에서 흉내 내는 저장소.
/// [issueError]나 [revokeError]를 주면 해당 호출이 그 오류로 실패한다.
class FakeDevicesRepository implements DevicesRepository {
  FakeDevicesRepository({
    List<AgentDevice> devices = const [],
    this.issuedCode,
    this.issueError,
    this.revokeError,
  }) : _devices = [...devices];

  final List<AgentDevice> _devices;

  /// 다음 [issuePairingCode] 호출이 돌려줄 코드. 호출 순번(1부터)을 받아 만든다.
  final PairingCode Function(int callNumber)? issuedCode;

  /// null이 아니면 [issuePairingCode]가 이 오류로 실패한다. 테스트 도중에 바꿀 수 있다.
  Object? issueError;
  final Object? revokeError;

  int issueCalls = 0;
  int getDevicesCalls = 0;
  final revoked = <String>[];

  @override
  Future<PairingCode> issuePairingCode() async {
    issueCalls++;
    final error = issueError;
    if (error != null) {
      throw error;
    }
    return issuedCode!(issueCalls);
  }

  @override
  Future<List<AgentDevice>> getDevices() async {
    getDevicesCalls++;
    return [..._devices];
  }

  @override
  Future<void> revoke(String deviceId) async {
    revoked.add(deviceId);
    final error = revokeError;
    if (error != null) {
      throw error;
    }
    _devices.removeWhere((d) => d.deviceId == deviceId);
  }
}

AgentDevice deviceOf(String id, String name, {DateTime? lastSeenAt, DateTime? createdAt}) =>
    AgentDevice(
      deviceId: id,
      name: name,
      lastSeenAt: lastSeenAt,
      createdAt: createdAt ?? DateTime.utc(2026, 10, 1, 9),
    );

/// 요청을 기록하고 미리 정한 세션을 돌려주는 세션 저장소.
/// [sessionType]이 있으면 그 유형만 거르고, page/pageSize만큼 잘라 돌려준다(서버 계약 흉내).
/// [details]에 없는 Id의 상세 조회는 404 [ApiException]으로 실패한다.
class FakeSessionsRepository implements SessionsRepository {
  FakeSessionsRepository({this.sessions = const [], this.details = const {}});

  final List<SessionSummary> sessions;
  final Map<String, SessionDetail> details;
  final requests = <({String? sessionType, int page, int pageSize})>[];
  final detailRequests = <String>[];

  @override
  Future<SessionSummaryPage> getMySessions({
    String? sessionType,
    int page = 1,
    int pageSize = kSessionsPageSize,
  }) async {
    requests.add((sessionType: sessionType, page: page, pageSize: pageSize));
    final matching = [
      for (final s in sessions)
        if (sessionType == null || s.sessionType == sessionType) s,
    ];
    final items = matching.skip((page - 1) * pageSize).take(pageSize).toList();
    return SessionSummaryPage(page: page, pageSize: pageSize, total: matching.length, items: items);
  }

  @override
  Future<SessionDetail> getMySession(String sessionId) async {
    detailRequests.add(sessionId);
    final detail = details[sessionId];
    if (detail == null) {
      throw ApiException('대상을 찾을 수 없어요.', statusCode: 404);
    }
    return detail;
  }
}

SessionSummary sessionOf(
  String id, {
  String trackName = 'Spa',
  String sessionType = 'Race',
  String sessionKind = 'Race',
  String gameMode = 'DriverCareer',
  String? seasonId,
  int carCount = 22,
  int? myPosition = 4,
  int? myGridPosition = 6,
  String? myResultStatus = 'Finished',
  int? myBestLapTimeMs = 105321,
  int? myPoints = 12,
  DateTime? classifiedAt,
  String? countryCode,
  LapTeam? myTeam,
  int? seasonNumber,
}) =>
    SessionSummary(
      countryCode: countryCode,
      myTeam: myTeam,
      seasonNumber: seasonNumber,
      sessionId: id,
      classifiedAt: classifiedAt ?? DateTime.utc(2026, 10, 12, 9),
      trackName: trackName,
      sessionType: sessionType,
      sessionKind: sessionKind,
      gameMode: gameMode,
      seasonId: seasonId,
      carCount: carCount,
      myPosition: myPosition,
      myGridPosition: myGridPosition,
      myResultStatus: myResultStatus,
      myBestLapTimeMs: myBestLapTimeMs,
      myPoints: myPoints,
    );

/// 결과 한 줄. [carIndex]를 생략하면 순위 - 1이다(행마다 달라야 기준 행 비교가 맞는다).
SessionResult resultOf(
  int position, {
  int? carIndex,
  String? name,
  String teamName = 'McLaren',
  String teamColor = '#FF8000',
  bool isAiControlled = true,
  bool isPlayer = false,
  int? gridPosition,
  int numLaps = 15,
  int? bestLapTimeMs,
  bool isFastestLap = false,
  int? totalRaceTimeMs,
  int penaltiesTimeMs = 0,
  int numPenalties = 0,
  int numPitStops = 1,
  int points = 0,
  String resultStatus = 'Finished',
  List<TyreStintView> tyreStints = const [],
  int? raceNumber,
  int? gapMs,
  int? positionChange,
}) =>
    SessionResult(
      gapMs: gapMs,
      positionChange: positionChange,
      position: position,
      carIndex: carIndex ?? position - 1,
      name: name ?? 'DRIVER $position',
      teamId: 8,
      teamName: teamName,
      teamColor: teamColor,
      raceNumber: raceNumber ?? position,
      isAiControlled: isAiControlled,
      isPlayer: isPlayer,
      gridPosition: gridPosition ?? position,
      numLaps: numLaps,
      bestLapTimeMs: bestLapTimeMs,
      isFastestLap: isFastestLap,
      totalRaceTimeMs: totalRaceTimeMs,
      penaltiesTimeMs: penaltiesTimeMs,
      numPenalties: numPenalties,
      numPitStops: numPitStops,
      points: points,
      resultStatus: resultStatus,
      tyreStints: tyreStints,
    );

SessionDetail detailOf(
  String id, {
  List<SessionResult> results = const [],
  String trackName = 'Spa',
  String sessionType = 'Race',
  String sessionKind = 'Race',
  String gameMode = 'DriverCareer',
  String? seasonId,
  int? round,
  int totalLaps = 15,
  int aiDifficulty = 85,
  bool isNetworkGame = false,
  String? countryCode,
  LapTeam? myTeam,
  int? seasonNumber,
  String? weather,
  int? myBestLapTimeMs,
  List<QualifyingPosition> qualifyingPositions = const [],
  SessionBestLap? myBestLap,
  Map<String, Object?>? setup,
  List<SessionLap> laps = const [],
  EngineWear? engineWear,
  List<SessionTyreStint> tyreStints = const [],
  List<SessionPenalty> penalties = const [],
}) =>
    SessionDetail(
      qualifyingPositions: qualifyingPositions,
      myBestLap: myBestLap,
      setup: setup,
      laps: laps,
      engineWear: engineWear,
      tyreStints: tyreStints,
      penalties: penalties,
      header: SessionDetailHeader(
        countryCode: countryCode,
        myTeam: myTeam,
        seasonNumber: seasonNumber,
        weather: weather,
        sessionId: id,
        classifiedAt: DateTime.utc(2026, 10, 12, 9),
        trackName: trackName,
        sessionType: sessionType,
        sessionKind: sessionKind,
        gameMode: gameMode,
        seasonId: seasonId,
        carCount: results.length,
        myPosition: null,
        myGridPosition: null,
        myResultStatus: null,
        myBestLapTimeMs: myBestLapTimeMs,
        myPoints: null,
        totalLaps: totalLaps,
        aiDifficulty: aiDifficulty,
        isNetworkGame: isNetworkGame,
        round: round,
      ),
      results: results,
    );

/// 요청을 기록하고 미리 정한 시즌을 돌려주는 시즌 저장소.
/// page/pageSize만큼 잘라 돌려준다(서버 계약 흉내). [details]에 없는 Id의 상세 조회는 404 [ApiException]으로 실패한다.
class FakeSeasonsRepository implements SeasonsRepository {
  FakeSeasonsRepository({this.seasons = const [], this.details = const {}});

  final List<SeasonSummary> seasons;
  final Map<String, SeasonDetail> details;
  final requests = <({int page, int pageSize})>[];
  final detailRequests = <String>[];

  @override
  Future<SeasonSummaryPage> getMySeasons({int page = 1, int pageSize = kSeasonsPageSize}) async {
    requests.add((page: page, pageSize: pageSize));
    final items = seasons.skip((page - 1) * pageSize).take(pageSize).toList();
    return SeasonSummaryPage(page: page, pageSize: pageSize, total: seasons.length, items: items);
  }

  @override
  Future<SeasonDetail> getMySeason(String seasonId) async {
    detailRequests.add(seasonId);
    final detail = details[seasonId];
    if (detail == null) {
      throw ApiException('대상을 찾을 수 없어요.', statusCode: 404);
    }
    return detail;
  }
}

/// 시즌 요약. 시각은 로컬 시간대로 만들어 날짜 표기가 PC의 시간대에 흔들리지 않게 한다.
SeasonSummary seasonOf(
  String id, {
  String gameMode = 'DriverCareer',
  int roundCount = 6,
  int? myPosition = 3,
  int? myPoints = 87,
  String? leaderName = 'VERSTAPPEN',
  int? leaderPoints = 120,
  DateTime? firstSessionAt,
  DateTime? lastSessionAt,
}) =>
    SeasonSummary(
      seasonId: id,
      gameCode: 'F1_25',
      gameMode: gameMode,
      firstSessionAt: firstSessionAt ?? DateTime(2026, 10, 17, 12),
      lastSessionAt: lastSessionAt ?? DateTime(2026, 10, 24, 12),
      roundCount: roundCount,
      myPosition: myPosition,
      myPoints: myPoints,
      leaderName: leaderName,
      leaderPoints: leaderPoints,
    );

SeasonRoundSession seasonSessionOf(
  String id, {
  String sessionType = 'Race',
  String sessionKind = 'Race',
  int? myPosition = 4,
  String? myResultStatus = 'Finished',
}) =>
    SeasonRoundSession(
      sessionId: id,
      sessionType: sessionType,
      sessionKind: sessionKind,
      myPosition: myPosition,
      myResultStatus: myResultStatus,
    );

SeasonRound seasonRoundOf(
  int round, {
  String? trackName,
  String? winnerName,
  int? myPoints,
  List<SeasonRoundSession> sessions = const [],
  DateTime? firstSessionAt,
}) =>
    SeasonRound(
      round: round,
      weekendId: 'w$round',
      trackName: trackName ?? 'Track $round',
      firstSessionAt: firstSessionAt ?? DateTime(2026, 10, 16 + round, 12),
      winnerName: winnerName,
      myPoints: myPoints,
      sessions: sessions,
    );

StandingCell standingCellOf(int round, {int? position, String? resultStatus, int points = 0}) =>
    StandingCell(round: round, position: position, resultStatus: resultStatus, points: points);

DriverStanding driverStandingOf(
  int position, {
  String? driverKey,
  String? name,
  String teamName = 'McLaren',
  String teamColor = '#FF8000',
  bool isPlayer = false,
  bool isAiControlled = true,
  int points = 0,
  int wins = 0,
  int podiums = 0,
  List<StandingCell> cells = const [],
}) =>
    DriverStanding(
      position: position,
      driverKey: driverKey ?? 'driver:$position',
      name: name ?? 'DRIVER $position',
      teamName: teamName,
      teamColor: teamColor,
      isPlayer: isPlayer,
      isAiControlled: isAiControlled,
      points: points,
      wins: wins,
      podiums: podiums,
      cells: cells,
    );

ConstructorStanding constructorStandingOf(
  int position, {
  int? teamId,
  String? teamName,
  String teamColor = '#3671C6',
  int points = 0,
  int wins = 0,
}) =>
    ConstructorStanding(
      position: position,
      teamId: teamId ?? position,
      teamName: teamName ?? 'Team $position',
      teamColor: teamColor,
      points: points,
      wins: wins,
    );

SeasonDetail seasonDetailOf(
  String id, {
  SeasonSummary? season,
  List<SeasonRound> rounds = const [],
  List<DriverStanding> drivers = const [],
  List<ConstructorStanding> constructors = const [],
}) =>
    SeasonDetail(
      season: season ?? seasonOf(id),
      rounds: rounds,
      standings: SeasonStandings(drivers: drivers, constructors: constructors),
    );

/// 팀 색 막대([key]가 붙은 `TeamColorBar`)가 칠한 색.
Color? teamBarColor(WidgetTester tester, Key key) {
  final bar = tester.widget<Container>(
    find.descendant(of: find.byKey(key), matching: find.byType(Container)),
  );
  return (bar.decoration as BoxDecoration).color;
}

/// 논리 픽셀 = 물리 픽셀(1:1)로 뷰 크기를 고정한다.
void setViewSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// 인증 컨트롤러를 가짜로 바꾸는 override.
Override fakeAuth([AppUser? user = testUser]) =>
    authControllerProvider.overrideWith(() => FakeAuthController(user));

/// 설정 화면용 사용자(이메일 포함, 기본 설정).
const settingsUser = AppUser(userId: 'u1', displayName: '홍길동', email: 'driver@simcenter.test');

/// 프로필 저장·이메일 변경을 메모리에서 흉내 내는 저장소(실제 HTTP 없음). 서버처럼 저장된 프로필을 돌려준다.
/// [updateError]·[emailError]를 주면 해당 호출이 그 오류로 실패한다. 테스트 도중에 바꿀 수 있다.
class FakeProfileRepository implements ProfileRepository {
  FakeProfileRepository({this.user = settingsUser, this.updateError, this.emailError});

  /// 서버에 저장된 현재 프로필.
  AppUser user;
  Object? updateError;
  Object? emailError;

  final updates = <ProfileDraft>[];
  final emailChanges = <({String newEmail, String currentPassword})>[];

  /// 지정하면 완료될 때까지 저장이 끝나지 않는다(진행 중 상태 재현).
  Completer<void>? updateGate;

  @override
  Future<AppUser> updateProfile(ProfileDraft draft) async {
    updates.add(draft);
    await updateGate?.future;
    final error = updateError;
    if (error != null) {
      throw error;
    }
    user = user.copyWith(displayName: draft.displayName, preferences: draft.preferences);
    return user;
  }

  @override
  Future<AppUser> changeEmail({required String newEmail, required String currentPassword}) async {
    emailChanges.add((newEmail: newEmail, currentPassword: currentPassword));
    final error = emailError;
    if (error != null) {
      throw error;
    }
    user = user.copyWith(email: newEmail.toLowerCase());
    return user;
  }
}
