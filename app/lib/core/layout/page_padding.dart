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

/// 셸 화면의 바깥 여백(F1Laps처럼 왼쪽 정렬). 스크롤 영역은 본문 끝까지 두어 어디서든 휠로 스크롤되고,
/// 내용은 오른쪽 여백을 늘려 [maxWidth](기본 [kContentMaxWidth])까지만 쓴다. 셸 밖(테스트 등)에서는 [kPagePadding] 그대로.
/// 그래프가 주인공인 화면(랩 상세)은 [kWideContentMaxWidth]를 넘겨 큰 모니터의 빈 폭을 쓴다.
EdgeInsets pagePadding(BuildContext context, {double maxWidth = kContentMaxWidth}) {
  final width = ContentAreaWidth.of(context);
  if (width == null) {
    return kPagePadding;
  }

  final extraRight = math.max(0.0, width - maxWidth - kPagePadding.horizontal);
  return kPagePadding.copyWith(right: kPagePadding.right + extraRight);
}
