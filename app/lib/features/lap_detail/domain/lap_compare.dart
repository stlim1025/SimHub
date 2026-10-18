/// 랩 상세의 비교 대상 선택·필터(docs/15 §10, D-51). 주소 쿼리
/// `?compare=best|leaderboard|lap|none&compareLapId=&sameTeam=true&sameSessionType=true&sameAssists=true`와
/// API 쿼리(`GET /me/laps/{lapId}`)가 같은 이름을 쓴다.
library;

/// 비교 대상 종류. [wire]는 주소·API 값.
enum LapCompareKind {
  best('best'),
  leaderboard('leaderboard'),
  lap('lap'),
  none('none');

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
const String _trueText = 'true';

/// 랩 ID로 보이는 글자(공백 없이 8~64자, 영숫자·하이픈). 붙여 넣은 값을 걸러 내는 데 쓴다 — 진짜 검사는 서버가 한다.
final RegExp _lapIdPattern = RegExp(r'^[0-9A-Za-z-]{8,64}$');

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
  const LapCompareSelection({this.kind = LapCompareKind.best, this.compareLapId, this.filters = const {}});

  static const LapCompareSelection defaults = LapCompareSelection();

  final LapCompareKind kind;

  /// [LapCompareKind.lap]일 때만 쓴다.
  final String? compareLapId;

  /// [LapCompareKind.best]·[LapCompareKind.leaderboard]일 때만 서버에 보낸다.
  final Set<LapCompareFilter> filters;

  bool get usesFilters => kind == LapCompareKind.best || kind == LapCompareKind.leaderboard;

  /// 주소 쿼리 → 선택. `compare=lap`인데 ID가 없거나 이상하면 기본(best)으로 본다.
  factory LapCompareSelection.fromQuery(Map<String, String> query) {
    var kind = LapCompareKind.parse(query[kCompareQuery]);
    final lapId = normalizeLapIdInput(query[kCompareLapIdQuery] ?? '');
    if (kind == LapCompareKind.lap && lapId == null) {
      kind = LapCompareKind.best;
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
        if (usesFilters)
          for (final filter in LapCompareFilter.values)
            if (filters.contains(filter)) filter.wire: _trueText,
      };

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
      other.filters.length == filters.length &&
      other.filters.containsAll(filters);

  @override
  int get hashCode => Object.hash(kind, compareLapId, Object.hashAllUnordered(filters));

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
