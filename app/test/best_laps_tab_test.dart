import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simcenter_app/core/theme/app_colors.dart';

import 'support/fakes.dart';
import 'support/lap_detail_harness.dart';

const _bestLocation = '/laps/l1?tab=best';

/// 이 트랙의 랩: l2(97.896) < l1(98.448, 지금 보는 랩) < l3(99.000), 무효 l4(90.000)는 빠진다.
FakeLapsRepository _laps() => FakeLapsRepository(laps: [
      sampleLap(),
      lapOf('l2', 'Jeddah', 97896, team: ferrari, gameMode: 'GrandPrix'),
      lapOf('l3', 'Jeddah', 99000),
      lapOf('l4', 'Jeddah', 90000, isValid: false),
    ]);

FakeLapDetailRepository _detailRepo() => FakeLapDetailRepository(details: {'l1': sampleDetail()});

Color? _rowColor(WidgetTester tester, String lapId) => tester
    .widget<Material>(find.descendant(of: find.byKey(ValueKey('best-row-$lapId')), matching: find.byType(Material)).first)
    .color;

void main() {
  testWidgets('이 트랙의 유효 랩 빠른 순 10개를 요청한다(sort=fastest&validOnly=true&pageSize=10)', (t) async {
    final laps = _laps();
    await pumpLapDetail(t, detailRepo: _detailRepo(), lapsRepo: laps, location: _bestLocation);

    expect(laps.requests.single, (trackId: 't1', sort: 'fastest', validOnly: true, page: 1, pageSize: 10));
  });

  testWidgets('열은 # · TEAM · TIME · GAP · MODE · DATE, GAP은 1위 대비이고 1위는 -', (t) async {
    await pumpLapDetail(t, detailRepo: _detailRepo(), lapsRepo: _laps(), location: _bestLocation);

    for (final header in ['#', 'TEAM', 'TIME', 'GAP', 'MODE', 'DATE']) {
      expect(find.text(header), findsOneWidget, reason: header);
    }
    double top(String lapId) => t.getTopLeft(find.byKey(ValueKey('best-row-$lapId'))).dy;
    expect(top('l2'), lessThan(top('l1')));
    expect(top('l1'), lessThan(top('l3')));
    expect(find.byKey(const ValueKey('best-row-l4')), findsNothing);
    expect(find.descendant(of: find.byKey(const ValueKey('best-row-l1')), matching: find.text('+0.552')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('best-row-l3')), matching: find.text('+1.104')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('best-row-l2')), matching: find.text('Grand Prix')), findsOneWidget);
  });

  testWidgets('지금 보는 랩만 강조한다', (t) async {
    await pumpLapDetail(t, detailRepo: _detailRepo(), lapsRepo: _laps(), location: _bestLocation);

    expect(_rowColor(t, 'l1'), AppColors.playerRow);
    expect(_rowColor(t, 'l2'), Colors.transparent);
  });

  testWidgets('행을 누르면 그 랩의 상세로 간다', (t) async {
    final repo = FakeLapDetailRepository(details: {'l1': sampleDetail(), 'l2': sampleDetail(lap: sampleLap(id: 'l2'))});
    final router = await pumpLapDetail(t, detailRepo: repo, lapsRepo: _laps(), location: _bestLocation);

    await t.tap(find.byKey(const ValueKey('best-row-l2')));
    await t.pumpAndSettle();

    expect(locationOf(router), '/laps/l2');
    expect(repo.detailRequests.last, 'l2');
  });

  testWidgets('유효 랩이 하나도 없으면 안내를 보인다', (t) async {
    await pumpLapDetail(t, detailRepo: _detailRepo(), location: _bestLocation);

    expect(find.text('이 트랙에 유효 랩이 없습니다'), findsOneWidget);
  });

  testWidgets('600px 미만이면 MODE·DATE를 숨긴다', (t) async {
    await pumpLapDetail(t, detailRepo: _detailRepo(), lapsRepo: _laps(), location: _bestLocation, size: const Size(375, 3000));

    expect(t.takeException(), isNull);
    expect(find.text('GAP'), findsOneWidget);
    expect(find.text('MODE'), findsNothing);
    expect(find.text('DATE'), findsNothing);
  });
}
