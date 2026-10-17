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
import 'package:simcenter_app/features/laps/data/laps_repository.dart';
import 'package:simcenter_app/features/laps/domain/lap_models.dart';
import 'package:simcenter_app/features/ranking/data/ranking_repository.dart';
import 'package:simcenter_app/features/ranking/domain/ranking_models.dart';
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

/// 실제 SignalR 연결 없이 `rankingUpdated`를 테스트가 직접 흘려보내는 허브.
class FakeRankingHub implements RankingHubClient {
  final updates = StreamController<Map<String, dynamic>>.broadcast();
  final subscribed = <String>[];
  final unsubscribed = <String>[];
  int stopCalls = 0;

  @override
  Stream<Map<String, dynamic>> get rankingUpdated => updates.stream;

  @override
  Stream<Map<String, dynamic>> get lapRecorded => const Stream.empty();

  @override
  Stream<Map<String, dynamic>> get personalBest => const Stream.empty();

  @override
  Future<void> connect() async {}

  @override
  Future<void> subscribeTrack(String trackId) async => subscribed.add(trackId);

  @override
  Future<void> unsubscribeTrack(String trackId) async => unsubscribed.add(trackId);

  @override
  Future<void> stop() async => stopCalls++;

  @override
  void dispose() => updates.close();
}

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

/// 요청을 기록하고 미리 정한 랩·트랙을 돌려주는 랩 저장소.
/// `sort=fastest`면 랩타임 오름차순으로 정렬하고, 요청한 page/pageSize만큼 잘라 돌려준다(서버 계약 흉내).
class FakeLapsRepository implements LapsRepository {
  FakeLapsRepository({this.laps = const [], this.tracks = const []});

  final List<Lap> laps;
  final List<MyTrack> tracks;
  final requests = <({String? trackId, String sort, int page, int pageSize})>[];

  List<int> get pageSizes => [for (final r in requests) r.pageSize];

  @override
  Future<MyLaps> getMyLaps({
    String? trackId,
    String? sessionType,
    String sort = kLapSortRecent,
    int page = 1,
    int pageSize = 20,
  }) async {
    requests.add((trackId: trackId, sort: sort, page: page, pageSize: pageSize));
    final ordered = sort == kLapSortFastest
        ? ([...laps]..sort((a, b) => a.lapTimeMs.compareTo(b.lapTimeMs)))
        : laps;
    final start = (page - 1) * pageSize;
    final items = ordered.skip(start).take(pageSize).toList();
    return MyLaps(personalBest: null, page: page, pageSize: pageSize, total: laps.length, laps: items);
  }

  @override
  Future<List<MyTrack>> getMyTracks() async => tracks;
}

Lap lapOf(
  String id,
  String trackName,
  int ms, {
  bool isValid = true,
  String sessionType = 'TimeTrial',
  List<LapSector> sectors = const [],
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
      setAt: DateTime.utc(2026, 10, 12, 9),
    );

MyTrack trackOf(String id, String name, {int lapCount = 3, int? bestMs = 83452}) => MyTrack(
      trackId: id,
      trackName: name,
      gameCode: 'F1_25',
      lapCount: lapCount,
      bestValidLapTimeMs: bestMs,
      lastSetAt: DateTime.utc(2026, 10, 12, 9),
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
  Future<SessionsPage> getMySessions({
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
    return SessionsPage(page: page, pageSize: pageSize, total: matching.length, items: items);
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
}) =>
    SessionSummary(
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
}) =>
    SessionResult(
      position: position,
      carIndex: carIndex ?? position - 1,
      name: name ?? 'DRIVER $position',
      teamId: 8,
      teamName: teamName,
      teamColor: teamColor,
      raceNumber: position,
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
}) =>
    SessionDetail(
      header: SessionDetailHeader(
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
        myBestLapTimeMs: null,
        myPoints: null,
        totalLaps: totalLaps,
        aiDifficulty: aiDifficulty,
        isNetworkGame: isNetworkGame,
        round: round,
      ),
      results: results,
    );

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
