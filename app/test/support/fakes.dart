import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simcenter_app/core/config/app_config.dart';
import 'package:simcenter_app/core/realtime/ranking_hub_client.dart';
import 'package:simcenter_app/features/auth/application/auth_controller.dart';
import 'package:simcenter_app/features/auth/domain/auth_models.dart';
import 'package:simcenter_app/features/laps/data/laps_repository.dart';
import 'package:simcenter_app/features/laps/domain/lap_models.dart';
import 'package:simcenter_app/features/ranking/data/ranking_repository.dart';
import 'package:simcenter_app/features/ranking/domain/ranking_models.dart';

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

/// 최근 랩 목록을 돌려주는 랩 저장소.
class FakeLapsRepository implements LapsRepository {
  FakeLapsRepository({this.laps = const []});

  final List<Lap> laps;
  final pageSizes = <int>[];

  @override
  Future<MyLaps> getMyLaps({String? trackId, String? sessionType, int page = 1, int pageSize = 20}) async {
    pageSizes.add(pageSize);
    return MyLaps(personalBest: null, page: page, pageSize: pageSize, total: laps.length, laps: laps);
  }
}

Lap lapOf(String id, String trackName, int ms, {bool isValid = true}) => Lap(
      lapId: id,
      trackName: trackName,
      gameCode: 'F1_25',
      sessionType: 'TimeTrial',
      lapTimeMs: ms,
      sectors: const [],
      isValid: isValid,
      isRankingEligible: isValid,
      setAt: DateTime.utc(2026, 10, 12, 9),
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
