import 'package:intl/intl.dart';

/// Laps 표가 MODE·날씨 열을 숨기는 콘텐츠 폭(논리 px, docs/15 §2.1). 세션 결과 표와 같은 기준이다.
const double kLapTableCompactWidth = 600;

/// 값이 없는 칸의 자리표시.
const String kLapNoValueText = '-';

/// 세션 유형 라벨(서버 `SessionType` 문자열). 모르는 값·`Unknown`은 `-`.
const Map<String, String> _sessionTypeLabels = {
  'TimeTrial': 'Time Trial',
  'Practice': 'Practice',
  'Qualifying': 'Qualifying',
  'Race': 'Race',
};

/// 게임 모드 라벨(docs/15 §2.1 MODE 열). `Other`·모르는 값은 여기 없다 — 세션 유형 라벨로 대신한다.
const Map<String, String> _gameModeLabels = {
  'DriverCareer': 'Driver Career',
  'MyTeamCareer': 'My Team',
  'OnlineCareer': 'Online Career',
  'ChallengeCareer': 'Challenge Career',
  'GrandPrix': 'Grand Prix',
  'TimeTrial': 'Time Trial',
  'Online': 'Online',
  'Story': 'Braking Point',
};

/// 날씨 이름(docs/15 §3.1: 게임 0~5).
const Map<String, String> _weatherLabels = {
  'Clear': 'Clear',
  'LightCloud': 'Light Cloud',
  'Overcast': 'Overcast',
  'LightRain': 'Light Rain',
  'HeavyRain': 'Heavy Rain',
  'Storm': 'Storm',
};

final DateFormat _dateFormat = DateFormat('yyyy-MM-dd');

/// `TimeTrial` → `Time Trial`. 모르는 값은 `-`(순수 함수).
String sessionTypeLabel(String sessionType) => _sessionTypeLabels[sessionType] ?? kLapNoValueText;

/// 아는 게임 모드의 라벨. `Other`·null·모르는 값은 null(순수 함수).
String? knownGameModeLabel(String? gameMode) => _gameModeLabels[gameMode];

/// MODE 열 글자: 게임 모드 라벨, `Other`·null·모르는 값이면 세션 유형 라벨(순수 함수).
String lapModeLabel({required String? gameMode, required String sessionType}) =>
    knownGameModeLabel(gameMode) ?? sessionTypeLabel(sessionType);

/// 날씨 이름. 모르는 값은 서버 문자열 그대로, null이면 null(순수 함수).
String? weatherLabel(String? weather) => weather == null ? null : (_weatherLabels[weather] ?? weather);

/// 트랙별 랩 표 주소(docs/15 §2.1).
String trackLapsLocation(String trackId) => '/laps/tracks/$trackId';

/// DATE 열: 로컬 시간대의 `yyyy-MM-dd`.
String formatLapDate(DateTime value) => _dateFormat.format(value.toLocal());
