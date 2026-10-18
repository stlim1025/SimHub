import '../../auth/domain/auth_models.dart';
import '../../auth/domain/user_preferences.dart';

/// 설정 화면에서 편집 중인 값(불변): 사용자 이름 + 설정. 이메일은 바로 저장하는 별도 흐름이라 여기 없다(docs/14 §8).
class ProfileDraft {
  const ProfileDraft({required this.displayName, required this.preferences});

  factory ProfileDraft.fromUser(AppUser user) =>
      ProfileDraft(displayName: user.displayName, preferences: user.preferences);

  final String displayName;
  final UserPreferences preferences;

  /// `PUT /me/profile` 본문.
  Map<String, dynamic> toJson() => {'displayName': displayName, ...preferences.toJson()};

  ProfileDraft copyWith({String? displayName, UserPreferences? preferences}) => ProfileDraft(
        displayName: displayName ?? this.displayName,
        preferences: preferences ?? this.preferences,
      );

  @override
  bool operator ==(Object other) =>
      other is ProfileDraft && other.displayName == displayName && other.preferences == preferences;

  @override
  int get hashCode => Object.hash(displayName, preferences);
}
