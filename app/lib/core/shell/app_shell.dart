import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/application/sign_out.dart';
import '../../features/devices/application/devices_providers.dart';
import '../../features/devices/domain/connection_status.dart';
import '../../features/live_laps/application/live_laps_controller.dart';
import '../../features/live_laps/presentation/new_lap_snack_bar.dart';
import '../../features/profile/presentation/team_avatar.dart';
import '../config/app_config.dart';
import '../layout/page_padding.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
import '../time/clock_provider.dart';
import '../widgets/brand_mark.dart';
import '../widgets/page_loading_bar.dart';
import 'command_palette.dart';
import 'nav_items.dart';

/// 이 너비(논리 px) 이상이면 위쪽 가로 메뉴, 미만이면 위쪽 바 + 서랍 메뉴.
const double kTopMenuBreakpoint = 1100;

/// 계정 설정 화면 경로(위쪽 바 계정 메뉴·서랍 아래 프로필에서 연다, docs/14 §8).
const String kSettingsPath = '/settings';

/// 위쪽 바 높이, 검색 칸·Agent 칩을 글자까지 다 보일 최소 셸 폭(그 아래는 아이콘만).
const double _topBarHeight = 56;
const double _fullTopBarWidth = 1400;
const double _topBarPaddingX = 16;
const double _menuGap = 24;
const double _menuItemPaddingX = 14;
const double _menuIconSize = 18;
const double _menuIconGap = 8;
const double _menuFontSize = 15;
const double _menuLetterSpacing = 0.6;
const double _selectedBarHeight = 3;
const double _searchWidth = 240;
const double _searchHeight = 34;
const double _accountAvatarSize = 32;
const double _statusDotSize = 8;

const double _drawerWidth = 260;
const double _drawerPadding = 12;
const double _selectedTileAlpha = 0.12;
const double _navItemHeight = 40;
const double _navItemGap = 2;
const double _navItemPaddingX = 12;
const double _navIconSize = 20;
const double _navIconGap = 12;
const double _navFontSize = 16;
const double _navChamfer = 12;
const double _navBarWidth = 3;
const double _navLetterSpacing = 0.8;
const double _brandLetterSpacing = 1.2;
const double _brandUnderlineWidth = 36;
const double _brandUnderlineHeight = 3;
const double _brandUnderlineGap = 4;
const double _footerChamfer = 10;
const double _footerAvatarSize = 32;

const String _brandName = AppConfig.brandName;
const String _accountSettingsLabel = '계정 설정';
const String _logoutLabel = '로그아웃';
const String _openMenuTooltip = '메뉴 열기';
const String _accountTooltip = '계정';
const String _searchLabel = '검색';
const String _searchTooltip = '검색 ($kCommandPaletteShortcutLabel)';

/// 로그인 후 화면의 공통 셸(docs/11 §7.2, B안 개편): 넓으면 위쪽 가로 메뉴 + 전체 폭 본문, 좁으면 위쪽 바 + 서랍.
/// 위쪽 바 오른쪽에 검색(Ctrl/⌘+K 검색 창), Agent 연결 상태 칩(→ Telemetry App), 계정 메뉴(계정 설정·Telemetry App·로그아웃).
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.child, required this.location});

  /// 현재 경로의 화면.
  final Widget child;

  /// 현재 경로(쿼리 제외). 선택된 메뉴를 표시하는 데 쓴다.
  final String location;

  /// 레이아웃이 바뀌어도(가로 메뉴 ↔ 서랍) 화면 상태가 유지되도록 하는 키.
  static const _contentKey = ValueKey('app-shell-content');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 로그인한 셸에 있는 동안 내 새 랩을 듣고, 받으면 어느 화면이든 알림을 띄운다(D-50, docs/15 §9).
    ref.listen<LiveLapEvent?>(liveLapsControllerProvider, (_, next) {
      if (next != null) {
        showNewLapSnackBar(context, next.lap);
      }
    });

    final content = KeyedSubtree(
      key: _contentKey,
      // 본문은 전체 폭(스크롤 영역이 화면 끝까지), 내용 정렬·최대 폭은 각 화면의 pagePadding이 맡는다.
      // 화면이 데이터를 불러오는 동안에는 본문 맨 위 전체 폭에 얇은 로딩 막대가 지나간다(F1Laps).
      child: PageLoadingHost(
        child: LayoutBuilder(
          builder: (context, constraints) => ContentAreaWidth(
            width: constraints.maxWidth,
            child: child,
          ),
        ),
      ),
    );

    return _PaletteShortcut(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= kTopMenuBreakpoint;
          return Scaffold(
            appBar: _TopBar(location: location, wide: wide, full: constraints.maxWidth >= _fullTopBarWidth),
            drawer: wide ? null : Drawer(width: _drawerWidth, child: _DrawerMenu(location: location)),
            body: content,
          );
        },
      ),
    );
  }
}

/// Ctrl+K(맥은 ⌘+K)로 어느 화면에서든 검색 창을 연다. 포커스와 상관없이 키보드 전체를 듣는다.
class _PaletteShortcut extends StatefulWidget {
  const _PaletteShortcut({required this.child});

  final Widget child;

  @override
  State<_PaletteShortcut> createState() => _PaletteShortcutState();
}

class _PaletteShortcutState extends State<_PaletteShortcut> {
  bool _open = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    final keyboard = HardwareKeyboard.instance;
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.keyK ||
        !(keyboard.isControlPressed || keyboard.isMetaPressed) ||
        _open ||
        !mounted) {
      return false;
    }
    _open = true;
    showCommandPalette(context).whenComplete(() => _open = false);
    return true;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// 위쪽 바: (좁으면 서랍 버튼) 브랜드 · 가로 메뉴(넓을 때) · 검색 · Agent 칩 · 계정 메뉴.
class _TopBar extends StatelessWidget implements PreferredSizeWidget {
  const _TopBar({required this.location, required this.wide, required this.full});

  final String location;
  final bool wide;

  /// 검색 칸·Agent 칩에 글자까지 넣을 만큼 넓은지.
  final bool full;

  @override
  Size get preferredSize => const Size.fromHeight(_topBarHeight);

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Material(
      color: palette.surface,
      child: Container(
        height: _topBarHeight,
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: palette.border))),
        padding: const EdgeInsets.symmetric(horizontal: _topBarPaddingX),
        child: SafeArea(
          bottom: false,
          child: Row(
            children: [
              if (!wide)
                Builder(
                  builder: (context) => IconButton(
                    tooltip: _openMenuTooltip,
                    icon: const Icon(Icons.menu),
                    onPressed: () => Scaffold.of(context).openDrawer(),
                  ),
                ),
              const _Brand(),
              if (wide) ...[
                const SizedBox(width: _menuGap),
                Expanded(child: _TopMenu(location: location)),
              ] else
                const Spacer(),
              _SearchButton(full: full),
              const SizedBox(width: 8),
              _AgentChip(location: location, full: full),
              const SizedBox(width: 8),
              _AccountMenu(location: location),
            ],
          ),
        ),
      ),
    );
  }
}

/// 가로 메뉴. 고른 메뉴는 밝은 글자 + 아래 앰버 막대. 모자라면 가로로 밀어 본다.
class _TopMenu extends StatelessWidget {
  const _TopMenu({required this.location});

  final String location;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final item in navItems)
            _TopMenuItem(item: item, selected: isNavItemSelected(item, location), onTap: () => context.go(item.path)),
        ],
      ),
    );
  }
}

class _TopMenuItem extends StatelessWidget {
  const _TopMenuItem({required this.item, required this.selected, required this.onTap});

  final NavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = selected ? palette.textPrimary : palette.textMuted;
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        key: ValueKey('nav-${item.path}'),
        onTap: onTap,
        child: Container(
          height: _topBarHeight,
          padding: const EdgeInsets.symmetric(horizontal: _menuItemPaddingX),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: selected ? AppColors.accent : Colors.transparent, width: _selectedBarHeight),
            ),
          ),
          child: Row(
            children: [
              Icon(item.icon, size: _menuIconSize, color: selected ? AppColors.accent : color),
              const SizedBox(width: _menuIconGap),
              Text(
                item.label,
                style: TextStyle(
                  color: color,
                  fontSize: _menuFontSize,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  letterSpacing: _menuLetterSpacing,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 검색 칸(넓으면 `검색 · Ctrl K` 칸, 아니면 돋보기 아이콘). 누르면 검색 창.
class _SearchButton extends StatelessWidget {
  const _SearchButton({required this.full});

  final bool full;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    if (!full) {
      return IconButton(
        key: const ValueKey('command-palette-button'),
        tooltip: _searchTooltip,
        icon: Icon(Icons.search, color: palette.textMuted),
        onPressed: () => showCommandPalette(context),
      );
    }
    return Tooltip(
      message: _searchTooltip,
      child: InkWell(
        key: const ValueKey('command-palette-button'),
        onTap: () => showCommandPalette(context),
        child: Container(
          width: _searchWidth,
          height: _searchHeight,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(color: palette.background, border: Border.all(color: palette.border)),
          child: Row(
            children: [
              Icon(Icons.search, size: 18, color: palette.textMuted),
              const SizedBox(width: 8),
              Text(_searchLabel, style: TextStyle(color: palette.textMuted)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(border: Border.all(color: palette.border)),
                child: Text(kCommandPaletteShortcutLabel, style: TextStyle(color: palette.textMuted, fontSize: 11)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Agent 연결 상태 칩: 점(수신 중 초록 · 연결됐지만 데이터 없음 앰버 · 연결 없음 회색) + 짧은 글자. 누르면 Telemetry App.
class _AgentChip extends ConsumerWidget {
  const _AgentChip({required this.location, required this.full});

  final String location;
  final bool full;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final devices = ref.watch(agentDevicesProvider).valueOrNull;
    final now = ref.watch(clockProvider)();
    final kind = devices == null ? null : connectionKindOf(devices, now);
    final (label, color) = switch (kind) {
      ConnectionKind.receiving => ('Agent 수신 중', AppColors.success),
      ConnectionKind.stale || ConnectionKind.neverReceived => ('Agent 대기', AppColors.accent),
      ConnectionKind.noDevices => ('Agent 연결 필요', palette.textMuted),
      null => ('Agent', palette.textMuted),
    };
    final status = devices == null ? telemetryAppNavItem.label : connectionStatusText(devices, now);
    final selected = isNavItemSelected(telemetryAppNavItem, location);
    return Tooltip(
      message: '$status\n${telemetryAppNavItem.label} 열기',
      child: InkWell(
        key: const ValueKey('agent-status-chip'),
        onTap: () => context.go(telemetryAppNavItem.path),
        child: Container(
          height: _searchHeight,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            border: Border.all(color: selected ? AppColors.accent : palette.border),
            color: selected ? AppColors.accent.withValues(alpha: _selectedTileAlpha) : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: _statusDotSize,
                height: _statusDotSize,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              if (full)
                Text(label, style: TextStyle(color: palette.textPrimary, fontSize: 13, fontWeight: FontWeight.w600))
              else
                Icon(telemetryAppNavItem.icon, size: 18, color: palette.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// 계정 메뉴(프로필 사진): 이름, 계정 설정, Telemetry App, 로그아웃.
class _AccountMenu extends ConsumerWidget {
  const _AccountMenu({required this.location});

  final String location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).valueOrNull;
    final displayName = user?.displayName ?? '';
    final palette = context.palette;
    return MenuAnchor(
      alignmentOffset: const Offset(-180, 6),
      menuChildren: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text(displayName, style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
        const Divider(height: 1),
        MenuItemButton(
          key: const ValueKey('account-settings'),
          leadingIcon: const Icon(Icons.settings_outlined),
          onPressed: () => context.go(kSettingsPath),
          child: const Text(_accountSettingsLabel),
        ),
        MenuItemButton(
          key: const ValueKey('account-telemetry-app'),
          leadingIcon: Icon(telemetryAppNavItem.icon),
          onPressed: () => context.go(telemetryAppNavItem.path),
          child: Text(telemetryAppNavItem.label),
        ),
        const Divider(height: 1),
        MenuItemButton(
          key: const ValueKey('account-logout'),
          leadingIcon: Icon(Icons.logout, color: palette.textMuted),
          onPressed: () => signOut(ref),
          child: const Text(_logoutLabel),
        ),
      ],
      builder: (context, controller, _) => Tooltip(
        message: _accountTooltip,
        child: InkWell(
          key: const ValueKey('account-menu'),
          customBorder: const CircleBorder(),
          onTap: () => controller.isOpen ? controller.close() : controller.open(),
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: location == kSettingsPath ? AppColors.accent : Colors.transparent, width: 2),
            ),
            child: TeamAvatar(teamCode: user?.preferences.avatarTeam, displayName: displayName, size: _accountAvatarSize),
          ),
        ),
      ),
    );
  }
}

/// 좁은 화면의 서랍 메뉴: 브랜드, 모든 메뉴(+ Telemetry App), 아래 프로필(계정 설정)과 로그아웃.
class _DrawerMenu extends ConsumerWidget {
  const _DrawerMenu({required this.location});

  final String location;

  void _navigate(BuildContext context, String path) {
    Scaffold.of(context).closeDrawer();
    context.go(path);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).valueOrNull;

    return Material(
      color: context.palette.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(padding: EdgeInsets.fromLTRB(20, 20, 20, 16), child: _Brand()),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: _drawerPadding),
                children: [
                  for (final item in [...navItems, telemetryAppNavItem])
                    _NavTile(
                      item: item,
                      selected: isNavItemSelected(item, location),
                      onTap: () => _navigate(context, item.path),
                    ),
                ],
              ),
            ),
            const Divider(),
            _UserFooter(
              displayName: user?.displayName ?? '',
              avatarTeam: user?.preferences.avatarTeam,
              selected: location == kSettingsPath,
              onOpenSettings: () => _navigate(context, kSettingsPath),
              onLogout: () => signOut(ref),
            ),
          ],
        ),
      ),
    );
  }
}

/// 브랜드: 로고 + `SimHub` + 계기판 눈금처럼 비스듬한 앰버 밑줄.
class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const BrandMark(),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _brandName,
              maxLines: 1,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: _brandLetterSpacing),
            ),
            const SizedBox(height: _brandUnderlineGap),
            Transform(
              transform: Matrix4.skewX(-0.35),
              child: Container(width: _brandUnderlineWidth, height: _brandUnderlineHeight, color: AppColors.accent),
            ),
          ],
        ),
      ],
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({required this.item, required this.selected, required this.onTap});

  final NavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: _navItemGap),
      // 선택 = 왼쪽 앰버 막대 + 옅은 앰버 줄(오른쪽 아래를 깎음) + 앰버 글자·아이콘.
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: selected ? AppColors.accent : Colors.transparent, width: _navBarWidth)),
        ),
        child: ListTile(
          selected: selected,
          minTileHeight: _navItemHeight,
          contentPadding: const EdgeInsets.symmetric(horizontal: _navItemPaddingX),
          horizontalTitleGap: _navIconGap,
          minLeadingWidth: _navIconSize,
          visualDensity: VisualDensity.compact,
          selectedColor: palette.link,
          selectedTileColor: AppColors.accent.withValues(alpha: _selectedTileAlpha),
          iconColor: palette.textMuted,
          textColor: palette.textPrimary,
          titleTextStyle: TextStyle(
            fontSize: _navFontSize,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            letterSpacing: _navLetterSpacing,
          ),
          shape: const BeveledRectangleBorder(borderRadius: BorderRadius.only(bottomRight: Radius.circular(_navChamfer))),
          leading: Icon(item.icon, size: _navIconSize),
          title: Text(item.label),
          onTap: onTap,
        ),
      ),
    );
  }
}

/// 서랍 아래: 프로필 사진 + 이름 + "계정 설정"(누르면 `/settings`, docs/14 §8) 과 로그아웃 아이콘.
class _UserFooter extends StatelessWidget {
  const _UserFooter({
    required this.displayName,
    required this.avatarTeam,
    required this.selected,
    required this.onOpenSettings,
    required this.onLogout,
  });

  final String displayName;
  final String? avatarTeam;

  /// 설정 화면을 보고 있는지(강조 표시).
  final bool selected;
  final VoidCallback onOpenSettings;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(_drawerPadding, 8, 8, 12),
      child: Row(
        children: [
          Expanded(
            child: Material(
              color: selected ? AppColors.accent.withValues(alpha: _selectedTileAlpha) : Colors.transparent,
              shape: const BeveledRectangleBorder(borderRadius: BorderRadius.only(topRight: Radius.circular(_footerChamfer))),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                key: const ValueKey('drawer-account-settings'),
                onTap: onOpenSettings,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      TeamAvatar(teamCode: avatarTeam, displayName: displayName, size: _footerAvatarSize),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            Text(
                              _accountSettingsLabel,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: palette.textMuted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: _logoutLabel,
            icon: Icon(Icons.logout, color: palette.textMuted),
            onPressed: onLogout,
          ),
        ],
      ),
    );
  }
}
