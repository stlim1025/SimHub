import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simcenter_app/core/network/api_exception.dart';
import 'package:simcenter_app/features/sessions/data/sessions_repository.dart';

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

(SessionsRepository, _StubAdapter) _repoReturning(int status, [String body = '']) {
  final adapter = _StubAdapter(status, body);
  final dio = Dio(BaseOptions(baseUrl: 'http://test/api/v1'))..httpClientAdapter = adapter;
  return (SessionsRepository(dio), adapter);
}

const _emptyPage = '{"page":1,"pageSize":15,"total":0,"items":[]}';

const _detailBody = '''
{"session":{"sessionId":"s1","classifiedAt":"2026-10-17T12:10:00Z","trackName":"Spa","sessionType":"Race",
  "sessionKind":"Race","gameMode":"DriverCareer","seasonId":null,"carCount":1,"myPosition":null,
  "myGridPosition":null,"myResultStatus":null,"myBestLapTimeMs":null,"myPoints":null,
  "totalLaps":15,"aiDifficulty":85,"isNetworkGame":false,"round":null},
 "results":[{"position":1,"carIndex":0,"name":"NORRIS","teamId":8,"teamName":"McLaren","teamColor":"#FF8000",
  "raceNumber":4,"isAiControlled":true,"isPlayer":false,"gridPosition":1,"numLaps":15,"bestLapTimeMs":104987,
  "isFastestLap":true,"totalRaceTimeMs":1598765,"penaltiesTimeMs":0,"numPenalties":0,"numPitStops":1,
  "points":25,"resultStatus":"Finished","tyreStints":[]}]}''';

void main() {
  test('getMySessions는 GET /me/sessions?sessionType=Race&page=2&pageSize=15를 호출한다', () async {
    final (repo, adapter) = _repoReturning(200, _emptyPage);

    await repo.getMySessions(sessionType: 'Race', page: 2);

    final request = adapter.requests.single;
    expect(request.method, 'GET');
    expect(request.path, '/me/sessions');
    expect(request.queryParameters, {'sessionType': 'Race', 'page': 2, 'pageSize': 15});
    expect(request.uri.toString(), 'http://test/api/v1/me/sessions?sessionType=Race&page=2&pageSize=15');
  });

  test('sessionType이 없으면 쿼리에 넣지 않고 기본은 1페이지 15개다', () async {
    final (repo, adapter) = _repoReturning(200, _emptyPage);

    await repo.getMySessions();

    expect(adapter.requests.single.queryParameters, {'page': 1, 'pageSize': 15});
  });

  test('getMySessions는 응답을 SessionsPage로 파싱한다', () async {
    final (repo, _) = _repoReturning(200, '''
{"page":1,"pageSize":15,"total":1,"items":[
  {"sessionId":"s1","classifiedAt":"2026-10-17T12:10:00Z","trackName":"Spa","sessionType":"Race",
   "sessionKind":"Race","gameMode":"DriverCareer","seasonId":null,"carCount":22,"myPosition":4,
   "myGridPosition":6,"myResultStatus":"Finished","myBestLapTimeMs":105321,"myPoints":12}
]}''');

    final page = await repo.getMySessions();

    expect(page.total, 1);
    expect(page.items.single.sessionId, 's1');
    expect(page.items.single.myPosition, 4);
  });

  test('getMySession은 GET /me/sessions/{id} 응답을 SessionDetail로 파싱한다', () async {
    final (repo, adapter) = _repoReturning(200, _detailBody);

    final detail = await repo.getMySession('s1');

    expect(adapter.requests.single.method, 'GET');
    expect(adapter.requests.single.path, '/me/sessions/s1');
    expect(detail.header.totalLaps, 15);
    expect(detail.results.single.name, 'NORRIS');
  });

  test('남의 세션·없는 세션(404)은 statusCode가 404인 ApiException이 된다', () async {
    final (repo, _) = _repoReturning(404);

    await expectLater(
      repo.getMySession('missing'),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 404)),
    );
  });

  test('목록 조회 실패도 ApiException이다', () async {
    final (repo, _) = _repoReturning(500);

    await expectLater(repo.getMySessions(), throwsA(isA<ApiException>()));
  });
}
