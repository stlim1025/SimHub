import 'race_highlights.dart';

/// 중계 그래픽(F1TV 모양 드라이버 이름 자막·레이스 컨트롤 메시지)의 순수 계산.

/// F1 25·26 그리드 드라이버의 이름(성 대문자 → 이름). 게임은 AI 드라이버를 성만 보낸다 — 자막 윗줄의 이름을 채우는 데 쓴다.
/// 표에 없는 이름(내 이름·사용자 드라이버)은 성 줄만 쓴다.
const Map<String, String> _firstNames = {
  'ALBON': 'Alexander',
  'ALONSO': 'Fernando',
  'ANTONELLI': 'Kimi',
  'BEARMAN': 'Oliver',
  'BORTOLETO': 'Gabriel',
  'BOTTAS': 'Valtteri',
  'COLAPINTO': 'Franco',
  'DOOHAN': 'Jack',
  'GASLY': 'Pierre',
  'HADJAR': 'Isack',
  'HAMILTON': 'Lewis',
  'HULKENBERG': 'Nico',
  'HÜLKENBERG': 'Nico',
  'LAWSON': 'Liam',
  'LECLERC': 'Charles',
  'LINDBLAD': 'Arvid',
  'NORRIS': 'Lando',
  'OCON': 'Esteban',
  'PEREZ': 'Sergio',
  'PÉREZ': 'Sergio',
  'PIASTRI': 'Oscar',
  'RUSSELL': 'George',
  'SAINZ': 'Carlos',
  'STROLL': 'Lance',
  'TSUNODA': 'Yuki',
  'VERSTAPPEN': 'Max',
};

/// 자막에 쓰는 이름 두 줄: 윗줄 이름(모르면 null), 아랫줄 성(대문자).
typedef DriverNameLines = ({String? first, String last});

/// 차 이름 → 자막 이름 두 줄(순수 함수). `Max VERSTAPPEN`처럼 띄어 쓴 이름은 마지막 낱말이 성이고,
/// 한 낱말이면 그 낱말이 성이며 이름은 그리드 표에서 찾는다.
DriverNameLines broadcastDriverName(String name) {
  final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) {
    return (first: null, last: '');
  }
  final last = words.last.toUpperCase();
  return (first: words.length > 1 ? words.take(words.length - 1).join(' ') : _firstNames[last], last: last);
}

const int _tens = 10;
const int _hundred = 100;
const int _teenLow = 11;
const int _teenHigh = 13;

/// 영어 서수 접미사(대문자): 1 → `ST`, 2 → `ND`, 3 → `RD`, 4 → `TH`, 11~13 → `TH`, 21 → `ST`(순수 함수).
String ordinalSuffix(int n) {
  final lastTwo = n.abs() % _hundred;
  if (lastTwo >= _teenLow && lastTwo <= _teenHigh) {
    return 'TH';
  }
  return switch (lastTwo % _tens) {
    1 => 'ST',
    2 => 'ND',
    3 => 'RD',
    _ => 'TH',
  };
}

/// 드라이버 이름 자막 오른쪽 칸에 무엇을 보일지.
sealed class LowerThirdDetail {
  const LowerThirdDetail();
}

/// 차 번호(기본).
final class LowerThirdNumber extends LowerThirdDetail {
  const LowerThirdNumber();
}

/// `CHASING NORRIS FOR 8TH`: 앞차([otherCar])와 그 차가 지키는 순위([position]).
final class LowerThirdChasing extends LowerThirdDetail {
  const LowerThirdChasing({required this.otherCar, required this.position});

  final int otherCar;
  final int position;
}

/// `RACE STORY — STARTED: 10TH · NOW: 9TH`. [finished]면 `NOW` 대신 `FINISHED`.
final class LowerThirdStory extends LowerThirdDetail {
  const LowerThirdStory({required this.started, required this.now, this.finished = false});

  final int started;
  final int now;
  final bool finished;
}

/// `RACE WINNER`(결승선을 1위로 지난 뒤).
final class LowerThirdWinner extends LowerThirdDetail {
  const LowerThirdWinner();
}

/// 클립 [clip]의 [timeMs] 순간 순위표에서 차 [carIndex]의 순위(1부터). 순위표가 없거나 그 차가 없으면 null(순수 함수).
int? highlightPositionAt(HighlightClip clip, double timeMs, int carIndex) {
  final standing = clip.standingAt(timeMs);
  if (standing == null) {
    return null;
  }
  final index = standing.rows.indexWhere((row) => row.carIndex == carIndex);
  return index < 0 ? null : index + 1;
}

/// 드라이버 이름 자막 오른쪽 칸(순수 함수). [gridPosition]은 중심 차의 출발 순위(모르면 null).
/// - 추월 클립: 추월 전에는 `CHASING {앞차} FOR {그 순위}`, 추월한 뒤에는 레이스 스토리(출발 순위 → 지금 순위).
/// - 출발 클립: 레이스 스토리.
/// - 결승 클립: 결승선을 지난 뒤 1위면 `RACE WINNER`, 아니면 레이스 스토리(`FINISHED`).
/// - 그 밖·필요한 순위를 모를 때: 차 번호.
LowerThirdDetail lowerThirdDetail(HighlightClip clip, double timeMs, {int? gridPosition}) {
  final now = highlightPositionAt(clip, timeMs, clip.focusCar);
  LowerThirdDetail story({bool finished = false}) => gridPosition != null && gridPosition > 0 && now != null
      ? LowerThirdStory(started: gridPosition, now: now, finished: finished)
      : const LowerThirdNumber();

  switch (clip.kind) {
    case HighlightKind.overtake:
      final other = clip.otherCar;
      if (other == null || timeMs >= clip.eventMs) {
        return story();
      }
      final target = highlightPositionAt(clip, timeMs, other);
      return target == null ? const LowerThirdNumber() : LowerThirdChasing(otherCar: other, position: target);
    case HighlightKind.start:
      return story();
    case HighlightKind.finish:
      if (timeMs < clip.eventMs) {
        return const LowerThirdNumber();
      }
      return now == 1 ? const LowerThirdWinner() : story(finished: true);
    case HighlightKind.collision:
    case HighlightKind.crash:
    case HighlightKind.retirement:
    case HighlightKind.safetyCar:
    case HighlightKind.virtualSafetyCar:
    case HighlightKind.redFlag:
    case HighlightKind.unknown:
      return const LowerThirdNumber();
  }
}

/// 레이스 컨트롤 메시지(중계 그래픽이라 영어, 순수 함수): 장면 순간([HighlightClip.eventMs])부터 띄운다.
/// 충돌 `TURN 4 INCIDENT INVOLVING VERSTAPPEN AND RUSSELL NOTED`, 벽 충돌 `… INCIDENT INVOLVING LECLERC NOTED`,
/// 리타이어 `LECLERC RETIRED FROM THE RACE`. 그 밖의 장면·장면 순간 전이면 null. [turn]은 장면이 난 코너 번호(모르면 생략).
String? raceControlMessage(HighlightClip clip, double timeMs, String Function(int carIndex) nameOf, {String? turn}) {
  if (timeMs < clip.eventMs) {
    return null;
  }
  final focus = broadcastDriverName(nameOf(clip.focusCar)).last;
  final other = clip.otherCar == null ? null : broadcastDriverName(nameOf(clip.otherCar!)).last;
  final where = turn == null ? '' : 'TURN $turn ';
  return switch (clip.kind) {
    HighlightKind.collision when other != null => '${where}INCIDENT INVOLVING $focus AND $other NOTED',
    HighlightKind.collision || HighlightKind.crash => '${where}INCIDENT INVOLVING $focus NOTED',
    HighlightKind.retirement => '$focus RETIRED FROM THE RACE',
    _ => null,
  };
}
