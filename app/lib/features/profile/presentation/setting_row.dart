import 'package:flutter/material.dart';

import '../../../core/theme/app_palette.dart';

/// 이 폭보다 좁으면 이름표를 값 위에 쌓는다(휴대폰 폭에서 넘침 방지).
const double _stackBelowWidth = 520;
const double _labelWidth = 150;
const double _rowPadding = 10;

/// 설정 화면의 한 줄: 왼쪽 이름표 + 오른쪽 값·컨트롤. 좁으면 위아래로 쌓는다(반응형, docs/14 §8).
class SettingRow extends StatelessWidget {
  const SettingRow({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final labelText = Text(label, style: TextStyle(color: context.palette.textMuted));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: _rowPadding),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < _stackBelowWidth) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [labelText, const SizedBox(height: 6), child],
            );
          }
          return Row(
            children: [
              SizedBox(width: _labelWidth, child: labelText),
              Expanded(child: Align(alignment: Alignment.centerLeft, child: child)),
            ],
          );
        },
      ),
    );
  }
}

/// 값 글자 + 오른쪽 "변경" 버튼(이메일·닉네임 줄).
class ValueWithChange extends StatelessWidget {
  const ValueWithChange({super.key, required this.value, required this.onChange, required this.buttonKey});

  final String value;
  final VoidCallback onChange;
  final Key buttonKey;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Flexible(
          child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        const SizedBox(width: 8),
        TextButton(key: buttonKey, onPressed: onChange, child: const Text('변경')),
      ],
    );
  }
}

/// 가로로 넘치면 스크롤되는 선택 버튼 묶음(좁은 화면에서 잘리지 않게).
class ChoiceSegments<T extends Enum> extends StatelessWidget {
  const ChoiceSegments({
    super.key,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onSelected,
  });

  final List<T> values;
  final T selected;
  final String Function(T) labelOf;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SegmentedButton<T>(
        showSelectedIcon: false,
        segments: [
          for (final value in values)
            ButtonSegment<T>(
              value: value,
              label: Text(labelOf(value), key: ValueKey('choice-${value.name}')),
            ),
        ],
        selected: {selected},
        onSelectionChanged: (selection) => onSelected(selection.first),
      ),
    );
  }
}
