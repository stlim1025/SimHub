import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simcenter_app/core/theme/app_theme.dart';
import 'package:simcenter_app/core/widgets/web_dialog.dart';

void main() {
  Future<Future<bool?>> open(WidgetTester tester) async {
    late Future<bool?> result;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => result = showDialog<bool>(
                context: context,
                builder: (dialogContext) => WebDialog(
                  title: '모달 제목',
                  content: const Text('본문'),
                  actions: [
                    const WebDialogCancelButton(),
                    WebDialogPrimaryButton(
                      key: const ValueKey('ok'),
                      label: '삭제',
                      destructive: true,
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                    ),
                  ],
                ),
              ),
              child: const Text('열기'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('웹 모달: 제목·본문·버튼을 보이고 Material AlertDialog를 쓰지 않는다', (tester) async {
    await open(tester);

    expect(find.byType(WebDialog), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('모달 제목'), findsOneWidget);
    expect(find.text('본문'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '취소'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '삭제'), findsOneWidget);
  });

  testWidgets('웹 모달: ✕ 버튼은 null로 닫는다', (tester) async {
    final result = await open(tester);

    await tester.tap(find.byKey(const ValueKey('web-dialog-close')));
    await tester.pumpAndSettle();

    expect(find.byType(WebDialog), findsNothing);
    expect(await result, isNull);
  });

  testWidgets('웹 모달: 주 버튼은 정한 값으로 닫는다', (tester) async {
    final result = await open(tester);

    await tester.tap(find.byKey(const ValueKey('ok')));
    await tester.pumpAndSettle();

    expect(await result, isTrue);
  });
}
