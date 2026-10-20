import 'package:flutter/material.dart';

import '../theme/app_palette.dart';

const double _groupHeight = 32;
const double _groupRadius = 6;
const double _dividerWidth = 1;
const EdgeInsets _segmentPadding = EdgeInsets.symmetric(horizontal: 12);

/// 버튼 묶음의 선택지 하나.
typedef ButtonGroupOption<T> = ({T value, String label});

/// F1Laps 모양의 작은 테두리 버튼 묶음(예: `Recent | Fastest`, docs/15 §2.1). 하나만 고른다.
/// 고른 칸은 테두리 색 배경 + 진한 글자, 나머지는 흐린 글자. Material `SegmentedButton`보다 낮고 촘촘하다.
class ButtonGroup<T> extends StatelessWidget {
  const ButtonGroup({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.segmentKeyOf,
  });

  final List<ButtonGroupOption<T>> options;
  final T selected;
  final ValueChanged<T> onSelected;

  /// 칸 위젯 키(테스트·자동화용). 없으면 키를 붙이지 않는다.
  final Key Function(T value)? segmentKeyOf;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(_groupRadius),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_groupRadius),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < options.length; i++) ...[
              if (i > 0) Container(width: _dividerWidth, height: _groupHeight, color: palette.border),
              _Segment(
                key: segmentKeyOf?.call(options[i].value),
                label: options[i].label,
                selected: options[i].value == selected,
                onTap: () => onSelected(options[i].value),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({super.key, required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Semantics(
      button: true,
      selected: selected,
      excludeSemantics: true,
      onTap: onTap,
      label: label,
      child: Material(
        color: selected ? palette.border : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Container(
            height: _groupHeight,
            padding: _segmentPadding,
            alignment: Alignment.center,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: selected ? palette.textPrimary : palette.textMuted,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}
