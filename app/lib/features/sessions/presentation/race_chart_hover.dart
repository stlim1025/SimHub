import 'package:flutter/material.dart';

import '../../../core/theme/app_palette.dart';
import 'session_widgets.dart';

// Race Review 그래프(순위·랩별 막대·랩별 페이스)가 같이 쓰는 마우스·터치 툴팁.

/// 그래프 툴팁: 선과의 간격, 최대 폭, 안쪽 여백, 모서리, 글자 크기, 세로선 두께.
const double _tooltipGap = 8;
const double _tooltipMaxWidth = 240;
const EdgeInsets _tooltipPadding = EdgeInsets.symmetric(horizontal: 8, vertical: 6);
const double _tooltipRadius = 6;
const double _tooltipFontSize = 12;
const double _hoverLineWidth = 1;

/// 그래프 위 마우스·터치 툴팁: 포인터에서 가장 가까운 점([xOf]로 가로 자리)에 세로선과 설명([tooltipOf])을 띄운다.
/// 설명은 그래프 왼쪽 절반이면 선 오른쪽, 오른쪽 절반이면 선 왼쪽에 둬 가장자리에서 잘리지 않게.
class RaceChartHover extends StatefulWidget {
  const RaceChartHover({super.key, required this.count, required this.xOf, required this.tooltipOf, required this.child});

  final int count;
  final double Function(int index, double width) xOf;
  final String Function(int index) tooltipOf;
  final Widget child;

  @override
  State<RaceChartHover> createState() => _RaceChartHoverState();
}

class _RaceChartHoverState extends State<RaceChartHover> {
  int? _index;

  void _pick(double dx, double width) {
    if (widget.count == 0) {
      return;
    }
    var nearest = 0;
    for (var i = 1; i < widget.count; i++) {
      if ((widget.xOf(i, width) - dx).abs() < (widget.xOf(nearest, width) - dx).abs()) {
        nearest = i;
      }
    }
    if (nearest != _index) {
      setState(() => _index = nearest);
    }
  }

  void _clear() {
    if (_index != null) {
      setState(() => _index = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final index = _index;
        final x = index == null ? 0.0 : widget.xOf(index, width);
        final left = x < width / 2;
        return MouseRegion(
          onHover: (event) => _pick(event.localPosition.dx, width),
          onExit: (_) => _clear(),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) => _pick(details.localPosition.dx, width),
            onHorizontalDragUpdate: (details) => _pick(details.localPosition.dx, width),
            onHorizontalDragEnd: (_) => _clear(),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(child: widget.child),
                if (index != null) ...[
                  Positioned(
                    left: x - _hoverLineWidth / 2,
                    top: 0,
                    bottom: 0,
                    width: _hoverLineWidth,
                    child: ColoredBox(color: palette.textMuted),
                  ),
                  Positioned(
                    top: 0,
                    left: left ? x + _tooltipGap : null,
                    right: left ? null : width - x + _tooltipGap,
                    child: Container(
                      key: const ValueKey('race-review-tooltip'),
                      constraints: const BoxConstraints(maxWidth: _tooltipMaxWidth),
                      padding: _tooltipPadding,
                      decoration: BoxDecoration(
                        color: palette.surface,
                        border: Border.all(color: palette.border),
                        borderRadius: BorderRadius.circular(_tooltipRadius),
                      ),
                      child: Text(
                        widget.tooltipOf(index),
                        style: kTabularStyle.copyWith(fontSize: _tooltipFontSize, color: palette.textPrimary),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
