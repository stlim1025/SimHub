import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simcenter_app/core/theme/app_colors.dart';
import 'package:simcenter_app/features/auth/domain/user_preferences.dart';
import 'package:simcenter_app/features/lap_detail/domain/lap_detail_models.dart';
import 'package:simcenter_app/features/sessions/domain/broadcast_graphics.dart';
import 'package:simcenter_app/features/sessions/domain/race_highlights.dart';
import 'package:simcenter_app/features/sessions/presentation/highlights_broadcast_overlay.dart';
import 'package:simcenter_app/features/sessions/presentation/highlights_f1tv_graphics.dart';
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

RaceHighlights _highlights({List<Map<String, dynamic>>? flags, List<Map<String, dynamic>>? mine}) => RaceHighlights.fromJson({
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
      'mine': mine ??
          [
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

Future<void> _pumpPlayer(
  WidgetTester tester,
  RaceHighlights highlights, {
  double width = 1200,
  Map<int, int> raceNumbers = const {},
  Map<int, int> gridPositions = const {},
}) async {
  tester.view
    ..physicalSize = Size(width, 1000)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: HighlightsPlayer(highlights: highlights, trace: _circleLap(), raceNumbers: raceNumbers, gridPositions: gridPositions),
      ),
    ),
  ));
  await tester.pump();
}

String _textOf(WidgetTester t, String key) => t.widget<Text>(find.byKey(ValueKey(key))).data!;

/// 하단 자막: 장면 태그 + 이름 자막의 성.
String _caption(WidgetTester t) => '${_textOf(t, 'highlights-caption-tag')} | ${_textOf(t, 'highlights-driver-last')}';

/// 재생을 켜고 [seconds]초 흘린 뒤 멈춘다.
Future<void> _play(WidgetTester t, int seconds) async {
  await t.tap(find.byKey(const ValueKey('highlights-play')));
  await t.pump();
  for (var i = 0; i < seconds * 2; i++) {
    await t.pump(const Duration(milliseconds: 500));
  }
  await t.tap(find.byKey(const ValueKey('highlights-play')));
  await t.pump();
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

    test('장면 태그는 랩·장면(출발은 랩 없이)', () {
      expect(highlightCaptionTag(highlights.mine[0]), '출발');
      expect(highlightCaptionTag(highlights.mine[1]), 'LAP 12 · 추월');
      expect(highlightCaptionTag(highlights.race[2]), 'LAP 39 · 결승');
    });
  });

  group('중계 그래픽 계산', () {
    final highlights = _highlights();
    final start = highlights.mine[0];
    final overtake = highlights.mine[1];
    final collision = highlights.race[1];
    final finish = highlights.race[2];

    test('이름은 윗줄 이름 · 아랫줄 성(성만 오면 그리드 표에서 이름을 찾는다)', () {
      expect(broadcastDriverName('VERSTAPPEN'), (first: 'Max', last: 'VERSTAPPEN'));
      expect(broadcastDriverName('Lando Norris'), (first: 'Lando', last: 'NORRIS'));
      expect(broadcastDriverName('ME'), (first: null, last: 'ME'));
      expect(broadcastDriverName('  '), (first: null, last: ''));
    });

    test('서수 접미사', () {
      expect([1, 2, 3, 4, 11, 12, 13, 21, 22].map(ordinalSuffix), ['ST', 'ND', 'RD', 'TH', 'TH', 'TH', 'TH', 'ST', 'ND']);
    });

    test('순위는 그 순간 순위표에서 읽는다', () {
      expect(highlightPositionAt(overtake, 20_000, 21), 2);
      expect(highlightPositionAt(overtake, 24_000, 21), 1);
      expect(highlightPositionAt(overtake, 20_000, 9), isNull);
    });

    test('자막 오른쪽 칸: 추월 전 CHASING, 추월 뒤·출발은 레이스 스토리, 결승선 뒤 1위는 WINNER, 그 밖은 차 번호', () {
      final chasing = lowerThirdDetail(overtake, 20_000, gridPosition: 5) as LowerThirdChasing;
      expect((chasing.otherCar, chasing.position), (2, 3));
      final story = lowerThirdDetail(overtake, 26_000, gridPosition: 5) as LowerThirdStory;
      expect((story.started, story.now, story.finished), (5, 1, false));
      expect(lowerThirdDetail(start, 0, gridPosition: 5), isA<LowerThirdStory>());
      // 출발 순위를 모르면 스토리 대신 차 번호.
      expect(lowerThirdDetail(start, 0), isA<LowerThirdNumber>());
      expect(lowerThirdDetail(collision, 46_000, gridPosition: 5), isA<LowerThirdNumber>());
      expect(lowerThirdDetail(finish, 60_000, gridPosition: 1), isA<LowerThirdNumber>());
      // 결승 클립 순위표(63초부터 21 · 4 · 2): 4번 차는 2위로, 21번 차는 1위로 결승선을 지난다.
      final finished = lowerThirdDetail(finish, 66_000, gridPosition: 1) as LowerThirdStory;
      expect((finished.started, finished.now, finished.finished), (1, 2, true));
      final won = _highlights(mine: [_clipJson('Finish', 21, startMs: 60_000, endMs: 70_000, lap: 39)]).mine.single;
      expect(lowerThirdDetail(won, 66_000, gridPosition: 3), isA<LowerThirdWinner>());
    });

    test('레이스 컨트롤 메시지: 장면 순간부터, 충돌은 두 차 · 벽 충돌은 한 차 · 리타이어', () {
      final nameOf = highlights.nameOf;
      expect(raceControlMessage(collision, 44_000, nameOf, turn: '4'), isNull);
      expect(raceControlMessage(collision, 45_000, nameOf, turn: '4'), 'TURN 4 INCIDENT INVOLVING RUSSELL AND VERSTAPPEN NOTED');
      expect(raceControlMessage(collision, 45_000, nameOf), 'INCIDENT INVOLVING RUSSELL AND VERSTAPPEN NOTED');
      expect(raceControlMessage(overtake, 26_000, nameOf, turn: '4'), isNull);
      final others = _highlights(mine: [_clipJson('Crash', 4), _clipJson('Retirement', 2)]).mine;
      expect(raceControlMessage(others[0], 5_000, nameOf, turn: '7A'), 'TURN 7A INCIDENT INVOLVING VERSTAPPEN NOTED');
      expect(raceControlMessage(others[1], 5_000, nameOf, turn: '7A'), 'RUSSELL RETIRED FROM THE RACE');
    });

    test('표본에 RPM·DRS/오버테이크 열이 있으면 읽고, 없으면 RPM 없음·표시 꺼짐', () {
      final track = HighlightCarTrack.fromJsonOrNull(
        _trackJson(1, fromMs: 0, toMs: 1000)
          ..['rpm'] = [for (var i = 0; i < 6; i++) 10_000 + i * 100]
          ..['boost'] = [0, 1, 2, 3, 0, 0],
      )!;
      final path = TimedCarPath(track);
      expect(path.hasRpm, isTrue);
      expect(path.frameAt(100).rpm, 10_050);
      expect([0, 200, 400, 600, 800].map((ms) => path.boostAt(ms.toDouble())), [
        HighlightBoost.none,
        HighlightBoost.drs,
        HighlightBoost.overtakeAvailable,
        HighlightBoost.overtakeActive,
        HighlightBoost.none,
      ]);

      final plain = TimedCarPath(HighlightCarTrack.fromJsonOrNull(_trackJson(1))!);
      expect(plain.hasRpm, isFalse);
      expect(plain.boostAt(0), HighlightBoost.none);
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

    test('옐로 플래그는 섹터와 함께 읽고, 세이프티카와 겹치면 세이프티카가 앞선다', () {
      final yellow = HighlightFlag.fromJsonOrNull({'kind': 'YellowFlag', 'fromMs': 0, 'toMs': 4000, 'sectors': [2]})!;
      const safetyCar = HighlightFlag(kind: RaceFlagKind.safetyCar, fromMs: 3000, toMs: 6000);

      expect(yellow.kind, RaceFlagKind.yellowFlag);
      expect(yellow.sectors, [2]);
      expect(activeHighlightFlag([yellow, safetyCar], 1000), same(yellow));
      expect(activeHighlightFlag([yellow, safetyCar], 3500), same(safetyCar));
    });

    test('깃발이 모두 걷힌 뒤 잠깐만 트랙 클리어', () {
      expect(trackClearAt(flags, 8500), isFalse);                       // 적기 중
      expect(trackClearAt(flags, 9000 + kTrackClearMs - 1), isTrue);    // 적기 끝 직후
      expect(trackClearAt(flags, 9000 + kTrackClearMs + 1), isFalse);   // 한참 뒤
      expect(trackClearAt(flags, 500), isFalse);                        // 깃발 전
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

    test('ERS 잔량(kJ)은 4 MJ 기준 백분율로 보간하고, 열이 없으면 모름', () {
      final json = _trackJson(1, fromMs: 0, toMs: 1000)
        ..['ersStoreKj'] = [for (var i = 0; i < 6; i++) 2000 + i * 400]; // 0ms 2000kJ → 1000ms 4000kJ
      final withErs = TimedCarPath(HighlightCarTrack.fromJsonOrNull(json)!);

      expect(withErs.frameAt(500).batteryPercent, closeTo(75, 0.001));
      expect(TimedCarPath(HighlightCarTrack.fromJsonOrNull(_trackJson(1, fromMs: 0, toMs: 1000))!).frameAt(500).batteryPercent, isNull);
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

      expect(_caption(t), '출발 | ME');
      expect(find.text('1 / 2'), findsOneWidget);
      expect(find.byKey(const ValueKey('highlights-view')), findsOneWidget);
    });

    testWidgets('다음 장면·레이스 하이라이트로 바꾸면 캡션이 바뀐다', (t) async {
      await _pumpPlayer(t, _highlights());

      await t.tap(find.byKey(const ValueKey('highlights-next')));
      await t.pump();
      expect(_caption(t), 'LAP 12 · 추월 | ME');
      expect(find.text('2 / 2'), findsOneWidget);

      await t.tap(find.byKey(const ValueKey('highlights-reel-race')));
      await t.pump();
      expect(_caption(t), '출발 | VERSTAPPEN');
      expect(find.text('1 / 3'), findsOneWidget);
    });

    testWidgets('재생하면 클립이 끝날 때 다음 장면으로 넘어간다', (t) async {
      await _pumpPlayer(t, _highlights());

      await t.tap(find.byKey(const ValueKey('highlights-play')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 2000));
      await t.pump(const Duration(milliseconds: 2500));
      await t.pump();

      expect(_caption(t), 'LAP 12 · 추월 | ME');
      await t.tap(find.byKey(const ValueKey('highlights-play')));
      await t.pump();
    });

    testWidgets('스페이스로 재생·일시정지한다(재생 버튼을 누른 뒤에도 한 번씩만 바뀐다)', (t) async {
      await _pumpPlayer(t, _highlights());
      IconData? playIcon() => t
          .widget<Icon>(find.descendant(of: find.byKey(const ValueKey('highlights-play')), matching: find.byType(Icon)))
          .icon;

      await t.sendKeyEvent(LogicalKeyboardKey.space);
      await t.pump();
      expect(playIcon(), Icons.pause);

      await t.tap(find.byKey(const ValueKey('highlights-play')));
      await t.pump();
      expect(playIcon(), Icons.play_arrow);

      await t.sendKeyEvent(LogicalKeyboardKey.space);
      await t.pump();
      expect(playIcon(), Icons.pause);

      await t.sendKeyEvent(LogicalKeyboardKey.space);
      await t.pump();
      expect(playIcon(), Icons.play_arrow);
    });

    testWidgets('깃발 구간이면 순위표 위쪽에 배너를 띄운다(가운데 띠 없이)', (t) async {
      await _pumpPlayer(t, _highlights(flags: [
        {'kind': 'SafetyCar', 'fromMs': 0, 'toMs': 3000},
      ]));

      final banner = find.byKey(const ValueKey('highlights-standings-flag'));
      expect(find.descendant(of: find.byKey(const ValueKey('highlights-standings')), matching: banner), findsOneWidget);
      expect(find.descendant(of: banner, matching: find.text('SAFETY')), findsOneWidget);
      expect(find.descendant(of: banner, matching: find.text('CAR')), findsOneWidget);
      expect(find.byKey(const ValueKey('highlights-flag')), findsNothing);

      await t.tap(find.byKey(const ValueKey('highlights-next')));
      await t.pump();
      expect(banner, findsNothing);
    });

    testWidgets('넓으면 오른쪽 아래에 중심 차 속도계(속도·기어·DRS 칸), 좁으면 없다', (t) async {
      await _pumpPlayer(t, _highlights());

      final dial = find.byKey(const ValueKey('highlights-telemetry'));
      expect(dial, findsOneWidget);
      expect(_textOf(t, 'highlights-telemetry-speed'), '180');
      expect(_textOf(t, 'highlights-telemetry-gear'), '6');
      expect(find.descendant(of: find.byKey(const ValueKey('highlights-telemetry-boost')), matching: find.text('DRS')), findsOneWidget);
      // 고정 데이터에 RPM·ERS 잔량이 없으면 RPM 줄·배터리 게이지도 없다.
      expect(find.byKey(const ValueKey('highlights-telemetry-rpm')), findsNothing);
      expect(find.byKey(const ValueKey('highlights-telemetry-battery')), findsNothing);
      // 정사각형으로 재생 화면 오른쪽 아래 안쪽.
      final rect = t.getRect(dial);
      final view = t.getRect(find.byKey(const ValueKey('highlights-view')));
      expect(rect.width, closeTo(rect.height, 0.5));
      expect(view.right - rect.right, closeTo(12, 0.5));
      expect(view.bottom - rect.bottom, closeTo(12, 0.5));

      await _pumpPlayer(t, _highlights(), width: 400);
      expect(dial, findsNothing);
    });

    testWidgets('아래에 중심 차 이름 자막: 출발은 레이스 스토리, 추월 전에는 CHASING, 추월 뒤에는 다시 스토리', (t) async {
      await _pumpPlayer(t, _highlights(), width: 1900, raceNumbers: {21: 44}, gridPositions: {21: 5});

      final name = find.byKey(const ValueKey('highlights-driver-name'));
      expect(name, findsOneWidget);
      expect(_textOf(t, 'highlights-driver-position'), '2');
      expect(_textOf(t, 'highlights-driver-last'), 'ME');
      expect(find.descendant(of: name, matching: find.text('RACE STORY')), findsOneWidget);
      expect(_textOf(t, 'highlights-driver-story-started'), '5');
      expect(_textOf(t, 'highlights-driver-story-now'), '2');
      // 자막은 순위표 오른쪽·속도계 왼쪽, 장면 태그 아래.
      final rect = t.getRect(name);
      expect(rect.left, greaterThan(t.getRect(find.byKey(const ValueKey('highlights-standings'))).right));
      expect(rect.right, lessThan(t.getRect(find.byKey(const ValueKey('highlights-telemetry'))).left));
      expect(rect.top, greaterThan(t.getRect(find.byKey(const ValueKey('highlights-caption'))).bottom));

      await t.tap(find.byKey(const ValueKey('highlights-next')));
      await t.pump();
      expect(_textOf(t, 'highlights-driver-chasing-name'), 'RUSSELL');
      expect(_textOf(t, 'highlights-driver-chasing-position'), '3');
      expect(find.byKey(const ValueKey('highlights-driver-story')), findsNothing);
      // 자막 종류가 바뀌어도 배율(높이)은 그대로.
      expect(t.getRect(name).height, closeTo(rect.height, 0.01));

      await _play(t, 6);
      expect(find.byKey(const ValueKey('highlights-driver-chasing')), findsNothing);
      expect(_textOf(t, 'highlights-driver-story-started'), '5');
      expect(_textOf(t, 'highlights-driver-story-now'), '1');
    });

    testWidgets('차 번호·출발 순위를 모르면 자막은 이름 칸까지만, 넓은 자막이 안 들어가는 폭이면 차 번호 칸만', (t) async {
      await _pumpPlayer(t, _highlights(), width: 1900);
      final name = find.byKey(const ValueKey('highlights-driver-name'));
      expect(find.byKey(const ValueKey('highlights-driver-number')), findsNothing);
      expect(find.byKey(const ValueKey('highlights-driver-story')), findsNothing);
      final plain = t.getSize(name).width;

      await _pumpPlayer(t, _highlights(), width: 1900, raceNumbers: {21: 44});
      expect(_textOf(t, 'highlights-driver-number'), '44');
      expect(t.getSize(name).width, greaterThan(plain));

      // 순위표와 속도계 사이가 좁아 넓은 자막이 읽을 만하게 안 들어가면, 출발 순위를 알아도 차 번호 칸.
      for (final width in [1200.0, 400.0]) {
        await _pumpPlayer(t, _highlights(), width: width, raceNumbers: {21: 44}, gridPositions: {21: 5});
        expect(_textOf(t, 'highlights-driver-number'), '44');
        expect(find.byKey(const ValueKey('highlights-driver-story')), findsNothing);
        expect(t.getRect(name).right, lessThanOrEqualTo(t.getRect(find.byKey(const ValueKey('highlights-view'))).right));
      }
      expect(t.takeException(), isNull);
    });

    testWidgets('충돌 장면 순간부터 위에 레이스 컨트롤 메시지, 좁으면 없다', (t) async {
      await _pumpPlayer(t, _highlights());
      await t.tap(find.byKey(const ValueKey('highlights-reel-race')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('highlights-next')));
      await t.pump();
      final box = find.byKey(const ValueKey('highlights-race-control'));
      expect(box, findsNothing);

      await _play(t, 6);
      expect(_textOf(t, 'highlights-race-control-text'), endsWith('INCIDENT INVOLVING RUSSELL AND VERSTAPPEN NOTED'));
      expect(find.descendant(of: box, matching: find.text('CONTROL')), findsOneWidget);
      // 순위표 오른쪽, 재생 화면 위쪽.
      expect(t.getRect(box).left, greaterThan(t.getRect(find.byKey(const ValueKey('highlights-standings'))).right));
      expect(t.getRect(box).top, closeTo(t.getRect(find.byKey(const ValueKey('highlights-view'))).top + 12, 0.5));

      await _pumpPlayer(t, _highlights(), width: 400);
      expect(box, findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('옐로 플래그면 순위표 배너에 섹터를 쓴다', (t) async {
      await _pumpPlayer(t, _highlights(flags: [
        {'kind': 'YellowFlag', 'fromMs': 0, 'toMs': 3000, 'sectors': [1, 3]},
      ]));

      final banner = find.byKey(const ValueKey('highlights-standings-flag'));
      expect(find.descendant(of: banner, matching: find.text('YELLOW FLAG')), findsOneWidget);
      expect(find.descendant(of: banner, matching: find.text('SECTORS 1 · 3')), findsOneWidget);
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

    testWidgets('왼쪽에 순위표: 랩, 순위·이름·간격, 피트는 IN PIT + P 칸, 따라가는 차 줄은 성만', (t) async {
      await _pumpPlayer(t, _highlights());

      final tower = find.byKey(const ValueKey('highlights-standings'));
      expect(t.widget<Text>(find.descendant(of: tower, matching: find.byKey(const ValueKey('highlights-standings-lap')))).textSpan!.toPlainText(), 'LAP 3 /39');
      expect(find.descendant(of: find.byKey(const ValueKey('standing-row-4')), matching: find.text('Leader')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('standing-tyre-4')), matching: find.text('S')), findsOneWidget);
      // 따라가는 차(ME)는 성만 보이고 간격·피트 글자·컴파운드는 숨긴다. 몸통 밖 피트 P 칸은 남는다.
      final me = find.byKey(const ValueKey('standing-row-21'));
      expect(find.descendant(of: me, matching: find.text('ME')), findsOneWidget);
      expect(find.descendant(of: me, matching: find.text('IN PIT')), findsNothing);
      expect(find.descendant(of: me, matching: find.text('P')), findsOneWidget);
      expect(find.byKey(const ValueKey('standing-tyre-21')), findsNothing);
      // 모르는 컴파운드는 글자 없음.
      expect(find.byKey(const ValueKey('standing-tyre-2')), findsNothing);

      // 다른 차를 따라가는 장면에서는 ME 줄이 세 글자 이름 + IN PIT(간격 대신) + 하드 H.
      await t.tap(find.byKey(const ValueKey('highlights-reel-race')));
      await t.pump();
      expect(find.descendant(of: find.byKey(const ValueKey('standing-row-4')), matching: find.text('VERSTAPPEN')), findsOneWidget);
      expect(find.descendant(of: me, matching: find.text('ME')), findsOneWidget);
      expect(find.descendant(of: me, matching: find.text('IN PIT')), findsOneWidget);
      expect(find.descendant(of: me, matching: find.text('+1.2')), findsNothing);
      expect(find.descendant(of: find.byKey(const ValueKey('standing-tyre-21')), matching: find.text('H')), findsOneWidget);
    });

    testWidgets('순위표는 재생 화면 높이에 맞춰 커지고, 깃발 배너가 떠도 줄이 잘리지 않는다', (t) async {
      await _pumpPlayer(t, _highlights(), width: 1600);
      final plain = t.getRect(find.byKey(const ValueKey('highlights-standings')));
      final rowHeight = t.getRect(find.byKey(const ValueKey('standing-row-4'))).height;
      expect(rowHeight, greaterThan(20));

      await _pumpPlayer(t, _highlights(flags: [
        {'kind': 'SafetyCar', 'fromMs': 0, 'toMs': 3000},
      ]), width: 1600);
      await t.pump(const Duration(milliseconds: 400));
      for (final car in [4, 21, 2]) {
        expect(find.byKey(ValueKey('standing-row-$car')), findsOneWidget);
      }
      final flagged = t.getRect(find.byKey(const ValueKey('highlights-standings')));
      expect(flagged.width, lessThanOrEqualTo(plain.width + 0.5));
    });

    test('순위표 폭은 높이에 맞춘 배율(상한 있음)과 최대 폭을 넘지 않는다', () {
      final tall = broadcastTowerWidth(height: 2000, maxWidth: 1000, rows: 3, compact: false);
      expect(tall, closeTo(kBroadcastTowerDesignWidth * 0.75, 0.01));
      final fit = broadcastTowerWidth(height: 700, maxWidth: 1000, rows: 22, compact: false);
      expect(fit, closeTo(kBroadcastTowerDesignWidth * 700 / broadcastTowerDesignHeight(22, banner: false), 0.01));
      expect(broadcastTowerWidth(height: 700, maxWidth: 100, rows: 22, compact: false), closeTo(100, 0.01));
    });

    testWidgets('넓으면 오른쪽에 장면 목록표, 재생기는 나머지 폭을 다 쓰고, 줄을 누르면 그 장면으로', (t) async {
      await _pumpPlayer(t, _highlights(), width: 1600);

      final player = t.getRect(find.byKey(const ValueKey('highlights-player')));
      final list = t.getRect(find.byKey(const ValueKey('highlights-list')));
      expect(player.width, greaterThan(1100));
      expect(list.width, inInclusiveRange(300, 480));
      expect(list.right, closeTo(1600, 1));
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
      // 종류마다 태그 색이 다르다(추월 ≠ 출발).
      Color chip(int i) => t.widget<Container>(find.byKey(ValueKey('highlights-list-kind-$i'))).color!;
      expect(chip(0), isNot(chip(1)));
      // 장면 칸은 태그 폭에 맞춰 드라이버 칸이 칸 간격만 두고 바로 이어진다.
      final tag = t.getRect(find.byKey(const ValueKey('highlights-list-kind-1')));
      final bar = t.getRect(find.descendant(of: row1, matching: find.byKey(const ValueKey('highlights-list-team-21'))));
      expect(bar.left - tag.right, lessThanOrEqualTo(13));
      expect(find.text('드라이버'), findsOneWidget);

      await t.tap(find.byKey(const ValueKey('highlights-list-row-1')));
      await t.pump();
      expect(_caption(t), 'LAP 12 · 추월 | ME');
      expect(find.text('2 / 2'), findsOneWidget);

      // 묶음을 바꾸면 목록도 그 묶음 장면.
      await t.tap(find.byKey(const ValueKey('highlights-reel-race')));
      await t.pump();
      expect(find.byKey(const ValueKey('highlights-list-row-2')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('highlights-list-row-1')), matching: find.text('충돌')), findsOneWidget);
    });

    testWidgets('본문이 1100px보다 좁으면 목록표를 재생기 아래에 둔다', (t) async {
      await _pumpPlayer(t, _highlights(), width: 1000);

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

  group('중계 그래픽 위젯', () {
    Future<void> pump(WidgetTester t, Widget child) =>
        t.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: FittedBox(child: child)))));

    testWidgets('속도계: 잔량을 알면 기어 위에 배터리 게이지와 %, RPM 열이 있으면 RPM', (t) async {
      final track = HighlightCarTrack.fromJsonOrNull(
        _trackJson(1, fromMs: 0, toMs: 1000)
          ..['ersStoreKj'] = [for (var i = 0; i < 6; i++) 2480]
          ..['rpm'] = [for (var i = 0; i < 6; i++) 11_250],
      )!;
      final path = TimedCarPath(track);
      await pump(t, BroadcastSpeedometer(frame: path.frameAt(0), units: UnitSystem.metric, showRpm: path.hasRpm));

      final battery = find.byKey(const ValueKey('highlights-telemetry-battery'));
      expect(find.descendant(of: battery, matching: find.text('62%')), findsOneWidget); // 2480kJ / 4MJ
      expect(t.getBottomLeft(battery).dy, lessThan(t.getTopLeft(find.byKey(const ValueKey('highlights-telemetry-gear'))).dy));
      expect(_textOf(t, 'highlights-telemetry-speed'), '180');
      expect(_textOf(t, 'highlights-telemetry-rpm'), '11250');
      expect(find.text('KMH'), findsOneWidget);
      expect(find.text('GEAR'), findsOneWidget);

      await pump(t, BroadcastSpeedometer(frame: path.frameAt(0), units: UnitSystem.imperial, showRpm: false));
      expect(_textOf(t, 'highlights-telemetry-speed'), '112'); // 180km/h
      expect(find.text('MPH'), findsOneWidget);
      expect(find.byKey(const ValueKey('highlights-telemetry-rpm')), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('속도계 표시 칸: 꺼짐은 DRS(2026 규정 차는 OT), DRS 열림은 초록, 오버테이크는 청록(쓸 수 있으면 테두리만)', (t) async {
      final frame = TimedCarPath(HighlightCarTrack.fromJsonOrNull(_trackJson(1))!).frameAt(0);
      final indicator = find.byKey(const ValueKey('highlights-telemetry-boost'));
      BoxDecoration box() => t.widget<Container>(indicator).decoration! as BoxDecoration;
      String label() => t.widget<Text>(find.descendant(of: indicator, matching: find.byType(Text))).data!;
      Future<void> show(HighlightBoost boost, {bool overtakeRegs = false}) =>
          pump(t, BroadcastSpeedometer(frame: frame, units: UnitSystem.metric, boost: boost, overtakeRegs: overtakeRegs));

      await show(HighlightBoost.none);
      expect(label(), 'DRS');
      expect(box().color, AppColors.replayF1tvIndicator);
      expect(box().border, isNull);

      await show(HighlightBoost.none, overtakeRegs: true);
      expect(label(), 'OT');

      await show(HighlightBoost.drs);
      expect(label(), 'DRS');
      expect(box().color, AppColors.replayF1tvDrs);

      await show(HighlightBoost.overtakeAvailable);
      expect(label(), 'OT');
      expect(box().color, AppColors.replayF1tvIndicator);
      expect((box().border! as Border).top.color, AppColors.replayF1tvOvertake);

      await show(HighlightBoost.overtakeActive);
      expect(label(), 'OT');
      expect(box().color, AppColors.replayF1tvOvertake);
    });

    testWidgets('이름 자막: 번호 · 추격 · 스토리 · 우승 칸', (t) async {
      const orange = Color(0xFFFF8000);
      Future<void> show(LowerThirdDetail detail, {int? number}) => pump(
            t,
            BroadcastDriverName(
              name: 'VERSTAPPEN',
              teamColor: const Color(0xFF3671C6),
              detail: detail,
              position: 3,
              teamName: 'Red Bull Racing',
              raceNumber: number,
              otherName: 'NORRIS',
              otherColor: orange,
            ),
          );

      await show(const LowerThirdNumber(), number: 1);
      expect(_textOf(t, 'highlights-driver-first'), 'Max');
      expect(_textOf(t, 'highlights-driver-last'), 'VERSTAPPEN');
      expect(_textOf(t, 'highlights-driver-team'), 'RED BULL RACING');
      expect(_textOf(t, 'highlights-driver-position'), '3');
      expect(_textOf(t, 'highlights-driver-number'), '1');

      await show(const LowerThirdChasing(otherCar: 4, position: 2));
      final chased = t.widget<Text>(find.byKey(const ValueKey('highlights-driver-chasing-name')));
      expect((chased.data, chased.style!.color), ('NORRIS', orange));
      expect(find.text('CHASING'), findsOneWidget);
      expect(find.text('ND'), findsOneWidget);
      expect(find.byKey(const ValueKey('highlights-driver-number')), findsNothing);

      await show(const LowerThirdStory(started: 10, now: 3, finished: true));
      expect(_textOf(t, 'highlights-driver-story-started'), '10');
      expect(_textOf(t, 'highlights-driver-story-now'), '3');
      expect(find.text('FINISHED:'), findsOneWidget);
      expect(find.text('NOW:'), findsNothing);

      await show(const LowerThirdWinner());
      expect(find.text('RACE'), findsOneWidget);
      expect(find.text('WINNER'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('턴 표시와 레이스 컨트롤 메시지', (t) async {
      await pump(t, const BroadcastTurnIndicator(turn: '7A'));
      expect(find.text('TURN'), findsOneWidget);
      expect(_textOf(t, 'highlights-turn-number'), '7A');

      const message = 'TURN 4 INCIDENT INVOLVING VERSTAPPEN AND RUSSELL NOTED';
      await pump(t, const BroadcastMessageBox(message: message));
      expect(find.text('RACE'), findsOneWidget);
      expect(find.text('CONTROL'), findsOneWidget);
      expect(_textOf(t, 'highlights-race-control-text'), message);
      expect(t.takeException(), isNull);
    });
  });
}
