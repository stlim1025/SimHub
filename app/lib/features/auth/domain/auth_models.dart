import 'user_preferences.dart';

/// 로그인 사용자(04 §3.2~3.3). 백엔드 camelCase 계약과 필드 일치.
/// `GET /me`에서 읽으면 [email]·[preferences]가 채워지고, 로그인 응답의 요약에서 읽으면 email은 null·설정은 기본값이다.
class AppUser {
  const AppUser({
    required this.userId,
    required this.displayName,
    this.email,
    this.preferences = UserPreferences.defaults,
  });

  final String userId;
  final String displayName;
  final String? email;

  /// 프로필 설정(공개 여부·프로필 사진·게임 환경·타임존·테마, docs/14 §3).
  final UserPreferences preferences;

  /// `GET /me`에서 읽은 전체 프로필인지. 로그인 응답의 요약(이메일 없음)이면 false — [preferences]는 실제 값이 아니라 기본값이라
  /// 그대로 저장하면 사용자의 설정(예: 랭킹 이름 비공개)을 덮어쓴다. 설정 화면은 false면 프로필을 다시 읽고, 읽기 전에는 저장을 막는다.
  bool get isProfileLoaded => email != null;

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        userId: json['userId'] as String,
        displayName: json['displayName'] as String,
        email: json['email'] as String?,
        preferences: UserPreferences.fromJson(json),
      );

  AppUser copyWith({String? displayName, String? email, UserPreferences? preferences}) => AppUser(
        userId: userId,
        displayName: displayName ?? this.displayName,
        email: email ?? this.email,
        preferences: preferences ?? this.preferences,
      );
}

/// 로그인 응답(04 §3.2).
class LoginResult {
  const LoginResult({required this.accessToken, required this.expiresAt, required this.user});

  final String accessToken;
  final DateTime expiresAt;
  final AppUser user;

  factory LoginResult.fromJson(Map<String, dynamic> json) => LoginResult(
        accessToken: json['accessToken'] as String,
        expiresAt: DateTime.parse(json['expiresAt'] as String),
        user: AppUser.fromJson(json['user'] as Map<String, dynamic>),
      );
}
