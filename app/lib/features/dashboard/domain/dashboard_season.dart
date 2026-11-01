import '../../seasons/domain/season_models.dart';

/// 대시보드 "최근 결과"에 보여 줄 라운드 수.
const int kDashboardRecentRoundCount = 5;

/// 대시보드 순위 미리보기에서 항상 보이는 위쪽 순위 수.
const int kStandingsPreviewTop = 3;

/// 순위 미리보기에서 내 위·아래로 함께 보이는 드라이버 수.
const int _standingsPreviewNeighbours = 1;

/// 달린 라운드(주말이 기록된 라운드)를 최근 라운드부터 [count]개.
List<SeasonCalendarRound> recentCalendarRounds(
  List<SeasonCalendarRound> calendar, {
  int count = kDashboardRecentRoundCount,
}) {
  final driven = [for (final r in calendar) if (r.weekendId != null) r]..sort((a, b) => b.round.compareTo(a.round));
  return driven.take(count).toList();
}

/// 마지막으로 달린 라운드 다음의 아직 달리지 않은 라운드. 캘린더를 다 달렸거나 캘린더가 없으면 null.
SeasonCalendarRound? nextCalendarRound(List<SeasonCalendarRound> calendar) {
  final sorted = [...calendar]..sort((a, b) => a.round.compareTo(b.round));
  final lastDriven = sorted.lastIndexWhere((r) => r.weekendId != null);
  for (final round in sorted.skip(lastDriven + 1)) {
    if (round.weekendId == null) {
      return round;
    }
  }
  return null;
}

/// 진행 라운드 수: 달린 라운드 / 캘린더 라운드. 캘린더가 없으면 기록된 라운드 수만(전체는 null).
({int driven, int? total}) roundProgress(SeasonDetail detail) {
  if (detail.calendar.isEmpty) {
    return (driven: detail.rounds.length, total: null);
  }
  final driven = detail.calendar.where((r) => r.weekendId != null).length;
  return (driven: driven, total: detail.calendar.length);
}

/// Standings에서 내 줄. 내 결과가 없으면 null.
DriverStanding? myStanding(List<DriverStanding> drivers) {
  for (final driver in drivers) {
    if (driver.isPlayer) {
      return driver;
    }
  }
  return null;
}

/// 선두와의 점수 차. 내가 선두면 2위와의 차(0 이상), 아니면 선두와의 차(0 이하). 비교할 상대가 없으면 null.
({int gap, DriverStanding rival})? leaderGap(List<DriverStanding> drivers) {
  final me = myStanding(drivers);
  if (me == null || drivers.length < 2) {
    return null;
  }
  final sorted = [...drivers]..sort((a, b) => a.position.compareTo(b.position));
  final rival = identical(sorted.first, me) ? sorted[1] : sorted.first;
  return (gap: me.points - rival.points, rival: rival);
}

/// 순위 미리보기 줄: 위쪽 [kStandingsPreviewTop]명 + 내 앞뒤 한 명씩(순위 순, 중복 없음).
/// 내 결과가 없으면 위쪽만.
List<DriverStanding> standingsPreview(List<DriverStanding> drivers) {
  final sorted = [...drivers]..sort((a, b) => a.position.compareTo(b.position));
  final picked = <int>{for (var i = 0; i < sorted.length && i < kStandingsPreviewTop; i++) i};
  final mine = sorted.indexWhere((d) => d.isPlayer);
  if (mine >= 0) {
    for (var i = mine - _standingsPreviewNeighbours; i <= mine + _standingsPreviewNeighbours; i++) {
      if (i >= 0 && i < sorted.length) {
        picked.add(i);
      }
    }
  }
  return [for (final i in picked.toList()..sort()) sorted[i]];
}
