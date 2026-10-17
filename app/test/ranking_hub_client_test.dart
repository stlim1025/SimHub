import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signalr_netcore/signalr_client.dart';
import 'package:simcenter_app/core/realtime/ranking_hub_client.dart';
import 'package:simcenter_app/core/storage/token_store.dart';

/// 실제 서버 없이 start·invoke·stop만 기록하는 허브 연결. start 결과는 [onStart]가 정한다.
class _FakeHubConnection implements HubConnection {
  _FakeHubConnection(this.onStart);

  final Future<void> Function() onStart;
  final invocations = <String>[];
  int startCalls = 0;
  int stopCalls = 0;
  HubConnectionState _state = HubConnectionState.Disconnected;

  @override
  HubConnectionState? get state => _state;

  @override
  Future<void>? start() async {
    startCalls++;
    _state = HubConnectionState.Connecting;
    try {
      await onStart();
      _state = HubConnectionState.Connected;
    } catch (_) {
      _state = HubConnectionState.Disconnected;
      rethrow;
    }
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    _state = HubConnectionState.Disconnected;
  }

  @override
  Future<Object?> invoke(String methodName, {List<Object>? args}) async {
    invocations.add('$methodName:${args?.join(',')}');
    return null;
  }

  @override
  void on(String methodName, MethodInvocationFunc newMethod) {}

  @override
  void onreconnected(ReconnectedCallback callback) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 만든 연결을 순서대로 모으고, 호출 순번(1부터)으로 start 결과를 정하는 클라이언트를 만든다.
({RankingHubClient client, List<_FakeHubConnection> created}) _clientWith(
  Future<void> Function(int connectionNumber) onStart,
) {
  final created = <_FakeHubConnection>[];
  final client = RankingHubClient(
    TokenStore(const FlutterSecureStorage()),
    connectionFactory: () {
      final number = created.length + 1;
      final connection = _FakeHubConnection(() => onStart(number));
      created.add(connection);
      return connection;
    },
  );
  return (client: client, created: created);
}

void main() {
  test('첫 연결 중에 subscribeTrack이 동시에 불려도 연결은 하나만 만든다', () async {
    final gate = Completer<void>();
    final (:client, :created) = _clientWith((_) => gate.future);

    final first = client.subscribeTrack('t1');
    final second = client.subscribeTrack('t2');
    gate.complete();
    await Future.wait([first, second]);

    expect(created, hasLength(1));
    expect(created.single.startCalls, 1);
    expect(created.single.invocations, unorderedEquals(['SubscribeTrack:t1', 'SubscribeTrack:t2']));
  });

  test('연결에 실패하면 다음 호출에서 새 연결로 다시 시도한다', () async {
    final (:client, :created) = _clientWith(
      (number) => number == 1 ? Future.error(StateError('서버 없음')) : Future.value(),
    );

    await expectLater(client.subscribeTrack('t1'), throwsStateError);
    await client.subscribeTrack('t1');

    expect(created, hasLength(2));
    expect(created.first.invocations, isEmpty);
    expect(created.last.invocations, ['SubscribeTrack:t1']);
  });

  test('연결 중에 stop()하면 그 연결을 버리고 다음 호출에서 새로 연결한다', () async {
    final gate = Completer<void>();
    final (:client, :created) = _clientWith((number) => number == 1 ? gate.future : Future.value());

    final pending = client.subscribeTrack('t1');
    await client.stop();
    gate.complete();
    await pending;

    expect(created.first.stopCalls, 1); // 늦게 열린 연결은 바로 닫는다.
    expect(created.first.invocations, isEmpty);

    await client.subscribeTrack('t2');

    expect(created, hasLength(2));
    expect(created.last.invocations, ['SubscribeTrack:t2']);
  });
}
