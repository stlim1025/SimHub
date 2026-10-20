import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simcenter_app/core/widgets/check_toggle.dart';
import 'package:simcenter_app/core/widgets/select_box.dart';

void main() {
  testWidgets('선택 상자: 현재 값을 보이고, 누르면 목록이 열려 고른 값을 알린다', (tester) async {
    String? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 240,
            child: SelectBox<String>(
              options: const [(value: 'F1_25', label: 'F1 25'), (value: 'F1_26', label: 'F1 26')],
              selected: 'F1_25',
              onSelected: (v) => picked = v,
              optionKeyOf: (v) => ValueKey('opt-$v'),
            ),
          ),
        ),
      ),
    );

    expect(find.text('F1 25'), findsOneWidget);
    expect(find.byType(DropdownButton<String>), findsNothing);

    await tester.tap(find.text('F1 25'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('opt-F1_26')));
    await tester.pumpAndSettle();

    expect(picked, 'F1_26');
  });

  testWidgets('체크 토글: 누르면 반대 값을 알린다', (tester) async {
    bool? changed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CheckToggle(label: '유효 랩만', value: false, onChanged: (v) => changed = v)),
      ),
    );

    await tester.tap(find.text('유효 랩만'));

    expect(changed, isTrue);
    expect(find.byIcon(Icons.check_box_outline_blank), findsOneWidget);
  });
}
