import 'package:flutter/widgets.dart';

/// 목록 보드의 왼쪽 목록 열 폭·오른쪽 카드 열 폭·열 사이 간격(논리 px).
const double kListBoardRailWidth = 280;
const double kListBoardAsideWidth = 380;
const double kListBoardGap = 20;

/// 받은 폭이 이 이상이면 오른쪽 카드 열을 두고, [kListBoardRailMinWidth] 이상이면 왼쪽 목록 열까지 둔다.
const double kListBoardAsideMinWidth = 1100;
const double kListBoardRailMinWidth = 1500;

/// 목록 화면(세션·랩·리더보드)의 보드 배치: 넓은 화면에서 가운데 목록만 덩그러니 놓이지 않게 왼쪽에 [rail](바로 옮겨 갈 목록),
/// 오른쪽에 [aside](요약 카드 열)를 둔다. 폭이 모자라면 왼쪽 열 → 오른쪽 열 순으로 빼고, 좁으면 [main]만 그린다.
/// 세 열은 위끝을 맞추고 함께 스크롤된다.
class ListBoard extends StatelessWidget {
  const ListBoard({super.key, required this.main, this.rail, this.aside});

  final Widget main;
  final Widget? rail;
  final Widget? aside;

  /// 폭 [width]에서 왼쪽 목록 열을 두는지.
  static bool showsRail(double width) => width >= kListBoardRailMinWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final rail = this.rail;
        final aside = this.aside;
        final showRail = rail != null && showsRail(constraints.maxWidth);
        final showAside = aside != null && constraints.maxWidth >= kListBoardAsideMinWidth;
        if (!showRail && !showAside) {
          return main;
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showRail) ...[
              SizedBox(width: kListBoardRailWidth, child: rail),
              const SizedBox(width: kListBoardGap),
            ],
            Expanded(child: main),
            if (showAside) ...[
              const SizedBox(width: kListBoardGap),
              SizedBox(width: kListBoardAsideWidth, child: aside),
            ],
          ],
        );
      },
    );
  }
}
