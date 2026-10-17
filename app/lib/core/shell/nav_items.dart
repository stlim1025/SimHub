import 'package:flutter/material.dart';

/// 셸 메뉴 한 항목.
class NavItem {
  const NavItem({required this.label, required this.icon, required this.path});

  final String label;
  final IconData icon;
  final String path;
}

/// P6 메뉴(docs/11 §7.2). Telemetry App은 해당 화면이 생길 때 추가한다.
const List<NavItem> navItems = [
  NavItem(label: 'Dashboard', icon: Icons.dashboard_outlined, path: '/'),
  NavItem(label: 'Laps', icon: Icons.timer_outlined, path: '/laps'),
  NavItem(label: 'Leaderboard', icon: Icons.emoji_events_outlined, path: '/leaderboard'),
];

/// [location](쿼리 제외 경로)이 [item] 또는 그 하위 경로이면 선택 상태.
/// 루트(`/`)는 모든 경로의 접두사이므로 정확히 일치할 때만 선택한다.
bool isNavItemSelected(NavItem item, String location) {
  if (item.path == '/') {
    return location == '/';
  }
  return location == item.path || location.startsWith('${item.path}/');
}
