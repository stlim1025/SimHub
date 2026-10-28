import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:simcenter_app/features/auth/domain/auth_models.dart';
import 'package:simcenter_app/features/lap_detail/application/lap_detail_providers.dart';
import 'package:simcenter_app/features/lap_detail/data/lap_detail_repository.dart';
import 'package:simcenter_app/features/lap_detail/domain/lap_compare.dart';
import 'package:simcenter_app/features/lap_detail/domain/lap_detail_models.dart';
import 'package:simcenter_app/features/lap_detail/presentation/lap_detail_page.dart';
import 'package:simcenter_app/features/lap_detail/presentation/lap_setup_page.dart';
import 'package:simcenter_app/features/laps/data/laps_repository.dart';
import 'package:simcenter_app/features/laps/domain/lap_models.dart';
import 'package:simcenter_app/features/ranking/data/ranking_repository.dart';

import 'fakes.dart';

const ferrari = LapTeam(name: 'Ferrari', color: '#E8002D');

/// 이 랩: 98.448초(S1 31.000 · S2 33.448 · S3 34.000), Ferrari, Driver Career, 맑음, 5번째 랩, 트레이스 있음.
final sampleSetAt = DateTime.utc(2026, 7, 26, 9, 3, 21);

Lap sampleLap({String id = 'l1', bool isValid = true, bool hasTrace = true, int ms = 98448}) => lapOf(
      id,
      'Jeddah',
      ms,
      isValid: isValid,
      sectors: const [
        LapSector(sectorNumber: 1, sectorTimeMs: 31000),
        LapSector(sectorNumber: 2, sectorTimeMs: 33448),
        LapSector(sectorNumber: 3, sectorTimeMs: 34000),
      ],
      team: ferrari,
      gameMode: 'DriverCareer',
      weather: 'Clear',
      lapNumber: 5,
      hasTrace: hasTrace,
      setAt: sampleSetAt,
    );

/// 내 최고 유효 랩: 98.000초(S1 30.500 · S2 33.300 · S3 34.200) → Delta TOTAL +0.448 · S1 +0.500 · S2 +0.148 · S3 −0.200.
ComparisonLap sampleComparison({String id = 'best', bool hasTrace = true}) => comparisonOf(
      id,
      98000,
      sectors: const [
        LapSector(sectorNumber: 1, sectorTimeMs: 30500),
        LapSector(sectorNumber: 2, sectorTimeMs: 33300),
        LapSector(sectorNumber: 3, sectorTimeMs: 34200),
      ],
      hasTrace: hasTrace,
    );

/// 마모 끝 FL 31(노랑) · FR 18 · RL 24(초록) · RR 80(빨강), 시작 27 · 14 · 20 · 14. 앞날개 L 0 · R 60, 사이드포드 20 · 기어박스 10 · 엔진 30.
const sampleCar = CarSnapshot(
  visualTyreCompound: 16,
  actualTyreCompound: 18,
  tyreAgeLaps: 3,
  tyreWearStart: WheelValues(frontLeft: 27, frontRight: 14, rearLeft: 20, rearRight: 14),
  tyreWearEnd: WheelValues(frontLeft: 31, frontRight: 18, rearLeft: 24, rearRight: 80),
  brakeDamage: WheelValues(frontLeft: 0, frontRight: 0, rearLeft: 0, rearRight: 5),
  frontLeftWingDamage: 0,
  frontRightWingDamage: 60,
  rearWingDamage: 0,
  floorDamage: 0,
  diffuserDamage: 0,
  sidepodDamage: 20,
  gearboxDamage: 10,
  engineDamage: 30,
  fuelStartKg: 24.4,
  fuelEndKg: 22.7,
  fuelRemainingLaps: 13.1,
  ersStoreStartJ: 1494000,
  ersStoreEndJ: 988000,
);

const sampleConditions = LapConditions(weather: 'Clear', airTempC: 21, trackTempC: 31, rainForecastPercent: 4);

/// TC Medium · ABS On · 조향 Off · 제동 Off · 기어 Manual · 라인 Corners(F1Laps 스크린샷과 같은 값).
const sampleAssists = LapAssists(
  tractionControl: 'Medium',
  antiLockBrakes: 'On',
  steeringAssist: 'Off',
  brakingAssist: 'Off',
  gearbox: 'Manual',
  racingLine: 'CornersOnly',
);

/// [withComparison]이 false면 비교 대상 없음 + 까닭 [unavailable](기본 noMatch).
LapDetail sampleDetail({
  Lap? lap,
  CarSnapshot? car = sampleCar,
  LapConditions? conditions = sampleConditions,
  LapAssists? assists = sampleAssists,
  ComparisonLap? comparison,
  bool withComparison = true,
  ComparisonUnavailable unavailable = ComparisonUnavailable.noMatch,
  String? sessionId = 's1',
}) =>
    lapDetailOf(
      lap ?? sampleLap(),
      sessionId: sessionId,
      car: car,
      conditions: conditions,
      assists: assists,
      comparison: withComparison ? (comparison ?? sampleComparison()) : null,
      unavailable: withComparison ? null : unavailable,
    );

String locationOf(GoRouter router) => router.routeInformationProvider.value.uri.toString();

/// 랩 상세 화면을 띄운다. 다른 화면 경로는 `track:…`·`session:…`·`laps` 글자로 확인한다.
Future<GoRouter> pumpLapDetail(
  WidgetTester tester, {
  required LapDetailRepository detailRepo,
  LapsRepository? lapsRepo,
  String location = '/laps/l1',
  Size size = const Size(1000, 3000),
  ThemeData? theme,
  AppUser? user = testUser,
  Uri? shareBase,
}) async {
  setViewSize(tester, size);
  final router = GoRouter(initialLocation: location, routes: [
    GoRoute(path: '/laps', builder: (_, _) => const Text('laps')),
    GoRoute(
      path: '/laps/tracks/:trackId',
      builder: (_, state) => Text('track:${state.pathParameters['trackId']}'),
    ),
    GoRoute(
      path: '/laps/:lapId',
      builder: (_, state) => Scaffold(
        body: LapDetailPage(
          lapId: state.pathParameters['lapId']!,
          tab: state.uri.queryParameters['tab'],
          compare: LapCompareSelection.fromQuery(state.uri.queryParameters),
        ),
      ),
    ),
    GoRoute(
      path: '/laps/:lapId/setup',
      builder: (_, state) => Scaffold(body: LapSetupPage(lapId: state.pathParameters['lapId']!)),
    ),
    GoRoute(path: '/sessions/:sessionId', builder: (_, state) => Text('session:${state.pathParameters['sessionId']}')),
  ]);

  await tester.pumpWidget(ProviderScope(
    overrides: [
      fakeAuth(user),
      lapDetailRepositoryProvider.overrideWithValue(detailRepo),
      lapsRepositoryProvider.overrideWithValue(lapsRepo ?? FakeLapsRepository()),
      rankingRepositoryProvider.overrideWithValue(FakeRankingRepository()),
      shareBaseUriProvider.overrideWithValue(shareBase ?? Uri.parse('https://simcenter.test/')),
    ],
    child: MaterialApp.router(theme: theme, routerConfig: router),
  ));
  await tester.pumpAndSettle();
  return router;
}
