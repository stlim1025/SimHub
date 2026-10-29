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
      'standings': [
        {'timeMs': startMs, 'lap': lap, 'cars': [4, 21, 2], 'gapMs': [0, 1234, null], 'lapsDown': [0, 0, 0], 'state': [0, 1, 0], 'tyre': [1, 3, 0]},
        {'timeMs': startMs + 3000, 'lap': lap, 'cars': [21, 4, 2], 'gapMs': [0, 800, 90000], 'lapsDown': [0, 0, 1], 'state': [2, 0, 3]},
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

Future<void> _pumpPlayer(WidgetTester tester, RaceHighlights highlights, {double width = 1200}) async {
  tester.view
    ..physicalSize = Size(width, 1000)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(child: HighlightsPlayer(highlights: highlights, trace: _circleLap())),
    ),
  ));
  await tester.pump();
}

/// 하단 자막: 머리 칸 + 본문(없으면 머리 칸만).
String _caption(WidgetTester t) {
  final tag = t.widget<Text>(find.byKey(const ValueKey('highlights-caption-tag'))).data!;
  final title = find.byKey(const ValueKey('highlights-caption-title'));
  return title.evaluate().isEmpty ? tag : '$tag | ${t.widget<Text>(title).data}';
}

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

  group('하단 자막', () {
    final highlights = _highlights();

    test('머리 칸은 랩·장면(출발은 랩 없이), 본문은 드라이버(추월 →, 충돌 ↔)', () {
      expect(highlightCaptionTag(highlights.mine[0]), '출발');
      expect(highlightCaptionTitle(highlights.mine[0], highlights.nameOf), '');
      expect(highlightCaptionTag(highlights.mine[1]), 'LAP 12 · 추월');
      expect(highlightCaptionTitle(highlights.mine[1], highlights.nameOf), 'ME → RUSSELL');
      expect(highlightCaptionTitle(highlights.race[1], highlights.nameOf), 'RUSSELL ↔ VERSTAPPEN');
      expect(highlightCaptionTag(highlights.race[2]), 'LAP 39 · 결승');
      expect(highlightCaptionTitle(highlights.race[2], highlights.nameOf), 'VERSTAPPEN');
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
      'tyre': [2, 2, 2, 1, 1],
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

    test('컴파운드는 그 순간 바로 앞 표본 값(피트에서 바뀐다), 열이 없으면 모름', () {
      expect(path.tyreAt(500), HighlightTyre.medium);
      expect(path.tyreAt(20500), HighlightTyre.soft);
      expect(TimedCarPath(HighlightCarTrack.fromJsonOrNull(_trackJson(1, fromMs: 0, toMs: 1000))!).tyreAt(0), HighlightTyre.unknown);
    });

    test('피니시는 결승 클립에서 결승선을 지난 뒤만', () {
      final highlights = _highlights();
      final finish = highlights.race[2];
      expect(highlightFinished(finish, finish.eventMs - 1.0), isFalse);
      expect(highlightFinished(finish, finish.eventMs.toDouble()), isTrue);
      expect(highlightFinished(highlights.race[1], 1e9), isFalse);
    });
  });

  group('순위표', () {
    test('프레임을 읽고, 시각마다 그 전 마지막 프레임을 고른다', () {
      final clip = _highlights().mine[1];
      expect(clip.standings, hasLength(2));
      expect(clip.standingAt(19000)!.rows.first.carIndex, 4);           // 처음 전은 첫 프레임
      expect(clip.standingAt(22000)!.rows.first.carIndex, 4);
      expect(clip.standingAt(23500)!.rows.first.carIndex, 21);
      expect(clip.standingAt(23500)!.rows.first.state, StandingState.finished);
    });

    test('이름은 세 글자, 간격은 Leader·+1.2·+1:10.2·+1 LAP·빈 글자', () {
      expect(standingAbbreviation('VERSTAPPEN'), 'VER');
      expect(standingAbbreviation('GOMDOL SUPER'), 'GOM');
      expect(standingAbbreviation('PÉREZ'), 'PÉR');
      const row = (carIndex: 1, gapMs: 1234, lapsDown: 0, state: StandingState.running, tyre: HighlightTyre.unknown);
      expect(standingGapText(row, leader: true), 'Leader');
      expect(standingGapText(row, leader: false), '+1.2');
      expect(standingGapText((carIndex: 1, gapMs: 90000, lapsDown: 2, state: StandingState.running, tyre: HighlightTyre.unknown), leader: false), '+2 LAPS');
      expect(standingGapText((carIndex: 1, gapMs: null, lapsDown: 0, state: StandingState.running, tyre: HighlightTyre.unknown), leader: false), '');
      expect(standingGapText((carIndex: 1, gapMs: 59_940, lapsDown: 0, state: StandingState.running, tyre: HighlightTyre.unknown), leader: false), '+59.9');
      expect(standingGapText((carIndex: 1, gapMs: 59_960, lapsDown: 0, state: StandingState.running, tyre: HighlightTyre.unknown), leader: false), '+1:00.0');
      expect(standingGapText((carIndex: 1, gapMs: 70_230, lapsDown: 0, state: StandingState.running, tyre: HighlightTyre.unknown), leader: false), '+1:10.2');
      expect(standingGapText((carIndex: 1, gapMs: 125_000, lapsDown: 0, state: StandingState.running, tyre: HighlightTyre.unknown), leader: false), '+2:05.0');
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
      expect(_caption(t), 'LAP 12 · 추월 | ME → RUSSELL');
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

      expect(_caption(t), 'LAP 12 · 추월 | ME → RUSSELL');
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

    testWidgets('왼쪽에 순위표: 랩, 순위·이름·간격, 피트 P', (t) async {
      await _pumpPlayer(t, _highlights());

      final tower = find.byKey(const ValueKey('highlights-standings'));
      expect(t.widget<Text>(find.descendant(of: tower, matching: find.byKey(const ValueKey('highlights-standings-lap')))).textSpan!.toPlainText(), 'LAP  3 / 39');
      expect(find.descendant(of: find.byKey(const ValueKey('standing-row-4')), matching: find.text('Leader')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('standing-row-21')), matching: find.text('+1.2')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('standing-row-21')), matching: find.text('PIT')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('standing-row-21')), matching: find.text('ME')), findsOneWidget);
      // 컴파운드 원: 소프트 S·하드 H, 모르는 차는 원 없음.
      expect(find.descendant(of: find.byKey(const ValueKey('standing-tyre-4')), matching: find.text('S')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('standing-tyre-21')), matching: find.text('H')), findsOneWidget);
      expect(find.byKey(const ValueKey('standing-tyre-2')), findsNothing);
    });

    testWidgets('넓으면 재생기 폭은 그대로 두고 오른쪽에 장면 목록표, 줄을 누르면 그 장면으로', (t) async {
      await _pumpPlayer(t, _highlights(), width: 1600);

      final player = t.getRect(find.byKey(const ValueKey('highlights-player')));
      final list = t.getRect(find.byKey(const ValueKey('highlights-list')));
      expect(player.width, lessThanOrEqualTo(1100));
      expect(player.width, greaterThan(1050));
      expect(list.left, greaterThan(player.right));
      expect(list.height, closeTo(player.height, 1));
      final row1 = find.byKey(const ValueKey('highlights-list-row-1'));
      expect(find.descendant(of: row1, matching: find.text('L12')), findsOneWidget);
      // 추월: 두 드라이버 이름 사이 →, 이름 앞 팀 색 막대.
      for (final text in ['ME', '→', 'RUSSELL', '추월']) {
        expect(find.descendant(of: row1, matching: find.textContaining(text)), findsOneWidget);
      }
      Color teamBar(int car) => t.widget<Container>(find.descendant(of: row1, matching: find.byKey(ValueKey('highlights-list-team-$car')))).color!;
      expect(teamBar(21), const Color(0xFFE8002D));
      expect(teamBar(2), const Color(0xFF27F4D2));
      // 출발은 드라이버 없이 종류 칩만.
      final row0 = find.byKey(const ValueKey('highlights-list-row-0'));
      expect(find.descendant(of: row0, matching: find.byKey(const ValueKey('highlights-list-team-21'))), findsNothing);
      // 종류마다 칩 색이 다르다(추월 ≠ 출발).
      Color chip(int i) => (t.widget<Container>(find.byKey(ValueKey('highlights-list-kind-$i'))).decoration! as BoxDecoration).color!;
      expect(chip(0), isNot(chip(1)));

      await t.tap(find.byKey(const ValueKey('highlights-list-row-1')));
      await t.pump();
      expect(_caption(t), 'LAP 12 · 추월 | ME → RUSSELL');
      expect(find.text('2 / 2'), findsOneWidget);

      // 묶음을 바꾸면 목록도 그 묶음 장면.
      await t.tap(find.byKey(const ValueKey('highlights-reel-race')));
      await t.pump();
      expect(find.byKey(const ValueKey('highlights-list-row-2')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('highlights-list-row-1')), matching: find.text('충돌')), findsOneWidget);
    });

    testWidgets('목록표 폭이 안 남으면 재생기 아래에 둔다', (t) async {
      await _pumpPlayer(t, _highlights());

      final player = t.getRect(find.byKey(const ValueKey('highlights-player')));
      final list = t.getRect(find.byKey(const ValueKey('highlights-list')));
      expect(list.top, greaterThan(player.bottom));
      expect(t.takeException(), isNull);
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
