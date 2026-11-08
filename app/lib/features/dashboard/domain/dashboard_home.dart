import '../../laps/domain/lap_models.dart';
import '../../sessions/domain/session_detail_display.dart';
import '../../sessions/domain/session_display.dart';
import '../../sessions/domain/session_models.dart';

/// 홈 Personal Bests 카드에 보여 줄 트랙 수.
const int kPersonalBestCount = 5;

/// 하이라이트(레이스 리플레이)를 만들 수 있는 세션 유형.
const String _raceSessionType = 'Race';

/// 세션 목록에서 가장 최근에 끝난(분류된) 세션. 목록이 비었으면 null(순수 함수).
SessionSummary? latestSession(List<SessionSummary> sessions) {
  SessionSummary? latest;
  for (final session in sessions) {
    if (latest == null || session.classifiedAt.isAfter(latest.classifiedAt)) {
      latest = session;
    }
  }
  return latest;
}

/// 출발 순위 - 결승 순위(올라간 자리 수, 내려갔으면 음수). 둘 중 하나라도 모르면 null(순수 함수).
int? positionsGained({required int? grid, required int? finish}) =>
    grid == null || finish == null ? null : grid - finish;

/// 순위 변화 글자: 올라가면 `+4`, 내려가면 `-2`, 그대로면 `±0`(순수 함수).
String positionsGainedText(int gained) => gained > 0 ? '+$gained' : (gained < 0 ? '$gained' : '±0');

/// Last Race 타일이 세션 상세에서 더 읽어 오는 값. 상세를 아직 받지 못했거나 못 읽었으면 [lastRaceExtrasOf]가 빈 값을 준다.
class LastRaceExtras {
  const LastRaceExtras({
    this.round,
    this.pitStops,
    this.winnerGap,
    this.fastestLap = false,
    this.hasHighlights = false,
  });

  /// 시즌 안의 라운드 번호. 시즌이 아니거나 모르면 null.
  final int? round;

  /// 내 피트 스톱 횟수. 내 결과가 없으면 null.
  final int? pitStops;

  /// 우승자와의 차(`+0:04.218`, 랩 뒤처지면 `+1 Lap`). 내가 우승했거나 완주하지 못했거나 모르면 null.
  final String? winnerGap;

  /// 내 베스트 랩이 그 레이스 전체 최고 랩인지.
  final bool fastestLap;

  /// 하이라이트(모든 차 표본으로 만든 레이스 리플레이)를 열 수 있는지.
  final bool hasHighlights;
}

/// 세션 상세 → Last Race 타일 보조 값. [detail]이 null이면 빈 값(순수 함수).
LastRaceExtras lastRaceExtrasOf(SessionDetail? detail) {
  if (detail == null) {
    return const LastRaceExtras();
  }
  final header = detail.header;
  final hasHighlights = header.sessionType == _raceSessionType && header.hasFieldSamples;
  SessionResult? mine;
  for (final row in detail.results) {
    if (row.isPlayer) {
      mine = row;
      break;
    }
  }
  if (mine == null) {
    return LastRaceExtras(round: header.round, hasHighlights: hasHighlights);
  }
  final finished = isRunningOrFinished(mine.resultStatus);
  final reference = referenceRow(detail.results, isRace: true);
  final winnerGap = !finished || reference == null || reference.carIndex == mine.carIndex
      ? null
      : classificationGapText(mine, reference, isRace: true);
  return LastRaceExtras(
    round: header.round,
    pitStops: mine.numPitStops,
    winnerGap: winnerGap == kNoValueText ? null : winnerGap,
    fastestLap: mine.isFastestLap,
    hasHighlights: hasHighlights,
  );
}

/// 유효 랩 기록이 있는 트랙만, 최근에 달린 트랙부터 [count]개(Personal Bests 카드, 순수 함수).
List<MyTrack> recentPersonalBests(List<MyTrack> tracks, {int count = kPersonalBestCount}) {
  final withBest = [
    for (final track in tracks)
      if (track.bestValidLapTimeMs != null) track,
  ]..sort((a, b) => b.lastSetAt.compareTo(a.lastSetAt));
  return withBest.take(count).toList();
}

/// 트랙 이름 → 그 트랙의 내 최고 유효 랩(ms). 유효 랩이 없는 트랙은 빠진다(순수 함수).
Map<String, int> personalBestByTrackName(List<MyTrack> tracks) => {
      for (final track in tracks) track.trackName: ?track.bestValidLapTimeMs,
    };

/// 최근 랩과 그 트랙 최고 랩의 차(ms, 0이면 그 랩이 최고 랩). 무효 랩이거나 그 트랙 최고 랩을 모르면 null(순수 함수).
int? gapToPersonalBest(Lap lap, Map<String, int> bests) {
  final best = bests[lap.trackName];
  return !lap.isValid || best == null ? null : lap.lapTimeMs - best;
}
