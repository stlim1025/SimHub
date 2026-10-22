import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simcenter_app/core/network/api_exception.dart';
import 'package:simcenter_app/core/theme/app_colors.dart';
import 'package:simcenter_app/core/widgets/team_name_cell.dart';
import 'package:simcenter_app/features/profile/application/selected_game_provider.dart';
import 'package:simcenter_app/features/setups/application/setups_providers.dart';
import 'package:simcenter_app/features/setups/data/setups_repository.dart';
import 'package:simcenter_app/features/setups/domain/setup_models.dart';
import 'package:simcenter_app/features/setups/domain/setups_display.dart';
import 'package:simcenter_app/features/tracks/data/tracks_repository.dart';

import 'support/setups_fakes.dart';
import 'support/stub_adapter.dart';

const _tracksBody = '''
[{"trackId":"au","name":"Australia","countryCode":"AU","displayOrder":1,"circuitName":"Melbourne Grand Prix Circuit",
  "dryCount":10,"wetCount":3},
 {"trackId":"at-r","name":"Austria Reverse","countryCode":"AT","displayOrder":25,"circuitName":null,
  "dryCount":2,"wetCount":0}]''';

const _listBody = '''
{"track":{"trackId":"au","name":"Australia","countryCode":"AU","circuitName":"Melbourne Grand Prix Circuit"},
 "condition":"Wet","fetchedAt":"2026-10-22T09:00:00Z",
 "items":[{"id":"s1","rank":1,"teamName":"Aston Martin","sessionType":"Time Trial",
   "lapTimeMs":75974,"sourceUrl":"https://www.f1laps.com/x/"}]}''';

const _emptyListBody = '''
{"track":{"trackId":"au","name":"Australia","countryCode":"AU","circuitName":null},
 "condition":"Dry","fetchedAt":null,"items":[]}''';

const _detailBody = '''
{"id":"s1","rank":1,"gameCode":"F1_25",
 "track":{"trackId":"au","name":"Australia","countryCode":"AU","circuitName":"Melbourne Grand Prix Circuit"},
 "condition":"Dry","teamName":"Aston Martin","sessionType":"Time Trial","lapTimeMs":75974,
 "steering":null,"setOn":"2025-12-22","sourceUrl":"https://www.f1laps.com/x/","fetchedAt":"2026-10-22T09:00:00Z",
 "sections":[{"title":"Aerodynamics","items":[{"label":"Front Wing","value":"23"},{"label":"Rear Wing","value":"21"}]},
   {"title":"Tyres","items":[{"label":"Front Right Tyre Pressure","value":"29.5"}]}]}''';

const _overviewBody = '''
{"track":{"trackId":"au","name":"Australia","countryCode":"AU","gameCode":"F1_26","circuitName":"Melbourne",
   "grandPrixName":"Australian GP","lengthKm":5.278,"f1LapRecord":79813},
 "myStats":{"lapCount":42,"sessionCount":5,"bestLapMs":77101,"bestTimeTrialLapMs":null,"averageLapMs":86500.4,
   "averageAiDifficulty":82},
 "topTimeTrial":[{"rank":1,"displayName":"tt_driver_1","teamName":"Red Bull Racing","lapTimeMs":77101,"lapId":"l1"}],
 "myBestLaps":[{"lapId":"m1","lapTimeMs":78000,"sessionType":"TimeTrial","teamName":null,"isValid":false,
   "setAt":"2026-10-20T10:00:00Z"}],
 "mapLapId":"l1"}''';

void main() {
  group('SetupsRepository', () {
    test('getTracks는 GET /setups/tracks?gameCode=를 호출하고 목록을 읽는다', () async {
      final adapter = StubAdapter(200, _tracksBody);
      final tracks = await SetupsRepository(stubDio(adapter)).getTracks(gameCode: 'F1_26');

      expect(adapter.requests.single.path, '/setups/tracks');
      expect(adapter.requests.single.queryParameters, {'gameCode': 'F1_26'});
      expect(tracks, hasLength(2));
      expect(tracks.first.name, 'Australia');
      expect(tracks.first.circuitName, 'Melbourne Grand Prix Circuit');
      expect(tracks.first.isCalendarRound, isTrue);
      expect(tracks.first.countOf(kSetupConditionWet), 3);
      expect(tracks.last.isCalendarRound, isFalse);
      expect(tracks.last.circuitName, isNull);
    });

    test('getSetups는 trackId·condition 쿼리로 부르고 목록을 읽는다', () async {
      final adapter = StubAdapter(200, _listBody);
      final list = await SetupsRepository(stubDio(adapter)).getSetups(trackId: 'au', condition: 'Wet');

      expect(adapter.requests.single.path, '/setups');
      expect(adapter.requests.single.queryParameters, {'trackId': 'au', 'condition': 'Wet'});
      expect(list.track.name, 'Australia');
      expect(list.condition, 'Wet');
      expect(list.fetchedAt, DateTime.utc(2026, 10, 22, 9));
      expect(list.items.single.teamName, 'Aston Martin');
      expect(list.items.single.lapTimeMs, 75974);
      expect(list.items.single.sourceUrl, 'https://www.f1laps.com/x/');
    });

    test('getSetups: 아직 가져오지 않았으면 fetchedAt null + 빈 목록', () async {
      final list = await SetupsRepository(stubDio(StubAdapter(200, _emptyListBody))).getSetups(trackId: 'au', condition: 'Dry');

      expect(list.fetchedAt, isNull);
      expect(list.items, isEmpty);
      expect(list.track.circuitName, isNull);
    });

    test('getSetup은 GET /setups/{id}를 부르고 묶음을 순서대로 읽는다', () async {
      final adapter = StubAdapter(200, _detailBody);
      final detail = await SetupsRepository(stubDio(adapter)).getSetup('s1');

      expect(adapter.requests.single.path, '/setups/s1');
      expect(detail.gameCode, 'F1_25');
      expect(detail.steering, isNull);
      expect(detail.setOn, DateTime(2025, 12, 22));
      expect([for (final s in detail.sections) s.title], ['Aerodynamics', 'Tyres']);
      expect(detail.sections.first.items.first, (label: 'Front Wing', value: '23'));
    });

    test('getSetup: 404면 상태 코드를 가진 ApiException', () async {
      final repo = SetupsRepository(stubDio(StubAdapter(404, '{}')));

      await expectLater(
        repo.getSetup('nope'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 404)),
      );
    });
  });

  group('TracksRepository', () {
    test('getOverview는 GET /tracks/{id}/overview를 부르고 읽는다(랩 레코드 밀리초는 m:ss.mmm)', () async {
      final adapter = StubAdapter(200, _overviewBody);
      final overview = await TracksRepository(stubDio(adapter)).getOverview('au');

      expect(adapter.requests.single.path, '/tracks/au/overview');
      expect(overview.track.gameCode, 'F1_26');
      expect(overview.track.lengthKm, 5.278);
      expect(overview.track.f1LapRecord, '1:19.813');
      expect(overview.myStats.lapCount, 42);
      expect(overview.myStats.bestTimeTrialLapMs, isNull);
      expect(overview.myStats.averageLapMs, 86500);
      expect(overview.myStats.averageAiDifficulty, 82);
      expect(overview.topTimeTrial.single.displayName, 'tt_driver_1');
      expect(overview.myBestLaps.single.isValid, isFalse);
      expect(overview.myBestLaps.single.setAt, DateTime.utc(2026, 10, 20, 10));
      expect(overview.mapLapId, 'l1');
    });

    test('getOverview: 404면 ApiException', () async {
      final repo = TracksRepository(stubDio(StubAdapter(404, '{}')));

      await expectLater(
        repo.getOverview('x'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 404)),
      );
    });
  });

  group('providers', () {
    test('setupTracksProvider는 선택한 게임 코드를 넘긴다', () async {
      final repo = FakeSetupsRepository(tracks: [setupTrackOf('au', 'Australia')]);
      final container = ProviderContainer(overrides: [
        setupsRepositoryProvider.overrideWithValue(repo),
        selectedGameProvider.overrideWithValue('F1_26'),
      ]);
      addTearDown(container.dispose);

      final tracks = await container.read(setupTracksProvider.future);

      expect(repo.trackRequests, ['F1_26']);
      expect(tracks.single.trackId, 'au');
    });

    test('setupListProvider는 트랙·조건을 넘긴다', () async {
      final repo = FakeSetupsRepository();
      final container = ProviderContainer(overrides: [setupsRepositoryProvider.overrideWithValue(repo)]);
      addTearDown(container.dispose);

      await container.read(setupListProvider((trackId: 'au', condition: 'Wet')).future);

      expect(repo.listRequests, [(trackId: 'au', condition: 'Wet')]);
    });
  });

  group('display', () {
    test('normalizeSetupCondition: wet만 Wet', () {
      expect(normalizeSetupCondition('wet'), 'Wet');
      expect(normalizeSetupCondition('WET'), 'Wet');
      expect(normalizeSetupCondition(null), 'Dry');
      expect(normalizeSetupCondition('snow'), 'Dry');
    });

    test('주소: Dry는 쿼리 없음, Wet은 ?condition=wet', () {
      expect(setupsLocation(), '/setups');
      expect(setupsLocation(condition: 'Wet'), '/setups?condition=wet');
      expect(setupTrackLocation('au'), '/setups/au');
      expect(setupTrackLocation('au', condition: 'Wet'), '/setups/au?condition=wet');
      expect(setupDetailLocation('au', 's1'), '/setups/au/s1');
      expect(trackOverviewLocation('au'), '/tracks/au');
      expect(leaderboardLocation('au'), '/leaderboard?trackId=au');
    });

    test('게임 이름: 제목은 F1 25, 이동 경로는 F1 2025', () {
      expect(gameTitleOf('F1_25'), 'F1 25');
      expect(gameTitleOf('F1_26'), 'F1 26');
      expect(gameYearLabelOf('F1_25'), 'F1 2025');
      expect(gameYearLabelOf('F1_26'), 'F1 2026');
      expect(gameYearLabelOf('ACC'), 'ACC');
    });

    test('setupSessionLabel: 서버 값은 표시 이름, 원본 글자는 그대로', () {
      expect(setupSessionLabel('TimeTrial'), 'Time Trial');
      expect(setupSessionLabel('Time Trial'), 'Time Trial');
      expect(setupSessionLabel(null), '-');
    });

    test('teamColorOfName: 팀 이름 글자 → 팀 색', () {
      expect(teamColorOfName('Aston Martin'), AppColors.teamAstonMartin);
      expect(teamColorOfName('Red Bull Racing'), AppColors.teamRedBull);
      expect(teamColorOfName('Racing Bulls'), AppColors.teamRacingBulls);
      expect(teamColorOfName('RB'), AppColors.teamRacingBulls);
      expect(teamColorOfName('Kick Sauber'), AppColors.teamSauber);
      expect(teamColorOfName('Unknown Team'), isNull);
      expect(teamColorOfName(null), isNull);
    });

    testWidgets('TeamNameCell: 이름이 없으면 -', (t) async {
      await t.pumpWidget(const MaterialApp(home: Scaffold(body: TeamNameCell(teamName: null))));
      expect(find.text('-'), findsOneWidget);
    });
  });
}
