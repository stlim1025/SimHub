import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/application/sign_out.dart';
import '../../features/live_laps/application/live_laps_controller.dart';
import '../../features/live_laps/presentation/new_lap_snack_bar.dart';
import '../../features/profile/presentation/team_avatar.dart';
import '../config/app_config.dart';
import '../layout/page_padding.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
import '../widgets/brand_mark.dart';
import '../widgets/page_loading_bar.dart';
import 'nav_items.dart';

/// 이 너비(논리 px) 이상이면 고정 사이드바, 미만이면 상단 바 + 서랍 메뉴.
const double kSidebarBreakpoint = 900;

/// 사이드바 폭.
const double kSidebarWidth = 220;

/// 계정 설정 화면 경로(사이드바 하단 프로필에서 연다, docs/14 §8).
const String kSettingsPath = '/settings';

const double _sidebarPadding = 12;
const double _selectedTileAlpha = 0.12;

// 좌측 메뉴 치수(웹 대시보드처럼 글자·아이콘을 키우고 줄 간격을 둔다, F1Laps 참고).
const double _navItemHeight = 40;
const double _navItemGap = 2;
const double _navItemPaddingX = 12;
const double _navIconSize = 20;
const double _navIconGap = 12;
const double _navFontSize = 16;
/// 선택된 메뉴 줄의 오른쪽 아래를 깎는 크기·왼쪽 앰버 막대 굵기.
const double _navChamfer = 12;
const double _navBarWidth = 3;
const double _navLetterSpacing = 0.8;
const double _brandLetterSpacing = 1.2;
const double _brandUnderlineWidth = 36;
const double _brandUnderlineHeight = 3;
const double _brandUnderlineGap = 6;
const double _footerChamfer = 10;
const double _footerAvatarSize = 32;
const String _brandName = AppConfig.brandName;
const String _accountSettingsLabel = '계정 설정';

/// 로그인 후 화면의 공통 셸(docs/11 §7.2). 넓으면 왼쪽 사이드바, 좁으면 상단 바 + 서랍.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.child, required this.location});

  /// 현재 경로의 화면.
  final Widget child;

  /// 현재 경로(쿼리 제외). 선택된 메뉴를 표시하는 데 쓴다.
  final String location;

  /// 레이아웃이 바뀌어도(사이드바 ↔ 서랍) 화면 상태가 유지되도록 하는 키.
  static const _contentKey = ValueKey('app-shell-content');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 로그인한 셸에 있는 동안 내 새 랩을 듣고, 받으면 어느 화면이든 아래 알림을 띄운다(D-50, docs/15 §9).
    ref.listen<LiveLapEvent?>(liveLapsControllerProvider, (_, next) {
      if (next != null) {
        showNewLapSnackBar(context, next.lap);
      }
    });

    final content = Expanded(
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= kSidebarBreakpoint;
        return Scaffold(
          appBar: wide ? null : const _NarrowAppBar(),
          drawer: wide
              ? null
              : Drawer(
                  width: kSidebarWidth,
                  child: _Sidebar(location: location, closeDrawerOnNavigate: true),
                ),
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (wide)
                SizedBox(
                  width: kSidebarWidth,
                  child: _Sidebar(location: location, closeDrawerOnNavigate: false),
                ),
              content,
            ],
          ),
        );
      },
    );
  }
}

class _NarrowAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _NarrowAppBar();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      automaticallyImplyLeading: false,
      leading: Builder(
        builder: (context) => IconButton(
          tooltip: '메뉴 열기',
          icon: const Icon(Icons.menu),
          onPressed: () => Scaffold.of(context).openDrawer(),
        ),
      ),
      title: const Text(_brandName),
    );
  }
}

class _Sidebar extends ConsumerWidget {
  const _Sidebar({required this.location, required this.closeDrawerOnNavigate});

  final String location;
  final bool closeDrawerOnNavigate;

  void _navigate(BuildContext context, String path) {
    if (closeDrawerOnNavigate) {
      Scaffold.of(context).closeDrawer();
    }
    context.go(path);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).valueOrNull;

    return Material(
      color: context.palette.surface,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(right: BorderSide(color: context.palette.border)),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _Brand(),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: _sidebarPadding),
                  children: [
                    for (final item in navItems)
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
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Row(
        children: [
          const BrandMark(),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _brandName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: _brandLetterSpacing),
                ),
                const SizedBox(height: _brandUnderlineGap),
                // 계기판 눈금처럼 비스듬한 앰버 밑줄.
                Transform(
                  transform: Matrix4.skewX(-0.35),
                  child: Container(width: _brandUnderlineWidth, height: _brandUnderlineHeight, color: AppColors.accent),
                ),
              ],
            ),
          ),
        ],
      ),
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

/// 사이드바 하단: 프로필 사진 + 이름 + "계정 설정"(누르면 `/settings`, docs/14 §8) 과 로그아웃 아이콘.
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
      padding: const EdgeInsets.fromLTRB(_sidebarPadding, 8, 8, 12),
      child: Row(
        children: [
          Expanded(
            child: Material(
              color: selected ? AppColors.accent.withValues(alpha: _selectedTileAlpha) : Colors.transparent,
              shape: const BeveledRectangleBorder(borderRadius: BorderRadius.only(topRight: Radius.circular(_footerChamfer))),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                key: const ValueKey('account-settings'),
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
            tooltip: '로그아웃',
            icon: Icon(Icons.logout, color: palette.textMuted),
            onPressed: onLogout,
          ),
        ],
      ),
    );
  }
}
