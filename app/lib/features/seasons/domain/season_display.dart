import 'package:intl/intl.dart';

import '../../sessions/domain/session_display.dart';
import 'season_models.dart';

/// Seasons 목록의 한 페이지 크기(docs/12 §8.3). 서버 최대값과 같다.
const int kSeasonsPageSize = 20;

/// Results 표의 행 높이. 이름 열(`Column`)과 스크롤되는 본문(`Column`)이 같은 값을 써서 행이 어긋나지 않는다.
const double kResultsRowHeight = 40;

/// Results 표에서 가로 스크롤하지 않고 고정해 두는 이름 열의 폭.
const double kResultsNameColumnWidth = 180;

/// 시상대 순위(1~3위).
const int _podiumPlaces = 3;

// -- 탭 (`/seasons/:id?tab=`) --------------------------------------------------

const String kSeasonTabSeason = 'season';
const String kSeasonTabResults = 'results';
const String kSeasonTabStandings = 'standings';

/// 화면에 보이는 순서.
const List<String> kSeasonTabs = [kSeasonTabSeason, kSeasonTabResults, kSeasonTabStandings];

/// 주소의 `tab` 값을 탭으로 바꾼다. 없거나 모르는 값이면 `season`(docs/12 §8.1).
String normalizeSeasonTab(String? value) => kSeasonTabs.contains(value) ? value! : kSeasonTabSeason;

/// 시즌 상세 주소. [tab]은 `season`·`results`·`standings`.
String seasonLocation(String seasonId, {String tab = kSeasonTabSeason}) => '/seasons/$seasonId?tab=$tab';

// -- 라벨 --------------------------------------------------------------------

final DateFormat _dateFormat = DateFormat('yyyy.MM.dd');

/// 로컬 시간대의 `yyyy.MM.dd`.
String formatSeasonDate(DateTime value) => _dateFormat.format(value.toLocal());

/// 시즌 표시 이름: `Driver Career · 2026.10.17`(게임 모드 라벨 + 시작 날짜, docs/12 §8.3).
String seasonTitle(SeasonSummary season) =>
    '${gameModeLabel(season.gameMode)} · ${formatSeasonDate(season.firstSessionAt)}';

/// 시즌 기간: `2026.10.17 ~ 2026.11.02`. 하루 안에 끝났으면 날짜 하나만.
String seasonPeriodLabel(SeasonSummary season) {
  final first = formatSeasonDate(season.firstSessionAt);
  final last = formatSeasonDate(season.lastSessionAt);
  return first == last ? first : '$first ~ $last';
}

/// 내 순위·점수: `P3 · 87 pts`. 내 결과가 없으면 `-`.
String myStandingLabel(int? position, int? points) {
  if (position == null) {
    return kNoValueText;
  }
  return points == null ? 'P$position' : 'P$position · $points pts';
}

/// 선두: `VERSTAPPEN 120`. 결과가 하나도 없으면 `-`.
String leaderLabel(String? name, int? points) {
  if (name == null) {
    return kNoValueText;
  }
  return points == null ? name : '$name $points';
}

/// 라운드 수: `6 rounds`.
String roundsLabel(int count) => '$count rounds';

// -- Results 칸 · 세션 칩 -------------------------------------------------------

/// 칸이 순위 숫자를 보이는 칸인가: 본 레이스 기록이 있고 끝까지 달렸다(Finished·Active).
bool standingCellShowsPosition(StandingCell? cell) {
  final status = cell?.resultStatus;
  return status != null && cell?.position != null && isRunningOrFinished(status);
}

/// Results 표 칸의 글자. 끝까지 달렸으면 순위, 완주하지 못했으면 상태 라벨(DNF·DSQ·NC·RET), 기록이 없으면 `-`.
String standingCellText(StandingCell? cell) {
  if (cell == null) {
    return kNoValueText;
  }
  if (standingCellShowsPosition(cell)) {
    return '${cell.position}';
  }
  final status = cell.resultStatus;
  return status != null && !isRunningOrFinished(status) ? resultStatusLabel(status) : kNoValueText;
}

/// 칸이 끝까지 달린 1·2·3위이면 그 순위, 아니면 null(금·은·동 색 판정용).
int? standingCellPodiumPlace(StandingCell? cell) {
  if (cell == null || !standingCellShowsPosition(cell)) {
    return null;
  }
  final position = cell.position!;
  return position >= 1 && position <= _podiumPlaces ? position : null;
}

/// Season 탭 세션 칩에 붙는 내 결과. 완주하지 못했으면 상태 라벨, 아니면 `P4`. 내 결과가 없으면 null.
String? sessionChipResult(int? position, String? status) {
  if (status != null && !isRunningOrFinished(status)) {
    final label = resultStatusLabel(status);
    if (label != kNoValueText) {
      return label;
    }
  }
  return position == null ? null : 'P$position';
}
