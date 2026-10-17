import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:simcenter_app/features/dashboard/presentation/dashboard_page.dart';
import 'package:simcenter_app/features/laps/data/laps_repository.dart';
import 'package:simcenter_app/features/laps/domain/lap_models.dart';

import 'support/fakes.dart';

Future<FakeLapsRepository> _pumpDashboard(WidgetTester tester, List<Lap> laps) async {
  setViewSize(tester, const Size(1000, 800));
  final repo = FakeLapsRepository(laps: laps);
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, _) => const DashboardPage()),
    GoRoute(path: '/laps', builder: (_, _) => const Text('body:laps')),
  ]);

  await tester.pumpWidget(ProviderScope(
    overrides: [fakeAuth(), lapsRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  testWidgets('환영 문구에 표시 이름이 들어간다', (t) async {
    await _pumpDashboard(t, const []);

    expect(find.text('Welcome 홍길동!'), findsOneWidget);
  });

  testWidgets('최근 랩을 5개만 요청해 트랙명과 랩타임을 보여준다', (t) async {
    final repo = await _pumpDashboard(t, [
      lapOf('l1', 'Silverstone', 83452),
      lapOf('l2', 'Monaco', 71000, isValid: false),
    ]);

    expect(repo.pageSizes, [5]);
    expect(find.text('Silverstone'), findsOneWidget);
    expect(find.text('1:23.452'), findsOneWidget);
    expect(find.text('Monaco'), findsOneWidget);
    expect(find.text('1:11.000'), findsOneWidget);
    expect(find.text('무효'), findsOneWidget);
  });

  testWidgets('랩이 없으면 안내 문구를 보여준다', (t) async {
    await _pumpDashboard(t, const []);

    expect(find.textContaining('아직 기록된 랩이 없어요'), findsOneWidget);
  });

  testWidgets('View all lap times를 누르면 /laps로 이동한다', (t) async {
    await _pumpDashboard(t, [lapOf('l1', 'Silverstone', 83452)]);

    await t.tap(find.text('View all lap times'));
    await t.pumpAndSettle();

    expect(find.text('body:laps'), findsOneWidget);
  });
}
