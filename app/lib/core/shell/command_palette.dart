import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/laps/domain/lap_display.dart';
import '../../features/ranking/application/ranking_providers.dart';
import '../../features/ranking/domain/ranking_models.dart';
import '../../features/setups/domain/setups_display.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
import 'nav_items.dart';

/// 검색 창 단축키 안내 글자(위쪽 바 검색 칸).
const String kCommandPaletteShortcutLabel = 'Ctrl K';

/// 계정 설정 경로(셸과 같다).
const String _settingsPath = '/settings';
const String _settingsLabel = '계정 설정';
const String _hint = '페이지·트랙 검색';
const String _emptyText = '맞는 항목이 없어요.';
const String _trackDetail = '트랙 · 기록 · 셋업';
const String _leaderboardDetail = '리더보드';
const String _lapsDetail = '내 랩';

const double _paletteWidth = 560;
const double _listMaxHeight = 420;
const double _paletteTop = 96;
const int _maxResults = 40;

/// 검색 창 한 줄: 보이는 이름, 부제(없으면 null), 아이콘, 갈 주소, 함께 찾을 말.
typedef CommandEntry = ({String label, String? detail, IconData icon, String location, String keywords});

/// 메뉴마다 한국어로도 찾게 하는 말.
const Map<String, String> _menuKeywords = {
  '/': 'home 홈 대시보드',
  '/seasons': '시즌 season',
  '/sessions': '세션 레이스 session race',
  '/laps': '랩 기록 lap',
  '/leaderboard': '리더보드 순위 랭킹 ranking',
  '/tracks': '트랙 셋업 setups setup',
  '/telemetry-app': 'agent 에이전트 연결 다운로드 telemetry',
};

/// 메뉴·계정 설정·트랙마다 개요·리더보드·내 랩을 담은 검색 항목(순수 함수).
List<CommandEntry> commandEntries(List<Track> tracks) => [
      for (final item in [...navItems, telemetryAppNavItem])
        (label: item.label, detail: null, icon: item.icon, location: item.path, keywords: _menuKeywords[item.path] ?? ''),
      (label: _settingsLabel, detail: null, icon: Icons.settings_outlined, location: _settingsPath, keywords: 'settings profile account 설정 프로필'),
      for (final track in tracks) ...[
        (label: track.name, detail: _trackDetail, icon: Icons.route_outlined, location: trackOverviewLocation(track.trackId), keywords: 'track setup 트랙 셋업'),
        (label: track.name, detail: _leaderboardDetail, icon: Icons.emoji_events_outlined, location: leaderboardLocation(track.trackId), keywords: 'leaderboard ranking 리더보드 순위'),
        (label: track.name, detail: _lapsDetail, icon: Icons.timer_outlined, location: trackLapsLocation(track.trackId), keywords: 'laps lap 랩'),
      ],
    ];

/// [query]의 낱말이 모두 이름·부제·함께 찾을 말 어딘가에 들어 있는 항목(대소문자 무시, 빈 검색이면 전부, 순수 함수).
List<CommandEntry> filterCommands(List<CommandEntry> entries, String query) {
  final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) {
    return entries;
  }
  return entries.where((entry) {
    final haystack = '${entry.label} ${entry.detail ?? ''} ${entry.keywords}'.toLowerCase();
    return words.every(haystack.contains);
  }).toList();
}

/// 검색 창을 연다(위쪽 바 검색 칸·Ctrl/⌘+K). 고르면 그 주소로 간다.
Future<void> showCommandPalette(BuildContext context) => showDialog<void>(
      context: context,
      builder: (_) => const CommandPalette(),
    );

/// 검색 창: 위에 입력 칸, 아래 맞는 항목(↑↓로 고르고 Enter로 이동, Esc로 닫기).
class CommandPalette extends ConsumerStatefulWidget {
  const CommandPalette({super.key});

  @override
  ConsumerState<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends ConsumerState<CommandPalette> {
  final _query = TextEditingController();
  int _selected = 0;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _go(String location) {
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.go(location);
  }

  KeyEventResult _onKey(List<CommandEntry> results, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown && results.isNotEmpty) {
      setState(() => _selected = (_selected + 1) % results.length);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp && results.isNotEmpty) {
      setState(() => _selected = (_selected - 1 + results.length) % results.length);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final tracks = ref.watch(tracksProvider).valueOrNull ?? const <Track>[];
    final results = filterCommands(commandEntries(tracks), _query.text).take(_maxResults).toList();
    final selected = results.isEmpty ? -1 : _selected.clamp(0, results.length - 1);
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.only(top: _paletteTop, left: 16, right: 16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _paletteWidth),
          child: Material(
            key: const ValueKey('command-palette'),
            color: palette.surface,
            shape: RoundedRectangleBorder(side: BorderSide(color: palette.border)),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Focus(
                  onKeyEvent: (_, event) => _onKey(results, event),
                  child: TextField(
                    key: const ValueKey('command-palette-input'),
                    controller: _query,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: _hint,
                      prefixIcon: Icon(Icons.search),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 14),
                    ),
                    onChanged: (_) => setState(() => _selected = 0),
                    onSubmitted: (_) {
                      if (selected >= 0) {
                        _go(results[selected].location);
                      }
                    },
                  ),
                ),
                Divider(height: 1, color: palette.border),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: _listMaxHeight),
                  child: results.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(_emptyText, style: TextStyle(color: palette.textMuted)),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: results.length,
                          itemBuilder: (context, i) {
                            final entry = results[i];
                            final detail = entry.detail;
                            return ListTile(
                              key: ValueKey('command-${entry.location}'),
                              dense: true,
                              selected: i == selected,
                              selectedTileColor: AppColors.accent.withValues(alpha: 0.12),
                              selectedColor: palette.link,
                              leading: Icon(entry.icon, size: 20),
                              title: Text(entry.label),
                              subtitle: detail == null ? null : Text(detail, style: TextStyle(color: palette.textMuted)),
                              onTap: () => _go(entry.location),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
