import 'package:flutter_test/flutter_test.dart';
import 'package:simcenter_app/core/network/api_exception.dart';
import 'package:simcenter_app/features/lap_detail/data/lap_detail_repository.dart';
import 'package:simcenter_app/features/lap_detail/domain/lap_compare.dart';
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

    test('getLapDetail은 기본 비교(best)면 쿼리를 붙이지 않는다', () async {
      final adapter = StubAdapter(200, _detailBody);

      await LapDetailRepository(stubDio(adapter)).getLapDetail('l1');

      expect(adapter.requests.single.queryParameters, isEmpty);
    });

    test('getLapDetail은 비교 선택을 API 쿼리(compare·compareLapId·필터)로 보낸다(D-51)', () async {
      final adapter = StubAdapter(200, _detailBody);
      final repo = LapDetailRepository(stubDio(adapter));

      await repo.getLapDetail(
        'l1',
        compare: const LapCompareSelection(
          kind: LapCompareKind.leaderboard,
          filters: {LapCompareFilter.sameTeam, LapCompareFilter.sameAssists},
        ),
      );
      await repo.getLapDetail(
        'l1',
        compare: const LapCompareSelection(kind: LapCompareKind.lap, compareLapId: 'other-lap-1', filters: {LapCompareFilter.sameTeam}),
      );

      expect(adapter.requests[0].queryParameters, {'compare': 'leaderboard', 'sameTeam': 'true', 'sameAssists': 'true'});
      // 랩 ID 비교에는 필터를 보내지 않는다.
      expect(adapter.requests[1].queryParameters, {'compare': 'lap', 'compareLapId': 'other-lap-1'});
    });

    test('getComparisonTrace는 GET /laps/{lapId}/trace(공개 규칙 경로)를 호출하고, 404면 null', () async {
      final ok = StubAdapter(200, _traceBody);
      final trace = await LapDetailRepository(stubDio(ok)).getComparisonTrace('r 1');
      expect(ok.requests.single.path, '/laps/r%201/trace');
      expect(trace?.length, 2);

      final missing = StubAdapter(404, '{"title":"Resource not found"}');
      expect(await LapDetailRepository(stubDio(missing)).getComparisonTrace('r1'), isNull);

      final failing = StubAdapter(500, '{"title":"boom"}');
      await expectLater(LapDetailRepository(stubDio(failing)).getComparisonTrace('r1'), throwsA(isA<ApiException>()));
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
