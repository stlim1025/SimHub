import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simcenter_app/features/lap_detail/domain/car_setup.dart';
import 'package:simcenter_app/features/lap_detail/domain/lap_detail_models.dart';
import 'package:simcenter_app/features/lap_detail/presentation/setup_diagnosis_card.dart';

/// 실제 카탈루냐 레이스 랩의 셋업(스냅샷 `details.setup`).
const Map<String, dynamic> _setupJson = {
  'ballast': 6,
  'rearToe': 0.11,
  'frontToe': 0.01,
  'rearWing': 26,
  'brakeBias': 54,
  'frontWing': 40,
  'onThrottle': 100,
  'rearCamber': -2,
  'frontCamber': -3.5,
  'offThrottle': 20,
  'brakePressure': 100,
  'engineBraking': 50,
  'rearSuspension': 3,
  'tyrePressureFL': 29.5,
  'tyrePressureFR': 29.5,
  'tyrePressureRL': 21.8,
  'tyrePressureRR': 21.8,
  'frontSuspension': 37,
  'rearAntiRollBar': 19,
  'frontAntiRollBar': 7,
  'rearSuspensionHeight': 43,
  'frontSuspensionHeight': 21,
};

void main() {
  final setup = CarSnapshot.fromJsonOrNull({
    'details': {'setup': _setupJson},
  })!.setup!;

  test('스냅샷 details.setup을 읽는다(공기압은 좌우 평균), 없으면 null', () {
    expect((setup.frontWing, setup.rearWing, setup.brakeBias), (40, 26, 54));
    expect((setup.frontRideHeight, setup.rearRideHeight), (21, 43));
    expect(setup.frontTyrePressure, 29.5);
    expect(CarSnapshot.fromJsonOrNull({'details': <String, dynamic>{}})!.setup, isNull);
  });

  test('앞 윙·리어 안티롤바·열린 오프스로틀이 겹치면 오버스티어 경향, 항목마다 효과를 짚는다', () {
    final d = diagnoseSetup(setup, 'Catalunya');
    String? effectOf(String area, String settingPart) =>
        d.findings.where((f) => f.area == area && f.setting.contains(settingPart)).firstOrNull?.effect;

    expect(d.balance, startsWith('전체적으로 오버스티어 경향'));
    expect(effectOf('공력 밸런스', '프론트가 14 높음'), contains('오버스티어'));
    expect(effectOf('디퍼렌셜', '온스로틀 100%'), contains('휠스핀'));
    expect(effectOf('안티롤바', '프론트 7 · 리어 19'), contains('리어가 먼저 미끄러져'));
    expect(effectOf('브레이크', '압력 100%'), contains('락업'));
    expect(effectOf('브레이크', '밸런스 앞 54%'), contains('무난'));
    expect(effectOf('타이어 공기압', '앞 29.5psi'), contains('과열'));
  });

  test('트랙 적합성: 카탈루냐(중간)엔 윙이 맞고, 모나코(고다운포스)엔 낮다', () {
    final catalunya = diagnoseSetup(setup, 'Catalunya').trackFit.single;
    expect((catalunya.area, catalunya.tone), ('다운포스', SetupTone.good));

    final monaco = diagnoseSetup(setup, 'Monaco').trackFit;
    expect(monaco.first.effect, contains('윙이 낮아요'));
    expect(monaco.first.tone, SetupTone.caution);
    expect(monaco.last.area, '서스펜션'); // 연석·요철 많은 트랙
  });

  testWidgets('셋업 진단 카드: 밸런스·트랙 적합성·항목별 효과', (t) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: SetupDiagnosisCard(setup: setup, trackName: 'Catalunya'))),
    ));

    expect(find.byKey(const ValueKey('setup-balance')), findsOneWidget);
    expect(find.text('트랙 적합성'), findsOneWidget);
    expect(find.text('공력 밸런스 — 프론트가 14 높음'), findsOneWidget);
  });
}
