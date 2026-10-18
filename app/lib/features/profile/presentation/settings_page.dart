import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/layout/layout_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/error_retry.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/application/sign_out.dart';
import '../application/profile_form_controller.dart';
import 'settings_sections.dart';

const double _sectionGap = 16;
const double _saveBarBreakpoint = 520;
const double _buttonHeight = 44;
const double _buttonMinWidth = 96;

/// 계정 설정(Edit Profile, docs/14 §8): 프로필 · 설정 · 프로필 사진 + 아래에 고정된 저장/취소 바.
/// 사이드바 하단 프로필(사진·이름·"계정 설정")을 누르면 열린다. 결제·비밀번호 변경·계정 삭제는 없다(범위 밖).
/// 로그인 직후 프로필 조회가 실패해 요약 사용자만 있으면, 폼 대신 프로필을 다시 읽는다(읽기 전에는 저장 바가 없다).
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // null = 로그아웃(라우터가 로그인 화면으로 보낸다), false = 요약 사용자(프로필을 다시 읽는다), true = 폼.
    final loaded = ref.watch(authControllerProvider.select((auth) => auth.valueOrNull?.isProfileLoaded));
    if (loaded == null) {
      return const SizedBox.shrink();
    }
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: kPagePadding,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Edit Profile',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('settings-logout'),
                    onPressed: () => signOut(ref),
                    icon: const Icon(Icons.logout, size: 18),
                    label: const Text('로그아웃'),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              if (loaded) ...const [
                ProfileSection(),
                SizedBox(height: _sectionGap),
                PreferencesSection(),
                SizedBox(height: _sectionGap),
                AvatarSection(),
              ] else
                const _ProfileLoader(),
            ],
          ),
        ),
        if (loaded) const _SaveBar(),
      ],
    );
  }
}

/// 전체 프로필을 다시 읽는 동안의 진행 표시, 실패하면 오류 + 다시 시도. 성공하면 인증 상태가 바뀌어 폼이 열린다.
class _ProfileLoader extends ConsumerWidget {
  const _ProfileLoader();

  static const _fallbackMessage = '프로필을 불러오지 못했어요. 잠시 후 다시 시도해 주세요.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reload = ref.watch(profileReloadProvider);
    return reload.when(
      error: (error, _) => ErrorRetry(
        key: const ValueKey('profile-reload-error'),
        error: error,
        fallbackMessage: _fallbackMessage,
        onRetry: () => ref.invalidate(profileReloadProvider),
      ),
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator(key: ValueKey('profile-reload-progress'))),
      ),
      // 성공하면 인증 상태가 전체 프로필로 바뀌어 이 위젯 대신 폼이 그려진다.
      data: (_) => const SizedBox.shrink(),
    );
  }
}

/// 아래 고정 바: 바뀐 것이 있을 때만 저장·취소가 켜진다. 취소 = 저장된 값으로 되돌리기.
class _SaveBar extends ConsumerWidget {
  const _SaveBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(profileFormControllerProvider);
    final form = ref.read(profileFormControllerProvider.notifier);
    final palette = context.palette;
    final canAct = state.canSave;

    final status = state.error != null
        ? Text(state.error!, style: TextStyle(color: context.palette.danger))
        : Text(
            state.isDirty ? '저장하지 않은 변경 사항이 있어요.' : '모든 변경 사항이 저장됐어요.',
            style: TextStyle(color: palette.textMuted),
          );

    final buttons = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        OutlinedButton(
          onPressed: canAct ? form.cancel : null,
          style: OutlinedButton.styleFrom(minimumSize: const Size(_buttonMinWidth, _buttonHeight)),
          child: const Text('취소'),
        ),
        const SizedBox(width: 8),
        FilledButton(
          key: const ValueKey('settings-save'),
          onPressed: canAct ? () => _save(context, form) : null,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.success,
            foregroundColor: AppColors.onSuccess,
            minimumSize: const Size(_buttonMinWidth, _buttonHeight),
          ),
          child: state.saving
              ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('변경 사항 저장'),
        ),
      ],
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(top: BorderSide(color: palette.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: LayoutBuilder(
            builder: (context, constraints) => constraints.maxWidth < _saveBarBreakpoint
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [Align(alignment: Alignment.centerLeft, child: status), const SizedBox(height: 8), buttons],
                  )
                : Row(children: [Expanded(child: status), buttons]),
          ),
        ),
      ),
    );
  }

  Future<void> _save(BuildContext context, ProfileFormController form) async {
    final messenger = ScaffoldMessenger.of(context);
    if (await form.save()) {
      messenger.showSnackBar(const SnackBar(content: Text('변경 사항을 저장했어요.')));
    }
  }
}
