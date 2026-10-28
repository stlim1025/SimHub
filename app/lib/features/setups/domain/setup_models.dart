import '../../sessions/domain/setup_display.dart';

/// 셋업 모음·트랙 화면이 쓰는 트랙 머리(`track` 객체: trackId · name · countryCode · circuitName).
class SetupTrackRef {
  const SetupTrackRef({required this.trackId, required this.name, this.countryCode, this.circuitName});

  final String trackId;

  /// 표시 이름(예: `Australia`).
  final String name;

  /// ISO 3166-1 alpha-2. 모르면 null(회색 원 국기).
  final String? countryCode;

  /// 서킷 이름(예: `Melbourne Grand Prix Circuit`). 모르면 null.
  final String? circuitName;

  factory SetupTrackRef.fromJson(Map<String, dynamic> json) => SetupTrackRef(
        trackId: json['trackId'] as String,
        name: json['name'] as String,
        countryCode: json['countryCode'] as String?,
        circuitName: json['circuitName'] as String?,
      );
}

/// 트랙 목록 한 줄(`GET /setups/tracks?gameCode=`). 캘린더 순서로 온다.
/// [displayOrder]가 [kCalendarRoundCount]를 넘으면 역방향·옛 레이아웃 트랙(라운드 번호 없이 뒤에 보인다).
class SetupTrackSummary {
  const SetupTrackSummary({
    required this.trackId,
    required this.name,
    required this.displayOrder,
    required this.dryCount,
    required this.wetCount,
    this.countryCode,
    this.circuitName,
  });

  final String trackId;
  final String name;
  final String? countryCode;
  final int displayOrder;
  final String? circuitName;

  /// 가져온 Dry 셋업 수.
  final int dryCount;

  /// 가져온 Wet 셋업 수.
  final int wetCount;

  /// 캘린더 라운드 트랙인가(역방향·옛 레이아웃이 아닌가).
  bool get isCalendarRound => displayOrder <= kCalendarRoundCount;

  /// [condition]의 셋업 수.
  int countOf(String condition) => condition == kSetupConditionWet ? wetCount : dryCount;

  factory SetupTrackSummary.fromJson(Map<String, dynamic> json) => SetupTrackSummary(
        trackId: json['trackId'] as String,
        name: json['name'] as String,
        countryCode: json['countryCode'] as String?,
        displayOrder: json['displayOrder'] as int,
        circuitName: json['circuitName'] as String?,
        dryCount: (json['dryCount'] as int?) ?? 0,
        wetCount: (json['wetCount'] as int?) ?? 0,
      );
}

/// 트랙·조건별 셋업 목록 한 줄.
class SetupListItem {
  const SetupListItem({
    required this.id,
    required this.rank,
    required this.lapTimeMs,
    required this.sourceUrl,
    this.teamName,
    this.sessionType,
  });

  final String id;
  final int rank;
  final String? teamName;

  /// 원본(F1Laps)의 세션 이름 또는 서버 `SessionType` 값.
  final String? sessionType;
  final int lapTimeMs;
  final String sourceUrl;

  factory SetupListItem.fromJson(Map<String, dynamic> json) => SetupListItem(
        id: json['id'] as String,
        rank: json['rank'] as int,
        teamName: json['teamName'] as String?,
        sessionType: json['sessionType'] as String?,
        lapTimeMs: json['lapTimeMs'] as int,
        sourceUrl: json['sourceUrl'] as String,
      );
}

/// 트랙·조건별 셋업 목록(`GET /setups?trackId=&condition=`). 아직 가져온 적 없으면 [fetchedAt]이 null이고 [items]가 비었다.
class SetupList {
  const SetupList({required this.track, required this.condition, required this.items, this.fetchedAt});

  final SetupTrackRef track;
  final String condition;
  final DateTime? fetchedAt;
  final List<SetupListItem> items;

  factory SetupList.fromJson(Map<String, dynamic> json) => SetupList(
        track: SetupTrackRef.fromJson(json['track'] as Map<String, dynamic>),
        condition: json['condition'] as String,
        fetchedAt: _dateTimeOrNull(json['fetchedAt']),
        items: [
          for (final item in (json['items'] as List<dynamic>? ?? const []))
            SetupListItem.fromJson(item as Map<String, dynamic>),
        ],
      );
}

/// 셋업 하나(`GET /setups/{id}`). [sections]는 화면 순서 그대로(Aerodynamics · Transmission · …).
class SetupDetail {
  const SetupDetail({
    required this.id,
    required this.rank,
    required this.gameCode,
    required this.track,
    required this.condition,
    required this.lapTimeMs,
    required this.sourceUrl,
    required this.sections,
    this.teamName,
    this.sessionType,
    this.steering,
    this.setOn,
    this.fetchedAt,
  });

  final String id;
  final int rank;
  final String gameCode;
  final SetupTrackRef track;
  final String condition;
  final String? teamName;
  final String? sessionType;
  final int lapTimeMs;
  final String? steering;

  /// 셋업을 올린 날(`yyyy-MM-dd`, 날짜만). 모르면 null.
  final DateTime? setOn;
  final String sourceUrl;
  final DateTime? fetchedAt;
  final List<SetupGroup> sections;

  factory SetupDetail.fromJson(Map<String, dynamic> json) => SetupDetail(
        id: json['id'] as String,
        rank: json['rank'] as int,
        gameCode: json['gameCode'] as String,
        track: SetupTrackRef.fromJson(json['track'] as Map<String, dynamic>),
        condition: json['condition'] as String,
        teamName: json['teamName'] as String?,
        sessionType: json['sessionType'] as String?,
        lapTimeMs: json['lapTimeMs'] as int,
        steering: json['steering'] as String?,
        setOn: _dateTimeOrNull(json['setOn']),
        sourceUrl: json['sourceUrl'] as String,
        fetchedAt: _dateTimeOrNull(json['fetchedAt']),
        sections: [
          for (final section in (json['sections'] as List<dynamic>? ?? const []))
            _sectionOf(section as Map<String, dynamic>),
        ],
      );

  static SetupGroup _sectionOf(Map<String, dynamic> json) => (
        title: json['title'] as String,
        items: [
          for (final item in (json['items'] as List<dynamic>? ?? const []))
            (
              label: (item as Map<String, dynamic>)['label'] as String,
              value: '${item['value'] ?? ''}',
            ),
        ],
      );
}

DateTime? _dateTimeOrNull(Object? value) => switch (value) {
      final String text when text.isNotEmpty => DateTime.parse(text),
      _ => null,
    };

/// 캘린더 라운드 수. `displayOrder`가 이보다 크면 역방향·옛 레이아웃 트랙이다.
const int kCalendarRoundCount = 24;

/// 서버 조건 값.
const String kSetupConditionDry = 'Dry';
const String kSetupConditionWet = 'Wet';

/// 주소 쿼리(`?condition=wet`)의 Wet 값.
const String _wetQuery = 'wet';

/// 주소 쿼리 → 서버 조건 값. `wet`(대소문자 무관)만 Wet, 나머지는 Dry(순수 함수).
String normalizeSetupCondition(String? query) =>
    query?.toLowerCase() == _wetQuery ? kSetupConditionWet : kSetupConditionDry;

/// 셋업 세션 종류(서버 `session` 쿼리 값). 타임 트라이얼은 Dry만 있다.
const String kSetupSessionTimeTrial = 'TimeTrial';
const String kSetupSessionRace = 'Race';
const String kSetupSessionQualifying = 'Qualifying';

/// 조건별 세션 종류(화면 순서).
List<String> setupSessionsFor(String condition) => condition == kSetupConditionWet
    ? const [kSetupSessionRace, kSetupSessionQualifying]
    : const [kSetupSessionTimeTrial, kSetupSessionRace, kSetupSessionQualifying];

/// 조건의 기본 세션 종류: Dry는 타임 트라이얼, Wet은 레이스.
String defaultSetupSession(String condition) =>
    condition == kSetupConditionWet ? kSetupSessionRace : kSetupSessionTimeTrial;

/// 주소 쿼리(`?session=race`) → 세션 종류. 없거나 모르거나 그 조건에 없는 값(Wet의 타임 트라이얼)이면 조건의 기본값.
String normalizeSetupSession(String? query, String condition) {
  final key = query?.toLowerCase();
  return setupSessionsFor(condition)
      .firstWhere((s) => s.toLowerCase() == key, orElse: () => defaultSetupSession(condition));
}
