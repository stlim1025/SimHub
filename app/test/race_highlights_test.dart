import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simcenter_app/features/lap_detail/domain/lap_detail_models.dart';
import 'package:simcenter_app/features/sessions/domain/race_highlights.dart';
import 'package:simcenter_app/features/sessions/presentation/session_highlights_page.dart';

/// 원 서킷(반지름 100m) 위를 50m/s로 도는 차의 클립 움직임: [fromMs]~[toMs], 200ms 간격, 출발 각도 [startRad].
Map<String, dynamic> _trackJson(int car, {int fromMs = 0, int toMs = 10_000, double startRad = 0}) {
  const radius = 100.0;
  const speed = 50.0;
  final times = [for (var t = fromMs; t <= toMs; t += 200) t];
  double angle(int t) => startRad + speed * (t - fromMs) / 1000 / radius;
  return {
    'carIndex': car,
    'timeMs': times,
    'x': [for (final t in times) radius * math.cos(angle(t))],
    'y': [for (final _ in times) 0],
    'z': [for (final t in times) radius * math.sin(angle(t))],
    'speedKph': [for (final _ in times) 180],
    'gear': [for (final _ in times) 6],
    'throttle': [for (final _ in times) 100],
    'brake': [for (final _ in times) 0],
    'lap': [for (final _ in times) 3],
  };
}

Map<String, dynamic> _clipJson(String kind, int focus, {int? other, int startMs = 0, int endMs = 10_000, int lap = 3}) => {
      'kind': kind,
      'startMs': startMs,
      'endMs': endMs,
      'eventMs': startMs + 5_000,
      'focusCar': focus,
      'otherCar': other,
      'lap': lap,
      'cars': [
        _trackJson(focus, fromMs: startMs, toMs: endMs),
        if (other != null) _trackJson(other, fromMs: startMs, toMs: endMs, startRad: 0.1),
      ],
    };

RaceHighlights _highlights({List<Map<String, dynamic>>? flags}) => RaceHighlights.fromJson({
      'sessionId': 's1',
      'trackId': 't1',
      'gameCode': 'F1_25',
      'totalLaps': 39,
      'cars': [
        {'carIndex': 4, 'name': 'VERSTAPPEN', 'teamColor': '#3671C6', 'isPlayer': false, 'position': 1},
        {'carIndex': 21, 'name': 'ME', 'teamColor': '#E8002D', 'isPlayer': true, 'position': 2},
        {'carIndex': 2, 'name': 'RUSSELL', 'teamColor': '#27F4D2', 'isPlayer': false, 'position': 3},
      ],
      'flags': flags ?? const [],
      'mine': [
        _clipJson('Start', 21, endMs: 4_000),
        _clipJson('Overtake', 21, other: 2, startMs: 20_000, endMs: 30_000, lap: 12),
      ],
      'race': [
        _clipJson('Start', 4, endMs: 4_000),
        _clipJson('Collision', 2, other: 4, startMs: 40_000, endMs: 50_000, lap: 20),
        _clipJson('Finish', 4, startMs: 60_000, endMs: 70_000, lap: 39),
      ],
    });

/// 원 서킷 한 바퀴(반지름 100m, 5m 간격) 내 랩: 서킷 모양을 잡는 데만 쓴다.
LapTrace _circleLap() {
  const count = 126;
  return LapTrace(
    lapId: 'lap-9',
    resolutionM: 5,
    timeMs: [for (var i = 0; i < count; i++) i * 100],
    speedKph: [for (var i = 0; i < count; i++) 180],
    throttle: [for (var i = 0; i < count; i++) 100],
    brake: [for (var i = 0; i < count; i++) 0],
    steer: [for (var i = 0; i < count; i++) 0],
    gear: [for (var i = 0; i < count; i++) 6],
    rpm: [for (var i = 0; i < count; i++) 11000],
    worldPosX: [for (var i = 0; i < count; i++) 100 * math.cos(i * 5 / 100)],
    worldPosZ: [for (var i = 0; i < count; i++) 100 * math.sin(i * 5 / 100)],
  );
}

Future<void> _pumpPlayer(WidgetTester tester, RaceHighlights highlights) async {
  tester.view
    ..physicalSize = const Size(1200, 1000)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(child: HighlightsPlayer(highlights: highlights, trace: _circleLap())),
    ),
  ));
  await tester.pump();
}

String _caption(WidgetTester t) => t.widget<Text>(find.descendant(
      of: find.byKey(const ValueKey('highlights-caption')),
      matching: find.byType(Text),
    )).data!;

void main() {
  group('RaceHighlights.fromJson', () {
    test('서버 enum 이름을 읽고, 중심 차 움직임이 없는 클립·열 길이가 다른 차는 버린다', () {
      final broken = _trackJson(2)..['x'] = [1.0];
      final highlights = RaceHighlights.fromJson({
        'sessionId': 's1',
        'trackId': 't1',
        'gameCode': 'F1_25',
        'totalLaps': 5,
        'cars': const [],
        'flags': [
          {'kind': 'VirtualSafetyCar', 'fromMs': 1000, 'toMs': 2000},
        ],
        'mine': const [],
        'race': [
          _clipJson('Overtake', 4, other: 2)..['cars'] = [_trackJson(4), broken],
          _clipJson('Crash', 9)..['cars'] = [_trackJson(4)],
        ],
      });

      expect(highlights.flags.single.kind, RaceFlagKind.virtualSafetyCar);
      final clip = highlights.race.single;
      expect(clip.kind, HighlightKind.overtake);
      expect(clip.cars.map((c) => c.carIndex), [4]);
      expect(highlights.nameOf(7), '#7');
    });
  });

  group('highlightCaption', () {
    final highlights = _highlights();

    test('랩·장면·드라이버(추월은 →, 충돌은 ↔, 출발은 랩 없이)', () {
      expect(highlightCaption(highlights.mine[0], highlights.nameOf), '출발');
      expect(highlightCaption(highlights.mine[1], highlights.nameOf), '12랩 · 추월 · ME → RUSSELL');
      expect(highlightCaption(highlights.race[1], highlights.nameOf), '20랩 · 충돌 · RUSSELL ↔ VERSTAPPEN');
      expect(highlightCaption(highlights.race[2], highlights.nameOf), '39랩 · 결승 · VERSTAPPEN');
    });
  });

  group('activeRaceFlag', () {
    const flags = [
      HighlightFlag(kind: RaceFlagKind.virtualSafetyCar, fromMs: 1000, toMs: 5000),
      HighlightFlag(kind: RaceFlagKind.safetyCar, fromMs: 3000, toMs: 8000),
      HighlightFlag(kind: RaceFlagKind.redFlag, fromMs: 7000, toMs: 9000),
    ];

    test('구간 밖은 null, 겹치면 적기 > 세이프티카 > 버추얼', () {
      expect(activeRaceFlag(flags, 500), isNull);
      expect(activeRaceFlag(flags, 2000), RaceFlagKind.virtualSafetyCar);
      expect(activeRaceFlag(flags, 4000), RaceFlagKind.safetyCar);
      expect(activeRaceFlag(flags, 7500), RaceFlagKind.redFlag);
      expect(activeRaceFlag(flags, 9500), isNull);
    });
  });

  group('TimedCarPath', () {
    final track = HighlightCarTrack.fromJsonOrNull({
      'carIndex': 1,
      'timeMs': [1000, 2000, 3000, 4000],
      'x': [0.0, 10.0, 20.0, 20.0],
      'z': [0.0, 0.0, 0.0, 0.0],
      'speedKph': [100, 200, 0, 0],
      'gear': [3, 4, 1, 1],
      'throttle': [50, 100, 0, 0],
      'brake': [0, 0, 100, 100],
      'lap': [1, 1, 1, 1],
    })!;
    final path = TimedCarPath(track);

    test('표본 사이는 시간으로 보간하고, 처음 전·끝 뒤에는 그 자리에 멈춘다', () {
      final middle = path.frameAt(1500);
      expect(middle.x, closeTo(5, 1e-9));
      expect(middle.speedKph, closeTo(150, 1e-9));
      expect(middle.gear, 3);
      expect(path.frameAt(0).x, 0);
      expect(path.frameAt(9000).x, 20);
    });

    test('진행 방향은 지나온 경로를 따르고, 멈춘 차는 마지막으로 움직인 방향', () {
      expect(path.frameAt(1500).heading, closeTo(0, 1e-9)); // +X
      expect(path.frameAt(3500).heading, closeTo(0, 1e-9)); // 멈췄어도 +X
      expect(path.headingAt(1500, lookM: 20), closeTo(0, 1e-9));
    });
  });

  group('피트·피니시', () {
    final track = HighlightCarTrack.fromJsonOrNull({
      'carIndex': 2,
      'timeMs': [0, 1000, 2000, 20000, 21000],
      'x': [0.0, 10.0, 20.0, 30.0, 40.0],
      'z': [0.0, 0.0, 0.0, 0.0, 0.0],
      'speedKph': [100, 100, 80, 60, 100],
      'gear': [3, 3, 3, 2, 3],
      'throttle': [50, 50, 50, 50, 50],
      'brake': [0, 0, 0, 0, 0],
      'lap': [5, 5, 5, 5, 5],
      'pit': [0, 1, 1, 2, 2],
    })!;
    final path = TimedCarPath(track);

    test('표본이 오래 끊긴 사이(피트 레인)에는 숨기고, 이름표에 PIT IN·PIT OUT을 붙인다', () {
      expect(path.visibleAt(500), isTrue);
      expect(path.visibleAt(10000), isFalse);
      expect(path.visibleAt(30000), isTrue);
      expect(highlightCarLabel('NORRIS', path, 500), 'NORRIS');
      expect(highlightCarLabel('NORRIS', path, 1500), 'NORRIS · PIT IN');
      expect(highlightCarLabel('NORRIS', path, 20500), 'NORRIS · PIT OUT');
    });

    test('피니시는 결승 클립에서 결승선을 지난 뒤만', () {
      final highlights = _highlights();
      final finish = highlights.race[2];
      expect(highlightFinished(finish, finish.eventMs - 1.0), isFalse);
      expect(highlightFinished(finish, finish.eventMs.toDouble()), isTrue);
      expect(highlightFinished(highlights.race[1], 1e9), isFalse);
    });
  });

  group('HighlightsPlayer', () {
    testWidgets('내 하이라이트부터 첫 장면 캡션과 장면 수를 보인다', (t) async {
      await _pumpPlayer(t, _highlights());

      expect(_caption(t), '출발');
      expect(find.text('1 / 2'), findsOneWidget);
      expect(find.byKey(const ValueKey('highlights-view')), findsOneWidget);
    });

    testWidgets('다음 장면·레이스 하이라이트로 바꾸면 캡션이 바뀐다', (t) async {
      await _pumpPlayer(t, _highlights());

      await t.tap(find.byKey(const ValueKey('highlights-next')));
      await t.pump();
      expect(_caption(t), '12랩 · 추월 · ME → RUSSELL');
      expect(find.text('2 / 2'), findsOneWidget);

      await t.tap(find.byKey(const ValueKey('highlights-reel-race')));
      await t.pump();
      expect(_caption(t), '출발');
      expect(find.text('1 / 3'), findsOneWidget);
    });

    testWidgets('재생하면 클립이 끝날 때 다음 장면으로 넘어간다', (t) async {
      await _pumpPlayer(t, _highlights());

      await t.tap(find.byKey(const ValueKey('highlights-play')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 2000));
      await t.pump(const Duration(milliseconds: 2500));
      await t.pump();

      expect(_caption(t), '12랩 · 추월 · ME → RUSSELL');
      await t.tap(find.byKey(const ValueKey('highlights-play')));
      await t.pump();
    });

    testWidgets('깃발 구간이면 배너를 띄운다', (t) async {
      await _pumpPlayer(t, _highlights(flags: [
        {'kind': 'SafetyCar', 'fromMs': 0, 'toMs': 3000},
      ]));

      expect(
        find.descendant(of: find.byKey(const ValueKey('highlights-flag')), matching: find.text('세이프티카')),
        findsOneWidget,
      );

      await t.tap(find.byKey(const ValueKey('highlights-next')));
      await t.pump();
      expect(find.byKey(const ValueKey('highlights-flag')), findsNothing);
    });

    testWidgets('결승 클립에서 결승선을 지나면 피니시 배너', (t) async {
      await _pumpPlayer(t, _highlights());
      await t.tap(find.byKey(const ValueKey('highlights-reel-race')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('highlights-next')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('highlights-next')));
      await t.pump();
      expect(find.byKey(const ValueKey('highlights-finish')), findsNothing);

      await t.tap(find.byKey(const ValueKey('highlights-play')));
      await t.pump();
      for (var i = 0; i < 12; i++) {
        await t.pump(const Duration(milliseconds: 500));
      }
      expect(find.descendant(of: find.byKey(const ValueKey('highlights-finish')), matching: find.text('피니시')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('highlights-play')));
      await t.pump();
    });

    testWidgets('묶음에 장면이 없으면 안내 문구', (t) async {
      final empty = RaceHighlights.fromJson({
        'sessionId': 's1',
        'trackId': 't1',
        'gameCode': 'F1_25',
        'totalLaps': 5,
        'cars': const [],
        'flags': const [],
        'mine': const [],
        'race': const [],
      });
      await _pumpPlayer(t, empty);

      expect(find.text('장면이 없어요.'), findsOneWidget);
    });
  });
}
