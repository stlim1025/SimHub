import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_palette.dart';
const double _circleSize = 18;
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

/// 컴파운드 원(색 + 한 글자, 세션 결과·랩 상세 공용). [compound]는 `Soft`·`Medium`·`Hard`·`Intermediate`·`Wet`, 모르면 회색 `?`.
class TyreCompoundCircle extends StatelessWidget {
  const TyreCompoundCircle({super.key, required this.compound, required this.tooltip, this.size = _circleSize});

  final String compound;
  final String tooltip;
  final double size;

  /// 원 지름 대비 글자 크기 비율.
  static const double _letterScale = _letterSize / _circleSize;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: tyreColorOf(compound),
          border: Border.all(color: context.palette.border),
        ),
        child: Text(
          _compoundLetter(compound),
          style: TextStyle(
            fontSize: size * _letterScale,
            fontWeight: FontWeight.bold,
            color: AppColors.background,
          ),
        ),
      ),
    );
  }
}
