import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'layout_constants.dart';

/// 셸 본문 영역의 폭을 아래 화면에 알린다. 화면은 [pagePadding]으로 내용을 왼쪽 정렬·최대 폭으로 묶는다.
class ContentAreaWidth extends InheritedWidget {
  const ContentAreaWidth({super.key, required this.width, required super.child});

  final double width;

  static double? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ContentAreaWidth>()?.width;

  @override
  bool updateShouldNotify(ContentAreaWidth oldWidget) => oldWidget.width != width;
}

/// 셸 화면의 바깥 여백(B안 개편: 화면 전체를 쓴다). 스크롤 영역은 본문 끝까지 두어 어디서든 휠로 스크롤되고,
/// 내용은 [maxWidth](기본 [kContentMaxWidth])보다 넓을 때만 좌우 여백을 똑같이 늘려 가운데로 모은다.
/// 셸 밖(테스트 등)에서는 [kPagePadding] 그대로. 그래프가 주인공인 화면은 [kWideContentMaxWidth], 글 위주 화면은 [kReadableContentMaxWidth].
EdgeInsets pagePadding(BuildContext context, {double maxWidth = kContentMaxWidth}) {
  final width = ContentAreaWidth.of(context);
  if (width == null) {
    return kPagePadding;
  }

  final extra = math.max(0.0, width - maxWidth - kPagePadding.horizontal) / 2;
  return kPagePadding.copyWith(left: kPagePadding.left + extra, right: kPagePadding.right + extra);
}
