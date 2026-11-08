import 'package:flutter/widgets.dart';

import '../../../core/widgets/button_group.dart';
import '../domain/setup_models.dart';

// 셋업 모음 목록 화면(`/setups`)은 Tracks에 합쳤다(B안 개편) — 트랙 목록이 Dry | Wet과 트랙별 셋업 수를 보이고,
// 트랙 화면의 셋업 탭이 상위 셋업 표를 보인다. 여기에는 두 화면이 함께 쓰는 조건 선택지만 남는다.

/// Dry | Wet 선택지.
const List<ButtonGroupOption<String>> kSetupConditionOptions = [
  (value: kSetupConditionDry, label: kSetupConditionDry),
  (value: kSetupConditionWet, label: kSetupConditionWet),
];

/// Dry | Wet 버튼 묶음 칸 키(`setup-condition-Dry` 등).
Key setupConditionKey(String condition) => ValueKey('setup-condition-$condition');
