import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simcenter_app/core/network/api_exception.dart';
import 'package:simcenter_app/features/seasons/data/seasons_repository.dart';

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

(SeasonsRepository, _StubAdapter) _repoReturning(int status, [String body = '']) {
  final adapter = _StubAdapter(status, body);
  final dio = Dio(BaseOptions(baseUrl: 'http://test/api/v1'))..httpClientAdapter = adapter;
  return (SeasonsRepository(dio), adapter);
}

const _summary = '''
{"seasonId":"se1","gameCode":"F1_25","gameMode":"DriverCareer","firstSessionAt":"2026-10-17T09:00:00Z",
 "lastSessionAt":"2026-10-24T11:30:00Z","roundCount":6,"myPosition":3,"myPoints":87,
 "leaderName":"VERSTAPPEN","leaderPoints":120}''';

const _emptyPage = '{"page":1,"pageSize":20,"total":0,"items":[]}';

const _detailBody = '''
{"season":$_summary,
 "rounds":[{"round":1,"weekendId":"w1","trackName":"Bahrain","firstSessionAt":"2026-10-17T09:00:00Z",
   "winnerName":"NORRIS","myPoints":12,
   "sessions":[{"sessionId":"r1","sessionType":"Race","sessionKind":"Race","myPosition":4,"myResultStatus":"Finished"}]}],
 "standings":{"drivers":[],"constructors":[]}}''';

void main() {
  test('getMySeasons는 GET /me/seasons?page=2&pageSize=20을 호출한다', () async {
    final (repo, adapter) = _repoReturning(200, _emptyPage);

    await repo.getMySeasons(page: 2);

    final request = adapter.requests.single;
    expect(request.method, 'GET');
    expect(request.path, '/me/seasons');
    expect(request.queryParameters, {'page': 2, 'pageSize': 20});
    expect(request.uri.toString(), 'http://test/api/v1/me/seasons?page=2&pageSize=20');
  });

  test('기본은 1페이지 20개다', () async {
    final (repo, adapter) = _repoReturning(200, _emptyPage);

    await repo.getMySeasons();

    expect(adapter.requests.single.queryParameters, {'page': 1, 'pageSize': 20});
  });

  test('getMySeasons는 응답을 SeasonSummaryPage로 파싱한다', () async {
    final (repo, _) = _repoReturning(200, '{"page":1,"pageSize":20,"total":1,"items":[$_summary]}');

    final page = await repo.getMySeasons();

    expect(page.total, 1);
    expect(page.items.single.seasonId, 'se1');
    expect(page.items.single.myPosition, 3);
  });

  test('getMySeason은 GET /me/seasons/{id} 응답을 SeasonDetail로 파싱한다', () async {
    final (repo, adapter) = _repoReturning(200, _detailBody);

    final detail = await repo.getMySeason('se1');

    expect(adapter.requests.single.method, 'GET');
    expect(adapter.requests.single.path, '/me/seasons/se1');
    expect(detail.season.seasonId, 'se1');
    expect(detail.rounds.single.trackName, 'Bahrain');
    expect(detail.rounds.single.sessions.single.sessionId, 'r1');
  });

  test('남의 시즌이거나 없으면 404 ApiException이다', () async {
    final (repo, _) = _repoReturning(404, '{"title":"Not Found","status":404}');

    await expectLater(
      repo.getMySeason('nope'),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 404)),
    );
  });

  test('목록 조회 실패도 ApiException으로 올라온다', () async {
    final (repo, _) = _repoReturning(500, '{"title":"Server Error","status":500}');

    await expectLater(
      repo.getMySeasons(),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 500)),
    );
  });
}
