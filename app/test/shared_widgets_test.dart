import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:simcenter_app/core/widgets/not_found_state.dart';
import 'package:simcenter_app/core/widgets/pagination_bar.dart';

import 'support/fakes.dart';

Future<List<int>> _pumpBar(
  WidgetTester tester, {
  required int page,
  int pageSize = 15,
  required int total,
  Size size = const Size(800, 200),
}) async {
  setViewSize(tester, size);
  final requested = <int>[];
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: PaginationBar(page: page, pageSize: pageSize, total: total, onPageChanged: requested.add),
    ),
  ));
  return requested;
}

OutlinedButton _button(WidgetTester tester, String label) =>
    tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, label));

void main() {
  group('PaginationBar', () {
    testWidgets('첫 페이지는 이전이 꺼지고 다음이 다음 페이지를 요청한다', (t) async {
      final requested = await _pumpBar(t, page: 1, total: 20);

      expect(find.text('Showing 1 to 15 of 20'), findsOneWidget);
      expect(_button(t, '이전').onPressed, isNull);

      await t.tap(find.text('다음'));

      expect(requested, [2]);
    });

    testWidgets('가운데 페이지는 이전·다음이 모두 켜진다', (t) async {
      final requested = await _pumpBar(t, page: 2, total: 50);

      await t.tap(find.text('이전'));
      await t.tap(find.text('다음'));

      expect(requested, [1, 3]);
    });

    testWidgets('마지막 페이지는 다음이 꺼진다', (t) async {
      await _pumpBar(t, page: 2, total: 20);

      expect(find.text('Showing 16 to 20 of 20'), findsOneWidget);
      expect(_button(t, '다음').onPressed, isNull);
      expect(_button(t, '이전').onPressed, isNotNull);
    });

    testWidgets('딱 한 페이지 분량이면 둘 다 꺼진다', (t) async {
      await _pumpBar(t, page: 1, total: 15);

      expect(_button(t, '이전').onPressed, isNull);
      expect(_button(t, '다음').onPressed, isNull);
    });

    testWidgets('좁은 화면에서도 넘치지 않는다', (t) async {
      await _pumpBar(t, page: 1, total: 20, size: const Size(320, 200));

      expect(t.takeException(), isNull);
    });
  });

  group('NotFoundState', () {
    testWidgets('메시지와 목록 링크를 보여 주고 다시 시도는 없다', (t) async {
      setViewSize(t, const Size(800, 600));
      final router = GoRouter(initialLocation: '/detail', routes: [
        GoRoute(
          path: '/detail',
          builder: (_, _) => const Scaffold(
            body: NotFoundState(message: '찾을 수 없는 세션입니다.', backLabel: 'Sessions', backPath: '/list'),
          ),
        ),
        GoRoute(path: '/list', builder: (_, _) => const Text('list-page')),
      ]);
      await t.pumpWidget(MaterialApp.router(routerConfig: router));
      await t.pumpAndSettle();

      expect(find.text('찾을 수 없는 세션입니다.'), findsOneWidget);
      expect(find.text('다시 시도'), findsNothing);

      await t.tap(find.text('Sessions'));
      await t.pumpAndSettle();

      expect(router.routeInformationProvider.value.uri.toString(), '/list');
      expect(find.text('list-page'), findsOneWidget);
    });
  });
}
