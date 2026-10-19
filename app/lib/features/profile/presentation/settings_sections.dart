import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_palette.dart';

import '../../auth/application/auth_controller.dart';
import '../../auth/domain/user_preferences.dart';
import '../application/profile_form_controller.dart';
import '../application/settings_notice.dart';
import '../domain/game_options.dart';
import '../domain/time_zones.dart';
import 'avatar_picker.dart';
import 'profile_dialogs.dart';
import 'setting_row.dart';

/// 드롭다운 최대 폭(넓은 화면에서 지나치게 길어지지 않게). 좁으면 가능한 폭에 맞춰 줄임표로 줄인다.
const double _dropdownMaxWidth = 320;

/// 프로필: 이메일(바로 저장) · 닉네임(폼에 반영) · 랭킹 공개 설정.
class ProfileSection extends ConsumerWidget {
  const ProfileSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final email = ref.watch(authControllerProvider.select((auth) => auth.valueOrNull?.email)) ?? '-';
    final draft = ref.watch(profileFormControllerProvider.select((s) => s.draft));
    final form = ref.read(profileFormControllerProvider.notifier);

    return SettingsSection(
      title: '프로필',
      child: Column(
        children: [
          SettingRow(
            label: '이메일',
            child: ValueWithChange(
              value: email,
              buttonKey: const ValueKey('change-email'),
              onChange: () => _changeEmail(context, ref, form),
            ),
          ),
          SettingRow(
            label: '닉네임',
            child: ValueWithChange(
              value: draft.displayName,
              buttonKey: const ValueKey('change-display-name'),
              onChange: () async {
                final name = await showChangeDisplayNameDialog(context, current: draft.displayName);
                if (name != null) {
                  form.setDisplayName(name);
                }
              },
            ),
          ),
          SettingRow(
            label: '공개 설정',
            child: _PrivacyToggle(
              value: draft.preferences.showOnLeaderboard,
              onChanged: form.setShowOnLeaderboard,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _changeEmail(BuildContext context, WidgetRef ref, ProfileFormController form) async {
    final notice = ref.read(settingsNoticeProvider.notifier);
    final changed = await showChangeEmailDialog(
      context,
      onSubmit: (newEmail, password) => form.changeEmail(newEmail: newEmail, currentPassword: password),
    );
    if (changed == true) {
      notice.show('이메일을 변경했어요. 다음 로그인부터 새 이메일을 쓰세요.');
    }
  }
}

class _PrivacyToggle extends StatelessWidget {
  const _PrivacyToggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            key: const ValueKey('privacy-checkbox'),
            value: value,
            onChanged: (checked) => onChanged(checked ?? false),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('리더보드에 내 닉네임 표시'),
                  Text(
                    '끄면 랭킹에 "익명 드라이버"로 보여요. 내 기록 화면은 그대로예요.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.palette.textMuted),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 설정: 게임 · 컨트롤러 · 플랫폼 · 단위 · 타임존 · 테마. 게임·컨트롤러·플랫폼·단위·타임존은 지금은 저장만 한다(docs/14 §3).
class PreferencesSection extends ConsumerWidget {
  const PreferencesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(profileFormControllerProvider.select((s) => s.draft.preferences));
    final form = ref.read(profileFormControllerProvider.notifier);

    return SettingsSection(
      title: '설정',
      child: Column(
        children: [
          SettingRow(
            label: '게임',
            child: _Dropdown(
              key: const ValueKey('game-select'),
              value: prefs.preferredGame,
              items: [
                for (final code in gameChoices(prefs.preferredGame))
                  DropdownMenuItem(value: code, child: Text(gameLabelOf(code), maxLines: 1, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (code) => code == null ? null : form.setPreferredGame(code),
            ),
          ),
          SettingRow(
            label: '컨트롤러',
            child: ChoiceSegments<ControllerType>(
              values: ControllerType.values,
              selected: prefs.controller,
              labelOf: (v) => v.label,
              onSelected: form.setController,
            ),
          ),
          SettingRow(
            label: '플랫폼',
            child: ChoiceSegments<ConsolePlatform>(
              values: ConsolePlatform.values,
              selected: prefs.console,
              labelOf: (v) => v.label,
              onSelected: form.setConsole,
            ),
          ),
          SettingRow(
            label: '단위',
            child: ChoiceSegments<UnitSystem>(
              values: UnitSystem.values,
              selected: prefs.units,
              labelOf: (v) => v.label,
              onSelected: form.setUnits,
            ),
          ),
          SettingRow(
            label: '타임존',
            child: _Dropdown(
              key: const ValueKey('timezone-select'),
              value: prefs.timeZoneId,
              items: [
                for (final id in timeZoneChoices(prefs.timeZoneId))
                  DropdownMenuItem(value: id, child: Text(id, maxLines: 1, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (id) => id == null ? null : form.setTimeZone(id),
            ),
          ),
          SettingRow(
            label: '테마',
            child: ChoiceSegments<ThemePreference>(
              values: ThemePreference.values,
              selected: prefs.theme,
              labelOf: (v) => v.label,
              onSelected: form.setTheme,
            ),
          ),
        ],
      ),
    );
  }
}

/// 프로필 사진(팀 색 원). 사이드바 하단에도 같은 사진이 보인다.
class AvatarSection extends ConsumerWidget {
  const AvatarSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(profileFormControllerProvider.select((s) => s.draft));
    return SettingsSection(
      title: '프로필 사진',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '좋아하는 팀 색을 고르세요. 팀 로고 대신 팀 색과 약자로 표시해요.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.palette.textMuted),
          ),
          const SizedBox(height: 12),
          AvatarPicker(
            selected: draft.preferences.avatarTeam,
            displayName: draft.displayName,
            onSelected: ref.read(profileFormControllerProvider.notifier).setAvatarTeam,
          ),
        ],
      ),
    );
  }
}

/// 폭에 맞춰 늘고 줄어드는 드롭다운(긴 타임존 이름이 휴대폰 폭에서 넘치지 않게).
class _Dropdown extends StatelessWidget {
  const _Dropdown({super.key, required this.value, required this.items, required this.onChanged});

  final String value;
  final List<DropdownMenuItem<String>> items;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _dropdownMaxWidth),
      child: DropdownButton<String>(isExpanded: true, value: value, items: items, onChanged: onChanged),
    );
  }
}
