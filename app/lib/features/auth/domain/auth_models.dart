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
