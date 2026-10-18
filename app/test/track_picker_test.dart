import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simcenter_app/core/theme/app_palette.dart';
import 'package:simcenter_app/core/theme/app_theme.dart';
import 'package:simcenter_app/core/widgets/track_flag.dart';
import 'package:simcenter_app/core/widgets/track_picker.dart';

import 'support/fakes.dart';

/// docs/15 §4.1 시드 순서의 앞부분 + 국가 코드가 없는 트랙.
const _tracks = [
  TrackChoice(id: 't0', name: 'Melbourne', countryCode: 'AU'),
  TrackChoice(id: 't2', name: 'Shanghai', countryCode: 'CN'),
  TrackChoice(id: 't13', name: 'Suzuka', countryCode: 'JP'),
  TrackChoice(id: 't29', name: 'Jeddah', countryCode: 'SA'),
  TrackChoice(id: 'tx', name: 'Mystery Ring'),
];

/// 31개 트랙(스크롤 확인용).
final _manyTracks = [
  for (var i = 1; i <= 31; i++) TrackChoice(id: 'm$i', name: 'Track $i', countryCode: 'GB'),
];

Future<List<TrackChoice>> _pump(
  WidgetTester tester, {
  List<TrackChoice> tracks = _tracks,
  TrackChoice? selected,
  Size size = const Size(1000, 800),
  ThemeData? theme,
}) async {
  setViewSize(tester, size);
  final picked = <TrackChoice>[];
  await tester.pumpWidget(MaterialApp(
    theme: theme,
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: TrackPicker(tracks: tracks, selected: selected, onSelected: picked.add),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return picked;
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('track-picker')));
  await tester.pumpAndSettle();
}

void main() {
  group('TrackFlag', () {
    testWidgets('알려진 국가 코드는 원형 국기(country_flags)로 그린다', (t) async {
      await t.pumpWidget(const MaterialApp(home: TrackFlag(countryCode: 'sa')));

      expect(find.byKey(const ValueKey('track-flag-SA')), findsOneWidget);
      expect(find.byType(CountryFlag), findsOneWidget);
    });

    testWidgets('코드가 없거나 모르는 코드면 회색 원', (t) async {
      for (final code in [null, 'XX', 'SAU', '']) {
        await t.pumpWidget(MaterialApp(home: TrackFlag(countryCode: code)));

        expect(find.byKey(const ValueKey('track-flag-fallback')), findsOneWidget, reason: '$code');
        expect(find.byType(CountryFlag), findsNothing, reason: '$code');
      }
    });

    test('flagCodeOf는 두 글자 코드만 대문자로 돌려준다', () {
      expect(TrackFlag.flagCodeOf('gb'), 'GB');
      expect(TrackFlag.flagCodeOf('GBR'), isNull);
      expect(TrackFlag.flagCodeOf('ZZ'), isNull);
      expect(TrackFlag.flagCodeOf(null), isNull);
    });
  });

  group('TrackPicker', () {
    testWidgets('제목은 고른 트랙의 국기 + 이름 + 펼침 아이콘', (t) async {
      await _pump(t, selected: _tracks[3]);

      expect(find.text('Jeddah'), findsOneWidget);
      expect(find.byKey(const ValueKey('track-flag-SA')), findsOneWidget);
      expect(find.byIcon(Icons.unfold_more), findsOneWidget);
    });

    testWidgets('고른 트랙이 없으면 자리표시 글자(국기 없음)', (t) async {
      await _pump(t);

      expect(find.text('Select track'), findsOneWidget);
      expect(find.byType(TrackFlag), findsNothing);
    });

    testWidgets('제목을 누르면 받은 순서(캘린더 순서)대로 국기와 함께 목록을 연다', (t) async {
      await _pump(t, selected: _tracks[0]);

      await _open(t);

      double top(String id) => t.getTopLeft(find.byKey(ValueKey('track-option-$id'))).dy;
      expect(top('t0'), lessThan(top('t2')));
      expect(top('t2'), lessThan(top('t13')));
      expect(top('t13'), lessThan(top('t29')));
      expect(top('t29'), lessThan(top('tx')));
      expect(
        find.descendant(of: find.byKey(const ValueKey('track-option-t13')), matching: find.byKey(const ValueKey('track-flag-JP'))),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byKey(const ValueKey('track-option-tx')), matching: find.byKey(const ValueKey('track-flag-fallback'))),
        findsOneWidget,
      );
    });

    testWidgets('목록의 폭은 280이고, 고른 트랙만 링크 색 글자 + ✓다', (t) async {
      await _pump(t, selected: _tracks[1]);

      await _open(t);

      expect(t.getSize(find.byKey(const ValueKey('track-option-t2'))).width, kTrackMenuWidth);
      Color? colorOf(String name) => t
          .widget<Text>(find.descendant(of: find.byType(MenuItemButton), matching: find.text(name)))
          .style
          ?.color;
      expect(colorOf('Shanghai'), AppPalette.dark.link);
      expect(find.descendant(of: find.byKey(const ValueKey('track-option-t2')), matching: find.byIcon(Icons.check)), findsOneWidget);
      expect(find.byIcon(Icons.check), findsOneWidget);
      expect(colorOf('Melbourne'), isNot(AppPalette.dark.link));
    });

    testWidgets('항목을 누르면 그 트랙을 알리고 목록을 닫는다', (t) async {
      final picked = await _pump(t, selected: _tracks[0]);
      await _open(t);

      await t.tap(find.byKey(const ValueKey('track-option-t29')));
      await t.pumpAndSettle();

      expect(picked, [_tracks[3]]);
      expect(find.byKey(const ValueKey('track-option-t29')), findsNothing);
    });

    testWidgets('목록이 열린 채로 메뉴 밖을 누르면 목록만 닫히고 아래 위젯은 눌리지 않는다', (t) async {
      setViewSize(t, const Size(1000, 800));
      var underneathTaps = 0;
      final picked = <TrackChoice>[];
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  key: const ValueKey('underneath'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => underneathTaps++,
                ),
              ),
              Align(
                alignment: Alignment.topLeft,
                child: TrackPicker(tracks: _tracks, selected: _tracks[0], onSelected: picked.add),
              ),
            ],
          ),
        ),
      ));
      await _open(t);

      await t.tapAt(const Offset(900, 600));
      await t.pumpAndSettle();

      expect(underneathTaps, 0);
      expect(picked, isEmpty);
      expect(find.byKey(const ValueKey('track-option-t29')), findsNothing);

      // 닫힌 뒤에는 아래 위젯이 평소처럼 눌린다.
      await t.tapAt(const Offset(900, 600));
      expect(underneathTaps, 1);
    });

    testWidgets('트랙이 많으면 목록 높이는 화면의 80% 이하이고 스크롤해 마지막 트랙을 고를 수 있다', (t) async {
      final picked = await _pump(t, tracks: _manyTracks, selected: _manyTracks.first, size: const Size(800, 600));
      await _open(t);

      final menu = find.ancestor(of: find.byKey(const ValueKey('track-option-m1')), matching: find.byType(Scrollable)).first;
      expect(t.getSize(menu).height, lessThanOrEqualTo(600 * kTrackMenuMaxHeightFactor));

      await t.scrollUntilVisible(find.byKey(const ValueKey('track-option-m31')), 200, scrollable: menu);
      await t.tap(find.byKey(const ValueKey('track-option-m31')));
      await t.pumpAndSettle();

      expect(picked.single.id, 'm31');
    });

    testWidgets('트랙이 없으면 눌러도 목록이 열리지 않는다', (t) async {
      await _pump(t, tracks: const []);

      await _open(t);

      expect(find.byType(MenuItemButton), findsNothing);
    });

    testWidgets('휴대폰 폭에서 긴 이름도 넘치지 않는다(밝은 테마 포함)', (t) async {
      const long = TrackChoice(id: 'l', name: 'Circuit de Barcelona-Catalunya Grand Prix Layout', countryCode: 'ES');
      for (final theme in [AppTheme.dark, AppTheme.light]) {
        await _pump(t, tracks: const [long], selected: long, size: const Size(375, 800), theme: theme);
        await _open(t);

        expect(t.takeException(), isNull);
        await t.tapAt(const Offset(10, 790)); // 목록 밖을 눌러 닫는다.
        await t.pumpAndSettle();
      }
    });
  });
}
