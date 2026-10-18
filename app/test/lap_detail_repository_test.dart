import 'package:flutter_test/flutter_test.dart';
import 'package:simcenter_app/core/network/api_exception.dart';
import 'package:simcenter_app/features/lap_detail/data/lap_detail_repository.dart';
import 'package:simcenter_app/features/laps/data/laps_repository.dart';

import 'support/stub_adapter.dart';

const _emptyLaps = '{"personalBest":null,"laps":{"page":1,"pageSize":10,"total":0,"items":[]}}';

const _detailBody = '''
{"lap":{"lapId":"l 1","trackName":"Jeddah","gameCode":"F1_25","sessionType":"TimeTrial","lapTimeMs":98448,
  "sectors":[],"isValid":true,"isRankingEligible":true,"setAt":"2026-07-26T09:00:00Z"},
 "trackId":"t1","countryCode":"SA","sessionId":null,"car":null,"conditions":null,"comparison":null}''';

const _traceBody = '''
{"lapId":"l1","resolutionM":5,"sampleCount":2,"timeMs":[0,90],"speedKph":[200,210],"throttle":[100,100],
 "brake":[0,0],"steer":[0,1],"gear":[7,7],"rpm":[11000,11100]}''';

void main() {
  group('LapsRepository.getMyLaps', () {
    test('validOnly=true면 쿼리에 validOnly=true를 붙인다', () async {
      final adapter = StubAdapter(200, _emptyLaps);
      final repo = LapsRepository(stubDio(adapter));

      await repo.getMyLaps(trackId: 't1', sort: 'fastest', validOnly: true, pageSize: 10);

      final request = adapter.requests.single;
      expect(request.path, '/me/laps');
      expect(request.queryParameters, {
        'trackId': 't1',
        'sort': 'fastest',
        'validOnly': true,
        'page': 1,
        'pageSize': 10,
      });
    });

    test('validOnly 기본값(false)이면 쿼리에 붙이지 않는다', () async {
      final adapter = StubAdapter(200, _emptyLaps);
      final repo = LapsRepository(stubDio(adapter));

      await repo.getMyLaps(trackId: 't1');

      expect(adapter.requests.single.queryParameters.containsKey('validOnly'), isFalse);
    });
  });

  group('LapDetailRepository', () {
    test('getLapDetail은 GET /me/laps/{lapId}를 호출하고(Id는 인코딩) 응답을 읽는다', () async {
      final adapter = StubAdapter(200, _detailBody);
      final repo = LapDetailRepository(stubDio(adapter));

      final detail = await repo.getLapDetail('l 1');

      expect(adapter.requests.single.path, '/me/laps/l%201');
      expect(detail.lap.lapId, 'l 1');
      expect(detail.countryCode, 'SA');
    });

    test('getLapDetail이 404면 statusCode 404인 ApiException을 던진다', () async {
      final repo = LapDetailRepository(stubDio(StubAdapter(404)));

      await expectLater(
        repo.getLapDetail('nope'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 404)),
      );
    });

    test('getLapTrace는 GET /me/laps/{lapId}/trace를 호출하고 트레이스를 읽는다', () async {
      final adapter = StubAdapter(200, _traceBody);
      final repo = LapDetailRepository(stubDio(adapter));

      final trace = await repo.getLapTrace('l1');

      expect(adapter.requests.single.path, '/me/laps/l1/trace');
      expect(trace, isNotNull);
      expect(trace!.length, 2);
      expect(trace.speedKph, [200, 210]);
    });

    test('getLapTrace가 404면 null(트레이스 없음)', () async {
      final repo = LapDetailRepository(stubDio(StubAdapter(404)));

      expect(await repo.getLapTrace('l1'), isNull);
    });

    test('getLapTrace가 404 밖의 오류면 ApiException을 던진다', () async {
      final repo = LapDetailRepository(stubDio(StubAdapter(500)));

      await expectLater(repo.getLapTrace('l1'), throwsA(isA<ApiException>()));
    });
  });
}
