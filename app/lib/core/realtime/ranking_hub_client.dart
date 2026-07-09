import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:signalr_netcore/signalr_client.dart';

import '../config/app_config.dart';
import '../storage/token_store.dart';

/// RankingHub(05 §3) 클라이언트. 사용자 JWT는 accessTokenFactory로 주입(secure store),
/// 자동 재접속 + 재접속 시 관심 트랙 재구독(05 §5). feature 결합을 피하려 raw Map 페이로드를 스트림으로 노출한다.
class RankingHubClient {
  RankingHubClient(this._tokenStore);

  final TokenStore _tokenStore;
  HubConnection? _connection;
  String? _subscribedTrackId;

  final _rankingUpdated = StreamController<Map<String, dynamic>>.broadcast();
  final _lapRecorded = StreamController<Map<String, dynamic>>.broadcast();
  final _personalBest = StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get rankingUpdated => _rankingUpdated.stream;
  Stream<Map<String, dynamic>> get lapRecorded => _lapRecorded.stream;
  Stream<Map<String, dynamic>> get personalBest => _personalBest.stream;

  bool get _isConnected => _connection?.state == HubConnectionState.Connected;

  Future<void> connect() async {
    if (_connection != null) {
      return;
    }

    final conn = HubConnectionBuilder()
        .withUrl(
          AppConfig.rankingHubUrl,
          options: HttpConnectionOptions(
            accessTokenFactory: () async => await _tokenStore.readToken() ?? '',
          ),
        )
        .withAutomaticReconnect()
        .build();

    conn.on('RankingUpdated', (args) => _emit(_rankingUpdated, args));
    conn.on('LapRecorded', (args) => _emit(_lapRecorded, args));
    conn.on('PersonalBestAchieved', (args) => _emit(_personalBest, args));

    conn.onreconnected(({connectionId}) async {
      final trackId = _subscribedTrackId;
      if (trackId != null) {
        await conn.invoke('SubscribeTrack', args: [trackId]);
      }
    });

    await conn.start();
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
    await _connection?.stop();
    _connection = null;
    _subscribedTrackId = null;
  }

  void _emit(StreamController<Map<String, dynamic>> controller, List<Object?>? args) {
    if (args != null && args.isNotEmpty && args.first is Map) {
      controller.add(Map<String, dynamic>.from(args.first as Map));
    }
  }

  void dispose() {
    _rankingUpdated.close();
    _lapRecorded.close();
    _personalBest.close();
    _connection?.stop();
  }
}

final rankingHubClientProvider = Provider<RankingHubClient>((ref) {
  final client = RankingHubClient(ref.watch(tokenStoreProvider));
  ref.onDispose(client.dispose);
  return client;
});
