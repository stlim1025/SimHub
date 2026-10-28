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
  static const Color teamAlpine = Color(0xFFFF87BC);
  static const Color teamWilliams = Color(0xFF64C4FF);
  static const Color teamRacingBulls = Color(0xFF6692FF);
  static const Color teamSauber = Color(0xFF52E252);
  static const Color teamAudi = Color(0xFFBB0A30);
  static const Color teamCadillac = Color(0xFF1F1F1F);
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

  /// 고스트 재생 화면(두 테마 공통, 늘 어두운 서킷): 바깥 잔디·런오프, 아스팔트, 흰 가장자리 선.
  static const Color replayGrass = Color(0xFF16231B);
  static const Color replayAsphalt = Color(0xFF3A3D45);
  static const Color replayRoadEdge = Color(0xFFF3F4F6);

  /// 고스트 재생 차 그림의 바퀴·조종석·서스펜션(팀 색 몸체 위에서 또렷하게).
  static const Color replayCarDark = Color(0xFF0B0D12);

  /// 고스트 재생 계기판 글자.
  static const Color replayHudText = Color(0xFFF3F4F6);
  static const Color replayHudMuted = Color(0xFFB4BAC6);

  /// 고스트 재생 서킷의 코너 바깥 그래블(자갈)·연석 빨강(흰 칸은 [replayRoadEdge]).
  static const Color replayGravel = Color(0xFF8C7B5A);
  static const Color replayKerbRed = Color(0xFFD62828);

  /// 고스트 재생 HUD의 ERS 배터리 잔량 막대(노랑)·사용 출력 막대(파랑, 충전은 [replayThrottle] 초록).
  static const Color replayBattery = Color(0xFFFACC15);
  static const Color replayDeploy = Color(0xFF60A5FA);


  /// 구간 비교 색(중계 화면처럼 앞서면 초록, 뒤지면 노랑)·스로틀(초록)·브레이크(빨강).
  static const Color replayFaster = Color(0xFF2BD66B);
  static const Color replaySlower = Color(0xFFFFD12E);
  static const Color replayThrottle = Color(0xFF2BD66B);
  static const Color replayBrake = Color(0xFFFF3B3B);

  /// 텔레메트리 그래프의 재생 위치 막대(노랑 — 이 랩 강조색·비교 랩 청록 선과 헷갈리지 않게, 두 테마 공통).
  static const Color telemetryPlayhead = Color(0xFFF5B800);

  /// 고스트 재생 3D 시점: 하늘(위·지평선 — 먼 곳 안개 색), 잔디, 낮은 방호벽.
  static const Color replaySkyTop = Color(0xFF3D6FA8);
  static const Color replaySkyHorizon = Color(0xFFB9CCDD);
  static const Color replayGrass3d = Color(0xFF3F7A3A);
  static const Color replayWall = Color(0xFFC9CDD4);

  /// 고스트 재생 3D 시가지 서킷의 도로 밖 바닥(보도·건물 바닥 회색).
  static const Color replayStreetGround = Color(0xFF55595F);

  /// 고스트 재생 3D 차: 타이어 고무·휠·헬멧(타이어 옆 띠는 컴파운드 색).
  static const Color replayCarTyre = Color(0xFF17181B);
  static const Color replayCarRim = Color(0xFF3B3F47);
  static const Color replayCarHelmet = Color(0xFFE9EBEF);

  /// 고스트 재생 계기판: 판, 빈 고리·막대, 경과 시간(초록), 속도 고리(파랑), 스로틀 고리(초록). 브레이크는 [replayBrake].
  static const Color replayDashPanel = Color(0xFF1F232B);
  static const Color replayDashTrack = Color(0xFF363B47);
  static const Color replayDashTime = Color(0xFF3DDC5A);
  static const Color replayDashSpeed = Color(0xFF2563EB);
  static const Color replayDashThrottle = Color(0xFF2DBE4E);

  /// 하이라이트 깃발 배너: 세이프티카·버추얼(노랑, 글자 어둡게)·적기(빨강).
  static const Color replayFlagYellow = Color(0xFFFACC15);
  static const Color replayFlagYellowText = Color(0xFF1A1A1A);
  static const Color replayFlagRed = Color(0xFFDC2626);

  /// 하이라이트 중계 그래픽: 판(검정에 가까운 남색)·줄 사이 판·포인트 빨강.
  static const Color replayBroadcastPanel = Color(0xFF15151E);
  static const Color replayBroadcastRow = Color(0xFF1E1E29);
  static const Color replayBroadcastRed = Color(0xFFE10600);
}
