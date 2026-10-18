import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/domain/auth_models.dart';
import '../../auth/domain/user_preferences.dart';
import '../data/profile_repository.dart';
import '../domain/profile_draft.dart';

/// 설정 화면 상태(불변): 저장된 값([saved])과 편집 중인 값([draft]). 둘이 다르면 저장·취소할 수 있다(docs/14 §8).
class ProfileFormState {
  const ProfileFormState({required this.saved, required this.draft, this.saving = false, this.error});

  final ProfileDraft saved;
  final ProfileDraft draft;

  /// 저장 요청 중.
  final bool saving;

  /// 마지막 저장 실패 메시지. 다시 편집·취소·저장하면 지운다.
  final String? error;

  bool get isDirty => draft != saved;

  ProfileFormState copyWith({ProfileDraft? saved, ProfileDraft? draft, bool? saving, String? error, bool clearError = false}) =>
      ProfileFormState(
        saved: saved ?? this.saved,
        draft: draft ?? this.draft,
        saving: saving ?? this.saving,
        error: clearError ? null : (error ?? this.error),
      );
}

/// 설정 화면의 편집·저장·취소. 화면을 떠나면 편집 중인 값은 버린다(autoDispose, 떠날 때 확인은 하지 않는다).
/// 사용자 이름·공개 여부·사진·게임 환경·타임존·테마는 "변경 사항 저장"으로 한 번에 저장하고, 이메일은 대화상자에서 바로 저장한다.
class ProfileFormController extends AutoDisposeNotifier<ProfileFormState> {
  @override
  ProfileFormState build() {
    // 다른 계정으로 바뀌면 폼을 새로 연다. 저장 뒤의 프로필 갱신(같은 사용자)으로는 다시 만들지 않는다.
    ref.watch(authControllerProvider.select((auth) => auth.valueOrNull?.userId));
    final user = ref.read(authControllerProvider).valueOrNull ?? const AppUser(userId: '', displayName: '');
    final saved = ProfileDraft.fromUser(user);
    return ProfileFormState(saved: saved, draft: saved);
  }

  void setDisplayName(String displayName) => _edit(state.draft.copyWith(displayName: displayName.trim()));

  void setShowOnLeaderboard(bool value) => _editPreferences((p) => p.copyWith(showOnLeaderboard: value));

  /// null이면 사진 없음(이름 첫 글자).
  void setAvatarTeam(String? code) =>
      _editPreferences((p) => code == null ? p.copyWith(clearAvatar: true) : p.copyWith(avatarTeam: code));

  void setPreferredGame(String gameCode) => _editPreferences((p) => p.copyWith(preferredGame: gameCode));

  void setController(ControllerType value) => _editPreferences((p) => p.copyWith(controller: value));

  void setConsole(ConsolePlatform value) => _editPreferences((p) => p.copyWith(console: value));

  void setUnits(UnitSystem value) => _editPreferences((p) => p.copyWith(units: value));

  void setTimeZone(String timeZoneId) => _editPreferences((p) => p.copyWith(timeZoneId: timeZoneId));

  void setTheme(ThemePreference value) => _editPreferences((p) => p.copyWith(theme: value));

  /// 편집을 버리고 저장된 값으로 되돌린다.
  void cancel() => state = state.copyWith(draft: state.saved, clearError: true);

  /// 바뀐 값을 저장한다. 성공하면 true(인증 상태의 프로필도 바뀌어 사이드바·테마가 따라온다), 실패하면 [ProfileFormState.error].
  Future<bool> save() async {
    if (!state.isDirty || state.saving) {
      return false;
    }
    final draft = state.draft;
    state = state.copyWith(saving: true, clearError: true);
    try {
      final user = await ref.read(profileRepositoryProvider).updateProfile(draft);
      ref.read(authControllerProvider.notifier).applyProfile(user);
      final saved = ProfileDraft.fromUser(user);
      state = ProfileFormState(saved: saved, draft: saved);
      return true;
    } on ApiException catch (e) {
      state = state.copyWith(saving: false, error: e.message);
      return false;
    } catch (e) {
      debugPrint('프로필 저장 실패: $e');
      state = state.copyWith(saving: false, error: _unexpectedSaveError);
      return false;
    }
  }

  static const _unexpectedSaveError = '저장하지 못했어요. 잠시 후 다시 시도해 주세요.';

  /// 이메일을 바로 바꾼다(편집 중인 다른 값은 그대로 둔다). 실패하면 [ApiException]을 던진다 — 대화상자가 필드별로 보인다.
  Future<void> changeEmail({required String newEmail, required String currentPassword}) async {
    final user = await ref
        .read(profileRepositoryProvider)
        .changeEmail(newEmail: newEmail.trim(), currentPassword: currentPassword);
    ref.read(authControllerProvider.notifier).applyProfile(user);
  }

  void _editPreferences(UserPreferences Function(UserPreferences) change) =>
      _edit(state.draft.copyWith(preferences: change(state.draft.preferences)));

  void _edit(ProfileDraft draft) => state = state.copyWith(draft: draft, clearError: true);
}

final profileFormControllerProvider =
    AutoDisposeNotifierProvider<ProfileFormController, ProfileFormState>(ProfileFormController.new);
