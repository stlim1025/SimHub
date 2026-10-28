import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simcenter_app/core/network/api_exception.dart';
import 'package:simcenter_app/core/theme/app_theme.dart';
import 'package:simcenter_app/features/lap_detail/domain/lap_compare.dart';
import 'package:simcenter_app/features/lap_detail/domain/lap_detail_models.dart';

import 'support/fakes.dart';
import 'support/lap_detail_harness.dart';

/// 첫 호출만 실패하고 이후엔 정상 응답하는 저장소(다시 시도 검증용).
class _FlakyDetailRepository extends FakeLapDetailRepository {
  _FlakyDetailRepository({super.details});

  int failuresLeft = 1;

  @override
  Future<LapDetail> getLapDetail(String lapId, {LapCompareSelection compare = LapCompareSelection.defaults}) async {
    if (failuresLeft-- > 0) throw ApiException('서버가 아파요.', statusCode: 500);
    return super.getLapDetail(lapId, compare: compare);
  }
}

FakeLapDetailRepository _repo([LapDetail? detail]) => FakeLapDetailRepository(details: {'l1': detail ?? sampleDetail()});

Future<void> _tapAndSettle(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('셋업이 저장된 랩은 Lap Details의 View Setup으로 셋업 값·셋업 진단을 연다', (t) async {
    const setup = <String, Object?>{'frontWing': 40, 'rearWing': 26, 'brakeBias': 54, 'onThrottle': 100};
    const car = CarSnapshot(visualTyreCompound: 16, tyreAgeLaps: 3, setup: setup);
    final router = await pumpLapDetail(t, detailRepo: _repo(sampleDetail(car: car)));

    await _tapAndSettle(t, find.byKey(const ValueKey('lap-view-setup')));

    expect(locationOf(router), '/laps/l1/setup');
    expect(find.text('Jeddah Setup'), findsOneWidget);
    expect(find.byKey(const ValueKey('setup-diagnosis')), findsOneWidget);
  });

  testWidgets('셋업이 없는 랩에는 View Setup이 없다', (t) async {
    await pumpLapDetail(t, detailRepo: _repo());
    expect(find.byKey(const ValueKey('lap-view-setup')), findsNothing);
  });

  testWidgets('머리줄은 국기 + 트랙 이름 · 랩타임이고, 뒤로 가기는 그 트랙의 표로 간다', (t) async {
    final router = await pumpLapDetail(t, detailRepo: _repo());

    expect(find.text('Jeddah Lap 1:38.448'), findsOneWidget);
    expect(find.byKey(const ValueKey('track-flag-SA')), findsWidgets);

    await _tapAndSettle(t, find.byTooltip('트랙 표로'));

    expect(locationOf(router), '/laps/tracks/t1');
  });

  testWidgets('탭 3개(Lap Details · Telemetry · Your Best Laps)를 보이고, 주소에 tab이 없거나 모르는 값이면 Lap Details', (t) async {
    for (final location in ['/laps/l1', '/laps/l1?tab=nope']) {
      await pumpLapDetail(t, detailRepo: _repo(), location: location);

      expect(find.widgetWithText(Tab, 'Lap Details'), findsOneWidget);
      expect(find.widgetWithText(Tab, 'Telemetry'), findsOneWidget);
      expect(find.widgetWithText(Tab, 'Your Best Laps'), findsOneWidget);
      expect(t.widget<TabBar>(find.byType(TabBar)).controller?.index, 0, reason: location);
      expect(find.text('Lap Time'), findsOneWidget, reason: location);
    }
  });

  testWidgets('탭을 누르면 주소의 tab만 바뀌고(전환 없이) 내용이 바뀐다', (t) async {
    final router = await pumpLapDetail(t, detailRepo: _repo());

    await _tapAndSettle(t, find.widgetWithText(Tab, 'Your Best Laps'));
    expect(locationOf(router), '/laps/l1?tab=best');
    expect(find.text('Lap Time'), findsNothing);

    await _tapAndSettle(t, find.widgetWithText(Tab, 'Telemetry'));
    expect(locationOf(router), '/laps/l1?tab=telemetry');

    await _tapAndSettle(t, find.widgetWithText(Tab, 'Lap Details'));
    expect(locationOf(router), '/laps/l1?tab=details');
    expect(find.text('Lap Time'), findsOneWidget);
  });

  testWidgets('주소가 바뀌면 탭 막대의 선택도 따라간다', (t) async {
    final router = await pumpLapDetail(t, detailRepo: _repo(), location: '/laps/l1?tab=best');
    expect(t.widget<TabBar>(find.byType(TabBar)).controller?.index, 3);

    router.go('/laps/l1?tab=telemetry');
    await t.pumpAndSettle();

    expect(t.widget<TabBar>(find.byType(TabBar)).controller?.index, 1);
  });

  testWidgets('탭 아래에 "Compare with: Your best lap"(기본)과 "Filter by"가 있다', (t) async {
    await pumpLapDetail(t, detailRepo: _repo());

    expect(find.text('Compare with: Your best lap'), findsOneWidget);
    expect(find.text('Filter by'), findsOneWidget);
  });

  testWidgets('이 랩이 내 최고면 비교 칸에 그렇게 보이고, 유효 랩이 없으면 비교할 랩이 없다고 보인다', (t) async {
    await pumpLapDetail(t, detailRepo: _repo(sampleDetail(comparison: sampleComparison(id: 'l1'))));
    expect(find.text('이 랩이 내 최고 기록'), findsOneWidget);

    await pumpLapDetail(t, detailRepo: _repo(sampleDetail(withComparison: false)));
    expect(find.text('비교할 유효 랩이 없어요'), findsOneWidget);
  });

  testWidgets('없거나 남의 랩(404)이면 찾을 수 없음 + Laps 링크', (t) async {
    final router = await pumpLapDetail(t, detailRepo: FakeLapDetailRepository(), location: '/laps/nope');

    expect(find.text('찾을 수 없는 랩입니다.'), findsOneWidget);
    expect(find.text('다시 시도'), findsNothing);

    await _tapAndSettle(t, find.text('Laps'));

    expect(locationOf(router), '/laps');
  });

  testWidgets('그 밖의 오류는 다시 시도할 수 있다', (t) async {
    final repo = _FlakyDetailRepository(details: {'l1': sampleDetail()});
    await pumpLapDetail(t, detailRepo: repo);

    expect(find.text('서버가 아파요.'), findsOneWidget);

    await _tapAndSettle(t, find.text('다시 시도'));

    expect(find.text('Jeddah Lap 1:38.448'), findsOneWidget);
    expect(repo.detailRequests, ['l1']); // 실패한 첫 호출은 기록 전에 던진다 — 다시 시도한 호출만 남는다.
  });

  group('반응형 (900px 기준)', () {
    testWidgets('넓으면 2열: Lap Time과 Car & Tyres가 나란히 놓인다', (t) async {
      await pumpLapDetail(t, detailRepo: _repo(), size: const Size(1400, 3000));

      expect(t.getTopLeft(find.text('Lap Time')).dy, t.getTopLeft(find.text('Car & Tyres')).dy);
      expect(t.getTopLeft(find.text('Lap Time')).dx, lessThan(t.getTopLeft(find.text('Car & Tyres')).dx));
    });

    testWidgets('좁으면 1열: Car & Tyres가 Lap Details 아래에 온다', (t) async {
      await pumpLapDetail(t, detailRepo: _repo(), size: const Size(800, 4000));

      expect(t.getTopLeft(find.text('Car & Tyres')).dy, greaterThan(t.getTopLeft(find.text('Lap Details').last).dy));
    });

    for (final tab in ['details', 'telemetry', 'best']) {
      testWidgets('375px에서 $tab 탭이 두 테마 모두 넘치지 않는다', (t) async {
        final traces = {'l1': traceOf('l1', count: 50), 'best': traceOf('best', count: 50)};
        final laps = FakeLapsRepository(laps: [sampleLap(), sampleLap(id: 'l2', ms: 99000)]);
        for (final theme in [AppTheme.dark, AppTheme.light]) {
          await pumpLapDetail(
            t,
            detailRepo: FakeLapDetailRepository(details: {'l1': sampleDetail()}, traces: traces),
            lapsRepo: laps,
            location: '/laps/l1?tab=$tab',
            size: const Size(375, 5000),
            theme: theme,
          );

          expect(t.takeException(), isNull, reason: '$tab ${theme.brightness}');
        }
      });
    }
  });
}
