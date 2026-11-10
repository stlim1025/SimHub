import 'package:flutter/material.dart';

/// 셸 메뉴 한 항목. [aliases]는 이 메뉴로 보는 다른 경로(그 아래 경로도 이 메뉴가 선택된다).
class NavItem {
  const NavItem({required this.label, required this.icon, required this.path, this.aliases = const []});

  final String label;
  final IconData icon;
  final String path;
  final List<String> aliases;
}

/// 위쪽 바 메뉴(B안 화면 개편). Setups는 같은 트랙 고르기 화면을 쓰던 Tracks에 합쳤다 —
/// 트랙 화면 안의 셋업 탭으로 가고, 예전 `/setups` 주소도 Tracks 메뉴로 본다.
/// Leaderboard는 혼자 쓰는 동안 의미가 없어 메뉴에서 뺐다(`/leaderboard` 주소와 화면은 남아 있다).
const List<NavItem> navItems = [
  NavItem(label: 'Dashboard', icon: Icons.dashboard_outlined, path: '/'),
  NavItem(label: 'Seasons', icon: Icons.calendar_month_outlined, path: '/seasons'),
  NavItem(label: 'Sessions', icon: Icons.flag_outlined, path: '/sessions'),
  NavItem(label: 'Laps', icon: Icons.timer_outlined, path: '/laps'),
  NavItem(label: 'Tracks', icon: Icons.route_outlined, path: '/tracks', aliases: ['/setups']),
];

/// Telemetry App(Agent 내려받기·연결). 넓은 화면은 위쪽 바 오른쪽 Agent 상태 칩, 좁은 화면은 서랍 메뉴 맨 아래에서 연다.
const NavItem telemetryAppNavItem = NavItem(label: 'Telemetry App', icon: Icons.sensors, path: '/telemetry-app');

/// [location](쿼리 제외 경로)이 [item](또는 그 별칭) 또는 그 하위 경로이면 선택 상태.
/// 루트(`/`)는 모든 경로의 접두사이므로 정확히 일치할 때만 선택한다.
bool isNavItemSelected(NavItem item, String location) {
  if (item.path == '/') {
    return location == '/';
  }
  return [item.path, ...item.aliases].any((path) => location == path || location.startsWith('$path/'));
}
