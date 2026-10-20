import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simcenter_app/core/widgets/page_loading_bar.dart';

void main() {
  testWidgets('호스트 안에서는 본문 맨 위에 막대를 띄우고, 로딩이 끝나면 걷는다', (tester) async {
    final loading = ValueNotifier<bool>(true);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PageLoadingHost(
            child: ListView(
              children: [
                const SizedBox(height: 200, child: Text('header')),
                ValueListenableBuilder<bool>(
                  valueListenable: loading,
                  builder: (_, isLoading, _) => isLoading ? const PageLoadingBar() : const Text('data'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    final bar = find.byType(LinearProgressIndicator);
    expect(bar, findsOneWidget);
    // 로딩 자리(헤더 아래)가 아니라 본문 영역 맨 위 전체 폭에 붙는다.
    expect(tester.getTopLeft(bar), Offset.zero);
    expect(tester.getSize(bar).width, tester.getSize(find.byType(PageLoadingHost)).width);
    expect(tester.getSize(bar).height, kPageLoadingBarHeight);

    loading.value = false;
    await tester.pump();
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('data'), findsOneWidget);
  });

  testWidgets('호스트가 없으면 그 자리에 전체 폭 막대를 그린다', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: PageLoadingBar())));

    final bar = find.byType(LinearProgressIndicator);
    expect(bar, findsOneWidget);
    expect(tester.getTopLeft(bar), Offset.zero);
    expect(tester.getSize(bar).height, kPageLoadingBarHeight);
  });
}
