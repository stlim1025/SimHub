import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_palette.dart';

const double _labelValueGap = 2;
const TextStyle _valueStyle = TextStyle(
  fontWeight: FontWeight.w600,
  fontFeatures: [FontFeature.tabularFigures()],
);

/// 링크 모양의 값(강조색 + 밑줄).
const TextStyle _linkStyle = TextStyle(
  fontWeight: FontWeight.w600,
  fontFeatures: [FontFeature.tabularFigures()],
  color: AppColors.accent,
  decoration: TextDecoration.underline,
  decorationColor: AppColors.accent,
);

/// 작은 회색 라벨 아래에 굵은 값을 놓는 요약 항목(트랙 카드·세션/시즌 헤더 공통).
/// [onTap]을 주면 값이 링크처럼 보이고 눌린다.
class Stat extends StatelessWidget {
  const Stat({super.key, required this.label, required this.value, this.onTap});

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final valueText = Text(value, style: onTap == null ? _valueStyle : _linkStyle);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.palette.textMuted),
        ),
        const SizedBox(height: _labelValueGap),
        if (onTap == null) valueText else InkWell(onTap: onTap, child: valueText),
      ],
    );
  }
}
