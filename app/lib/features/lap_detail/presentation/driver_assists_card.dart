import 'package:flutter/material.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/section_card.dart';
import '../domain/lap_detail_display.dart';
import '../domain/lap_detail_models.dart';

const double _itemWidth = 136;
const double _itemSpacing = 12;
const double _dotSize = 8;
const double _dotGap = 6;
const double _labelGap = 4;

/// 서버 값 → 보이는 글자(docs/15 §10, F1Laps와 같은 말). 표에 없는 값은 그대로.
const Map<String, String> _valueLabels = {
  'CornersOnly': 'Corners',
  'ManualSuggested': 'Manual + hint',
  'Automatic': 'Auto',
};

/// 보조가 켜진 상태가 아닌 값(흐리게 그린다). 기어는 Manual이 "보조 없음"이다.
const Set<String> _inactiveValues = {'Off', 'Manual'};

/// 한 칸: 이름 + 값(null이면 그 칸을 그리지 않는다).
typedef _AssistItem = ({String label, String? value});

/// Driver Assists 띠(docs/15 §10, D-51): Traction Control · Anti-Lock Brakes · Steering Assist · Braking Assist · Gearbox · Racing Line.
/// 칸마다 작은 이름 + 점 + 값, 켜진 보조는 강조색으로 굵게. 모르는 칸은 빼고, 모두 모르면 호출자가 카드를 숨긴다.
class DriverAssistsCard extends StatelessWidget {
  const DriverAssistsCard({super.key, required this.assists});

  final LapAssists assists;

  @override
  Widget build(BuildContext context) {
    final List<_AssistItem> items = [
      (label: 'Traction Control', value: assists.tractionControl),
      (label: 'Anti-Lock Brakes', value: assists.antiLockBrakes),
      (label: 'Steering Assist', value: assists.steeringAssist),
      (label: 'Braking Assist', value: assists.brakingAssist),
      (label: 'Gearbox', value: assists.gearbox),
      (label: 'Racing Line', value: assists.racingLine),
    ];
    return SectionCard(
      title: 'Driver Assists',
      child: Wrap(
        spacing: _itemSpacing,
        runSpacing: _itemSpacing,
        children: [
          for (final item in items)
            if (item.value case final String value) _AssistTile(label: item.label, value: value),
        ],
      ),
    );
  }
}

class _AssistTile extends StatelessWidget {
  const _AssistTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final active = !_inactiveValues.contains(value);
    final color = active ? palette.link : palette.textMuted;
    final theme = Theme.of(context).textTheme;
    return SizedBox(
      key: ValueKey('assist-$label'),
      width: _itemWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.labelSmall?.copyWith(color: palette.textMuted)),
          const SizedBox(height: _labelGap),
          Row(
            children: [
              Container(
                width: _dotSize,
                height: _dotSize,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: _dotGap),
              Flexible(
                child: Text(
                  _valueLabels[value] ?? (value.isEmpty ? kDetailNoValueText : value),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: active ? color : null,
                    fontWeight: active ? FontWeight.bold : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
