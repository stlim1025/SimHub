/// 로그인 사용자(04 §3.2~3.3). 백엔드 camelCase 계약과 필드 일치.
class AppUser {
  const AppUser({required this.userId, required this.displayName, this.email});

  final String userId;
  final String displayName;
  final String? email;

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        userId: json['userId'] as String,
        displayName: json['displayName'] as String,
        email: json['email'] as String?,
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
