import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:signalr_netcore/signalr_client.dart';

import '../config/app_config.dart';
import '../storage/token_store.dart';

/// 허브 연결을 만드는 함수. 테스트에서 실제 서버 없이 가짜 연결을 넣을 때만 바꾼다.
typedef HubConnectionFactory = HubConnection Function();

/// RankingHub(05 §3) 클라이언트. 사용자 JWT는 accessTokenFactory로 주입(secure store),
/// 자동 재접속 + 재접속 시 관심 트랙 재구독(05 §5). feature 결합을 피하려 raw Map 페이로드를 스트림으로 노출한다.
class RankingHubClient {
  RankingHubClient(this._tokenStore, {HubConnectionFactory? connectionFactory})
      : _connectionFactory = connectionFactory;

  final TokenStore _tokenStore;
  final HubConnectionFactory? _connectionFactory;
  HubConnection? _connection;
  String? _subscribedTrackId;

  /// 진행 중인 첫 연결. 동시에 불린 [connect]가 이 Future를 함께 기다려 연결을 하나만 만든다.
  /// 실패하거나 [stop]되면 비워서 다음 호출이 새로 연결한다.
  Future<void>? _connecting;

  /// [stop]·[dispose]마다 올린다. 연결 중에 세대가 바뀌면 늦게 열린 연결은 버린다.
  int _generation = 0;

  final _rankingUpdated = StreamController<Map<String, dynamic>>.broadcast();
  final _lapRecorded = StreamController<Map<String, dynamic>>.broadcast();
  final _personalBest = StreamController<Map<String, dynamic>>.broadcast();
  final _reconnected = StreamController<void>.broadcast();
  final _closed = StreamController<void>.broadcast();

  Stream<Map<String, dynamic>> get rankingUpdated => _rankingUpdated.stream;

  /// 내 새 랩(D-50, docs/15 §9). 페이로드 = `GET /me/laps`의 LapDto 한 건 + `trackId`. 서버가 랩 주인에게만 보낸다.
  Stream<Map<String, dynamic>> get lapRecorded => _lapRecorded.stream;
  Stream<Map<String, dynamic>> get personalBest => _personalBest.stream;

  /// 자동 재접속에 성공할 때마다(놓친 이벤트를 REST로 채우는 신호, 05 §5·docs/15 §9).
  Stream<void> get reconnected => _reconnected.stream;

  /// 자동 재접속도 포기하고 연결이 끊겼을 때([stop]으로 닫은 경우는 제외). 이후 [connect]는 새 연결을 만든다.
  Stream<void> get closed => _closed.stream;

  bool get _isConnected => _connection?.state == HubConnectionState.Connected;

  Future<void> connect() {
    if (_connection != null) {
      return Future.value();
    }

    final inFlight = _connecting;
    if (inFlight != null) {
      return inFlight;
    }

    late final Future<void> attempt;
    attempt = _open(_generation).whenComplete(() {
      // 성공·실패 모두 비운다. 성공하면 이후 호출은 _connection으로 바로 돌아간다.
      if (identical(_connecting, attempt)) {
        _connecting = null;
      }
    });
    _connecting = attempt;
    return attempt;
  }

  Future<void> _open(int generation) async {
    final conn = _createConnection();

    conn.on('RankingUpdated', (args) => _emit(_rankingUpdated, args));
    conn.on('LapRecorded', (args) => _emit(_lapRecorded, args));
    conn.on('PersonalBestAchieved', (args) => _emit(_personalBest, args));

    conn.onreconnected(({connectionId}) async {
      final trackId = _subscribedTrackId;
      if (trackId != null) {
        await conn.invoke('SubscribeTrack', args: [trackId]);
      }
      _addIfOpen(_reconnected);
    });

    conn.onclose(({error}) {
      // stop()이 닫은 연결은 이미 _connection에서 빠져 있다 — 지금 쓰는 연결이 끊긴 경우만 알린다.
      if (identical(_connection, conn)) {
        _connection = null;
        _addIfOpen(_closed);
      }
    });

    await conn.start();
    if (generation != _generation) {
      // 연결하는 동안 stop()·dispose()가 불렸다 — 이 연결은 쓰지 않고 닫는다.
      await conn.stop();
      return;
    }
    _connection = conn;
  }

  Future<void> subscribeTrack(String trackId) async {
    _subscribedTrackId = trackId;
    await connect();
    if (_isConnected) {
      await _connection!.invoke('SubscribeTrack', args: [trackId]);
    }
  }

  Future<void> unsubscribeTrack(String trackId) async {
    if (_subscribedTrackId == trackId) {
      _subscribedTrackId = null;
    }
    if (_isConnected) {
      await _connection!.invoke('UnsubscribeTrack', args: [trackId]);
    }
  }

  Future<void> stop() async {
    _generation++;
    _connecting = null;
    _subscribedTrackId = null;
    final conn = _connection;
    _connection = null;
    await conn?.stop();
  }

  HubConnection _createConnection() => _connectionFactory?.call() ?? _buildConnection();

  HubConnection _buildConnection() => HubConnectionBuilder()
      .withUrl(
        AppConfig.rankingHubUrl,
        options: HttpConnectionOptions(
          accessTokenFactory: () async => await _tokenStore.readToken() ?? '',
        ),
      )
      .withAutomaticReconnect()
      .build();

  void _emit(StreamController<Map<String, dynamic>> controller, List<Object?>? args) {
    if (args != null && args.isNotEmpty && args.first is Map && !controller.isClosed) {
      controller.add(Map<String, dynamic>.from(args.first as Map));
    }
  }

  void _addIfOpen(StreamController<void> controller) {
    if (!controller.isClosed) {
      controller.add(null);
    }
  }

  void dispose() {
    _generation++;
    _connecting = null;
    _rankingUpdated.close();
    _lapRecorded.close();
    _personalBest.close();
    _reconnected.close();
    _closed.close();
    _connection?.stop();
  }
}

final rankingHubClientProvider = Provider<RankingHubClient>((ref) {
  final client = RankingHubClient(ref.watch(tokenStoreProvider));
  ref.onDispose(client.dispose);
  return client;
});
