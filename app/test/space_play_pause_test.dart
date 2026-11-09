import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simcenter_app/core/widgets/space_play_pause.dart';

/// 바깥 글자 칸·바깥 포커스 칸·[SpacePlayPause] 영역(안에 버튼 하나)을 띄운다. [toggles]는 재생·일시정지 횟수.
class _Harness {
  int toggles = 0;
  int innerPressed = 0;
  final FocusNode outside = FocusNode(debugLabel: 'outside');

  Widget build({bool tickerEnabled = true}) => MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              const TextField(key: ValueKey('field')),
              Focus(focusNode: outside, child: const SizedBox(width: 10, height: 10)),
              TickerMode(
                enabled: tickerEnabled,
                child: SpacePlayPause(
                  onToggle: () => toggles++,
                  child: TextButton(
                    key: const ValueKey('inner-button'),
                    onPressed: () => innerPressed++,
                    child: const Text('inner'),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

void main() {
  testWidgets('영역 안에 포커스가 있으면 스페이스를 누를 때마다 한 번 바뀌고, 누른 채 반복돼도 더 바뀌지 않는다', (t) async {
    final h = _Harness();
    await t.pumpWidget(h.build());
    await t.pump();

    await t.sendKeyDownEvent(LogicalKeyboardKey.space);
    await t.sendKeyRepeatEvent(LogicalKeyboardKey.space);
    await t.sendKeyUpEvent(LogicalKeyboardKey.space);
    expect(h.toggles, 1);

    await t.sendKeyEvent(LogicalKeyboardKey.space);
    expect(h.toggles, 2);
  });

  testWidgets('영역 안 버튼을 누른 뒤 스페이스는 재생만 바꾸고 그 버튼을 다시 누르지 않는다', (t) async {
    final h = _Harness();
    await t.pumpWidget(h.build());
    await t.tap(find.byKey(const ValueKey('inner-button')));
    await t.pump();
    expect(h.innerPressed, 1);

    await t.sendKeyEvent(LogicalKeyboardKey.space);
    expect(h.toggles, 1);
    expect(h.innerPressed, 1);
  });

  testWidgets('포커스가 영역 밖에 있어도 스페이스로 바뀌고, 그 뒤로는 영역이 포커스를 갖는다', (t) async {
    final h = _Harness();
    await t.pumpWidget(h.build());
    h.outside.requestFocus();
    await t.pump();

    await t.sendKeyEvent(LogicalKeyboardKey.space);
    await t.pump();
    expect(h.toggles, 1);
    expect(h.outside.hasFocus, isFalse);

    await t.sendKeyEvent(LogicalKeyboardKey.space);
    expect(h.toggles, 2);
  });

  testWidgets('글자 칸에 포커스가 있으면 스페이스는 글자로 넘긴다', (t) async {
    final h = _Harness();
    await t.pumpWidget(h.build());
    await t.tap(find.byKey(const ValueKey('field')));
    await t.pump();

    await t.sendKeyEvent(LogicalKeyboardKey.space);
    expect(h.toggles, 0);
  });

  testWidgets('Ctrl과 함께 누르면 넘긴다', (t) async {
    final h = _Harness();
    await t.pumpWidget(h.build());
    await t.pump();

    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.space);
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(h.toggles, 0);
  });

  testWidgets('위에 다른 화면(대화 상자)이 열려 있으면 넘긴다', (t) async {
    final h = _Harness();
    await t.pumpWidget(h.build());
    await t.pump();
    showDialog<void>(
      context: t.element(find.byKey(const ValueKey('inner-button'))),
      builder: (_) => const AlertDialog(content: Text('dialog')),
    );
    await t.pumpAndSettle();

    await t.sendKeyEvent(LogicalKeyboardKey.space);
    expect(h.toggles, 0);
  });

  testWidgets('보이지 않는 자리(꺼진 탭)에서는 포커스가 밖에 있을 때 넘긴다', (t) async {
    final h = _Harness();
    await t.pumpWidget(h.build(tickerEnabled: false));
    h.outside.requestFocus();
    await t.pump();

    await t.sendKeyEvent(LogicalKeyboardKey.space);
    expect(h.toggles, 0);
  });
}
