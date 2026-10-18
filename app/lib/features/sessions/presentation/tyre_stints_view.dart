import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_palette.dart';
import '../domain/session_display.dart';
import '../domain/session_models.dart';

const double _circleSize = 18;
const double _circleGap = 4;
const double _letterSize = 10;

/// 컴파운드 이름 → 원 색(`AppColors` 토큰). 모르는 컴파운드는 `textMuted`.
Color tyreColorOf(String compound) => switch (compound) {
      'Soft' => AppColors.tyreSoft,
      'Medium' => AppColors.tyreMedium,
      'Hard' => AppColors.tyreHard,
      'Intermediate' => AppColors.tyreIntermediate,
      'Wet' => AppColors.tyreWet,
      _ => AppColors.textMuted,
    };

/// 색만으로 구분하지 않도록 원 안에 넣는 한 글자.
String _compoundLetter(String compound) => switch (compound) {
      'Soft' => 'S',
      'Medium' => 'M',
      'Hard' => 'H',
      'Intermediate' => 'I',
      'Wet' => 'W',
      _ => '?',
    };

/// `Medium (C3) · ~L7`: 보이는 컴파운드, 실제 컴파운드(있으면), 스틴트가 끝난 랩(있으면).
String _stintTooltip(TyreStintView stint) {
  final actual = stint.actualCompound;
  return '${stint.visualCompound}'
      '${actual == null ? '' : ' ($actual)'}'
      '${stint.endLap > 0 ? ' · ~L${stint.endLap}' : ''}';
}

/// 스틴트 순서대로 컴파운드 원을 나열한다. 스틴트가 없으면 `-`.
class TyreStintsView extends StatelessWidget {
  const TyreStintsView({super.key, required this.stints});

  final List<TyreStintView> stints;

  @override
  Widget build(BuildContext context) {
    if (stints.isEmpty) {
      return const Text(kNoValueText);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < stints.length; i++) ...[
          if (i > 0) const SizedBox(width: _circleGap),
          _TyreCircle(stint: stints[i]),
        ],
      ],
    );
  }
}

class _TyreCircle extends StatelessWidget {
  const _TyreCircle({required this.stint});

  final TyreStintView stint;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: _stintTooltip(stint),
      child: Container(
        width: _circleSize,
        height: _circleSize,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: tyreColorOf(stint.visualCompound),
          border: Border.all(color: context.palette.border),
        ),
        child: Text(
          _compoundLetter(stint.visualCompound),
          style: const TextStyle(
            fontSize: _letterSize,
            fontWeight: FontWeight.bold,
            color: AppColors.background,
          ),
        ),
      ),
    );
  }
}
