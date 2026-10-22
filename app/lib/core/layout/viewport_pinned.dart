import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// 고정 자식과 보이는 영역(뷰포트) 가장자리 사이 기본 여백(논리 px).
const double kViewportPinnedMargin = 16;

/// 고정 자식을 뷰포트의 어느 쪽 가장자리에 붙일지.
enum ViewportPinEdge {
  /// 뷰포트 위쪽 + 여백.
  top,

  /// 뷰포트 아래쪽 − 여백.
  bottom,
}

/// 가장 가까운 조상 스크롤 영역이 스크롤되어도 [pinned]를 보이는 영역 안에 붙잡아 두는 배치.
/// [pinned]는 이 위젯의 세로 범위 `[0, 높이 − pinned 높이]` 안에서만 움직인다(부모 밖으로 나가지 않음).
///
/// - [asideWidth]가 있으면 **옆 칸**: [main]은 `폭 − asideWidth − gap`, [pinned]는 오른쪽 [asideWidth] 칸.
///   높이는 둘 중 큰 쪽.
/// - [asideWidth]가 null이면 **떠 있는 자식**: [main]이 전체 폭·높이를 쓰고 [pinned]는 오른쪽 끝([margin] 안쪽)에 겹쳐 그린다.
///   터치·마우스는 [pinned] 위에서만 가로채고 나머지는 [main]으로 간다.
///
/// 위치는 그릴 때마다 이 상자의 뷰포트 안 좌표로 다시 계산한다(`IntrinsicHeight`를 쓰지 않으므로 안쪽 `LayoutBuilder`와 함께 써도 된다).
class ViewportPinned extends StatelessWidget {
  const ViewportPinned({
    super.key,
    required this.main,
    required this.pinned,
    this.asideWidth,
    this.gap = 0,
    this.edge = ViewportPinEdge.top,
    this.margin = kViewportPinnedMargin,
  });

  final Widget main;
  final Widget pinned;

  /// 옆 칸 폭. null이면 [pinned]를 [main] 위에 띄운다.
  final double? asideWidth;

  /// 옆 칸일 때 [main]과의 가로 간격.
  final double gap;
  final ViewportPinEdge edge;

  /// 뷰포트 가장자리(와 떠 있을 때 오른쪽 끝)와의 여백.
  final double margin;

  @override
  Widget build(BuildContext context) {
    return _ViewportPinnedLayout(
      position: Scrollable.maybeOf(context)?.position,
      asideWidth: asideWidth,
      gap: gap,
      edge: edge,
      margin: margin,
      children: [main, pinned],
    );
  }
}

class _ViewportPinnedLayout extends MultiChildRenderObjectWidget {
  const _ViewportPinnedLayout({
    required this.position,
    required this.asideWidth,
    required this.gap,
    required this.edge,
    required this.margin,
    required super.children,
  });

  final ScrollPosition? position;
  final double? asideWidth;
  final double gap;
  final ViewportPinEdge edge;
  final double margin;

  @override
  RenderViewportPinned createRenderObject(BuildContext context) => RenderViewportPinned(
        position: position,
        asideWidth: asideWidth,
        gap: gap,
        edge: edge,
        margin: margin,
      );

  @override
  void updateRenderObject(BuildContext context, RenderViewportPinned renderObject) {
    renderObject
      ..position = position
      ..asideWidth = asideWidth
      ..gap = gap
      ..edge = edge
      ..margin = margin;
  }
}

class _PinnedParentData extends ContainerBoxParentData<RenderBox> {}

/// [ViewportPinned]의 렌더 상자. 자식 0 = main, 자식 1 = pinned.
/// 스크롤 위치가 바뀌면 다시 그리고(배치는 그대로), 그릴 때 pinned의 세로 위치를 정한다.
class RenderViewportPinned extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _PinnedParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _PinnedParentData> {
  RenderViewportPinned({
    required ScrollPosition? position,
    required double? asideWidth,
    required double gap,
    required ViewportPinEdge edge,
    required double margin,
  })  : _position = position,
        _asideWidth = asideWidth,
        _gap = gap,
        _edge = edge,
        _margin = margin;

  ScrollPosition? _position;
  set position(ScrollPosition? value) {
    if (identical(value, _position)) return;
    if (attached) _position?.removeListener(markNeedsPaint);
    _position = value;
    if (attached) _position?.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  double? _asideWidth;
  set asideWidth(double? value) {
    if (value == _asideWidth) return;
    _asideWidth = value;
    markNeedsLayout();
  }

  double _gap;
  set gap(double value) {
    if (value == _gap) return;
    _gap = value;
    markNeedsLayout();
  }

  ViewportPinEdge _edge;
  set edge(ViewportPinEdge value) {
    if (value == _edge) return;
    _edge = value;
    markNeedsPaint();
  }

  double _margin;
  set margin(double value) {
    if (value == _margin) return;
    _margin = value;
    markNeedsLayout();
  }

  /// 마지막으로 그린 pinned의 위치(터치 판정에 같은 값을 쓴다).
  Offset _pinnedOffset = Offset.zero;

  RenderBox get _main => firstChild!;
  RenderBox get _pinned => lastChild!;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _position?.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _position?.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _PinnedParentData) child.parentData = _PinnedParentData();
  }

  @override
  void performLayout() {
    final width = constraints.maxWidth;
    final aside = _asideWidth;
    if (aside != null) {
      final mainWidth = math.max(0.0, width - aside - _gap);
      _main.layout(BoxConstraints.tightFor(width: mainWidth), parentUsesSize: true);
      _pinned.layout(BoxConstraints.tightFor(width: math.min(aside, width)), parentUsesSize: true);
      size = constraints.constrain(Size(width, math.max(_main.size.height, _pinned.size.height)));
    } else {
      _main.layout(BoxConstraints.tightFor(width: width), parentUsesSize: true);
      _pinned.layout(BoxConstraints(maxWidth: math.max(0.0, width - _margin)), parentUsesSize: true);
      size = constraints.constrain(Size(width, _main.size.height));
    }
    (_main.parentData! as _PinnedParentData).offset = Offset.zero;
  }

  /// pinned의 세로 위치: 뷰포트 가장자리에 맞춘 값을 `[0, 높이 − pinned 높이]`로 자른다.
  /// 뷰포트가 없으면(스크롤 영역 밖) 위쪽 고정은 0, 아래쪽 고정은 상자 바닥.
  double _pinnedTop() {
    final maxTop = math.max(0.0, size.height - _pinned.size.height);
    final viewport = RenderAbstractViewport.maybeOf(this);
    if (viewport is! RenderBox) {
      return _edge == ViewportPinEdge.top ? 0 : maxTop;
    }
    final viewportHeight = (viewport as RenderBox).size.height;
    final topInViewport = localToGlobal(Offset.zero, ancestor: viewport).dy;
    final desired = switch (_edge) {
      ViewportPinEdge.top => _margin - topInViewport,
      ViewportPinEdge.bottom => viewportHeight - _margin - _pinned.size.height - topInViewport,
    };
    return desired.clamp(0.0, maxTop);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    context.paintChild(_main, offset);
    final left = _asideWidth != null
        ? size.width - _pinned.size.width
        : math.max(0.0, size.width - _margin - _pinned.size.width);
    _pinnedOffset = Offset(left, _pinnedTop());
    (_pinned.parentData! as _PinnedParentData).offset = _pinnedOffset;
    context.paintChild(_pinned, offset + _pinnedOffset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final hitPinned = result.addWithPaintOffset(
      offset: _pinnedOffset,
      position: position,
      hitTest: (result, transformed) => _pinned.hitTest(result, position: transformed),
    );
    if (hitPinned) return true;
    return _main.hitTest(result, position: position);
  }
}
