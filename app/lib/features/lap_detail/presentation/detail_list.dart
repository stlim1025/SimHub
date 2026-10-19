import 'package:flutter/material.dart';

import '../../../core/theme/app_palette.dart';

const double _rowVerticalPadding = 11;
const double _labelValueGap = 12;

/// 상세 목록의 한 줄: 왼쪽 라벨 + 오른쪽 값(글자 또는 위젯).
class DetailItem {
  const DetailItem(this.label, {this.text, this.value}) : assert((text == null) != (value == null), 'text와 value 중 하나만 준다.');

  final String label;
  final String? text;
  final Widget? value;
}

/// F1Laps 모양의 키-값 목록(Lap Details·Damage·Conditions 등, docs/15 §2.3): 줄 사이 얇은 구분선.
/// 각 줄은 `detail-row-{라벨}` 키를 갖는다(테스트·찾기용).
class DetailList extends StatelessWidget {
  const DetailList({super.key, required this.items});

  final List<DetailItem> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const Divider(height: 1),
          _DetailRow(key: ValueKey('detail-row-${items[i].label}'), item: items[i]),
        ],
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({super.key, required this.item});

  final DetailItem item;

  @override
  Widget build(BuildContext context) {
    final text = item.text;
    final value = item.value ??
        Text(
          text!,
          textAlign: TextAlign.end,
          style: const TextStyle(fontWeight: FontWeight.w600, fontFeatures: [FontFeature.tabularFigures()]),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: _rowVerticalPadding),
      child: Row(
        children: [
          Expanded(
            // F1Laps처럼 이름표도 밝게·굵게(흐린 회색 이름표는 화면이 지저분해 보인다).
            child: Text(item.label, style: TextStyle(color: context.palette.textPrimary, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: _labelValueGap),
          Flexible(child: Align(alignment: Alignment.centerRight, child: value)),
        ],
      ),
    );
  }
}
