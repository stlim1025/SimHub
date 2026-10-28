import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simcenter_app/features/auth/domain/user_preferences.dart';
import 'package:simcenter_app/features/lap_detail/domain/lap_analysis.dart';
import 'package:simcenter_app/features/lap_detail/domain/lap_corners.dart';
import 'package:simcenter_app/features/lap_detail/domain/lap_detail_models.dart';
import 'package:simcenter_app/features/lap_detail/presentation/analysis_tab.dart';
import 'package:simcenter_app/features/lap_detail/presentation/lap_analysis_card.dart';

const int _res = 5;
const double _straightM = 400;
const double _radiusM = 60;

/// 400m 직선(+X) → 반지름 60m 오른쪽 90° 코너(+Z 쪽으로) → 직선. 랩 거리 [d]의 위치. [lateral]은 진행 방향 오른쪽으로 민 거리.
({double x, double z}) _position(double d, {double lateral = 0}) {
  final arc = _radiusM * math.pi / 2;
  if (d <= _straightM) {
    return (x: d, z: lateral);
  }
  if (d <= _straightM + arc) {
    final phi = (d - _straightM) / _radiusM;
    final r = _radiusM - lateral;
    return (x: _straightM + r * math.sin(phi), z: _radiusM - r * math.cos(phi));
  }
  return (x: _straightM + _radiusM - lateral, z: _radiusM + d - _straightM - arc);
}

/// 브레이크를 [brakeAtM]부터 코너 입구(400m)까지 밟아 [apexKph]로 줄이고, 코너 끝부터 풀 스로틀. 1km.
/// [cornerSteer]는 380m(브레이킹 끝)부터 코너 끝 20m 뒤까지의 조향(%).
LapTrace _lap({
  required double brakeAtM,
  required double apexKph,
  double lateral = 0,
  List<double>? ersStore,
  int cornerSteer = 0,
}) {
  final arcEnd = _straightM + _radiusM * math.pi / 2;
  const totalM = 1000;
  const n = totalM ~/ _res + 1;
  final speed = <int>[];
  final brake = <int>[];
  final throttle = <int>[];
  for (var i = 0; i < n; i++) {
    final d = (i * _res).toDouble();
    if (d < brakeAtM) {
      speed.add(300);
      brake.add(0);
      throttle.add(100);
    } else if (d < _straightM) {
      final t = (d - brakeAtM) / (_straightM - brakeAtM);
      speed.add((300 - (300 - apexKph) * t).round());
      brake.add(100);
      throttle.add(0);
    } else if (d < arcEnd) {
      speed.add(apexKph.round());
      brake.add(0);
      throttle.add(50);
    } else {
      speed.add(math.min(300, apexKph + (d - arcEnd) * 0.6).round());
      brake.add(0);
      throttle.add(100);
    }
  }
  final time = <int>[0];
  for (var i = 1; i < n; i++) {
    final mps = (speed[i] + speed[i - 1]) / 2 / 3.6;
    time.add(time.last + (_res / mps * 1000).round());
  }
  final positions = [for (var i = 0; i < n; i++) _position((i * _res).toDouble(), lateral: lateral)];
  return LapTrace(
    lapId: 'lap',
    resolutionM: _res,
    timeMs: time,
    speedKph: speed,
    throttle: throttle,
    brake: brake,
    steer: [for (var i = 0; i < n; i++) i * _res >= 380 && i * _res <= arcEnd + 20 ? cornerSteer : 0],
    gear: List.filled(n, 6),
    rpm: List.filled(n, 11000),
    worldPosX: [for (final p in positions) p.x],
    worldPosZ: [for (final p in positions) p.z],
    ersStoreJ: ersStore ?? const [],
    ersDeployedJ: ersStore == null ? const [] : List.filled(n, 0),
  );
}

void main() {
  final reference = _lap(brakeAtM: 300, apexKph: 110);

  test('주행선의 꺾임으로 코너를 찾고 방향·구간을 정한다', () {
    final corners = detectLapCorners(reference);

    expect(corners, hasLength(1));
    final corner = corners.single;
    expect((corner.label, corner.direction), ('T1', CornerDirection.right));
    expect(corner.startM, inInclusiveRange(380, 420));
    expect(corner.endM, inInclusiveRange(470, 520));
    expect(cornerAt(corners, 450)?.number, 1);
    expect(cornerAt(corners, 200), isNull);
    expect(nearestLapDistance(reference, 200, 0), 200);
  });

  test('공식 코너가 있으면 공식 번호·글자로, 직선의 킹크도 공식 지점 앞뒤로 코너를 만든다', () {
    // 1km 랩: 공식 7번 = 회전 구간 안(450m), 7A = 직선 위(700m).
    final corners = resolveLapCorners(reference, const [
      (number: 7, letter: '', fraction: 0.45),
      (number: 7, letter: 'A', fraction: 0.70),
    ]);

    expect(corners.map((c) => c.label), ['T7', 'T7A']);
    expect(corners.first.direction, CornerDirection.right);
    expect(corners.first.startM, inInclusiveRange(380, 420));
    expect((corners.last.startM, corners.last.endM), (675, 725));
    expect(resolveLapCorners(reference, const []).single.label, 'T1'); // 공식 데이터가 없으면 주행선으로
  });

  test('공식 코너 asset: 게임 트랙 이름별 번호·비율(역방향은 원래 번호를 거꾸로)', () {
    final json = jsonDecode(File('assets/track_corners/track_corners.json').readAsStringSync()) as Map<String, dynamic>;
    final tracks = parseTrackCorners(json);

    expect(tracks['Catalunya']!.map((c) => c.number), [for (var i = 1; i <= 14; i++) i]);
    expect(tracks['Monaco'], hasLength(19));
    expect(tracks['Hungaroring']!.where((c) => c.letter == 'A').map((c) => c.number), [1, 12]);
    final reverse = tracks['Silverstone (Reverse)']!;
    expect(reverse.first.number, tracks['Silverstone']!.last.number);
    expect(reverse.first.fraction, closeTo(1 - tracks['Silverstone']!.last.fraction, 1e-5));
  });

  test('브레이크를 늦게 밟아 최저속도가 낮으면 그 코너에서 시간을 잃고 이유를 짚는다', () {
    final lap = _lap(brakeAtM: 320, apexKph: 100);
    final analysis = analyzeLap(lap, reference, detectLapCorners(reference));
    final corner = analysis.corners.single;
    final kinds = {for (final f in corner.factors) f.kind: f.amount};

    expect(corner.lossS, greaterThan(kCornerLossThresholdS));
    expect(analysis.losses.single.corner.number, 1);
    expect(kinds[CornerFactorKind.brakeLater], closeTo(20, 2));
    expect(kinds[CornerFactorKind.slowerApex], closeTo(10, 1));
    expect(analysis.ers, isNull);
  });

  test('비교 랩이 없으면 시간 손실은 없고, 타이어 기준이면 이 랩만 보고 무리한 운전을 짚는다', () {
    final lap = _lap(brakeAtM: 300, apexKph: 110, cornerSteer: 60);

    final alone = analyzeLap(lap, null, detectLapCorners(lap));
    expect(alone.hasReference, isFalse);
    expect(alone.losses, isEmpty);
    expect(alone.corners.single.factors, isEmpty);

    final tyres = analyzeLap(lap, null, detectLapCorners(lap), focus: AnalysisFocus.tyres);
    final kinds = tyres.corners.single.factors.map((f) => f.kind);
    expect(kinds, containsAll([CornerFactorKind.brakingWhileTurning, CornerFactorKind.throttleWhileTurning]));
    expect(tyres.tyreStress.single.corner.label, 'T1');
  });

  test('배터리 기준: 결승선을 사이에 둔 직선을 하나로 보고 배포하기 가장 좋은 직선을 짚는다', () {
    const n = 1000 ~/ _res + 1;
    final lap = _lap(brakeAtM: 300, apexKph: 110, ersStore: List.filled(n, 2e6));
    final ers = analyzeLap(lap, null, detectLapCorners(lap), focus: AnalysisFocus.battery).ers!;

    final straight = ers.straights.single; // 코너 뒤 ~ 결승선 + 출발선 ~ 코너 앞
    expect(straight.lengthM, closeTo(1000 - (straight.after!.endM - straight.before!.startM), 1));
    expect(straight.entryKph, lessThan(150));
    expect(ersFeedbackLines(ers, focus: AnalysisFocus.battery).last, startsWith('배포는 T1–T1 직선'));
    expect(ersFeedbackLines(ers), hasLength(1)); // 최대 속도 기준은 잔량만
  });

  test('레이스는 타이어 관리, 그 밖은 최대 속도가 기본 분석 기준', () {
    expect(defaultAnalysisFocus('Race'), AnalysisFocus.tyres);
    expect(defaultAnalysisFocus('Qualifying'), AnalysisFocus.pace);
    expect(defaultAnalysisFocus('TimeTrial'), AnalysisFocus.pace);
  });

  test('같은 랩이면 잃은 코너도 이유도 없다', () {
    final analysis = analyzeLap(reference, reference, detectLapCorners(reference));
    expect(analysis.losses, isEmpty);
    expect(analysis.corners.single.factors, isEmpty);
  });

  test('에이펙스에서 기준 라인보다 바깥이면 넓게 돈 것으로 짚는다', () {
    final lap = _lap(brakeAtM: 300, apexKph: 110, lateral: -2.5); // 오른쪽 코너의 바깥 = 왼쪽
    final factors = analyzeLap(lap, reference, detectLapCorners(reference)).corners.single.factors;
    final wide = factors.where((f) => f.kind == CornerFactorKind.wideAtApex).single;
    expect(wide.amount, closeTo(2.5, 0.3));
  });

  test('이 랩만 배터리가 바닥나면 그 자리를 짚는다', () {
    const n = 1000 ~/ _res + 1;
    final lap = _lap(brakeAtM: 300, apexKph: 110, ersStore: [for (var i = 0; i < n; i++) i * _res < 600 ? 2e6 : 0]);
    final full = _lap(brakeAtM: 300, apexKph: 110, ersStore: List.filled(n, 2e6));
    final ers = analyzeLap(lap, full, detectLapCorners(full)).ers!;

    expect(ers.emptyAtM, closeTo(600, 5));
    expect(ers.emptyNear?.number, 1);
    expect(ers.startFraction, 0.5);
    expect(ersFeedbackLines(ers).first, '랩 시작 50% → 끝 0% (기준 50% → 50%)');
  });

  test('피드백 글자: 관찰 → 고칠 점, 속도는 사용자 단위', () {
    expect(cornerFactorText((kind: CornerFactorKind.brakeLater, amount: 19.6), UnitSystem.metric),
        '브레이킹이 20m 늦어요 → 진입 오버슛, 브레이크 포인트를 앞당기세요');
    expect(cornerFactorText((kind: CornerFactorKind.slowerApex, amount: 16.1), UnitSystem.imperial),
        '코너 최저속도가 10mph 낮아요 → 진입 속도를 더 가져가세요');
  });

  testWidgets('랩 분석 카드: 잃은 코너·이유, 누르면 그 코너를 알린다', (t) async {
    final lap = _lap(brakeAtM: 320, apexKph: 100);
    LapCorner? selected;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: LapAnalysisCard(
            analysis: analyzeLap(lap, reference, detectLapCorners(reference)),
            referenceLabel: '내 최고 랩',
            units: UnitSystem.metric,
            onSelect: (c) => selected = c,
          ),
        ),
      ),
    ));

    expect(find.text('기준: 내 최고 랩'), findsOneWidget);
    expect(find.textContaining('브레이킹이 20m 늦어요'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('lap-analysis-corner-T1')));
    expect(selected?.number, 1);
  });
}
