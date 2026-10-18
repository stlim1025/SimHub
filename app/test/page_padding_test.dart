import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simcenter_app/core/layout/layout_constants.dart';
import 'package:simcenter_app/core/layout/page_padding.dart';

/// 셸 화면 여백: 넓은 화면에서 내용은 왼쪽 정렬·최대 폭, 스크롤 영역은 본문 전체.
void main() {
  Future<EdgeInsets> paddingFor(WidgetTester tester, double? width) async {
    late EdgeInsets padding;
    final probe = Builder(builder: (context) {
      padding = pagePadding(context);
      return const SizedBox();
    });
    await tester.pumpWidget(width == null ? probe : ContentAreaWidth(width: width, child: probe));
    return padding;
  }

  testWidgets('넓은 본문이면 오른쪽 여백을 늘려 내용 폭을 최대 폭에 맞추고 왼쪽에 붙인다', (t) async {
    final padding = await paddingFor(t, 2000);

    expect(padding.left, kPagePadding.left);
    expect(2000 - padding.horizontal, kContentMaxWidth);
  });

  testWidgets('본문이 최대 폭보다 좁거나 셸 밖이면 기본 여백', (t) async {
    expect(await paddingFor(t, 800), kPagePadding);
    expect(await paddingFor(t, null), kPagePadding);
  });
}
