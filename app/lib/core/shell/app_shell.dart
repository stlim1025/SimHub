import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/application/auth_controller.dart';
import '../layout/layout_constants.dart';
import '../realtime/ranking_hub_client.dart';
import '../theme/app_colors.dart';
import 'nav_items.dart';

/// 이 너비(논리 px) 이상이면 고정 사이드바, 미만이면 상단 바 + 서랍 메뉴.
const double kSidebarBreakpoint = 900;

/// 사이드바 폭.
const double kSidebarWidth = 220;

const double _sidebarPadding = 12;
const double _selectedTileAlpha = 0.14;
const String _brandName = 'SimCenter';

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
    final content = Expanded(
      key: _contentKey,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kContentMaxWidth),
          child: child,
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
      Navigator.of(context).pop();
    }
    context.go(path);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final displayName = ref.watch(authControllerProvider).valueOrNull?.displayName ?? '';

    return Material(
      color: AppColors.surface,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(right: BorderSide(color: AppColors.border)),
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
              _UserFooter(displayName: displayName, onLogout: () => _logout(ref)),
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
          const Icon(Icons.speed, color: AppColors.accent),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              _brandName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        dense: true,
        selected: selected,
        selectedColor: AppColors.textPrimary,
        selectedTileColor: AppColors.accent.withValues(alpha: _selectedTileAlpha),
        iconColor: AppColors.textMuted,
        textColor: AppColors.textMuted,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        leading: Icon(item.icon, color: selected ? AppColors.accent : null),
        title: Text(item.label),
        onTap: onTap,
      ),
    );
  }
}

class _UserFooter extends StatelessWidget {
  const _UserFooter({required this.displayName, required this.onLogout});

  final String displayName;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 8, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          IconButton(
            tooltip: '로그아웃',
            icon: const Icon(Icons.logout, color: AppColors.textMuted),
            onPressed: onLogout,
          ),
        ],
      ),
    );
  }
}

/// 허브 연결을 먼저 끊고 로그아웃한다. 허브 종료가 실패해도 로그아웃은 반드시 수행한다.
Future<void> _logout(WidgetRef ref) async {
  try {
    await ref.read(rankingHubClientProvider).stop();
  } catch (e) {
    debugPrint('랭킹 허브 종료 실패(로그아웃은 계속 진행): $e');
  }
  await ref.read(authControllerProvider.notifier).logout();
}
