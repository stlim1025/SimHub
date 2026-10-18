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
  const ProfileFormState({
    required this.saved,
    required this.draft,
    required this.loaded,
    this.saving = false,
    this.error,
  });

  final ProfileDraft saved;
  final ProfileDraft draft;

  /// [saved]가 서버의 전체 프로필에서 왔는지([AppUser.isProfileLoaded]). false면 기본값이라 저장하지 않는다.
  final bool loaded;

  /// 저장 요청 중.
  final bool saving;

  /// 마지막 저장 실패 메시지. 다시 편집·취소·저장하면 지운다.
  final String? error;

  bool get isDirty => draft != saved;

  /// 저장할 수 있는지: 전체 프로필을 읽었고, 바뀐 것이 있고, 저장 중이 아님.
  bool get canSave => loaded && isDirty && !saving;

  ProfileFormState copyWith({ProfileDraft? saved, ProfileDraft? draft, bool? saving, String? error, bool clearError = false}) =>
      ProfileFormState(
        saved: saved ?? this.saved,
        draft: draft ?? this.draft,
        loaded: loaded,
        saving: saving ?? this.saving,
        error: clearError ? null : (error ?? this.error),
      );
}

/// 설정 화면의 편집·저장·취소. 화면을 떠나면 편집 중인 값은 버린다(autoDispose, 떠날 때 확인은 하지 않는다).
/// 사용자 이름·공개 여부·사진·게임 환경·타임존·테마는 "변경 사항 저장"으로 한 번에 저장하고, 이메일은 대화상자에서 바로 저장한다.
class ProfileFormController extends AutoDisposeNotifier<ProfileFormState> {
  static const _unexpectedSaveError = '저장하지 못했어요. 잠시 후 다시 시도해 주세요.';

  @override
  ProfileFormState build() {
    // 다른 계정으로 바뀌거나 전체 프로필을 새로 읽으면 폼을 새로 연다. 저장 뒤의 프로필 갱신(같은 사용자·이미 읽음)으로는 다시 만들지 않는다.
    ref.watch(authControllerProvider.select((auth) => (auth.valueOrNull?.userId, auth.valueOrNull?.isProfileLoaded)));
    final user = ref.read(authControllerProvider).valueOrNull ?? const AppUser(userId: '', displayName: '');
    final saved = ProfileDraft.fromUser(user);
    return ProfileFormState(saved: saved, draft: saved, loaded: user.isProfileLoaded);
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
  /// 전체 프로필을 읽기 전([ProfileFormState.loaded]가 false)에는 보내지 않는다. 저장하는 동안 더 고친 값은 버리지 않는다.
  Future<bool> save() async {
    if (!state.canSave) {
      return false;
    }
    final sent = state.draft;
    state = state.copyWith(saving: true, clearError: true);
    try {
      final user = await ref.read(profileRepositoryProvider).updateProfile(sent);
      ref.read(authControllerProvider.notifier).applyProfile(user);
      final saved = ProfileDraft.fromUser(user);
      // 요청 중에 더 고쳤으면 그 편집을 남긴다(저장된 값과 다르니 다시 저장할 수 있다).
      final draft = state.draft == sent ? saved : state.draft;
      state = ProfileFormState(saved: saved, draft: draft, loaded: true);
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

/// 설정 화면에서 요약 사용자(로그인 직후 `GET /me` 실패)의 전체 프로필을 다시 읽는다. 다시 시도 = `ref.invalidate`.
final profileReloadProvider = FutureProvider.autoDispose<void>(
  (ref) => ref.read(authControllerProvider.notifier).reloadProfile(),
);
