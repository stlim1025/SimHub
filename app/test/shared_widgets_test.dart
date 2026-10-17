import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:simcenter_app/core/theme/app_colors.dart';
import 'package:simcenter_app/core/widgets/ai_badge.dart';
import 'package:simcenter_app/core/widgets/empty_state_card.dart';
import 'package:simcenter_app/core/widgets/not_found_state.dart';
import 'package:simcenter_app/core/widgets/pagination_bar.dart';
import 'package:simcenter_app/core/widgets/stat.dart';
import 'package:simcenter_app/core/widgets/team_color_bar.dart';

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

  group('Stat', () {
    testWidgets('라벨과 값을 위아래로 보여 준다', (t) async {
      await t.pumpWidget(const MaterialApp(home: Scaffold(body: Stat(label: '랩 수', value: '12'))));

      expect(find.text('랩 수'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
      expect(t.getTopLeft(find.text('랩 수')).dy, lessThan(t.getTopLeft(find.text('12')).dy));
      expect(find.byType(InkWell), findsNothing);
    });

    testWidgets('onTap을 주면 값이 링크처럼 눌린다', (t) async {
      var taps = 0;
      await t.pumpWidget(MaterialApp(
        home: Scaffold(body: Stat(label: '시즌', value: 'R7', onTap: () => taps++)),
      ));

      await t.tap(find.text('R7'));

      expect(taps, 1);
      expect(t.widget<Text>(find.text('R7')).style?.color, AppColors.accent);
      expect(t.widget<Text>(find.text('R7')).style?.decoration, TextDecoration.underline);
      expect(t.widget<Text>(find.text('시즌')).style?.decoration, isNot(TextDecoration.underline));
    });
  });

  group('TeamColorBar', () {
    testWidgets('#RRGGBB는 그 색으로 칠한다', (t) async {
      await t.pumpWidget(const MaterialApp(
        home: Scaffold(body: TeamColorBar(key: ValueKey('bar'), colorHex: '#FF8000')),
      ));

      expect(teamBarColor(t, const ValueKey('bar')), const Color(0xFFFF8000));
    });

    testWidgets('잘못된 값은 textMuted로 칠한다', (t) async {
      await t.pumpWidget(const MaterialApp(
        home: Scaffold(body: TeamColorBar(key: ValueKey('bar'), colorHex: 'red')),
      ));

      expect(teamBarColor(t, const ValueKey('bar')), AppColors.textMuted);
    });
  });

  group('AiBadge', () {
    testWidgets('AI 글자를 보여 준다', (t) async {
      await t.pumpWidget(const MaterialApp(home: Scaffold(body: AiBadge())));

      expect(find.text('AI'), findsOneWidget);
    });
  });

  group('EmptyStateCard', () {
    Future<GoRouter> pump(WidgetTester t, {String? actionLabel, String? actionPath}) async {
      setViewSize(t, const Size(800, 600));
      final router = GoRouter(initialLocation: '/empty', routes: [
        GoRoute(
          path: '/empty',
          builder: (_, _) => Scaffold(
            body: EmptyStateCard(message: '아직 없습니다.', actionLabel: actionLabel, actionPath: actionPath),
          ),
        ),
        GoRoute(path: '/target', builder: (_, _) => const Text('target-page')),
      ]);
      await t.pumpWidget(MaterialApp.router(routerConfig: router));
      await t.pumpAndSettle();
      return router;
    }

    testWidgets('메시지만 보여 준다', (t) async {
      await pump(t);

      expect(find.text('아직 없습니다.'), findsOneWidget);
      expect(find.byType(TextButton), findsNothing);
    });

    testWidgets('링크를 주면 누를 수 있고 그 경로로 이동한다', (t) async {
      final router = await pump(t, actionLabel: 'Go', actionPath: '/target');

      await t.tap(find.text('Go'));
      await t.pumpAndSettle();

      expect(router.routeInformationProvider.value.uri.toString(), '/target');
      expect(find.text('target-page'), findsOneWidget);
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
