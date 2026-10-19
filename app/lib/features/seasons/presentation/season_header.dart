import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/app_notice.dart';
import '../../../core/widgets/menu_items.dart';
import '../../profile/domain/game_options.dart';
import '../../sessions/domain/session_display.dart';
import '../application/seasons_providers.dart';
import '../data/seasons_repository.dart';
import '../domain/season_display.dart';
import '../domain/season_models.dart';
import 'season_import_dialog.dart';

const String _seasonsPath = '/seasons';
const String _sessionsPath = '/sessions';

/// 시즌 이름을 알 수 없을 때(로딩 중·조회 실패)의 제목.
const String _fallbackTitle = 'Season';

const String _switcherSemanticLabel = '시즌 선택';
const String _activeSectionLabel = '진행 중인 시즌';
const String _completedSectionLabel = '완료된 시즌';
const String _addSeasonLabel = '새 시즌 추가';
const String _allSessionsLabel = '전체 세션 보기';
const String _closeTooltip = '닫기';
const String _subtitleSeparator = ' · ';

const String _optionsLabel = '옵션';
const String _renameLabel = '이름 변경';
const String _completeLabel = '완료로 표시';
const String _reopenLabel = '진행 중으로 되돌리기';
const String _importLabel = '시즌 추가 (F1Laps 가져오기)';
const String _deleteLabel = '삭제';

const String _renamedText = '시즌 이름을 바꿨어요.';
const String _completedText = '시즌을 완료로 표시했어요.';
const String _reopenedText = '시즌을 진행 중으로 되돌렸어요.';
const String _deletedText = '시즌을 삭제했어요.';
const String _actionFailedText = '시즌을 바꾸지 못했어요. 잠시 후 다시 시도해 주세요.';
const String _cancelLabel = '취소';
const String _saveLabel = '저장';

// -- 크기 ---------------------------------------------------------------------

const double _titleRadius = 8;
const double _titleIconGap = 4;
const EdgeInsets _titlePadding = EdgeInsets.symmetric(horizontal: 4, vertical: 4);
const EdgeInsets _driverNamePadding = EdgeInsets.only(left: 4);
const double _headerGap = 12;

/// 시즌 메뉴(패널) 폭·최대 높이 비율·안쪽 여백.
const double _panelWidth = 320;
const double _panelMaxHeightFactor = 0.8;
const double _panelRadius = 8;
const EdgeInsets _panelHeaderPadding = EdgeInsets.fromLTRB(16, 8, 4, 8);
const EdgeInsets _sectionLabelPadding = EdgeInsets.fromLTRB(16, 10, 16, 4);
const EdgeInsets _panelItemPadding = EdgeInsets.symmetric(horizontal: 16);
const double _seasonItemHeight = 48;
const double _panelItemIconSize = 18;
const double _closeIconSize = 18;
const double _menuIconSize = 18;
const double _sectionLabelLetterSpacing = 0.6;

/// 시즌 상세 헤더(F1Laps 시즌 화면): 왼쪽 `Driver Career Season 1` ⇕(시즌 메뉴) + 아래 흐린 내 이름,
/// 오른쪽 `옵션 ▾`(이름 변경·완료 표시·시즌 추가·삭제). [season]이 null(로딩 중·조회 실패)이면 제목만 보인다.
class SeasonHeader extends StatelessWidget {
  const SeasonHeader({super.key, required this.season});

  final SeasonSummary? season;

  @override
  Widget build(BuildContext context) {
    final current = season;
    final titleStyle = Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold);
    final driverName = current?.myDriverName;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (current == null)
                Padding(padding: _titlePadding, child: Text(_fallbackTitle, style: titleStyle))
              else
                _SeasonSwitcher(current: current, textStyle: titleStyle),
              if (driverName != null && driverName.isNotEmpty)
                Padding(
                  padding: _driverNamePadding,
                  child: Text(
                    driverName,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.palette.textMuted),
                  ),
                ),
            ],
          ),
        ),
        if (current != null) ...[
          const SizedBox(width: _headerGap),
          _SeasonOptionsMenu(season: current),
        ],
      ],
    );
  }
}

// -- 시즌 메뉴(제목 ⇕) ---------------------------------------------------------

/// 제목을 누르면 아래에 붙어 열리는 시즌 패널: 큰 제목 + 게임·모드·드라이버 + 닫기,
/// 진행 중인 시즌 / 완료된 시즌(각각 최근 순, 지금 시즌은 링크 색) + 새 시즌 추가 · 전체 세션 보기.
class _SeasonSwitcher extends ConsumerStatefulWidget {
  const _SeasonSwitcher({required this.current, required this.textStyle});

  final SeasonSummary current;
  final TextStyle? textStyle;

  @override
  ConsumerState<_SeasonSwitcher> createState() => _SeasonSwitcherState();
}

class _SeasonSwitcherState extends ConsumerState<_SeasonSwitcher> {
  final _controller = MenuController();

  void _toggle() => _controller.isOpen ? _controller.close() : _controller.open();

  void _go(String location) {
    _controller.close();
    context.go(location);
  }

  Future<void> _addSeason() async {
    _controller.close();
    await openSeasonImport(context, ref);
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.current;
    final palette = context.palette;
    final listed = ref.watch(allSeasonsProvider).valueOrNull ?? const <SeasonSummary>[];
    // 목록에는 지금 시즌을 방금 읽은 상세 헤더로 바꿔 넣는다(이름·완료 상태가 목록보다 새롭다).
    final seasons = sortSeasonsByRecent([
      current,
      for (final s in listed)
        if (s.seasonId != current.seasonId) s,
    ]);
    final active = [for (final s in seasons) if (!s.isCompleted) s];
    final completed = [for (final s in seasons) if (s.isCompleted) s];
    final maxHeight = MediaQuery.sizeOf(context).height * _panelMaxHeightFactor;

    Widget seasonItem(SeasonSummary season) => _SeasonItem(
          key: ValueKey('season-switch-${season.seasonId}'),
          season: season,
          selected: season.seasonId == current.seasonId,
          onPressed: () => _go(seasonLocation(season.seasonId)),
        );

    return MenuAnchor(
      controller: _controller,
      crossAxisUnconstrained: false,
      // 열린 패널 밖 누름이 아래 표까지 전달되지 않게(트랙 메뉴와 같은 이유).
      consumeOutsideTap: true,
      style: MenuStyle(
        minimumSize: const WidgetStatePropertyAll(Size(_panelWidth, 0)),
        maximumSize: WidgetStatePropertyAll(Size(_panelWidth, maxHeight)),
        side: WidgetStatePropertyAll(BorderSide(color: palette.border)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_panelRadius),
            side: BorderSide(color: palette.border),
          ),
        ),
      ),
      menuChildren: [
        _PanelHeader(current: current, onClose: _controller.close),
        const Divider(height: 1),
        if (active.isNotEmpty) ...[
          const _SectionLabel(_activeSectionLabel),
          for (final s in active) seasonItem(s),
        ],
        if (completed.isNotEmpty) ...[
          const _SectionLabel(_completedSectionLabel),
          for (final s in completed) seasonItem(s),
        ],
        const Divider(height: 1),
        _PanelAction(
          key: const ValueKey('season-switcher-add'),
          icon: Icons.add,
          label: _addSeasonLabel,
          onPressed: _addSeason,
        ),
        _PanelAction(
          key: const ValueKey('season-switcher-sessions'),
          icon: Icons.list,
          label: _allSessionsLabel,
          onPressed: () => _go(_sessionsPath),
        ),
      ],
      builder: (context, controller, _) => Semantics(
        button: true,
        label: _switcherSemanticLabel,
        child: InkWell(
          key: const ValueKey('season-switcher'),
          borderRadius: BorderRadius.circular(_titleRadius),
          onTap: _toggle,
          child: Padding(
            padding: _titlePadding,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    seasonDisplayTitle(current),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: widget.textStyle,
                  ),
                ),
                const SizedBox(width: _titleIconGap),
                Icon(Icons.unfold_more, color: palette.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 패널 머리: 지금 시즌 이름(크게) + `F1 25 · Driver Career · GOM` + 닫기 X.
class _PanelHeader extends StatelessWidget {
  const _PanelHeader({required this.current, required this.onClose});

  final SeasonSummary current;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final driver = current.myDriverName;
    final subtitle = [
      gameLabelOf(current.gameCode),
      gameModeLabel(current.gameMode),
      if (driver != null && driver.isNotEmpty) driver,
    ].join(_subtitleSeparator);
    return SizedBox(
      width: _panelWidth,
      child: Padding(
        padding: _panelHeaderPadding,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    seasonDisplayTitle(current),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: context.palette.textMuted),
                  ),
                ],
              ),
            ),
            IconButton(
              key: const ValueKey('season-switcher-close'),
              tooltip: _closeTooltip,
              iconSize: _closeIconSize,
              onPressed: onClose,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
    );
  }
}

/// 패널의 묶음 이름(작은 흐린 대문자 느낌).
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: _sectionLabelPadding,
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: context.palette.textMuted,
              fontWeight: FontWeight.w600,
              letterSpacing: _sectionLabelLetterSpacing,
            ),
      ),
    );
  }
}

/// 패널의 시즌 한 줄: 이름 + 아래 흐린 드라이버 이름. 지금 시즌은 링크 색 굵게 + 선택 상태.
class _SeasonItem extends StatelessWidget {
  const _SeasonItem({super.key, required this.season, required this.selected, required this.onPressed});

  final SeasonSummary season;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final driver = season.myDriverName;
    return Semantics(
      selected: selected,
      child: SizedBox(
        width: _panelWidth,
        child: MenuItemButton(
          onPressed: onPressed,
          style: const ButtonStyle(
            minimumSize: WidgetStatePropertyAll(Size.fromHeight(_seasonItemHeight)),
            padding: WidgetStatePropertyAll(_panelItemPadding),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                seasonDisplayTitle(season),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? palette.link : palette.textPrimary,
                  fontWeight: selected ? FontWeight.bold : FontWeight.w600,
                ),
              ),
              if (driver != null && driver.isNotEmpty)
                Text(
                  driver,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: palette.textMuted),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 패널 아래쪽 동작 한 줄(새 시즌 추가 · 전체 세션 보기).
class _PanelAction extends StatelessWidget {
  const _PanelAction({super.key, required this.icon, required this.label, required this.onPressed});

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _panelWidth,
      child: MenuItemButton(
        onPressed: onPressed,
        leadingIcon: Icon(icon, size: _panelItemIconSize),
        style: const ButtonStyle(
          minimumSize: WidgetStatePropertyAll(Size.fromHeight(kMenuItemHeight)),
          padding: WidgetStatePropertyAll(_panelItemPadding),
        ),
        child: Text(label),
      ),
    );
  }
}

// -- 옵션 메뉴 -----------------------------------------------------------------

/// 오른쪽 위 `옵션 ▾`: 이름 변경 · 완료로 표시/진행 중으로 되돌리기 · 시즌 추가 · 삭제(위험 색).
/// 바꾼 뒤에는 이 시즌 상세와 시즌 목록을 새로 읽고 오른쪽 위 알림으로 결과를 알린다.
class _SeasonOptionsMenu extends ConsumerWidget {
  const _SeasonOptionsMenu({required this.season});

  final SeasonSummary season;

  /// 서버에 바꾸기를 보내고 성공하면 두 provider를 새로 읽게 한 뒤 [successText]를 띄운다. 성공하면 true.
  Future<bool> _apply(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function(SeasonsRepository repo) action,
    String successText, {
    bool refreshDetail = true,
  }) async {
    final toaster = AppToaster.of(context);
    try {
      await action(ref.read(seasonsRepositoryProvider));
    } on ApiException catch (e) {
      toaster.show(e.message, tone: NoticeTone.error);
      return false;
    } catch (e) {
      debugPrint('Season update failed: $e');
      toaster.show(_actionFailedText, tone: NoticeTone.error);
      return false;
    }
    if (!context.mounted) return false;
    ref.invalidate(allSeasonsProvider);
    if (refreshDetail) {
      ref.invalidate(seasonDetailProvider(season.seasonId));
    }
    toaster.show(successText, tone: NoticeTone.success);
    return true;
  }

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final name = await showDialog<String>(context: context, builder: (_) => _RenameSeasonDialog(season: season));
    if (name == null || !context.mounted) return;
    await _apply(context, ref, (repo) => repo.renameSeason(season.seasonId, name.isEmpty ? null : name), _renamedText);
  }

  Future<void> _toggleCompleted(BuildContext context, WidgetRef ref) async {
    final completed = !season.isCompleted;
    await _apply(
      context,
      ref,
      (repo) => repo.setSeasonCompleted(season.seasonId, completed: completed),
      completed ? _completedText : _reopenedText,
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _DeleteSeasonDialog(title: seasonDisplayTitle(season)),
    );
    if (confirmed != true || !context.mounted) return;
    // 지운 시즌의 상세는 다시 읽지 않는다(404). Seasons로 가면 남은 시즌이나 빈 화면이 열린다.
    final deleted = await _apply(
      context,
      ref,
      (repo) => repo.deleteSeason(season.seasonId),
      _deletedText,
      refreshDetail: false,
    );
    if (deleted && context.mounted) {
      context.go(_seasonsPath);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final danger = context.palette.danger;
    MenuItemButton item(String key, IconData icon, String label, VoidCallback onPressed, {Color? color}) =>
        MenuItemButton(
          key: ValueKey(key),
          onPressed: onPressed,
          leadingIcon: Icon(icon, size: _menuIconSize, color: color),
          style: ButtonStyle(
            minimumSize: const WidgetStatePropertyAll(Size(0, kMenuItemHeight)),
            foregroundColor: color == null ? null : WidgetStatePropertyAll(color),
          ),
          child: Text(label),
        );

    return MenuAnchor(
      consumeOutsideTap: true,
      menuChildren: [
        item('season-options-rename', Icons.edit_outlined, _renameLabel, () => _rename(context, ref)),
        item(
          'season-options-complete',
          season.isCompleted ? Icons.replay : Icons.check_circle_outline,
          season.isCompleted ? _reopenLabel : _completeLabel,
          () => _toggleCompleted(context, ref),
        ),
        const Divider(height: 1),
        item('season-options-import', Icons.add, _importLabel, () => openSeasonImport(context, ref)),
        const Divider(height: 1),
        item('season-options-delete', Icons.delete_outline, _deleteLabel, () => _delete(context, ref), color: danger),
      ],
      builder: (context, controller, _) => OutlinedButton(
        key: const ValueKey('season-options'),
        onPressed: () => controller.isOpen ? controller.close() : controller.open(),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_optionsLabel),
            Icon(Icons.arrow_drop_down, size: _menuIconSize),
          ],
        ),
      ),
    );
  }
}

/// 이름 변경 대화상자. 저장하면 다듬은 이름(빈 문자열 = 기본 이름으로 되돌리기)을, 취소하면 null을 돌려준다.
class _RenameSeasonDialog extends StatefulWidget {
  const _RenameSeasonDialog({required this.season});

  final SeasonSummary season;

  @override
  State<_RenameSeasonDialog> createState() => _RenameSeasonDialogState();
}

class _RenameSeasonDialogState extends State<_RenameSeasonDialog> {
  late final _name = TextEditingController(text: widget.season.name ?? '');

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() => Navigator.of(context).pop(_name.text.trim());

  @override
  Widget build(BuildContext context) {
    final defaultTitle = seasonHeaderTitle(widget.season);
    return AlertDialog(
      title: const Text('시즌 이름 변경'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const ValueKey('season-rename-field'),
            controller: _name,
            autofocus: true,
            maxLength: kSeasonNameMaxLength,
            decoration: InputDecoration(labelText: '시즌 이름', hintText: defaultTitle),
            onSubmitted: (_) => _save(),
          ),
          Text(
            '비워 두면 기본 이름($defaultTitle)으로 돌아가요.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.palette.textMuted),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text(_cancelLabel)),
        FilledButton(key: const ValueKey('season-rename-confirm'), onPressed: _save, child: const Text(_saveLabel)),
      ],
    );
  }
}

/// 삭제 확인 대화상자. 확인하면 true.
class _DeleteSeasonDialog extends StatelessWidget {
  const _DeleteSeasonDialog({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AlertDialog(
      title: Text('"$title" 시즌을 삭제할까요?'),
      content: const Text('세션과 랩 기록은 그대로 남지만, 이 시즌 묶음과 순위표는 목록에서 사라져요.'),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text(_cancelLabel)),
        FilledButton(
          key: const ValueKey('season-delete-confirm'),
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(backgroundColor: palette.danger, foregroundColor: palette.surface),
          child: const Text(_deleteLabel),
        ),
      ],
    );
  }
}
