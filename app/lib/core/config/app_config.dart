/// 앱 전역 설정. 시크릿은 담지 않는다(헌장 Security). baseUrl은 빌드시 `--dart-define`으로 주입한다.
/// 기본값은 개발 편의를 위한 값이며, 릴리스는 반드시 HTTPS 오리진을 주입한다.
class AppConfig {
  const AppConfig._();

  /// REST API 오리진. 예: `--dart-define=API_BASE_URL=https://api.simcenter.example`.
  /// 기본값은 개발 HTTPS 포트(launchSettings). 웹/에뮬레이터 dev는 http 오리진을 주입해 사용한다.
  static const String apiBaseUrl =
      String.fromEnvironment('API_BASE_URL', defaultValue: 'https://localhost:7251');

  /// REST 경로 접두사(04-api-design).
  static const String apiPrefix = '/api/v1';

  /// RankingHub 오리진(미주입 시 apiBaseUrl 기준).
  static const String _hubOverride = String.fromEnvironment('RANKING_HUB_URL');

  static String get rankingHubUrl =>
      _hubOverride.isNotEmpty ? _hubOverride : '$apiBaseUrl/hubs/ranking';

  /// 기본 게임 코드(MVP 단일 게임, D-14).
  static const String defaultGameCode = 'F1_25';
}
