import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// 같은 폭·같은 높이 칸의 줄(docs/15 §2.3·§11.3 카드 격자).
/// 칸을 한 번 자연 높이로 배치해 가장 높은 값을 찾고, 모든 칸을 그 높이로 다시 배치한다.
/// `IntrinsicHeight`와 달리 카드 안의 `LayoutBuilder`(표·그래프)와 함께 써도 된다.
class EqualHeightRow extends MultiChildRenderObjectWidget {
  const EqualHeightRow({super.key, required super.children, required this.gap});

  /// 칸 사이 가로 간격(논리 px).
  final double gap;

  @override
  RenderEqualHeightRow createRenderObject(BuildContext context) => RenderEqualHeightRow(gap: gap);

  @override
  void updateRenderObject(BuildContext context, RenderEqualHeightRow renderObject) => renderObject.gap = gap;
}

/// 카드를 [gap] 간격으로 위에서부터 쌓는 열. 받은 최소 높이가 내용보다 크면 마지막 카드를 늘려 아래 끝을 맞춘다
/// ([EqualHeightRow] 칸 안에서 두 열의 바닥을 맞출 때).
class FillColumn extends MultiChildRenderObjectWidget {
  const FillColumn({super.key, required super.children, required this.gap});

  /// 카드 사이 세로 간격(논리 px).
  final double gap;

  @override
  RenderFillColumn createRenderObject(BuildContext context) => RenderFillColumn(gap: gap);

  @override
  void updateRenderObject(BuildContext context, RenderFillColumn renderObject) => renderObject.gap = gap;
}

class _CellParentData extends ContainerBoxParentData<RenderBox> {}

/// 두 렌더 상자의 공통 부분(자식 목록·그리기·터치 판정·간격).
abstract class _CellsRenderBox extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _CellParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _CellParentData> {
  _CellsRenderBox({required double gap}) : _gap = gap;

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
    if (child.parentData is! _CellParentData) child.parentData = _CellParentData();
  }

  @override
  void paint(PaintingContext context, Offset offset) => defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

class RenderEqualHeightRow extends _CellsRenderBox {
  RenderEqualHeightRow({required super.gap});

  double _cellWidth(double width) => childCount == 0 ? 0 : math.max(0, (width - totalGap) / childCount);

  @override
  double computeMinIntrinsicHeight(double width) =>
      cells.fold(0, (h, c) => math.max(h, c.getMinIntrinsicHeight(_cellWidth(width))));

  @override
  double computeMaxIntrinsicHeight(double width) =>
      cells.fold(0, (h, c) => math.max(h, c.getMaxIntrinsicHeight(_cellWidth(width))));

  @override
  double computeMinIntrinsicWidth(double height) => cells.fold(totalGap, (w, c) => w + c.getMinIntrinsicWidth(height));

  @override
  double computeMaxIntrinsicWidth(double height) => cells.fold(totalGap, (w, c) => w + c.getMaxIntrinsicWidth(height));

  @override
  void performLayout() {
    final width = constraints.maxWidth;
    final cellWidth = _cellWidth(width);
    final children = cells;
    var height = constraints.minHeight;
    for (final child in children) {
      child.layout(BoxConstraints.tightFor(width: cellWidth), parentUsesSize: true);
      height = math.max(height, child.size.height);
    }
    var x = 0.0;
    for (final child in children) {
      child.layout(BoxConstraints.tightFor(width: cellWidth, height: height), parentUsesSize: true);
      (child.parentData! as _CellParentData).offset = Offset(x, 0);
      x += cellWidth + gap;
    }
    size = constraints.constrain(Size(width, height));
  }
}

class RenderFillColumn extends _CellsRenderBox {
  RenderFillColumn({required super.gap});

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
      final last = children.last;
      last.layout(BoxConstraints.tightFor(width: width, height: last.size.height + extra), parentUsesSize: true);
      height += extra;
    }
    var y = 0.0;
    for (final child in children) {
      (child.parentData! as _CellParentData).offset = Offset(0, y);
      y += child.size.height + gap;
    }
    size = constraints.constrain(Size(width, height));
  }
}
