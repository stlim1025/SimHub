import 'package:flutter/material.dart';

import '../../../core/theme/app_palette.dart';

/// 기록된 랩이 하나도 없을 때의 기본 안내.
const String kNoLapsText = '아직 기록된 랩이 없습니다';

/// 랩 목록이 비었을 때의 안내(Laps 화면 공통). 문구는 상황(예: 유효 랩만)에 맞게 바꿀 수 있다.
class EmptyLapsCard extends StatelessWidget {
  const EmptyLapsCard({super.key, this.message = kNoLapsText});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Text(message, textAlign: TextAlign.center, style: TextStyle(color: context.palette.textMuted)),
        ),
      ),
    );
  }
}
