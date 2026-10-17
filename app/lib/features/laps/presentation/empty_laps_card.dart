import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// 기록된 랩이 하나도 없을 때의 안내(트랙 목록·트랙별 랩 표 공통).
class EmptyLapsCard extends StatelessWidget {
  const EmptyLapsCard({super.key});

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Center(
          child: Text('아직 기록된 랩이 없습니다', style: TextStyle(color: AppColors.textMuted)),
        ),
      ),
    );
  }
}
