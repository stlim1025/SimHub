import '../../laps/domain/lap_display.dart';
import '../../profile/domain/game_options.dart';
import 'setup_models.dart';

/// 셋업 모음 목록 경로.
const String kSetupsPath = '/setups';

/// 트랙 목록 경로.
const String kTracksPath = '/tracks';

/// 주소 쿼리 이름(`?condition=wet`).
const String kSetupConditionQuery = 'condition';

const String _wetQueryValue = 'wet';

Map<String, String>? _conditionQuery(String condition) =>
    condition == kSetupConditionWet ? {kSetupConditionQuery: _wetQueryValue} : null;

/// 셋업 모음 목록 주소. Wet이면 `?condition=wet`(Dry는 쿼리 없음).
String setupsLocation({String condition = kSetupConditionDry}) =>
    Uri(path: kSetupsPath, queryParameters: _conditionQuery(condition)).toString();

/// 한 트랙의 상위 셋업 주소(`/setups/:trackId`, Wet이면 `?condition=wet`).
String setupTrackLocation(String trackId, {String condition = kSetupConditionDry}) =>
    Uri(path: '$kSetupsPath/${Uri.encodeComponent(trackId)}', queryParameters: _conditionQuery(condition)).toString();

/// 셋업 하나의 주소(`/setups/:trackId/:setupId`).
String setupDetailLocation(String trackId, String setupId) =>
    '$kSetupsPath/${Uri.encodeComponent(trackId)}/${Uri.encodeComponent(setupId)}';

/// 트랙 개요 주소(`/tracks/:trackId`).
String trackOverviewLocation(String trackId) => '$kTracksPath/${Uri.encodeComponent(trackId)}';

/// 리더보드에서 그 트랙을 고른 주소(`/leaderboard?trackId=`).
String leaderboardLocation(String trackId) =>
    Uri(path: '/leaderboard', queryParameters: {'trackId': trackId}).toString();

/// 게임 코드 → 짧은 제목 이름(`F1_25` → `F1 25`, 모르면 코드 그대로).
String gameTitleOf(String gameCode) => gameLabelOf(gameCode);

final RegExp _f1CodePattern = RegExp(r'^F1_(\d{2})$');
const String _centuryPrefix = '20';

/// 게임 코드 → 이동 경로(breadcrumb)의 연도 이름(`F1_25` → `F1 2025`). 모양이 다르면 [gameTitleOf](순수 함수).
String gameYearLabelOf(String gameCode) {
  final match = _f1CodePattern.firstMatch(gameCode);
  return match == null ? gameTitleOf(gameCode) : 'F1 $_centuryPrefix${match.group(1)}';
}

/// 셋업 세션 이름: 서버 `SessionType`(예: `TimeTrial`)이면 표시 이름, 원본 글자(예: `Time Trial`)면 그대로. 없으면 `-`.
String setupSessionLabel(String? sessionType) {
  if (sessionType == null || sessionType.isEmpty) {
    return kLapNoValueText;
  }
  final label = sessionTypeLabel(sessionType);
  return label == kLapNoValueText ? sessionType : label;
}
