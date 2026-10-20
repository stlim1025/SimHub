import 'package:flutter/painting.dart';

/// 앱 전체 색 토큰(docs/11 §7.1, 밝은 테마·팀 색은 docs/14 §7). 어두운 남색 배경 + 보라(인디고) 강조색.
/// 위젯은 색 리터럴을 직접 쓰지 않고 이 토큰만 참조한다. 배경·표면·테두리·글자처럼 테마마다 다른 색은
/// 위젯이 [AppPalette](`context.palette`)로 읽는다 — 아래 이름 없는 토큰은 어두운 테마 값, `light*`는 밝은 테마 값이다.
class AppColors {
  const AppColors._();

  static const Color background = Color(0xFF12141C);
  static const Color surface = Color(0xFF181B25);
  static const Color border = Color(0xFF262A36);
  static const Color accent = Color(0xFF6366F1);
  static const Color textPrimary = Color(0xFFE5E7EB);
  static const Color textMuted = Color(0xFF9CA3AF);

  /// 밝은 테마의 배경·표면·테두리·글자(docs/14 §7). 강조색은 두 테마가 같다.
  static const Color lightBackground = Color(0xFFF5F6FA);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightBorder = Color(0xFFE2E5EC);
  static const Color lightTextPrimary = Color(0xFF111827);
  static const Color lightTextMuted = Color(0xFF646B78);

  /// 밝은 표면 위 상태·시상대 글자색. 흰 표면 대비 약 4.5:1 이상(어두운 테마는 아래 `danger`·`success`·`podium*`을 그대로 쓴다).
  static const Color lightDanger = Color(0xFFB91C1C);
  static const Color lightSuccess = Color(0xFF15803D);
  static const Color lightPodiumGold = Color(0xFF8A6500);
  static const Color lightPodiumSilver = Color(0xFF5B6472);
  static const Color lightPodiumBronze = Color(0xFF8C4A12);

  /// 강조색 위에 올리는 글자색.
  static const Color onAccent = Color(0xFFFFFFFF);

  /// 정상·실시간 연결 표시.
  static const Color success = Color(0xFF22C55E);

  /// 초록(`success`) 버튼 위 글자색(설정 화면의 "변경 사항 저장").
  static const Color onSuccess = Color(0xFF052E16);

  /// 오류·무효 표시.
  static const Color danger = Color(0xFFF87171);

  /// 시상대 1·2·3위(docs/12 §8.5).
  static const Color podiumGold = Color(0xFFF5C542);
  static const Color podiumSilver = Color(0xFFC0C7D1);
  static const Color podiumBronze = Color(0xFFCD7F32);

  /// 결과·순위 표에서 내 행의 배경(`accent`를 약 14% 투명도로).
  static const Color playerRow = Color(0x246366F1);

  /// 세션 최고 랩. `accent` 인디고와 뚜렷이 구분되는 자홍색.
  static const Color fastestLap = Color(0xFFD946EF);

  /// 타이어 컴파운드(visualCompound).
  static const Color tyreSoft = Color(0xFFEF4444);
  static const Color tyreMedium = Color(0xFFFACC15);
  static const Color tyreHard = Color(0xFFF3F4F6);
  static const Color tyreIntermediate = Color(0xFF22C55E);
  static const Color tyreWet = Color(0xFF3B82F6);

  /// 프로필 사진 팀 원(docs/14 §4). 값은 백엔드 `TeamCatalog`(D-33)의 팀 색과 같다. 실제 팀 로고는 쓰지 않는다.
  static const Color teamMercedes = Color(0xFF27F4D2);
  static const Color teamFerrari = Color(0xFFE8002D);
  static const Color teamRedBull = Color(0xFF3671C6);
  static const Color teamMcLaren = Color(0xFFFF8000);
  static const Color teamAstonMartin = Color(0xFF229971);
  static const Color teamAlpine = Color(0xFF0093CC);
  static const Color teamWilliams = Color(0xFF64C4FF);
  static const Color teamRacingBulls = Color(0xFF6692FF);
  static const Color teamSauber = Color(0xFF52E252);
  static const Color teamHaas = Color(0xFFB6BABD);

  /// 밝은 팀 색 원 위의 코드 글자색(대비 확보용 진한 남색).
  static const Color onTeamLight = Color(0xFF111827);

  /// 촘촘한 표(F1Laps 배치, docs/15 §2)의 머리줄 배경 — 표면보다 살짝 어둡다.
  static const Color tableHeader = Color(0xFF14161F);
  static const Color lightTableHeader = Color(0xFFF1F2F6);

  /// 눌러서 여는 값(랩타임)의 글자. `accent` 인디고 계열로 표면 대비 4.5:1 이상(어두운 표면은 밝게, 흰 표면은 진하게).
  static const Color link = Color(0xFF818CF8);
  static const Color lightLink = Color(0xFF4F46E5);

  /// 표 행에 마우스를 올렸을 때의 배경(`accent` 약 8%).
  static const Color rowHover = Color(0x146366F1);

  /// 실시간으로 막 들어온 랩 행의 강조 시작색(`accent` 약 30%, D-50). 몇 초에 걸쳐 투명해진다.
  static const Color freshRow = Color(0x4D6366F1);

  /// 텔레메트리 비교 랩(내 최고 랩) 선 — 청록. 이 랩은 `accent`.
  static const Color comparisonLap = Color(0xFF2DD4BF);
  static const Color lightComparisonLap = Color(0xFF0D9488);

  /// 타이어 마모 단계(docs/15 §2.3: 25% 미만 · 50% 미만 · 75% 미만 · 그 이상). 차 그림의 바퀴·앞날개를 칠한다(두 테마 공통).
  static const Color wearLow = Color(0xFF22C55E);
  static const Color wearMedium = Color(0xFFFACC15);
  static const Color wearHigh = Color(0xFFF97316);
  static const Color wearCritical = Color(0xFFEF4444);

  /// 트랙 지도 섹터 색(F1Laps처럼 S1 빨강 · S2 파랑 · S3 노랑, 타이어 색과 같은 계열 — 두 테마 공통).
  static const Color trackSector1 = Color(0xFFEF4444);
  static const Color trackSector2 = Color(0xFF3B82F6);
  static const Color trackSector3 = Color(0xFFFACC15);

  /// 트랙 지도 바깥 테두리(굵은 어두운 선, 두 테마 공통).
  static const Color trackOutline = Color(0xFF0B0D12);

  /// 트랙 지도 위치 점: 검은 고리 + 흰 가운데(두 테마 공통).
  static const Color trackDotRing = Color(0xFF000000);
  static const Color trackDotCenter = Color(0xFFFFFFFF);
}
