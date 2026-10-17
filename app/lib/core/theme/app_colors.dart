import 'package:flutter/painting.dart';

/// 앱 전체 색 토큰(docs/11 §7.1). 어두운 남색 배경 + 보라(인디고) 강조색.
/// 위젯은 색 리터럴을 직접 쓰지 않고 이 토큰만 참조한다.
class AppColors {
  const AppColors._();

  static const Color background = Color(0xFF12141C);
  static const Color surface = Color(0xFF181B25);
  static const Color border = Color(0xFF262A36);
  static const Color accent = Color(0xFF6366F1);
  static const Color textPrimary = Color(0xFFE5E7EB);
  static const Color textMuted = Color(0xFF9CA3AF);

  /// 강조색 위에 올리는 글자색.
  static const Color onAccent = Color(0xFFFFFFFF);

  /// 정상·실시간 연결 표시.
  static const Color success = Color(0xFF22C55E);

  /// 오류·무효 표시.
  static const Color danger = Color(0xFFF87171);
}
