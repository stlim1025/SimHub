import 'dart:math' as math;

import 'session_models.dart';

/// Sessions 목록의 한 페이지 크기(docs/12 §8.1). 서버 기본(20)과 별개로 앱이 보낸다.
const int kSessionsPageSize = 15;

/// 세션 결과 표가 Grid·Tyres·Pits·Pen 열을 숨기는 콘텐츠 폭(논리 px, docs/12 §8.4).
const double kSessionTableCompactWidth = 600;

/// 값이 없는 칸의 자리표시.
const String kNoValueText = '-';

const int _msPerSecond = 1000;
const int _secondsPerMinute = 60;
const int _msPerMinute = _msPerSecond * _secondsPerMinute;
const int _minutesPerHour = 60;
const int _msPerHour = _msPerMinute * _minutesPerHour;

// -- 필터 (`/sessions?type=`) ------------------------------------------------

const String kSessionFilterAll = 'all';
const String kSessionFilterRace = 'race';
const String kSessionFilterQualifying = 'qualifying';
const String kSessionFilterPractice = 'practice';

/// 화면에 보이는 순서.
const List<String> kSessionFilters = [
  kSessionFilterAll,
  kSessionFilterRace,
  kSessionFilterQualifying,
  kSessionFilterPractice,
];

/// 필터 → API `sessionType`(`all`은 필터 없음 = null).
const Map<String, String?> _sessionTypeByFilter = {
  kSessionFilterAll: null,
  kSessionFilterRace: 'Race',
  kSessionFilterQualifying: 'Qualifying',
  kSessionFilterPractice: 'Practice',
};

/// 주소의 `type` 값을 필터로 바꾼다. 없거나 모르는 값이면 `all`(docs/12 §8.1).
String normalizeSessionFilter(String? value) =>
    kSessionFilters.contains(value) ? value! : kSessionFilterAll;

/// 필터에 해당하는 API `sessionType`. `all`·모르는 값은 null(전체).
String? sessionTypeForFilter(String filter) => _sessionTypeByFilter[filter];

// -- 라벨 --------------------------------------------------------------------

const Map<String, String> _sessionKindLabels = {
  'Practice1': 'P1',
  'Practice2': 'P2',
  'Practice3': 'P3',
  'ShortPractice': 'P',
  'Qualifying1': 'Q1',
  'Qualifying2': 'Q2',
  'Qualifying3': 'Q3',
  'ShortQualifying': 'Q',
  'OneShotQualifying': 'OSQ',
  'SprintShootout1': 'SQ1',
  'SprintShootout2': 'SQ2',
  'SprintShootout3': 'SQ3',
  'ShortSprintShootout': 'SQ',
  'OneShotSprintShootout': 'OSSQ',
  'Race': 'R',
  'Race2': 'R2',
  'Race3': 'R3',
  'TimeTrial': 'TT',
};

/// 세션 종류 라벨(`Practice1` → `P1`, `Race` → `R`). `Unknown`과 모르는 값은 `-`(docs/12 §8.4).
String sessionKindLabel(String kind) => _sessionKindLabels[kind] ?? kNoValueText;

const Map<String, String> _resultStatusLabels = {
  'DidNotFinish': 'DNF',
  'Disqualified': 'DSQ',
  'NotClassified': 'NC',
  'Retired': 'RET',
  'Finished': '',
  'Active': '',
};

/// 결과 상태 라벨. Finished·Active는 라벨 없이 시간을 보여 주므로 빈 문자열, 그 밖의 모르는 값은 `-`.
String resultStatusLabel(String status) => _resultStatusLabels[status] ?? kNoValueText;

/// 끝까지 달렸거나(Finished) 아직 달리는 중(Active)인 상태.
bool isRunningOrFinished(String status) => status == 'Finished' || status == 'Active';

/// 게임 모드 라벨. 목록에 없는 값은 `Other`.
String gameModeLabel(String mode) => switch (mode) {
      'DriverCareer' => 'Driver Career',
      'MyTeamCareer' => 'My Team',
      'OnlineCareer' => 'Online Career',
      'ChallengeCareer' => 'Challenge Career',
      'GrandPrix' => 'Grand Prix',
      'TimeTrial' => 'Time Trial',
      'Online' => 'Online',
      'Story' => 'Story',
      _ => 'Other',
    };

// -- 시간·gap ----------------------------------------------------------------

String _two(int value) => value.toString().padLeft(2, '0');

String _three(int value) => value.toString().padLeft(3, '0');

/// 1시간 미만 `m:ss.SSS`, 이상 `h:mm:ss.SSS`. 음수는 0으로 본다(순수 함수).
String formatRaceTime(int ms) {
  final total = math.max(0, ms);
  final hours = total ~/ _msPerHour;
  final minutes = (total ~/ _msPerMinute) % _minutesPerHour;
  final seconds = (total ~/ _msPerSecond) % _secondsPerMinute;
  final tail = '${_two(seconds)}.${_three(total % _msPerSecond)}';
  return hours > 0 ? '$hours:${_two(minutes)}:$tail' : '${total ~/ _msPerMinute}:$tail';
}

/// 앞선 차와의 시간 차. 60초 미만 `+s.SSS`, 이상 `+m:ss.SSS`. 음수는 `+0.000`(순수 함수).
String formatGapMs(int ms) {
  final gap = math.max(0, ms);
  final millis = _three(gap % _msPerSecond);
  if (gap < _msPerMinute) {
    return '+${gap ~/ _msPerSecond}.$millis';
  }
  return '+${gap ~/ _msPerMinute}:${_two((gap ~/ _msPerSecond) % _secondsPerMinute)}.$millis';
}

/// Pen 칸. 패널티가 없으면 `-`, 시간이 있으면 `+5s (2)`, 시간이 0이면 `(1)`.
String penaltyLabel(int numPenalties, int penaltiesTimeMs) {
  if (numPenalties <= 0) {
    return kNoValueText;
  }
  if (penaltiesTimeMs <= 0) {
    return '($numPenalties)';
  }
  final seconds = penaltiesTimeMs % _msPerSecond == 0
      ? '${penaltiesTimeMs ~/ _msPerSecond}'
      : (penaltiesTimeMs / _msPerSecond).toStringAsFixed(1);
  return '+${seconds}s ($numPenalties)';
}

// -- Time/Gap 열 -------------------------------------------------------------

/// Time/Gap의 기준 행(docs/12 §8.4).
/// 레이스: 순위가 가장 앞이면서 Finished·Active인 행. 그 밖(연습·예선): 베스트 랩이 가장 빠른 행(상태·순위 무관).
/// 해당하는 행이 없으면 null.
SessionResult? referenceRow(List<SessionResult> results, {required bool isRace}) {
  SessionResult? reference;
  for (final row in results) {
    final eligible = isRace ? isRunningOrFinished(row.resultStatus) : row.bestLapTimeMs != null;
    if (eligible && (reference == null || _compareForReference(row, reference, isRace: isRace) < 0)) {
      reference = row;
    }
  }
  return reference;
}

/// 기준 행 후보끼리의 순서: 비레이스는 베스트 랩, 같으면(레이스는 처음부터) 순위, 그다음 차 번호.
int _compareForReference(SessionResult a, SessionResult b, {required bool isRace}) {
  if (!isRace) {
    final byBestLap = a.bestLapTimeMs!.compareTo(b.bestLapTimeMs!);
    if (byBestLap != 0) {
      return byBestLap;
    }
  }
  final byPosition = a.position.compareTo(b.position);
  return byPosition != 0 ? byPosition : a.carIndex.compareTo(b.carIndex);
}

/// 결과 표 Time/Gap 칸의 글자(docs/12 §8.4). [reference]는 [referenceRow]의 결과.
String timeOrGap(SessionResult row, SessionResult? reference, {required bool isRace}) =>
    isRace ? _raceTimeOrGap(row, reference) : _bestLapTimeOrGap(row, reference);

String _raceTimeOrGap(SessionResult row, SessionResult? reference) {
  if (!isRunningOrFinished(row.resultStatus)) {
    return resultStatusLabel(row.resultStatus);
  }
  if (reference == null) {
    return kNoValueText;
  }
  if (row.carIndex == reference.carIndex) {
    final total = _totalWithPenalties(row);
    return total == null ? kNoValueText : formatRaceTime(total);
  }
  final lapsBehind = reference.numLaps - row.numLaps;
  if (lapsBehind > 0) {
    return lapsBehind == 1 ? '+1 Lap' : '+$lapsBehind Laps';
  }
  final rowTotal = _totalWithPenalties(row);
  final referenceTotal = _totalWithPenalties(reference);
  if (rowTotal == null || referenceTotal == null) {
    return kNoValueText;
  }
  return formatGapMs(rowTotal - referenceTotal);
}

String _bestLapTimeOrGap(SessionResult row, SessionResult? reference) {
  final bestLap = row.bestLapTimeMs;
  if (bestLap == null) {
    return isRunningOrFinished(row.resultStatus) ? kNoValueText : resultStatusLabel(row.resultStatus);
  }
  final referenceBestLap = reference?.bestLapTimeMs;
  if (reference == null || referenceBestLap == null || row.carIndex == reference.carIndex) {
    return formatRaceTime(bestLap);
  }
  return formatGapMs(bestLap - referenceBestLap);
}

/// 총 레이스 시간 + 패널티 시간. 총 시간이 없으면 null.
int? _totalWithPenalties(SessionResult row) {
  final total = row.totalRaceTimeMs;
  return total == null ? null : total + row.penaltiesTimeMs;
}
