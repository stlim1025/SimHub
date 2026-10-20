import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

const double _brandMarkSize = 28;
const double _brandMarkRadius = 7;
const double _brandMarkIconSize = 20;

/// 웹 아이콘과 같은 모양의 로고: 인디고 둥근 사각형 + 흰 ≫(docs: app/web/favicon.svg). 사이드바·공유 화면 머리줄이 함께 쓴다.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _brandMarkSize,
      height: _brandMarkSize,
      decoration: BoxDecoration(
        color: AppColors.accent,
        borderRadius: BorderRadius.circular(_brandMarkRadius),
      ),
      child: const Icon(Icons.keyboard_double_arrow_right, color: AppColors.onAccent, size: _brandMarkIconSize),
    );
  }
}
