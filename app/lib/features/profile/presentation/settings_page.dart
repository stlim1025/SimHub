import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/layout/layout_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_palette.dart';
import '../../auth/application/sign_out.dart';
import '../application/profile_form_controller.dart';
import 'settings_sections.dart';

const double _sectionGap = 16;
const double _saveBarBreakpoint = 520;
const double _buttonHeight = 44;
const double _buttonMinWidth = 96;

/// 계정 설정(Edit Profile, docs/14 §8): 프로필 · 설정 · 프로필 사진 + 아래에 고정된 저장/취소 바.
/// 사이드바 하단 프로필(사진·이름·"계정 설정")을 누르면 열린다. 결제·비밀번호 변경·계정 삭제는 없다(범위 밖).
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
              const ProfileSection(),
              const SizedBox(height: _sectionGap),
              const PreferencesSection(),
              const SizedBox(height: _sectionGap),
              const AvatarSection(),
            ],
          ),
        ),
        const _SaveBar(),
      ],
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
    final canAct = state.isDirty && !state.saving;

    final status = state.error != null
        ? Text(state.error!, style: const TextStyle(color: AppColors.danger))
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
