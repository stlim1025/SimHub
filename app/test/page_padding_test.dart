import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simcenter_app/core/layout/layout_constants.dart';
import 'package:simcenter_app/core/layout/page_padding.dart';

/// 셸 화면 여백: 넓은 화면에서 내용은 최대 폭으로 가운데 정렬, 스크롤 영역은 본문 전체.
void main() {
  Future<EdgeInsets> paddingFor(WidgetTester tester, double? width, {double? maxWidth}) async {
    late EdgeInsets padding;
    final probe = Builder(builder: (context) {
      padding = maxWidth == null ? pagePadding(context) : pagePadding(context, maxWidth: maxWidth);
      return const SizedBox();
    });
    await tester.pumpWidget(width == null ? probe : ContentAreaWidth(width: width, child: probe));
    return padding;
  }

  testWidgets('넓은 본문이면 남는 폭을 좌우 여백에 똑같이 나눠 내용을 최대 폭으로 가운데에 둔다', (t) async {
    const width = kContentMaxWidth + 600;
    final padding = await paddingFor(t, width);

    expect(padding.left, padding.right);
    expect(padding.left, greaterThan(kPagePadding.left));
    expect(width - padding.horizontal, kContentMaxWidth);
    expect(padding.top, kPagePadding.top);
    expect(padding.bottom, kPagePadding.bottom);
  });

  testWidgets('maxWidth를 넘기면 그 폭으로 가운데 정렬한다(글 위주 화면)', (t) async {
    const width = 1600.0;
    final padding = await paddingFor(t, width, maxWidth: kReadableContentMaxWidth);

    expect(padding.left, padding.right);
    expect(width - padding.horizontal, kReadableContentMaxWidth);
  });

  testWidgets('본문이 최대 폭보다 좁거나 셸 밖이면 기본 여백', (t) async {
    expect(await paddingFor(t, 800), kPagePadding);
    expect(await paddingFor(t, kContentMaxWidth), kPagePadding);
    expect(await paddingFor(t, null), kPagePadding);
  });
}
