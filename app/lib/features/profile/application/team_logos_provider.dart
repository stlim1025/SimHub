import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';

/// 팀 로고 URL 경로(D-48). 서버가 자기 PC 폴더(`TeamLogos:Directory`)의 `{코드}.png`를 내보낸다.
/// 로고는 상표라 저장소·앱 번들에 넣지 않는다.
const String kTeamLogoPath = '/team-logos/';
const String _logoExtension = '.png';

/// 팀 코드 → 로고 URL. null이면 로고를 요청하지 않는다(팀 색 원 + 코드).
typedef TeamLogoUrlBuilder = String? Function(String teamCode);

/// 서버 [apiBaseUrl]의 로고 URL(`{apiBaseUrl}/team-logos/FER.png`, 코드는 대문자). 순수 함수.
String teamLogoUrlFor(String apiBaseUrl, String teamCode) =>
    '$apiBaseUrl$kTeamLogoPath${Uri.encodeComponent(teamCode.toUpperCase())}$_logoExtension';

/// 로고 URL을 만드는 함수. 기본은 API 서버([AppConfig.apiBaseUrl]), 테스트에서 바꿔 끼운다(네트워크 이미지 없이 코드 원으로).
final teamLogoUrlProvider = Provider<TeamLogoUrlBuilder>(
  (ref) => (teamCode) => teamLogoUrlFor(AppConfig.apiBaseUrl, teamCode),
);
