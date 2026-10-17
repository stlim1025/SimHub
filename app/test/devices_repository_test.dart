import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simcenter_app/core/network/api_exception.dart';
import 'package:simcenter_app/features/devices/data/devices_repository.dart';

/// 실제 HTTP 없이 요청을 기록하고 정해 둔 응답을 돌려주는 Dio 어댑터.
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this._status, [this._body = '']);

  final int _status;
  final String _body;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      _body,
      _status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

(DevicesRepository, _StubAdapter) _repoReturning(int status, [String body = '']) {
  final adapter = _StubAdapter(status, body);
  final dio = Dio(BaseOptions(baseUrl: 'http://test/api/v1'))..httpClientAdapter = adapter;
  return (DevicesRepository(dio), adapter);
}

void main() {
  test('issuePairingCode는 POST /me/agent-pairing-codes 응답을 파싱한다', () async {
    final (repo, adapter) = _repoReturning(
      201,
      '{"code":"K7F2-9QXM","expiresAt":"2026-10-17T12:10:00Z"}',
    );

    final code = await repo.issuePairingCode();

    expect(adapter.requests.single.method, 'POST');
    expect(adapter.requests.single.path, '/me/agent-pairing-codes');
    expect(code.code, 'K7F2-9QXM');
    expect(code.expiresAt, DateTime.utc(2026, 10, 17, 12, 10));
  });

  test('getDevices는 GET /me/agent-devices의 items를 순서대로 파싱한다', () async {
    final (repo, adapter) = _repoReturning(200, '''
{"items":[
  {"deviceId":"d2","name":"LAPTOP","lastSeenAt":null,"createdAt":"2026-10-02T09:00:00Z"},
  {"deviceId":"d1","name":"RIG-PC","lastSeenAt":"2026-10-17T11:55:00Z","createdAt":"2026-10-01T09:00:00Z"}
]}''');

    final devices = await repo.getDevices();

    expect(adapter.requests.single.method, 'GET');
    expect(adapter.requests.single.path, '/me/agent-devices');
    expect(devices.map((d) => d.deviceId), ['d2', 'd1']);
    expect(devices.first.lastSeenAt, isNull);
    expect(devices.last.lastSeenAt, DateTime.utc(2026, 10, 17, 11, 55));
  });

  test('revoke는 DELETE /me/agent-devices/{id}를 호출한다(204)', () async {
    final (repo, adapter) = _repoReturning(204);

    await repo.revoke('d1');

    expect(adapter.requests.single.method, 'DELETE');
    expect(adapter.requests.single.path, '/me/agent-devices/d1');
  });

  test('발급 한도 초과(429)는 읽을 수 있는 ApiException이 된다', () async {
    final (repo, _) = _repoReturning(429);

    await expectLater(
      repo.issuePairingCode(),
      throwsA(
        isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 429)
            .having((e) => e.message, 'message', '요청이 너무 많아요. 잠시 후 다시 시도해 주세요.'),
      ),
    );
  });

  test('남의 장치(403)·없는 장치(404) 해제는 ApiException이 된다', () async {
    final (forbidden, _) = _repoReturning(403);
    final (missing, _) = _repoReturning(404);

    await expectLater(
      forbidden.revoke('d1'),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 403)),
    );
    await expectLater(
      missing.revoke('d1'),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 404)),
    );
  });

  test('목록 조회 실패도 ApiException이다', () async {
    final (repo, _) = _repoReturning(500);

    await expectLater(repo.getDevices(), throwsA(isA<ApiException>()));
  });
}
