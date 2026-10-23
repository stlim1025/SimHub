/// 랩 상세의 비교 대상 선택·필터(docs/15 §10, D-51). 주소 쿼리
/// `?compare=best|leaderboard|lap|none&compareLapId=&sameTeam=true&sameSessionType=true&sameAssists=true`와
/// API 쿼리(`GET /me/laps/{lapId}`)가 같은 이름을 쓴다.
/// `compare=car`(같은 세션의 다른 차 — 세션 순위표의 비교 버튼)는 앱만 쓰고 API에는 비교 없음으로 보낸다:
/// `&compareSession=&compareCar=&compareName=&compareTimeMs=&compareTeamColor=`.
library;

/// 비교 대상 종류. [wire]는 주소·API 값.
enum LapCompareKind {
  best('best'),
  leaderboard('leaderboard'),
  lap('lap'),
  none('none'),

  /// 같은 세션의 다른 차 베스트 랩(모든 차 표본으로 복원, `GET /me/sessions/{id}/cars/{carIndex}/best-lap-trace`).
  car('car');

  const LapCompareKind(this.wire);

  final String wire;

  /// 주소 값 → 종류. 없거나 모르는 값이면 [best](기본).
  static LapCompareKind parse(String? value) =>
      values.where((k) => k.wire == value?.toLowerCase()).firstOrNull ?? LapCompareKind.best;
}

/// 비교 필터(내 최고 랩·리더보드 최고 랩을 고를 때만, 복수 선택). [wire]는 주소·API 쿼리 이름이자 응답 `appliedFilters` 값.
enum LapCompareFilter {
  sameTeam('sameTeam'),
  sameSessionType('sameSessionType'),
  sameAssists('sameAssists');

  const LapCompareFilter(this.wire);

  final String wire;

  static LapCompareFilter? parse(Object? value) => values.where((f) => f.wire == value).firstOrNull;
}

const String kCompareQuery = 'compare';
const String kCompareLapIdQuery = 'compareLapId';
const String kCompareSessionQuery = 'compareSession';
const String kCompareCarQuery = 'compareCar';
const String kCompareNameQuery = 'compareName';
const String kCompareTimeQuery = 'compareTimeMs';
const String kCompareTeamColorQuery = 'compareTeamColor';
const String _trueText = 'true';

/// 랩 ID = GUID(서버 `Guid? compareLapId`). GUID가 아니면 서버가 400을 내 화면 전체가 오류가 되므로 여기서 거른다.
final RegExp _lapIdPattern = RegExp(r'^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$');

/// 붙여 넣은 랩 ID를 다듬는다. 앞뒤 공백을 빼고, 랩 상세 주소(`…/laps/{id}…`)를 붙여 넣었으면 그 안의 ID를 꺼낸다.
/// 랩 ID로 보이지 않으면 null.
String? normalizeLapIdInput(String raw) {
  var text = raw.trim();
  final fromUrl = RegExp(r'/laps/([0-9A-Za-z-]+)').firstMatch(text);
  if (fromUrl != null) {
    text = fromUrl.group(1)!;
  }
  return _lapIdPattern.hasMatch(text) ? text : null;
}

/// 비교 선택 하나(값 객체 — provider family 키로 쓴다).
class LapCompareSelection {
  const LapCompareSelection({
    this.kind = LapCompareKind.best,
    this.compareLapId,
    this.filters = const {},
    this.compareSessionId,
    this.compareCar,
    this.compareName,
    this.compareTimeMs,
    this.compareTeamColor,
  });

  /// 같은 세션의 다른 차([LapCompareKind.car]).
  const LapCompareSelection.car({
    required String sessionId,
    required int carIndex,
    required String name,
    int? lapTimeMs,
    String? teamColor,
  }) : this(
          kind: LapCompareKind.car,
          compareSessionId: sessionId,
          compareCar: carIndex,
          compareName: name,
          compareTimeMs: lapTimeMs,
          compareTeamColor: teamColor,
        );

  static const LapCompareSelection defaults = LapCompareSelection();

  final LapCompareKind kind;

  /// [LapCompareKind.lap]일 때만 쓴다.
  final String? compareLapId;

  /// [LapCompareKind.best]·[LapCompareKind.leaderboard]일 때만 서버에 보낸다.
  final Set<LapCompareFilter> filters;

  /// [LapCompareKind.car]일 때만: 세션 Id·차 번호·드라이버 이름·베스트 랩(ms)·팀 색(`#RRGGBB`).
  final String? compareSessionId;
  final int? compareCar;
  final String? compareName;
  final int? compareTimeMs;
  final String? compareTeamColor;

  bool get usesFilters => kind == LapCompareKind.best || kind == LapCompareKind.leaderboard;

  /// 주소 쿼리 → 선택. `compare=lap`인데 ID가 없거나 이상하면, `compare=car`인데 세션·차 번호가 없으면 기본(best)으로 본다.
  factory LapCompareSelection.fromQuery(Map<String, String> query) {
    var kind = LapCompareKind.parse(query[kCompareQuery]);
    final lapId = normalizeLapIdInput(query[kCompareLapIdQuery] ?? '');
    if (kind == LapCompareKind.lap && lapId == null) {
      kind = LapCompareKind.best;
    }
    final sessionId = normalizeLapIdInput(query[kCompareSessionQuery] ?? '');
    final car = int.tryParse(query[kCompareCarQuery] ?? '');
    if (kind == LapCompareKind.car) {
      if (sessionId == null || car == null) {
        kind = LapCompareKind.best;
      } else {
        return LapCompareSelection.car(
          sessionId: sessionId,
          carIndex: car,
          name: query[kCompareNameQuery] ?? '',
          lapTimeMs: int.tryParse(query[kCompareTimeQuery] ?? ''),
          teamColor: query[kCompareTeamColorQuery],
        );
      }
    }
    return LapCompareSelection(
      kind: kind,
      compareLapId: kind == LapCompareKind.lap ? lapId : null,
      filters: {
        for (final filter in LapCompareFilter.values)
          if (query[filter.wire] == _trueText) filter,
      },
    );
  }

  /// 선택 → 쿼리(주소·API 공용). 기본값은 싣지 않는다(기본 선택 = 빈 맵). 필터는 쓰는 종류일 때만.
  Map<String, String> toQuery() => {
        if (kind != LapCompareKind.best) kCompareQuery: kind.wire,
        if (kind == LapCompareKind.lap && compareLapId != null) kCompareLapIdQuery: compareLapId!,
        if (kind == LapCompareKind.car) ...{
          kCompareSessionQuery: ?compareSessionId,
          kCompareCarQuery: ?compareCar?.toString(),
          kCompareNameQuery: ?compareName,
          kCompareTimeQuery: ?compareTimeMs?.toString(),
          kCompareTeamColorQuery: ?compareTeamColor,
        },
        if (usesFilters)
          for (final filter in LapCompareFilter.values)
            if (filters.contains(filter)) filter.wire: _trueText,
      };

  /// 랩 상세 API 쿼리. 다른 차 비교는 서버가 모르는 종류라 비교 없음으로 보낸다(다른 차 트레이스는 따로 읽는다).
  Map<String, String> toApiQuery() =>
      kind == LapCompareKind.car ? const LapCompareSelection(kind: LapCompareKind.none).toQuery() : toQuery();

  LapCompareSelection withKind(LapCompareKind next, {String? lapId}) =>
      LapCompareSelection(kind: next, compareLapId: next == LapCompareKind.lap ? lapId : null, filters: filters);

  LapCompareSelection toggle(LapCompareFilter filter) => LapCompareSelection(
        kind: kind,
        compareLapId: compareLapId,
        filters: filters.contains(filter) ? ({...filters}..remove(filter)) : {...filters, filter},
      );

  @override
  bool operator ==(Object other) =>
      other is LapCompareSelection &&
      other.kind == kind &&
      other.compareLapId == compareLapId &&
      other.compareSessionId == compareSessionId &&
      other.compareCar == compareCar &&
      other.compareName == compareName &&
      other.compareTimeMs == compareTimeMs &&
      other.compareTeamColor == compareTeamColor &&
      other.filters.length == filters.length &&
      other.filters.containsAll(filters);

  @override
  int get hashCode => Object.hash(
        kind,
        compareLapId,
        compareSessionId,
        compareCar,
        compareName,
        compareTimeMs,
        compareTeamColor,
        Object.hashAllUnordered(filters),
      );

  @override
  String toString() => 'LapCompareSelection(${toQuery()})';
}

/// 랩 상세 provider 키: 랩 + 비교 선택.
class LapDetailKey {
  const LapDetailKey(this.lapId, [this.selection = LapCompareSelection.defaults]);

  final String lapId;
  final LapCompareSelection selection;

  @override
  bool operator ==(Object other) => other is LapDetailKey && other.lapId == lapId && other.selection == selection;

  @override
  int get hashCode => Object.hash(lapId, selection);
}

/// 공유할 주소(Share 버튼): 지금 브라우저 주소의 출처에 앱 안 위치를 붙인다. 해시 주소(`/#/laps/…`)면 해시에 붙인다.
/// [base]가 http(s)가 아니면(모바일 등) 앱 안 위치만 돌려준다(순수 함수).
String shareUrlFor(Uri base, String location) {
  if (base.scheme != 'http' && base.scheme != 'https') {
    return location;
  }
  final target = Uri.parse(location);
  if (base.fragment.startsWith('/')) {
    return base.replace(fragment: location).toString();
  }
  return Uri(
    scheme: base.scheme,
    host: base.host,
    port: base.hasPort ? base.port : null,
    path: target.path,
    query: target.hasQuery ? target.query : null,
  ).toString();
}
