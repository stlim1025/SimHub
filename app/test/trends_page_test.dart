import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simcenter_app/features/trends/data/trends_repository.dart';
import 'package:simcenter_app/features/trends/domain/trends_models.dart';
import 'package:simcenter_app/features/trends/presentation/trend_chart.dart';
import 'package:simcenter_app/features/trends/presentation/trends_page.dart';

import 'support/fakes.dart';

class _FakeTrendsRepository implements TrendsRepository {
  _FakeTrendsRepository(this.trends);

  final Trends trends;
  final gameCodes = <String?>[];

  @override
  Future<Trends> getMyTrends({String? gameCode}) async {
    gameCodes.add(gameCode);
    return trends;
  }
}

Map<String, dynamic> _race(String id, String day, String track, int position, {int? pace, double? field, int? consistency}) => {
      'sessionId': id, 'classifiedAt': '2026-10-${day}T12:00:00Z', 'trackName': track, 'countryCode': 'IT',
      'sessionKind': 'Race', 'isSprint': false, 'gameMode': 'DriverCareer', 'aiDifficulty': 103, 'grid': 4,
      'position': position, 'resultStatus': 'Finished', 'teammatePaceGapPerLapMs': pace, 'fieldPaceGapPercent': field,
      'consistencyMs': consistency, 'cleanLaps': consistency == null ? null : 20,
    };

Trends _trends() => Trends.fromJson({
      'races': [
        _race('r1', '18', 'Miami', 22, pace: 1524, field: 1.6, consistency: 640),
        _race('r2', '24', 'Monaco', 2, pace: -925, field: -1.1, consistency: 410),
        _race('r3', '30', 'Austria', 1, pace: -1592, field: -1.5, consistency: 380),
      ],
      'qualifying': [
        {'weekendId': 'w1', 'at': '2026-10-24T10:00:00Z', 'trackName': 'Monaco', 'countryCode': 'MC', 'aiDifficulty': 103,
          'position': 5, 'teammateGapMs': -179, 'teammateGapPercent': -0.24},
      ],
      'weeklyLaps': [
        {'weekStart': '2026-10-12', 'laps': 120},
        {'weekStart': '2026-10-19', 'laps': 0},
        {'weekStart': '2026-10-26', 'laps': 64},
      ],
      'tracks': [
        {
          'trackId': 't1', 'trackName': 'Silverstone', 'countryCode': 'GB', 'lapCount': 41, 'points': [
            {'at': '2026-10-20T10:00:00Z', 'sessionType': 'TimeTrial', 'sessionBestMs': 84000, 'bestSoFarMs': 84000},
            {'at': '2026-10-21T10:00:00Z', 'sessionType': 'TimeTrial', 'sessionBestMs': 83000, 'bestSoFarMs': 83000},
          ],
        },
        {
          'trackId': 't2', 'trackName': 'Monaco', 'countryCode': 'MC', 'lapCount': 12, 'points': [
            {'at': '2026-10-22T10:00:00Z', 'sessionType': 'Qualifying', 'sessionBestMs': 72684, 'bestSoFarMs': 72684},
          ],
        },
      ],
    });

Future<_FakeTrendsRepository> _pump(WidgetTester tester, {Trends? trends, Size size = const Size(1600, 2600)}) async {
  setViewSize(tester, size);
  final repo = _FakeTrendsRepository(trends ?? _trends());
  await tester.pumpWidget(ProviderScope(
    overrides: [trendsRepositoryProvider.overrideWithValue(repo)],
    child: const MaterialApp(home: Scaffold(body: TrendsPage())),
  ));
  await tester.pumpAndSettle();
  return repo;
}

TrendChart _chartIn(WidgetTester tester, String cardKey) =>
    tester.widget<TrendChart>(find.descendant(of: find.byKey(ValueKey(cardKey)), matching: find.byType(TrendChart)));

void main() {
  testWidgets('레이스 결과·AI·팀메이트 대비·필드 대비·꾸준함·주행량·최고 랩 변화 그래프를 시간 순으로 그린다', (t) async {
    final repo = await _pump(t);

    expect(repo.gameCodes, isNotEmpty);
    for (final key in [
      'trend-race-results', 'trend-ai-difficulty', 'trend-race-pace', 'trend-qualifying', 'trend-field-pace',
      'trend-consistency', 'trend-weekly-laps', 'trend-progression',
    ]) {
      expect(find.byKey(ValueKey(key)), findsOneWidget, reason: key);
    }

    final results = _chartIn(t, 'trend-race-results');
    expect(results.invertY, isTrue); // P1이 위
    expect([for (final p in results.points) p.value], [22, 2, 1]);
    expect(results.points.first.secondary, 4); // 출발 그리드
    expect([for (final p in _chartIn(t, 'trend-race-pace').points) p.value], [1.524, -0.925, -1.592]);
    expect([for (final p in _chartIn(t, 'trend-qualifying').points) p.value], [-0.179]);
    expect([for (final p in _chartIn(t, 'trend-consistency').points) p.value], [0.64, 0.41, 0.38]);
    expect([for (final p in _chartIn(t, 'trend-weekly-laps').points) p.value], [120, 0, 64]);
    // 기본 트랙 = 랩이 가장 많은 트랙(서버 순서 첫 번째).
    expect([for (final p in _chartIn(t, 'trend-progression').points) p.value], [84000, 83000]);
  });

  testWidgets('최고 랩 변화 트랙 메뉴로 다른 트랙을 고른다', (t) async {
    await _pump(t);

    await t.tap(find.byKey(const ValueKey('trend-progression-track')));
    await t.pumpAndSettle();
    await t.tap(find.text('Monaco').last);
    await t.pumpAndSettle();

    expect([for (final p in _chartIn(t, 'trend-progression').points) p.value], [72684]);
  });

  testWidgets('점에 마우스를 올리면 그 레이스와 값을 툴팁으로 보인다', (t) async {
    await _pump(t);

    final chart = find.descendant(of: find.byKey(const ValueKey('trend-race-pace')), matching: find.byType(TrendChart));
    final gesture = await t.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    await gesture.moveTo(t.getTopRight(chart) + const Offset(-20, 60));
    await t.pumpAndSettle();

    final tooltip = find.byKey(const ValueKey('trend-chart-tooltip'));
    expect(tooltip, findsOneWidget);
    expect(find.descendant(of: tooltip, matching: find.textContaining('Austria')), findsOneWidget);
    expect(find.descendant(of: tooltip, matching: find.text('-1.592s / lap')), findsOneWidget);
    await gesture.removePointer();
  });

  testWidgets('기록이 없으면 안내 문구, 좁은 화면에서도 넘치지 않는다', (t) async {
    await _pump(t, trends: const Trends(races: [], qualifying: [], weeklyLaps: [], tracks: []));
    expect(find.text('아직 기록된 레이스·랩이 없어요.'), findsOneWidget);

    await _pump(t, size: const Size(360, 4000));
    expect(t.takeException(), isNull);
    expect(find.byKey(const ValueKey('trend-progression')), findsOneWidget);
  });

  group('trend_chart 순수 함수', () {
    test('trendRange는 막대면 0을 담고 위아래 여유를 둔다', () {
      final range = trendRange([1, 3], includeZero: true)!;
      expect(range.min, lessThan(0));
      expect(range.max, greaterThan(3));
      expect(trendRange(const [], includeZero: false), isNull);
    });

    test('trendXTicks는 많으면 건너뛰고 마지막 점을 넣는다', () {
      expect(trendXTicks(3), [0, 1, 2]);
      final ticks = trendXTicks(30);
      expect(ticks.first, 0);
      expect(ticks.last, 29);
      expect(ticks.length, lessThanOrEqualTo(7));
      // 좁은 그래프: 눈금 수를 줄인다.
      expect(trendXTicks(30, maxTicks: 3).length, lessThanOrEqualTo(4));
    });

    test('trendHoverIndex는 칸 번호로 바꾸고 범위를 벗어나지 않는다', () {
      expect(trendHoverIndex(dx: 0, width: 464, count: 4), 0);
      expect(trendHoverIndex(dx: 10000, width: 464, count: 4), 3);
      expect(trendHoverIndex(dx: 100, width: 464, count: 0), isNull);
    });
  });
}
