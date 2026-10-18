/// 설정 화면의 "게임" 선택지(게임 코드 → 표시 이름, docs/14 §3). 지원 게임이 늘면 여기에 더한다(백엔드 `GameCodes.Supported`와 맞춘다).
const Map<String, String> kGameLabels = {'F1_25': 'F1 25'};

/// 드롭다운 항목: 지원 게임 + 목록에 없는 현재 값(잃지 않게 그대로 보인다).
List<String> gameChoices(String current) =>
    kGameLabels.containsKey(current) ? kGameLabels.keys.toList() : [current, ...kGameLabels.keys];

String gameLabelOf(String code) => kGameLabels[code] ?? code;
