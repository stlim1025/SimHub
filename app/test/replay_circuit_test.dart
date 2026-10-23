import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:simcenter_app/features/lap_detail/domain/ghost_replay.dart';
import 'package:simcenter_app/features/lap_detail/domain/lap_detail_models.dart';
import 'package:simcenter_app/features/lap_detail/domain/track_alignment.dart';
import 'package:simcenter_app/features/lap_detail/presentation/replay_circuit.dart';
import 'package:simcenter_app/features/tracks/domain/track_width_profile.dart';

/// 대칭이 아닌 닫힌 서킷 모양(반지름이 각도에 따라 바뀐다). [count]개 점.
List<Offset> _shape(int count) => [
      for (var i = 0; i < count; i++)
        () {
          final a = 2 * math.pi * i / count;
          final r = 300 + 60 * math.cos(3 * a) + 30 * math.sin(2 * a);
          return Offset(r * math.cos(a), r * math.sin(a));
        }(),
    ];

/// 회전 [angle] → (뒤집기) → 이동.
Offset _place(Offset p, {required double angle, required bool reflect, required Offset shift}) {
  final q = reflect ? Offset(p.dx, -p.dy) : p;
  return Offset(q.dx * math.cos(angle) - q.dy * math.sin(angle), q.dx * math.sin(angle) + q.dy * math.cos(angle)) + shift;
}

TrackWidthProfile _profile(List<Offset> center, {double left = 4, double right = 6}) => TrackWidthProfile(
      center: center,
      leftM: List.filled(center.length, left),
      rightM: List.filled(center.length, right),
    );

/// 위치(와 연석 기록)만 의미 있는 트레이스. 표본 100ms 간격.
LapTrace _trace(List<Offset> points, {List<bool> kerbContact = const []}) {
  final n = points.length;
  List<int> filled(int v) => List.filled(n, v);
  return LapTrace(
    lapId: 'lap',
    resolutionM: 5,
    timeMs: [for (var i = 0; i < n; i++) i * 100],
    speedKph: filled(200),
    throttle: filled(100),
    brake: filled(0),
    steer: filled(0),
    gear: filled(7),
    rpm: filled(11000),
    worldPosX: [for (final p in points) p.dx],
    worldPosZ: [for (final p in points) p.dy],
    kerbContact: kerbContact,
  );
}

void main() {
  group('실측 트랙 폭 asset', () {
    test('앱 트랙 이름으로 실측 서킷을 읽고, 역방향 레이아웃도 같은 데이터를 쓴다', () {
      final json = jsonDecode(File('assets/track_widths/track_widths.json').readAsStringSync()) as Map<String, dynamic>;
      final widths = parseTrackWidths(json);

      final montreal = widths['Montreal']!;
      expect(montreal.length, greaterThan(800));
      expect(montreal.leftM.length, montreal.length);
      expect(montreal.rightM.every((w) => w > 0 && w < 15), isTrue);
      expect(identical(widths['Silverstone'], widths['Silverstone (Reverse)']), isTrue);
      expect(widths['Monaco'], isNull);
    });

    test('형식이 틀린 항목은 건너뛴다', () {
      final widths = parseTrackWidths({
        'tracks': {'A': 'a', 'B': 'b', 'C': 'missing'},
        'data': {
          'a': [
            [0, 0, 5, 5],
            [5, 0, 5, 5],
            [5, 5, 5, 5],
          ],
          'b': [
            [0, 0, 5],
          ],
        },
      });
      expect(widths.keys, ['A']);
    });
  });

  group('실측 서킷 정렬', () {
    final real = _shape(400);

    test('회전·뒤집기·이동·역방향·다른 시작점이어도 주행선에 맞추고, 뒤집히면 좌우 폭을 바꾼다', () {
      const angle = 0.7;
      const shift = Offset(1000, -500);
      final placed = [for (final p in real) _place(p, angle: angle, reflect: true, shift: shift)];
      // 주행선: 실측 점을 거꾸로, 37번째부터.
      final driving = [for (var i = 0; i < placed.length; i++) placed[(37 - i) % placed.length]];

      final aligned = alignTrackProfile(_profile(real), driving)!;

      for (var i = 0; i < real.length; i++) {
        expect((aligned.center[i] - placed[i]).distance, lessThan(0.5));
      }
      expect(aligned.leftM.first, 6);
      expect(aligned.rightM.first, 4);
    });

    test('모양이 다른 서킷이면 null', () {
      final circle = [for (var i = 0; i < 400; i++) Offset(300 * math.cos(2 * math.pi * i / 400), 300 * math.sin(2 * math.pi * i / 400))];
      expect(alignTrackProfile(_profile(real), circle), isNull);
    });
  });

  group('서킷 모양', () {
    // 반지름 200m 원을 반시계로 돈다(왼쪽 = 원 안쪽). 표본 5m 간격.
    const radius = 200.0;
    final count = (2 * math.pi * radius / 5).round();
    Offset onCircle(int i, double r) => Offset(r * math.cos(2 * math.pi * i / count), r * math.sin(2 * math.pi * i / count));

    test('연석은 바퀴가 연석을 밟은 자리, 차가 있던 쪽 가장자리에만 그린다', () {
      // 표본 50~55에서 안쪽(왼쪽)으로 4m 붙어 연석을 밟았다.
      final contact = [for (var i = 0; i < count; i++) i >= 50 && i <= 55];
      final points = [for (var i = 0; i < count; i++) onCircle(i, contact[i] ? radius - 4 : radius)];
      final real = _profile([for (var i = 0; i < count; i++) onCircle(i, radius)], left: 5, right: 5);

      final circuit = ReplayCircuit.build(LapReplay(_trace(points, kerbContact: contact)), real: real);
      bool kerbAt(Offset p) => circuit.kerbRed.contains(p) || circuit.kerbWhite.contains(p);

      expect(circuit.isMeasured, isTrue);
      expect(kerbAt(onCircle(52, radius - 5.75)), isTrue); // 왼쪽 가장자리 바깥 0.75m
      expect(kerbAt(onCircle(52, radius + 5.75)), isFalse); // 오른쪽에는 없다
      expect(kerbAt(onCircle(150, radius - 5.75)), isFalse); // 밟지 않은 곳에는 없다
    });

    test('실측 폭으로 도로를 그리고, 실측 서킷이 없으면 주행 기록으로 추정한다', () {
      final points = [for (var i = 0; i < count; i++) onCircle(i, radius)];
      final real = _profile(points, left: 5, right: 5);

      final measured = ReplayCircuit.build(LapReplay(_trace(points)), real: real);
      expect(measured.asphalt.contains(onCircle(10, radius + 4.5)), isTrue);
      expect(measured.asphalt.contains(onCircle(10, radius + 5.5)), isFalse);

      final estimated = ReplayCircuit.build(LapReplay(_trace(points)));
      expect(estimated.isMeasured, isFalse);
      expect(estimated.leftWidths.first, greaterThan(kCircuitBaseWidthM / 2 - 0.01));

      // 트랙별 기본 폭(모나코)을 주면 그 폭으로 추정한다.
      final narrow = ReplayCircuit.build(LapReplay(_trace(points)), baseWidthM: kEstimatedTrackWidthsM['Monaco']!);
      final monacoHalf = kEstimatedTrackWidthsM['Monaco']! / 2;
      expect(narrow.rightWidths.first, inInclusiveRange(monacoHalf, monacoHalf + kCircuitCornerExtraWidthM / 2));
    });

    test('레이아웃이 일부 바뀐 서킷은 맞는 구간만 실측 폭을, 바뀐 구간은 추정 폭을 쓴다', () {
      // 대칭이 없는 서킷(원이면 어느 각도로 돌려도 맞아 바뀐 구간을 가려낼 수 없다).
      final points = _shape(400);
      // 옛 레이아웃: 100~140번 점 구간이 바깥으로 최대 60m 돌아 나간다(지금 게임은 곧장 간다).
      final old = [
        for (var i = 0; i < points.length; i++)
          () {
            final detour = i >= 100 && i <= 140 ? 60 * math.sin(math.pi * (i - 100) / 40) : 0.0;
            return points[i] * ((points[i].distance + detour) / points[i].distance);
          }(),
      ];
      final circuit = ReplayCircuit.build(LapReplay(_trace(points)), real: _profile(old, left: 5, right: 5));

      expect(circuit.isMeasured, isTrue);
      // 맞는 구간: 실측 폭(좌우 5m). 바뀐 구간: 추정 폭(반폭 6.5m 이상).
      expect(circuit.leftWidths[20], closeTo(5, 0.01));
      expect(circuit.rightWidths[300], closeTo(5, 0.01));
      expect(circuit.leftWidths[120], greaterThan(6.4));
      expect(circuit.rightWidths[120], greaterThan(6.4));
    });

    test('실측 중심선이 어긋나 주행선이 도로 밖이면 중심선을 옮겨 도로 안에 들인다', () {
      final points = [for (var i = 0; i < count; i++) onCircle(i, radius)];
      // 실측 중심선이 바깥으로 6m 어긋남(폭 좌우 5m → 주행선이 가장자리 밖).
      final real = _profile([for (var i = 0; i < count; i++) onCircle(i, radius + 6)], left: 5, right: 5);

      final circuit = ReplayCircuit.build(LapReplay(_trace(points)), real: real);
      expect(circuit.asphalt.contains(onCircle(80, radius)), isTrue);
    });
  });

  test('높이 채널이 있으면 서킷 점마다 노면 높이를 붙이고, 없으면 0', () {
    const radius = 200.0;
    final count = (2 * math.pi * radius / 5).round();
    final points = [
      for (var i = 0; i < count; i++) Offset(radius * math.cos(2 * math.pi * i / count), radius * math.sin(2 * math.pi * i / count)),
    ];
    // 높이: 한 바퀴에 0 → 20m → 0(코사인 언덕).
    double heightAt(int i) => 10 - 10 * math.cos(2 * math.pi * i / count);
    final flat = _trace(points);
    final hilly = LapTrace(
      lapId: 'lap',
      resolutionM: flat.resolutionM,
      timeMs: flat.timeMs,
      speedKph: flat.speedKph,
      throttle: flat.throttle,
      brake: flat.brake,
      steer: flat.steer,
      gear: flat.gear,
      rpm: flat.rpm,
      worldPosX: flat.worldPosX,
      worldPosZ: flat.worldPosZ,
      worldPosY: [for (var i = 0; i < count; i++) heightAt(i)],
    );

    final circuit = ReplayCircuit.build(LapReplay(hilly));
    expect(hilly.hasElevation, isTrue);
    final top = circuit.center.indexWhere((p) => (p - Offset(-radius, 0)).distance < 6);
    expect(circuit.elevations[top], closeTo(20, 0.5));
    expect(circuit.elevations.reduce(math.min), closeTo(0, 0.5));
    expect(ReplayCircuit.build(LapReplay(flat)).elevations.every((e) => e == 0), isTrue);
  });

  test('트레이스 JSON의 네 바퀴 노면 채널로 연석을 밟았는지 읽는다', () {
    Map<String, dynamic> json(Map<String, dynamic> extra) => {
          'lapId': 'x',
          'resolutionM': 5,
          'timeMs': [0, 100, 200],
          'speedKph': [1, 2, 3],
          'throttle': [0, 0, 0],
          'brake': [0, 0, 0],
          'steer': [0, 0, 0],
          'gear': [1, 1, 1],
          'rpm': [1, 1, 1],
          'extra': extra,
        };
    final trace = LapTrace.fromJson(json({
      'surfaceTypeFL': [0, 1, 0],
      'surfaceTypeFR': [0, 0, 0],
      'surfaceTypeRL': [0, 0, 7],
      'surfaceTypeRR': [0, 0, 0],
    }));
    expect(trace.kerbContact, [false, true, false]);
    expect(LapTrace.fromJson(json({'worldPosX': [0, 1, 2], 'worldPosZ': [0, 0, 0], 'worldPosY': [5, 6, 7]})).worldPosY, [5, 6, 7]);
    expect(LapTrace.fromJson(json({'surfaceTypeFL': [0, 1, 0]})).hasKerbContact, isFalse);
  });
}
