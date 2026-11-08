import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// 세션 상세 보드(B안 12칸 격자)의 한 줄: 칸마다 [flex] 비율의 폭(예: 5 : 7), 모든 칸은 가장 높은 칸의 높이.
/// `EqualHeightRow`(같은 폭)와 같은 두 번 배치 방식이라 칸 안의 `LayoutBuilder`(표·그래프)와 함께 써도 된다.
class BoardRow extends MultiChildRenderObjectWidget {
  const BoardRow({super.key, required super.children, required this.flex, required this.gap})
      : assert(flex.length == children.length, 'flex마다 칸이 하나씩 있어야 한다');

  /// 칸마다 폭 비율(길이 = 칸 수).
  final List<int> flex;

  /// 칸 사이 가로 간격(논리 px).
  final double gap;

  @override
  RenderBoardRow createRenderObject(BuildContext context) => RenderBoardRow(flex: flex, gap: gap);

  @override
  void updateRenderObject(BuildContext context, RenderBoardRow renderObject) => renderObject
    ..flex = flex
    ..gap = gap;
}

/// 보드 칸 안에서 카드를 [gap] 간격으로 쌓는 열. 받은 최소 높이가 내용보다 크면 [stretchIndex]번 카드를 늘려
/// 아래 끝을 맞춘다(옆 칸이 더 높을 때 그래프 카드가 남는 높이를 채우게).
class BoardColumn extends MultiChildRenderObjectWidget {
  const BoardColumn({super.key, required super.children, required this.gap, this.stretchIndex = 0});

  /// 카드 사이 세로 간격(논리 px).
  final double gap;

  /// 남는 높이를 받을 카드 번호(범위를 벗어나면 마지막 카드).
  final int stretchIndex;

  @override
  RenderBoardColumn createRenderObject(BuildContext context) => RenderBoardColumn(gap: gap, stretchIndex: stretchIndex);

  @override
  void updateRenderObject(BuildContext context, RenderBoardColumn renderObject) => renderObject
    ..gap = gap
    ..stretchIndex = stretchIndex;
}

class _BoardParentData extends ContainerBoxParentData<RenderBox> {}

/// 두 렌더 상자의 공통 부분(자식 목록·그리기·터치 판정·간격).
abstract class _BoardRenderBox extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _BoardParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _BoardParentData> {
  _BoardRenderBox({required double gap}) : _gap = gap;

  double _gap;
  double get gap => _gap;
  set gap(double value) {
    if (value == _gap) return;
    _gap = value;
    markNeedsLayout();
  }

  List<RenderBox> get cells => getChildrenAsList();

  double get totalGap => childCount <= 1 ? 0 : gap * (childCount - 1);

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _BoardParentData) child.parentData = _BoardParentData();
  }

  @override
  void paint(PaintingContext context, Offset offset) => defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

class RenderBoardRow extends _BoardRenderBox {
  RenderBoardRow({required List<int> flex, required super.gap}) : _flex = flex;

  List<int> _flex;
  List<int> get flex => _flex;
  set flex(List<int> value) {
    if (listEquals(value, _flex)) return;
    _flex = value;
    markNeedsLayout();
  }

  /// 칸마다 폭(비율이 칸 수와 다르면 같은 폭).
  List<double> _cellWidths(double width) {
    final count = childCount;
    if (count == 0) {
      return const [];
    }
    final weights = _flex.length == count ? _flex : List<int>.filled(count, 1);
    final total = weights.fold<int>(0, (sum, w) => sum + math.max(0, w));
    final room = math.max(0.0, width - totalGap);
    return [for (final w in weights) total == 0 ? room / count : room * math.max(0, w) / total];
  }

  @override
  double computeMinIntrinsicHeight(double width) {
    final widths = _cellWidths(width);
    final children = cells;
    return [for (var i = 0; i < children.length; i++) children[i].getMinIntrinsicHeight(widths[i])].fold(0.0, math.max);
  }

  @override
  double computeMaxIntrinsicHeight(double width) {
    final widths = _cellWidths(width);
    final children = cells;
    return [for (var i = 0; i < children.length; i++) children[i].getMaxIntrinsicHeight(widths[i])].fold(0.0, math.max);
  }

  @override
  double computeMinIntrinsicWidth(double height) => cells.fold(totalGap, (w, c) => w + c.getMinIntrinsicWidth(height));

  @override
  double computeMaxIntrinsicWidth(double height) => cells.fold(totalGap, (w, c) => w + c.getMaxIntrinsicWidth(height));

  @override
  void performLayout() {
    final width = constraints.maxWidth;
    final widths = _cellWidths(width);
    final children = cells;
    var height = constraints.minHeight;
    for (var i = 0; i < children.length; i++) {
      children[i].layout(BoxConstraints.tightFor(width: widths[i]), parentUsesSize: true);
      height = math.max(height, children[i].size.height);
    }
    var x = 0.0;
    for (var i = 0; i < children.length; i++) {
      // 높이는 최소 높이로만 준다(EqualHeightRow와 같은 이유: 늦게 로드된 웹 폰트로 글자 높이가 바뀌어도 다시 잰다).
      children[i].layout(
        BoxConstraints(minWidth: widths[i], maxWidth: widths[i], minHeight: height),
        parentUsesSize: true,
      );
      (children[i].parentData! as _BoardParentData).offset = Offset(x, 0);
      x += widths[i] + gap;
    }
    size = constraints.constrain(Size(width, height));
  }
}

class RenderBoardColumn extends _BoardRenderBox {
  RenderBoardColumn({required super.gap, required int stretchIndex}) : _stretchIndex = stretchIndex;

  int _stretchIndex;
  int get stretchIndex => _stretchIndex;
  set stretchIndex(int value) {
    if (value == _stretchIndex) return;
    _stretchIndex = value;
    markNeedsLayout();
  }

  @override
  double computeMinIntrinsicHeight(double width) => cells.fold(totalGap, (h, c) => h + c.getMinIntrinsicHeight(width));

  @override
  double computeMaxIntrinsicHeight(double width) => cells.fold(totalGap, (h, c) => h + c.getMaxIntrinsicHeight(width));

  @override
  double computeMinIntrinsicWidth(double height) =>
      cells.fold(0, (w, c) => math.max(w, c.getMinIntrinsicWidth(height)));

  @override
  double computeMaxIntrinsicWidth(double height) =>
      cells.fold(0, (w, c) => math.max(w, c.getMaxIntrinsicWidth(height)));

  @override
  void performLayout() {
    final width = constraints.maxWidth;
    final children = cells;
    var height = totalGap;
    for (final child in children) {
      child.layout(BoxConstraints.tightFor(width: width), parentUsesSize: true);
      height += child.size.height;
    }
    final extra = constraints.minHeight - height;
    if (children.isNotEmpty && extra > 0) {
      final target = children[_stretchIndex >= 0 && _stretchIndex < children.length ? _stretchIndex : children.length - 1];
      target.layout(BoxConstraints.tightFor(width: width, height: target.size.height + extra), parentUsesSize: true);
      height += extra;
    }
    var y = 0.0;
    for (final child in children) {
      (child.parentData! as _BoardParentData).offset = Offset(0, y);
      y += child.size.height + gap;
    }
    size = constraints.constrain(Size(width, height));
  }
}
