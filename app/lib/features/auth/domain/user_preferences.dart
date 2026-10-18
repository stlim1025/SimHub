/// 내 프로필 설정(docs/14 §3). 백엔드 `GET /me`의 설정 필드와 같다. 값은 enum 이름 문자열로 주고받는다.
library;

/// 입력 장치(저장만 한다 — 이후 Phase).
enum ControllerType {
  gamepad('Gamepad', 'Gamepad'),
  wheel('Wheel', 'Wheel');

  const ControllerType(this.wire, this.label);

  /// 서버 계약 값.
  final String wire;

  /// 화면 표시 이름.
  final String label;

  static ControllerType fromWire(String? value) => _fromWire(values, value, (e) => e.wire, UserPreferences.defaults.controller);
}

/// 플랫폼(저장만 한다 — 이후 Phase).
enum ConsolePlatform {
  pc('Pc', 'PC'),
  xbox('Xbox', 'Xbox'),
  playStation('PlayStation', 'PlayStation');

  const ConsolePlatform(this.wire, this.label);

  final String wire;
  final String label;

  static ConsolePlatform fromWire(String? value) => _fromWire(values, value, (e) => e.wire, UserPreferences.defaults.console);
}

/// 속도·거리 단위(저장만 한다 — 텔레메트리 화면에서 쓴다).
enum UnitSystem {
  metric('Metric', 'Metric (km/h)'),
  imperial('Imperial', 'Imperial (mph)');

  const UnitSystem(this.wire, this.label);

  final String wire;
  final String label;

  static UnitSystem fromWire(String? value) => _fromWire(values, value, (e) => e.wire, UserPreferences.defaults.units);
}

/// 화면 테마. 기본은 [dark](D-40). [system]을 고르면 기기 밝기 설정을 따른다.
enum ThemePreference {
  light('Light', 'Light'),
  dark('Dark', 'Dark'),
  system('System', 'System');

  const ThemePreference(this.wire, this.label);

  final String wire;
  final String label;

  static ThemePreference fromWire(String? value) => _fromWire(values, value, (e) => e.wire, UserPreferences.defaults.theme);
}

/// 서버 값 → enum. 모르는 값(서버가 먼저 새 값을 추가한 경우 등)은 기본값으로 받는다(대소문자 무시).
T _fromWire<T>(List<T> values, String? value, String Function(T) wireOf, T fallback) {
  if (value == null) {
    return fallback;
  }
  for (final candidate in values) {
    if (wireOf(candidate).toLowerCase() == value.toLowerCase()) {
      return candidate;
    }
  }
  return fallback;
}

/// 사용자 설정 묶음(불변). 저장된 값과 편집 중인 값을 [==]로 비교해 "바뀐 것이 있는지"를 판단한다.
class UserPreferences {
  const UserPreferences({
    required this.showOnLeaderboard,
    required this.avatarTeam,
    required this.preferredGame,
    required this.controller,
    required this.console,
    required this.units,
    required this.timeZoneId,
    required this.theme,
  });

  /// 새 사용자 기본값(백엔드 `UserProfileDefaults`와 같다). 테마는 Dark(D-40, 기존 어두운 화면 유지).
  static const defaults = UserPreferences(
    showOnLeaderboard: true,
    avatarTeam: null,
    preferredGame: 'F1_25',
    controller: ControllerType.wheel,
    console: ConsolePlatform.pc,
    units: UnitSystem.metric,
    timeZoneId: 'Asia/Seoul',
    theme: ThemePreference.dark,
  );

  /// false면 랭킹에 "익명 드라이버"로 보인다.
  final bool showOnLeaderboard;

  /// 프로필 사진 팀 코드. null이면 이름 첫 글자.
  final String? avatarTeam;
  final String preferredGame;
  final ControllerType controller;
  final ConsolePlatform console;
  final UnitSystem units;
  final String timeZoneId;
  final ThemePreference theme;

  /// `GET /me` 응답에서 읽는다. 빠진 필드(예: 로그인 응답의 사용자 요약)는 기본값.
  factory UserPreferences.fromJson(Map<String, dynamic> json) => UserPreferences(
        showOnLeaderboard: json['showOnLeaderboard'] as bool? ?? defaults.showOnLeaderboard,
        avatarTeam: json['avatarTeam'] as String?,
        preferredGame: json['preferredGame'] as String? ?? defaults.preferredGame,
        controller: ControllerType.fromWire(json['controller'] as String?),
        console: ConsolePlatform.fromWire(json['console'] as String?),
        units: UnitSystem.fromWire(json['units'] as String?),
        timeZoneId: json['timeZoneId'] as String? ?? defaults.timeZoneId,
        theme: ThemePreference.fromWire(json['theme'] as String?),
      );

  /// `PUT /me/profile` 본문의 설정 부분.
  Map<String, dynamic> toJson() => {
        'showOnLeaderboard': showOnLeaderboard,
        'avatarTeam': avatarTeam,
        'preferredGame': preferredGame,
        'controller': controller.wire,
        'console': console.wire,
        'units': units.wire,
        'timeZoneId': timeZoneId,
        'theme': theme.wire,
      };

  /// [clearAvatar]가 true면 사진을 지운다(null로 되돌리기는 `copyWith(avatarTeam: null)`로 표현할 수 없어서).
  UserPreferences copyWith({
    bool? showOnLeaderboard,
    String? avatarTeam,
    bool clearAvatar = false,
    String? preferredGame,
    ControllerType? controller,
    ConsolePlatform? console,
    UnitSystem? units,
    String? timeZoneId,
    ThemePreference? theme,
  }) =>
      UserPreferences(
        showOnLeaderboard: showOnLeaderboard ?? this.showOnLeaderboard,
        avatarTeam: clearAvatar ? null : (avatarTeam ?? this.avatarTeam),
        preferredGame: preferredGame ?? this.preferredGame,
        controller: controller ?? this.controller,
        console: console ?? this.console,
        units: units ?? this.units,
        timeZoneId: timeZoneId ?? this.timeZoneId,
        theme: theme ?? this.theme,
      );

  @override
  bool operator ==(Object other) =>
      other is UserPreferences &&
      other.showOnLeaderboard == showOnLeaderboard &&
      other.avatarTeam == avatarTeam &&
      other.preferredGame == preferredGame &&
      other.controller == controller &&
      other.console == console &&
      other.units == units &&
      other.timeZoneId == timeZoneId &&
      other.theme == theme;

  @override
  int get hashCode =>
      Object.hash(showOnLeaderboard, avatarTeam, preferredGame, controller, console, units, timeZoneId, theme);
}
