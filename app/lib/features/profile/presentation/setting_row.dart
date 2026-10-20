import 'package:flutter/material.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/button_group.dart';

/// 이 폭보다 좁으면 이름표를 값 위에 쌓는다(휴대폰 폭에서 넘침 방지).
const double _stackBelowWidth = 520;
const double _labelWidth = 180;
const double _rowPadding = 12;
const double _sectionTitleGap = 8;

/// 설정 화면의 구획: 카드 없이 제목 + 구분선으로 나뉜 줄들(웹 대시보드 배치, F1Laps 참고).
class SettingsSection extends StatelessWidget {
  const SettingsSection({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: _sectionTitleGap),
        child,
      ],
    );
  }
}

/// 설정 화면의 한 줄: 왼쪽 이름표 + 오른쪽 값·컨트롤, 아래 얇은 구분선. 좁으면 위아래로 쌓는다(반응형, docs/14 §8).
class SettingRow extends StatelessWidget {
  const SettingRow({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final labelText = Text(label, style: TextStyle(color: context.palette.textMuted, fontWeight: FontWeight.w600));
    return Container(
      padding: const EdgeInsets.symmetric(vertical: _rowPadding),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: context.palette.border))),
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

/// 값 글자 + 줄 오른쪽 끝의 "변경" 링크(이메일·닉네임 줄).
class ValueWithChange extends StatelessWidget {
  const ValueWithChange({super.key, required this.value, required this.onChange, required this.buttonKey});

  final String value;
  final VoidCallback onChange;
  final Key buttonKey;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
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
      child: ButtonGroup<T>(
        options: [for (final value in values) (value: value, label: labelOf(value))],
        selected: selected,
        onSelected: onSelected,
        segmentKeyOf: (value) => ValueKey('choice-${value.name}'),
      ),
    );
  }
}
