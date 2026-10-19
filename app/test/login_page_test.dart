import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simcenter_app/features/auth/application/auth_controller.dart';
import 'package:simcenter_app/features/auth/presentation/login_page.dart';

import 'support/fakes.dart';

/// 실제 HTTP 없이 login/register 호출만 기록하는 인증 컨트롤러.
class _RecordingAuthController extends FakeAuthController {
  _RecordingAuthController() : super(null);

  final logins = <({String email, String password})>[];
  final registers = <({String email, String password, String displayName})>[];

  /// 지정하면 완료될 때까지 login이 끝나지 않는다(진행 중 상태 재현).
  Completer<void>? loginGate;

  @override
  Future<void> login(String email, String password) async {
    logins.add((email: email, password: password));
    await loginGate?.future;
  }

  @override
  Future<void> register(String email, String password, String displayName) async {
    registers.add((email: email, password: password, displayName: displayName));
  }
}

Future<_RecordingAuthController> _pumpLogin(WidgetTester tester) async {
  setViewSize(tester, const Size(800, 900));
  final controller = _RecordingAuthController();
  await tester.pumpWidget(ProviderScope(
    overrides: [authControllerProvider.overrideWith(() => controller)],
    child: const MaterialApp(home: LoginPage()),
  ));
  await tester.pumpAndSettle();
  return controller;
}

Finder _field(String label) => find.widgetWithText(TextFormField, label);

Future<void> _type(WidgetTester tester, String label, String text) async {
  await tester.enterText(_field(label), text);
}

bool _hasFocus(WidgetTester tester, String label) => tester
    .widget<EditableText>(find.descendant(of: _field(label), matching: find.byType(EditableText)))
    .focusNode
    .hasFocus;

void main() {
  testWidgets('이메일에서 엔터를 누르면 비밀번호로 포커스가 이동하고 제출하지 않는다', (t) async {
    final controller = await _pumpLogin(t);

    await _type(t, '이메일', 'a@b.com');
    await t.testTextInput.receiveAction(TextInputAction.next);
    await t.pump();

    expect(_hasFocus(t, '비밀번호'), isTrue);
    expect(controller.logins, isEmpty);
  });

  testWidgets('로그인 모드에서 비밀번호 엔터는 로그인 버튼과 같은 제출을 한다', (t) async {
    final controller = await _pumpLogin(t);

    await _type(t, '이메일', ' a@b.com ');
    await _type(t, '비밀번호', 'secret-pw');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();

    expect(controller.logins, [(email: 'a@b.com', password: 'secret-pw')]);
    expect(controller.registers, isEmpty);
  });

  testWidgets('입력이 비어 있으면 엔터로 제출해도 검증 오류만 보이고 호출하지 않는다', (t) async {
    final controller = await _pumpLogin(t);

    await _type(t, '비밀번호', 'x');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();

    expect(find.text('이메일을 입력해 주세요.'), findsOneWidget);
    expect(controller.logins, isEmpty);
  });

  testWidgets('진행 중에 엔터를 다시 눌러도 중복 제출하지 않는다', (t) async {
    final controller = await _pumpLogin(t);
    controller.loginGate = Completer<void>();

    await _type(t, '이메일', 'a@b.com');
    await _type(t, '비밀번호', 'secret-pw');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pump();
    // 첫 제출이 끝나기 전에 같은 입력창에서 엔터를 한 번 더 누른다.
    await t.showKeyboard(find.descendant(of: _field('비밀번호'), matching: find.byType(EditableText)));
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pump();

    expect(controller.logins, hasLength(1));

    controller.loginGate!.complete();
    await t.pumpAndSettle();
  });

  testWidgets('회원가입 모드에서는 비밀번호 엔터가 닉네임으로 이동하고 닉네임 엔터가 제출한다', (t) async {
    final controller = await _pumpLogin(t);
    await t.tap(find.text('회원가입하기'));
    await t.pumpAndSettle();

    await _type(t, '이메일', 'a@b.com');
    await _type(t, '비밀번호', 'secret-pw');
    await t.testTextInput.receiveAction(TextInputAction.next);
    await t.pump();

    expect(_hasFocus(t, '닉네임'), isTrue);
    expect(controller.registers, isEmpty);

    await _type(t, '닉네임', '  홍길동 ');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();

    expect(controller.registers, [(email: 'a@b.com', password: 'secret-pw', displayName: '홍길동')]);
    expect(controller.logins, isEmpty);
  });
}
