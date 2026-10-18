import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simcenter_app/core/theme/app_colors.dart';
import 'package:simcenter_app/core/widgets/button_group.dart';
import 'package:simcenter_app/core/widgets/compact_table.dart';

import 'support/fakes.dart';

final _columns = [
  CompactColumn<String>(label: 'Name', flex: 2, cell: (row) => Text(row)),
  CompactColumn<String>(label: 'Extra', compactHidden: true, cell: (row) => Text('x-$row')),
  CompactColumn<String>(label: 'Fixed', width: 40, header: const Icon(Icons.star), cell: (_) => const Text('f')),
];

Future<List<String>> _pumpTable(WidgetTester tester, {double width = 800, String? highlighted}) async {
  setViewSize(tester, Size(width, 600));
  final tapped = <String>[];
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: CompactTable<String>(
        columns: _columns,
        rows: const ['a', 'b'],
        rowKey: (row) => ValueKey('row-$row'),
        isHighlighted: (row) => row == highlighted,
        onRowTap: tapped.add,
        footer: const Text('footer'),
      ),
    ),
  ));
  return tapped;
}

Color? _rowColor(WidgetTester tester, String row) => tester
    .widget<Material>(find.descendant(of: find.byKey(ValueKey('row-$row')), matching: find.byType(Material)).first)
    .color;

void main() {
  group('CompactTable', () {
    testWidgets('머리글은 대문자, 아이콘 머리글도 쓰며, 행을 누르면 그 행을 알린다', (t) async {
      final tapped = await _pumpTable(t);

      expect(find.text('NAME'), findsOneWidget);
      expect(find.text('EXTRA'), findsOneWidget);
      expect(find.byIcon(Icons.star), findsOneWidget);
      expect(find.text('footer'), findsOneWidget);
      expect(t.getSize(find.byKey(const ValueKey('row-a'))).height, kCompactRowHeight);

      await t.tap(find.text('x-b'));

      expect(tapped, ['b']);
    });

    testWidgets('폭이 기준(600) 미만이면 compactHidden 열을 숨긴다', (t) async {
      await _pumpTable(t, width: 500);

      expect(find.text('EXTRA'), findsNothing);
      expect(find.text('x-a'), findsNothing);
      expect(find.text('NAME'), findsOneWidget);
    });

    testWidgets('강조 행만 playerRow 배경이다', (t) async {
      await _pumpTable(t, highlighted: 'b');

      expect(_rowColor(t, 'b'), AppColors.playerRow);
      expect(_rowColor(t, 'a'), Colors.transparent);
    });
  });

  testWidgets('ButtonGroup은 누른 값을 알린다', (t) async {
    final picked = <int>[];
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ButtonGroup<int>(
          options: const [(value: 1, label: 'One'), (value: 2, label: 'Two')],
          selected: 1,
          onSelected: picked.add,
        ),
      ),
    ));

    await t.tap(find.text('Two'));

    expect(picked, [2]);
  });
}
