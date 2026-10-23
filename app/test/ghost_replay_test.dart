import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simcenter_app/core/theme/app_colors.dart';
import 'package:simcenter_app/features/auth/domain/user_preferences.dart';
import 'package:simcenter_app/features/lap_detail/domain/ghost_replay.dart';
import 'package:simcenter_app/features/lap_detail/domain/lap_detail_models.dart';
import 'package:simcenter_app/features/lap_detail/presentation/ghost_replay_painter.dart';
import 'package:simcenter_app/features/lap_detail/presentation/telemetry_tab.dart';
import 'package:simcenter_app/features/laps/domain/lap_models.dart';

/// 위치가 있는 트레이스: 표본 [count]개(5m 간격), 시간 i×[msPerSample], 속도 200+i, 기어 i÷10+1, 위치는 [positionAt].
LapTrace _positionedTrace(
  String lapId, {
  int count = 41,
  int msPerSample = 100,
  (double, double) Function(int i)? positionAt,
}) {
  final positions = [for (var i = 0; i < count; i++) positionAt?.call(i) ?? (i * 5.0, 0.0)];
  return LapTrace(
    lapId: lapId,
    resolutionM: 5,
    timeMs: [for (var i = 0; i < count; i++) i * msPerSample],
    speedKph: [for (var i = 0; i < count; i++) 200 + i],
    throttle: [for (var i = 0; i < count; i++) 100],
    brake: [for (var i = 0; i < count; i++) 0],
    steer: [for (var i = 0; i < count; i++) 0],
    gear: [for (var i = 0; i < count; i++) i ~/ 10 + 1],
    rpm: [for (var i = 0; i < count; i++) 11000],
    worldPosX: [for (final p in positions) p.$1],
    worldPosZ: [for (final p in positions) p.$2],
  );
}

LapTrace _withoutPositions(LapTrace t) => LapTrace(
  lapId: t.lapId,
  resolutionM: t.resolutionM,
  timeMs: t.timeMs,
  speedKph: t.speedKph,
  throttle: t.throttle,
  brake: t.brake,
  steer: t.steer,
  gear: t.gear,
  rpm: t.rpm,
);

/// 이 랩: 4.0초·200m. 비교 랩: 표본당 90ms(3.6초) — 이 랩이 뒤처진다.
final _player = _positionedTrace('l1');
final _reference = _positionedTrace('best', msPerSample: 90);

Future<void> _pumpCharts(
  WidgetTester tester, {
  required LapTrace trace,
  LapTrace? reference,
  List<LapSector> sectors = const [],
  List<LapSector> referenceSectors = const [],
  Size size = const Size(1000, 2400),
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: TelemetryCharts(
            trace: trace,
            reference: reference,
            lapTimeMs: trace.timeMs.last,
            referenceLapTimeMs: reference?.timeMs.last,
            units: UnitSystem.metric,
            sectors: sectors,
            referenceSectors: referenceSectors,
          ),
        ),
      ),
    ),
  );
}

String _textOf(WidgetTester tester, String key) => tester.widget<Text>(find.byKey(ValueKey(key))).data!;

void main() {
  group('재생 계산', () {
    test('경과 시간 사이를 앞뒤 표본으로 보간한다(위치·거리·속도)', () {
      final frame = LapReplay(_player).frameAt(150);

      expect(frame.distanceM, closeTo(7.5, 1e-9));
      expect(frame.x, closeTo(7.5, 1e-9));
      expect(frame.z, 0);
      expect(frame.speedKph, closeTo(201.5, 1e-9));
      expect(frame.gear, 1);
      expect(frame.finished, isFalse);
    });

    test('같은 시간이 이어지는 표본도 0으로 나누지 않는다', () {
      final trace = _positionedTrace('l1', count: 4);
      final stalled = LapTrace(
        lapId: 'l1',
        resolutionM: 5,
        timeMs: const [0, 100, 100, 300],
        speedKph: trace.speedKph,
        throttle: trace.throttle,
        brake: trace.brake,
        steer: trace.steer,
        gear: trace.gear,
        rpm: trace.rpm,
        worldPosX: trace.worldPosX,
        worldPosZ: trace.worldPosZ,
      );
      final replay = LapReplay(stalled);

      expect(replay.samplePositionAt(100), 2);
      expect(replay.samplePositionAt(200), closeTo(2.5, 1e-9));
    });

    test('랩을 끝낸 뒤에는 결승점에 멈춰 있고, 시작 전은 출발점', () {
      final replay = LapReplay(_player);

      final end = replay.frameAt(99999);
      expect(end.distanceM, 200);
      expect(end.x, 200);
      expect(end.finished, isTrue);
      expect(replay.frameAt(-50).distanceM, 0);
    });

    test('진행 방향: +X로 달리면 0, +Z로 달리면 90°', () {
      expect(LapReplay(_player).frameAt(1000).heading, closeTo(0, 1e-9));
      final south = LapReplay(_positionedTrace('l1', positionAt: (i) => (0, i * 5.0)));
      expect(south.frameAt(1000).heading, closeTo(math.pi / 2, 1e-9));
    });

    test('진행 방향은 앞뒤 몇 m를 보아 표본마다의 흔들림을 누른다', () {
      // 표본마다 옆으로 ±0.4m 흔들리며 +X로 달린다 — 이웃 표본만 보면 ±4.6°, 앞뒤 8m를 보면 거의 0.
      final zigzag = LapReplay(_positionedTrace('l1', positionAt: (i) => (i * 5.0, i.isEven ? 0.4 : -0.4)));

      for (final t in [1000.0, 1050.0, 1500.0, 2230.0]) {
        expect(zigzag.frameAt(t).heading.abs(), lessThan(0.06));
      }
    });

    test('재생 시계 끝 = 두 랩 중 늦게 끝나는 쪽', () {
      expect(replayDurationMs(LapReplay(_player), LapReplay(_reference)), 4000);
      expect(replayDurationMs(LapReplay(_reference), null), 3600);
    });

    test('시간 차 = 이 랩 시간 − 같은 거리의 비교 랩 시간: 음수면 앞선다, 거리가 없으면 null', () {
      expect(replayGapMs(_player, _reference, 50), closeTo(100, 1e-9));
      expect(replayGapMs(_reference, _player, 50), closeTo(-100, 1e-9));
      expect(replayGapMs(_player, _positionedTrace('short', count: 3), 50), isNull);
    });

    test('시간 차 글자', () {
      expect(formatReplayGap(-214), '-0.214');
      expect(formatReplayGap(381.4), '+0.381');
      expect(formatReplayGap(0.2), '0.000');
    });
  });

  group('ERS 배터리', () {
    // 표본 100ms마다 배터리 4MJ → 표본당 −20kJ, 누적 배포 표본당 +10kJ(= 100 kW).
    LapTrace withErs() {
      final base = _player;
      return LapTrace(
        lapId: base.lapId,
        resolutionM: base.resolutionM,
        timeMs: base.timeMs,
        speedKph: base.speedKph,
        throttle: base.throttle,
        brake: base.brake,
        steer: base.steer,
        gear: base.gear,
        rpm: base.rpm,
        worldPosX: base.worldPosX,
        worldPosZ: base.worldPosZ,
        ersStoreJ: [for (var i = 0; i < base.length; i++) 4000000.0 - i * 20000],
        ersDeployedJ: [for (var i = 0; i < base.length; i++) i * 10000.0],
      );
    }

    test('배터리 잔량(%)과 배포 출력(kW)을 계산한다', () {
      final frame = LapReplay(withErs()).frameAt(1000); // 표본 10
      expect(frame.batteryPercent, closeTo(95, 0.01)); // 3.8 MJ / 4 MJ
      expect(frame.deployKw, closeTo(100, 0.01));
    });

    test('ERS 채널이 없으면 null', () {
      final frame = LapReplay(_player).frameAt(1000);
      expect(frame.batteryPercent, isNull);
      expect(frame.deployKw, isNull);
    });

    test('트레이스 JSON의 extra ERS 채널을 읽는다(길이가 다르면 버린다)', () {
      Map<String, dynamic> json(List<num> store) => {
        'lapId': 'x',
        'resolutionM': 5,
        'timeMs': [0, 100],
        'speedKph': [1, 2],
        'throttle': [0, 0],
        'brake': [0, 0],
        'steer': [0, 0],
        'gear': [1, 1],
        'rpm': [1, 1],
        'extra': {'ersStoreEnergy': store, 'ersDeployedThisLap': [0, 10]},
      };
      expect(LapTrace.fromJson(json([4000000, 3990000])).hasErs, isTrue);
      expect(LapTrace.fromJson(json([4000000])).hasErs, isFalse);
    });

    testWidgets('ERS가 있으면 HUD에 배터리 %와 배포 막대가 보인다', (t) async {
      await _pumpCharts(t, trace: withErs());

      expect(find.byKey(const ValueKey('ghost-replay-player-hud-battery')), findsOneWidget);
      expect(find.byKey(const ValueKey('ghost-replay-player-hud-deploy')), findsOneWidget);
      expect(_textOf(t, 'ghost-replay-player-hud-battery-text'), '100%');
    });
  });

  group('섹터 비교', () {
    const mine = [LapSector(sectorNumber: 2, sectorTimeMs: 30000), LapSector(sectorNumber: 1, sectorTimeMs: 20000)];
    const theirs = [LapSector(sectorNumber: 1, sectorTimeMs: 21000), LapSector(sectorNumber: 2, sectorTimeMs: 29000)];

    test('누적 시간까지 지난 섹터만 채운다(순서와 무관)', () {
      expect(replaySectorRows(mine, theirs, 19999), [
        (sector: 1, playerMs: null, referenceMs: null),
        (sector: 2, playerMs: null, referenceMs: null),
      ]);
      expect(replaySectorRows(mine, theirs, 20500), [
        (sector: 1, playerMs: 20000, referenceMs: null),
        (sector: 2, playerMs: null, referenceMs: null),
      ]);
      expect(replaySectorRows(mine, theirs, 50000), [
        (sector: 1, playerMs: 20000, referenceMs: 21000),
        (sector: 2, playerMs: 30000, referenceMs: 29000),
      ]);
    });

    test('비교 랩 섹터가 없으면 이 랩만', () {
      expect(replaySectorRows(mine, const [], 50000).map((r) => r.referenceMs), [null, null]);
    });
  });

  group('차 색', () {
    test('팀 색 글자가 맞으면 그 색, 아니면 팀 이름의 색, 둘 다 없으면 대체색', () {
      expect(
        replayCarColor(
          const LapTeam(name: 'Ferrari', color: '#E8002D'),
          fallback: AppColors.accent,
        ),
        const Color(0xFFE8002D),
      );
      expect(replayCarColor(const LapTeam(name: 'McLaren'), fallback: AppColors.accent), AppColors.teamMcLaren);
      expect(
        replayCarColor(
          const LapTeam(name: 'Mystery', color: 'red'),
          fallback: AppColors.comparisonLap,
        ),
        AppColors.comparisonLap,
      );
      expect(replayCarColor(null, fallback: AppColors.accent), AppColors.accent);
    });
  });

  test('추격 카메라 그림은 예외 없이 그려진다(고스트 있음·없음, 빈 크기)', () {
    final player = LapReplay(_player);
    final time = ValueNotifier<double>(1234);
    addTearDown(time.dispose);
    for (final ghost in [LapReplay(_reference), null]) {
      final painter = GhostReplayPainter(
        player: player,
        ghost: ghost,
        road: replayRoadPath(player),
        time: time,
        playerColor: AppColors.teamFerrari,
        ghostColor: AppColors.comparisonLap,
      );
      for (final size in const [Size(600, 360), Size.zero]) {
        final recorder = ui.PictureRecorder();
        painter.paint(Canvas(recorder), size);
        recorder.endRecording().dispose();
      }
    }
  });

  group('고스트 재생 카드', () {
    testWidgets('이 랩에 위치가 없으면 카드가 없다', (t) async {
      await _pumpCharts(t, trace: _withoutPositions(_player), reference: _reference);

      expect(find.byKey(const ValueKey('ghost-replay')), findsNothing);
    });

    testWidgets('고스트(비교 랩 HUD·시간 차)는 비교 랩에 위치가 있을 때만', (t) async {
      await _pumpCharts(t, trace: _player, reference: _withoutPositions(_reference));
      expect(find.byKey(const ValueKey('ghost-replay')), findsOneWidget);
      expect(find.byKey(const ValueKey('ghost-replay-ghost-hud')), findsNothing);
      expect(find.byKey(const ValueKey('ghost-replay-gap')), findsNothing);

      await _pumpCharts(t, trace: _player, reference: _reference);
      expect(find.byKey(const ValueKey('ghost-replay-ghost-hud')), findsOneWidget);
      expect(_textOf(t, 'ghost-replay-gap'), '0.000');
    });

    testWidgets('HUD에 두 차의 스로틀·브레이크 막대와 섹터 비교 표(지난 섹터만 채움)가 있다', (t) async {
      const mine = [LapSector(sectorNumber: 1, sectorTimeMs: 800), LapSector(sectorNumber: 2, sectorTimeMs: 900)];
      const theirs = [LapSector(sectorNumber: 1, sectorTimeMs: 700), LapSector(sectorNumber: 2, sectorTimeMs: 1000)];
      await _pumpCharts(t, trace: _player, reference: _reference, sectors: mine, referenceSectors: theirs);

      for (final key in ['player', 'ghost']) {
        expect(find.byKey(ValueKey('ghost-replay-$key-hud-throttle')), findsOneWidget);
        expect(find.byKey(ValueKey('ghost-replay-$key-hud-brake')), findsOneWidget);
      }
      final table = find.byKey(const ValueKey('ghost-replay-sectors'));
      expect(find.descendant(of: table, matching: find.text('S1')), findsOneWidget);
      expect(find.descendant(of: table, matching: find.text('0:00.800')), findsNothing); // 아직 S1 전

      await t.tap(find.byKey(const ValueKey('ghost-replay-play')));
      await t.pump();
      await t.pump(const Duration(seconds: 1)); // 1초: 두 랩 모두 S1 지남, S2는 아직

      expect(find.descendant(of: table, matching: find.text('0:00.800')), findsOneWidget);
      expect(find.descendant(of: table, matching: find.text('0:00.700')), findsOneWidget);
      expect(find.descendant(of: table, matching: find.text('+0.100')), findsOneWidget);
      expect(find.descendant(of: table, matching: find.text('0:00.900')), findsNothing);
    });

    testWidgets('재생하면 시간이 흐르고 그래프 십자선이 따라오며, 일시정지하면 멈춘다', (t) async {
      await _pumpCharts(t, trace: _player, reference: _reference);

      await t.tap(find.byKey(const ValueKey('ghost-replay-play')));
      await t.pump();
      await t.pump(const Duration(seconds: 1));

      expect(_textOf(t, 'ghost-replay-elapsed'), '0:01.000');
      expect(_textOf(t, 'telemetry-cursor-distance'), '50 m');
      expect(_textOf(t, 'ghost-replay-gap'), '+0.100');

      await t.tap(find.byKey(const ValueKey('ghost-replay-play')));
      await t.pump();
      final paused = _textOf(t, 'ghost-replay-elapsed');
      await t.pump(const Duration(seconds: 1));
      expect(_textOf(t, 'ghost-replay-elapsed'), paused);
    });

    testWidgets('배속 2×면 1초에 2초가 흐르고, 끝나면 랩 끝에서 멈춘다', (t) async {
      await _pumpCharts(t, trace: _player, reference: _reference);

      await t.tap(find.byKey(const ValueKey('ghost-replay-speed-2.0')));
      await t.tap(find.byKey(const ValueKey('ghost-replay-play')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      expect(_textOf(t, 'ghost-replay-elapsed'), '0:01.000');

      await t.pump(const Duration(seconds: 5));
      expect(_textOf(t, 'ghost-replay-elapsed'), '0:04.000');
      expect(_textOf(t, 'telemetry-cursor-distance'), '200 m');
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    });

    testWidgets('시간 막대를 옮기면 그 시간으로 가고, 처음부터를 누르면 0', (t) async {
      await _pumpCharts(t, trace: _player, reference: _reference);

      t.widget<Slider>(find.byKey(const ValueKey('ghost-replay-scrub'))).onChanged!(2500);
      await t.pump();
      expect(_textOf(t, 'ghost-replay-elapsed'), '0:02.500');
      expect(_textOf(t, 'telemetry-cursor-distance'), '125 m');

      await t.tap(find.byKey(const ValueKey('ghost-replay-restart')));
      await t.pump();
      expect(_textOf(t, 'ghost-replay-elapsed'), '0:00.000');
    });

    testWidgets('375px 폭에서도 HUD·조작 줄이 넘치지 않는다', (t) async {
      await _pumpCharts(t, trace: _player, reference: _reference, size: const Size(375, 2400));

      expect(find.byKey(const ValueKey('ghost-replay-ghost-hud')), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });
}
